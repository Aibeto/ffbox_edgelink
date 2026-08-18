package top.raincrat.aibeto.ffboxedgelink.localnode

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.LocalSocket
import android.net.LocalSocketAddress
import android.os.IBinder
import android.util.Log
import org.json.JSONObject
import top.raincrat.aibeto.ffboxedgelink.MainActivity
import java.io.File
import java.io.BufferedReader
import java.io.InputStreamReader
import java.nio.charset.StandardCharsets
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * 内置 FFBox 服务前台服务。
 *
 * 职责：
 * 1. 前台服务 + 通知保活（转码期间息屏不被杀）；
 * 2. 首次启动将 assets/nodejs-project 解包到 filesDir；
 * 3. 通过 JNI 启动 nodejs-mobile 引擎（进程内 Node 线程，仅一次）；
 * 4. 连接 Node 侧控制 Unix socket，收发日志与启停指令。
 *
 * Node 引擎为进程内常驻线程：worker 中运行 FFBox 后端，可启停可重启；
 * 引擎本身随进程销毁而终止（Flutter 被 kill 即服务停止，符合预期）。
 */
class LocalNodeService : Service() {

    companion object {
        private const val TAG = "LocalNodeService"
        const val ACTION_START = "top.raincrat.aibeto.ffboxedgelink.action.NODE_START"
        const val ACTION_STOP = "top.raincrat.aibeto.ffboxedgelink.action.NODE_STOP"
        private const val NOTIFICATION_ID = 3002
        private const val CHANNEL_ID = "local_node_service"

        /** assets 中 nodejs-project 的版本标记文件（内容变化触发重新解包）。 */
        private const val ASSET_VERSION_FILE = "nodejs-project/BUILD_VERSION"

        /** Node 主线程 main.js 相对 filesDir 的路径。 */
        private const val NODE_PROJECT_DIR = "nodejs-project"
        private const val NODE_MAIN = "main.js"

        /** 控制 socket 文件（相对 filesDir）。 */
        private const val CONTROL_SOCKET = "nodejs-project/nodectl.sock"

        /** Node 引擎是否已在本进程内启动（引擎仅可启动一次）。 */
        @Volatile
        private var engineStarted = false

        /** FFBox 服务（worker）是否在运行。 */
        @Volatile
        var isNodeRunning = false
            private set

        /** 日志行监听（LocalNodeChannel 的 EventChannel 注册）。 */
        @Volatile
        var logListener: ((String) -> Unit)? = null

        /** 服务状态监听（运行/停止回调）。 */
        @Volatile
        var stateListener: ((Boolean) -> Unit)? = null

        /**
         * 请求启动服务（幂等，阻塞式）。
         *
         * ⚠️ 阻塞调用：内部 sleep 轮询等待服务就绪，至多 [timeoutSec] 秒；
         * **禁止在 UI/主线程直接调用**（会造成 ANR），必须由后台线程调用
         * （如 LocalNodeChannel 的后台线程）。
         */
        fun requestStart(context: Context, timeoutSec: Long = 40): Boolean {
            val ctx = context.applicationContext
            // 引擎与服务均就绪视为成功；否则拉起前台服务走启动流程
            if (isNodeRunning) return true
            ctx.startForegroundService(Intent(ctx, LocalNodeService::class.java).apply {
                action = ACTION_START
            })
            return awaitRunning(timeoutSec)
        }

        /**
         * 请求停止服务（阻塞式，停止 worker 与前台服务，引擎保留）。
         *
         * ⚠️ 阻塞调用：内部 sleep 轮询等待服务停止，至多 [timeoutSec] 秒；
         * **禁止在 UI/主线程直接调用**（会造成 ANR），必须由后台线程调用
         * （如 LocalNodeChannel 的后台线程）。
         */
        fun requestStop(context: Context, timeoutSec: Long = 20): Boolean {
            val ctx = context.applicationContext
            if (!isNodeRunning) {
                ctx.startService(Intent(ctx, LocalNodeService::class.java).apply {
                    action = ACTION_STOP
                })
                return true
            }
            ctx.startService(Intent(ctx, LocalNodeService::class.java).apply {
                action = ACTION_STOP
            })
            return awaitStopped(timeoutSec)
        }

        /** 轮询等待服务进入运行态（阻塞，禁止在主线程调用）。 */
        private fun awaitRunning(timeoutSec: Long): Boolean {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(timeoutSec)
            while (System.nanoTime() < deadline) {
                if (isNodeRunning) return true
                Thread.sleep(200)
            }
            return isNodeRunning
        }

        /** 轮询等待服务进入停止态（阻塞，禁止在主线程调用）。 */
        private fun awaitStopped(timeoutSec: Long): Boolean {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(timeoutSec)
            while (System.nanoTime() < deadline) {
                if (!isNodeRunning) return true
                Thread.sleep(200)
            }
            return !isNodeRunning
        }
    }

