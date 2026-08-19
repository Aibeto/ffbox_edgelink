package top.raincrat.aibeto.ffboxedgelink.localnode

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Environment
import android.provider.Settings
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import top.raincrat.aibeto.ffboxedgelink.localnode.LocalNodeService.Companion.isNodeRunning

/**
 * 内置 FFBox 服务 MethodChannel / EventChannel 桥。
 *
 * - `top.raincrat.aibeto.ffboxedgelink/local_node`：startNode / stopNode / isNodeRunning
 * - `top.raincrat.aibeto.ffboxedgelink/local_node_logs`：实时日志流（每行一条）
 *
 * 启停调用可能阻塞等待（数十秒），在后台线程执行后经主线程回发结果；
 * 日志回调源自控制 socket 读线程，同样切换到主线程（Flutter 要求）。
 */
class LocalNodeChannel(
    private val context: Context,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val methodChannel = MethodChannel(
        messenger,
        "top.raincrat.aibeto.ffboxedgelink/local_node",
    )
    private val logsChannel = EventChannel(
        messenger,
        "top.raincrat.aibeto.ffboxedgelink/local_node_logs",
    )

    fun register() {
        methodChannel.setMethodCallHandler { call, result ->
            // 启停为阻塞式（requestStart/requestStop 内部 sleep 轮询等待状态，
            // 至多数十秒），一律在后台线程执行后经主线程回发，禁止在主线程
            // 直接调用 requestStart/requestStop（会造成 ANR）。
            Thread {
                try {
                    val reply: Any? = when (call.method) {
                        "startNode" -> LocalNodeService.requestStart(context)
                        "stopNode" -> LocalNodeService.requestStop(context)
                        "isNodeRunning" -> isNodeRunning
                        // 内置服务仅 arm64-v8a 可用，Flutter 侧据此决定是否显示入口
                        "abi" -> Build.SUPPORTED_ABIS.firstOrNull()
                        // 所有文件访问权：API 30+ 为 MANAGE_EXTERNAL_STORAGE，API 23-29 为 READ_EXTERNAL_STORAGE
                        "hasStoragePermission" -> hasStoragePermission()
                        "requestStoragePermission" -> requestStoragePermission()
                        else -> {
                            mainHandler.post { result.notImplemented() }
                            return@Thread
                        }
                    }
                    mainHandler.post { result.success(reply) }
                } catch (e: Exception) {
                    mainHandler.post { result.error("LOCAL_NODE_ERROR", e.message, null) }
                }
            }.start()
        }

        logsChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                val sink = events
                LocalNodeService.logListener = { line ->
                    mainHandler.post { sink.success(line) }
                }
            }

            override fun onCancel(arguments: Any?) {
                LocalNodeService.logListener = null
            }
        })
    }

    // --- 存储权限（内置服务读取用户媒体文件进行转码） ---

    /** 是否已获得读取用户文件的权限。 */
    private fun hasStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // API 30+：所有文件访问权（MANAGE_EXTERNAL_STORAGE）
            Environment.isExternalStorageManager()
        } else {
            // API 23-29：读取外部存储运行时权限
            @Suppress("DEPRECATION")
            context.checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    /** 引导用户授予存储权限：API 30+ 打开“所有文件访问”设置页，API 23-29 打开应用详情。 */
    private fun requestStoragePermission(): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:${context.packageName}"),
            )
        } else {
            @Suppress("DEPRECATION")
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${context.packageName}"),
            )
        }
        // 个别厂商设备上 ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION 可能缺失，回退到全部文件访问总列表
        val target = if (intent.resolveActivity(context.packageManager) != null) {
            intent
        } else {
            Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
        }
        return try {
            context.startActivity(target.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
    }
}