    private val controlSocket = AtomicReference<LocalSocket?>(null)
    private val reading = AtomicBoolean(false)

    // --- 生命周期 ---

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> Thread { handleStart() }.start()
            ACTION_STOP -> Thread { handleStop() }.start()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        disconnectControl()
        super.onDestroy()
    }

    // --- 启动流程 ---

    private fun handleStart() {
        startForeground(NOTIFICATION_ID, buildNotification(running = false))
        try {
            val projectDir = File(filesDir, NODE_PROJECT_DIR)
            extractAssetsIfNeeded(projectDir)

            if (!engineStarted) {
                engineStarted = true
                System.loadLibrary("nodeext")
                val main = File(projectDir, NODE_MAIN).absolutePath
                // node::Start 阻塞至 Node 线程退出；引擎设计为常驻，此线程不返回
                Thread {
                    try {
                        val code = startNodeWithArguments(arrayOf("node", main))
                        Log.w(TAG, "Node 引擎已退出，code=$code")
                    } catch (e: Throwable) {
                        Log.e(TAG, "Node 引擎异常退出", e)
                    }
                }.start()
                Log.i(TAG, "nodejs-mobile 引擎已启动")
            }

            connectControl()
            sendCommand(buildStartCommand(projectDir))
        } catch (e: Throwable) {
            Log.e(TAG, "启动失败", e)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    /** 解包 assets/nodejs-project 到 filesDir（版本变化时全量覆盖）。 */
    private fun extractAssetsIfNeeded(projectDir: File) {
        val currentVersion = readAsset(ASSET_VERSION_FILE)?.trim().orEmpty()
        val versionFile = File(projectDir, "BUILD_VERSION")
        if (projectDir.isDirectory && versionFile.isFile &&
            versionFile.readText().trim() == currentVersion && currentVersion.isNotEmpty()
        ) {
            return
        }
        projectDir.deleteRecursively()
        projectDir.mkdirs()
        copyAssetDir("nodejs-project", projectDir)
        // 注：ffmpeg/ffprobe 不在 assets（filesDir 不可 exec，见 buildStartCommand 注释），
        // 由 jniLibs 解压至 nativeLibraryDir，无需补执行位。
        Log.i(TAG, "nodejs-project 已解包，版本=$currentVersion")
    }

    private fun readAsset(path: String): String? = try {
        assets.open(path).bufferedReader().use { it.readText() }
    } catch (_: Exception) {
        null
    }

    private fun copyAssetDir(assetPath: String, target: File) {
        val children = assets.list(assetPath).orEmpty()
        if (children.isEmpty()) {
            target.outputStream().use { out ->
                assets.open(assetPath).use { it.copyTo(out) }
            }
            return
        }
        target.mkdirs()
        for (child in children) {
            copyAssetDir("$assetPath/$child", File(target, child))
        }
    }

    // --- 停止流程 ---

    private fun handleStop() {
        sendCommand(JSONObject().put("type", "stop"))
        // 状态回调（state:false）到达后由 onStateChanged 收尾
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
        while (System.nanoTime() < deadline && isNodeRunning) {
            Thread.sleep(100)
        }
        onStateChanged(false)
    }

    // --- 控制 socket 客户端 ---

    private fun connectControl() {
        val sockFile = File(filesDir, CONTROL_SOCKET)
        // Node 引擎初始化需要时间，轮询等待 socket 文件出现
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(30)
        while (!sockFile.exists() && System.nanoTime() < deadline) {
            Thread.sleep(300)
        }
        check(sockFile.exists()) { "控制 socket 未出现: $sockFile" }

        var lastError: Exception? = null
        // 连接重试使用独立期限（等待 socket 文件可能已消耗大部分时间）
        val connectDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
        while (System.nanoTime() < connectDeadline) {
            try {
                val socket = LocalSocket()
                socket.connect(LocalSocketAddress(sockFile.absolutePath, LocalSocketAddress.Namespace.FILESYSTEM))
                controlSocket.set(socket)
                reading.set(true)
                Thread { readLoop(socket) }.start()
                Log.i(TAG, "控制通道已连接")
                return
            } catch (e: Exception) {
                lastError = e
                Thread.sleep(500)
            }
        }
        throw IllegalStateException("连接控制 socket 失败", lastError)
    }

    private fun readLoop(socket: LocalSocket) {
        try {
            // 显式指定 UTF-8：Node 侧以 UTF-8 写入，避免设备默认字符集（如 GBK）
            // 解码导致中文/特殊字符乱码变成“口”
            BufferedReader(
                InputStreamReader(socket.inputStream, StandardCharsets.UTF_8),
            ).useLines { lines ->
                for (raw in lines) {
                    val line = raw.trim()
                    if (line.isEmpty()) continue
                    handleLine(line)
                }
            }
        } catch (_: Exception) {
            // 连接断开（服务停止或进程退出）
        } finally {
            if (reading.compareAndSet(true, false)) {
                disconnectControl()
            }
        }
    }

    private fun handleLine(line: String) {
        try {
            val json = JSONObject(line)
            when (json.optString("type")) {
                "log" -> logListener?.invoke(json.optString("line"))
                "state" -> onStateChanged(json.optBoolean("running"))
            }
        } catch (e: Exception) {
            Log.w(TAG, "无法解析控制消息: $line", e)
        }
    }

    private fun onStateChanged(running: Boolean) {
        if (isNodeRunning == running) return
        isNodeRunning = running
        stateListener?.invoke(running)
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIFICATION_ID, buildNotification(running))
        if (!running) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun sendCommand(json: JSONObject) {
        try {
            controlSocket.get()?.outputStream?.let {
                it.write((json.toString() + "\n").toByteArray())
                it.flush()
            }
        } catch (e: Exception) {
            Log.w(TAG, "发送控制指令失败", e)
        }
    }

    private fun buildStartCommand(projectDir: File): JSONObject {
        return JSONObject()
            .put("type", "start")
            .put("projectDir", projectDir.absolutePath)
            // nativeLibraryDir 是 App 域内唯一可 exec 自带二进制的位置
            // （filesDir 因 targetSdk≥29 的 SELinux W^X 限制不可执行），
            // 内置 ffmpeg/ffprobe（libffmpeg.so / libffprobe.so）位于此处。
            .put("nativeLibraryDir", applicationInfo.nativeLibraryDir)
    }

    private fun disconnectControl() {
        try {
            controlSocket.getAndSet(null)?.close()
        } catch (_: Exception) {
        }
    }

    // --- 通知 ---

    private fun createChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "本地转码服务",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "FFBox 本地服务运行状态"
                setShowBadge(false)
            },
        )
    }

    private fun buildNotification(running: Boolean): Notification {
        val contentIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(if (running) "FFBox 本地服务运行中" else "FFBox 本地服务启动中")
            .setContentText("127.0.0.1:33269 · 手动停止前持续运行")
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .build()
    }

    // --- JNI：libnodeext 中实现 ---

    private external fun startNodeWithArguments(arguments: Array<String>): Int
}
