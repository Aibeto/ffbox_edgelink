package top.raincrat.aibeto.ffboxedgelink.live

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import top.raincrat.aibeto.ffboxedgelink.live.LiveNotificationBuilder.Companion.NOTIFICATION_ID
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * 实时活动前台服务（完整重构版）。
 *
 * 职责：后台轮询 FFBox 任务详情（GET /api/v1/tasks/{id}），将进度实时渲染为
 * 单条 Live Updates 通知。暂停状态下保留通知（ongoing），用户可直接从通知栏
 * 点击暂停/继续按钮操作，Service 直接调用后端 API。
 *
 * 终态集合仅包含 finished/error/deleted（不含 idle），暂停时不停止服务。
 */
class LiveTaskService : Service() {

    companion object {
        private const val TAG = "LiveTaskService"
        const val ACTION_START = "top.raincrat.aibeto.ffboxedgelink.action.START_LIVE"
        const val ACTION_STOP = "top.raincrat.aibeto.ffboxedgelink.action.STOP_LIVE"
        const val ACTION_PAUSE = "top.raincrat.aibeto.ffboxedgelink.action.PAUSE_LIVE"
        const val ACTION_RESUME = "top.raincrat.aibeto.ffboxedgelink.action.RESUME_LIVE"
        const val ACTION_START_TASK = "top.raincrat.aibeto.ffboxedgelink.action.START_TASK_LIVE"
        const val EXTRA_CONFIG = "config"
        const val PREFS_NAME = "live_activity_prefs"
        const val KEY_CONFIG = "config_json"
        const val POLL_INTERVAL_MS = 2000L
        const val TIMEOUT_MS = 5000

        /** 当前活跃配置（供 App 重启后恢复 UI 状态）。 */
        @Volatile
        var activeConfigJson: String? = null
            private set

        @Volatile
        var isServiceRunning = false
            private set
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var pollJob: Job? = null
    private lateinit var notifier: LiveNotificationBuilder
    private var config: LiveActivityConfig? = null
    /** 首次成功轮询前不覆盖通知（避免闪烁"连接中…"）。 */
    private var hasFetchedOnce = false

    override fun onCreate() {
        super.onCreate()
        notifier = LiveNotificationBuilder(this)
        notifier.createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val cfg = parseConfig(intent.getStringExtra(EXTRA_CONFIG))
                if (cfg != null) {
                    startLiveTracking(cfg)
                } else {
                    Log.e(TAG, "缺少实时活动配置，停止服务")
                    stopTracking(keepFinal = false)
                }
            }
            ACTION_STOP -> stopTracking(keepFinal = false)
            ACTION_PAUSE -> pauseTask()
            ACTION_RESUME -> resumeTask()
            ACTION_START_TASK -> startTask()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    // --- 追踪生命周期 ---

    /** 开始/替换实时活动：取消旧轮询，以同一条通知展示新任务。 */
    private fun startLiveTracking(cfg: LiveActivityConfig) {
        pollJob?.cancel()
        config = cfg
        hasFetchedOnce = false
        activeConfigJson = cfg.toJson().toString()
        isServiceRunning = true
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putString(KEY_CONFIG, activeConfigJson)
            .apply()

        val initial = TaskSnapshot(
            taskName = cfg.taskName,
            status = "running",
            progress = 0,
            total = 0,
            elapsed = 0,
            remaining = -1,
            errorMessage = "",
        )
        try {
            startForeground(NOTIFICATION_ID, notifier.build(initial, cfg.baseUrl))
        } catch (e: SecurityException) {
            Log.e(TAG, "startForeground 失败（通知权限被撤销？）", e)
            stopTracking(keepFinal = false)
            return
        }

        startPolling(cfg)
    }

    private fun stopTracking(keepFinal: Boolean) {
        pollJob?.cancel()
        pollJob = null
        config = null
        isServiceRunning = false
        if (keepFinal) {
            stopForeground(STOP_FOREGROUND_DETACH)
        } else {
            stopForeground(STOP_FOREGROUND_REMOVE)
            notifier.cancel()
        }
        activeConfigJson = null
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .remove(KEY_CONFIG)
            .apply()
        stopSelf()
    }

    // --- 轮询 ---

    private fun startPolling(cfg: LiveActivityConfig) {
        pollJob?.cancel()
        pollJob = scope.launch {
            while (isActive) {
                try {
                    val snapshot = fetchTask(cfg)
                    if (snapshot != null) {
                        hasFetchedOnce = true
                        notifier.show(snapshot, cfg.baseUrl)
                        if (snapshot.status in LiveNotificationBuilder.TERMINAL_STATUSES) {
                            stopTracking(keepFinal = true)
                            break
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "轮询失败", e)
                    // 首次成功轮询前不覆盖通知（避免闪烁"连接中…"）
                    if (hasFetchedOnce) {
                        notifier.show(
                            TaskSnapshot(
                                taskName = cfg.taskName,
                                status = "unknown",
                                progress = 0,
                                total = 0,
                                elapsed = 0,
                                remaining = -1,
                                errorMessage = "",
                            ),
                            cfg.baseUrl,
                        )
                    }
                }
                delay(POLL_INTERVAL_MS)
            }
        }
    }

    // --- 暂停 / 继续 / 启动 ---

    private fun startTask() {
        val cfg = config ?: restoreConfigFromPrefs() ?: return
        scope.launch {
            // 先真实调用后端，成功后拉取真实状态刷新通知（不做乐观假切换）
            val ok = callBackend(cfg, "start")
            Log.d(TAG, "启动任务 id=${cfg.taskId} result=$ok")
            // 稍等后端生效，再拉取真实状态纠正通知
            delay(300)
            refreshNow(cfg)
        }
    }

    private fun pauseTask() {
        val cfg = config ?: restoreConfigFromPrefs() ?: return
        scope.launch {
            // 先真实调用后端，成功后拉取真实状态刷新通知（不做乐观假切换）
            val ok = callBackend(cfg, "pause")
            Log.d(TAG, "暂停任务 id=${cfg.taskId} result=$ok")
            // 稍等后端生效，再拉取真实状态纠正通知
            delay(300)
            refreshNow(cfg)
        }
    }

    private fun resumeTask() {
        val cfg = config ?: restoreConfigFromPrefs() ?: return
        scope.launch {
            val ok = callBackend(cfg, "resume")
            Log.d(TAG, "继续任务 id=${cfg.taskId} result=$ok")
            delay(300)
            refreshNow(cfg)
        }
    }

    /** 立即拉取一次任务详情并刷新通知（不等 2s 轮询周期）。 */
    private fun refreshNow(cfg: LiveActivityConfig) {
        try {
            val snapshot = fetchTask(cfg)
            if (snapshot != null) {
                notifier.show(snapshot, cfg.baseUrl)
            }
        } catch (e: Exception) {
            Log.w(TAG, "按钮操作后刷新失败", e)
        }
    }

    /** 服务进程被回收重建后，从 SharedPreferences 恢复活跃配置。 */
    private fun restoreConfigFromPrefs(): LiveActivityConfig? {
        val json = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .getString(KEY_CONFIG, null) ?: return null
        val cfg = parseConfig(json) ?: return null
        // 恢复后确保前台服务仍在运行（按钮点击要求服务存活）
        config = cfg
        if (!isServiceRunning) {
            isServiceRunning = true
            val initial = TaskSnapshot(
                taskName = cfg.taskName,
                status = "running",
                progress = 0,
                total = 0,
                elapsed = 0,
                remaining = -1,
                errorMessage = "",
            )
            try {
                startForeground(NOTIFICATION_ID, notifier.build(initial, cfg.baseUrl))
                // 恢复后重启轮询，保证通知持续更新
                startPolling(cfg)
            } catch (e: Exception) {
                Log.e(TAG, "恢复前台服务失败", e)
                return null
            }
        }
        return cfg
    }

    /**
     * 直接调用后端批量操作 API（POST /api/v1/tasks/{action}）。
     * @return true 表示 HTTP 2xx 成功。
     */
    private fun callBackend(cfg: LiveActivityConfig, action: String): Boolean {
        val conn = URL("${cfg.baseUrl}/api/v1/tasks/$action")
            .openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "POST"
            conn.setRequestProperty("Authorization", "Bearer ${cfg.sessionId}")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Accept", "application/json")
            conn.doOutput = true
            conn.connectTimeout = TIMEOUT_MS
            conn.readTimeout = TIMEOUT_MS
            val body = JSONObject().apply {
                put("ids", JSONArray().put(cfg.taskId))
            }.toString()
            OutputStreamWriter(conn.outputStream).use { it.write(body) }
            val code = conn.responseCode
            // 消费响应体，确保请求完整发送与连接释放
            if (code in 200..299) {
                conn.inputStream.bufferedReader().use { it.readText() }
            } else {
                conn.errorStream?.bufferedReader()?.use { it.readText() }
            }
            Log.d(TAG, "POST /api/v1/tasks/$action -> HTTP $code")
            return code in 200..299
        } catch (e: Exception) {
            Log.w(TAG, "调用后端 $action 失败", e)
            return false
        } finally {
            conn.disconnect()
        }
    }

    // --- 远端轮询 ---

    /** 拉取任务详情并解析为通知快照；网络失败返回 null。 */
    private fun fetchTask(cfg: LiveActivityConfig): TaskSnapshot? {
        val conn = URL("${cfg.baseUrl}/api/v1/tasks/${cfg.taskId}")
            .openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "GET"
            conn.setRequestProperty("Authorization", "Bearer ${cfg.sessionId}")
            conn.connectTimeout = TIMEOUT_MS
            conn.readTimeout = TIMEOUT_MS
            val code = conn.responseCode
            if (code == 200) {
                val body = conn.inputStream.bufferedReader().readText()
                return parseTask(JSONObject(body))
            }
            return if (code == 401 || code == 404) {
                TaskSnapshot(
                    taskName = cfg.taskName,
                    status = if (code == 401) "error" else "deleted",
                    progress = 0,
                    total = 0,
                    elapsed = 0,
                    remaining = -1,
                    errorMessage = if (code == 401) "登录已失效" else "任务不存在",
                )
            } else {
                Log.w(TAG, "轮询 HTTP $code")
                null
            }
        } finally {
            conn.disconnect()
        }
    }

    /** 复刻 Task.fromJson 的「当前 run」语义：从后往前取第一条活跃态 run。 */
    private fun parseTask(root: JSONObject): TaskSnapshot {
        val taskName = root.optString("taskName")
        val status = root.optString("status")
        var total = 0
        var elapsed = 0
        var processed = 0
        var errorMessage = ""

        val before = root.optJSONArray("before")
        if (before != null && before.length() > 0) {
            total = (before.getJSONObject(0).optDouble("duration") * 1000).toInt()
        }

        val run = pickCurrentRun(root.optJSONArray("runs"))
        if (run != null) {
            elapsed = (run.optDouble("elapsed") * 1000).toInt()
            processed = lastProgressTime(run.optJSONObject("progressLog"))
            val errors = run.optJSONArray("errorInfo")
            if (errors != null && errors.length() > 0) {
                errorMessage = errors.optString(0)
            }
        }

        // 完成态强制 100%：ffmpeg 末段 time 上报可能达不到容器时长估值
        // （远程上传媒体的 duration 偏差尤甚），末条采样计算的进度会停在
        // 不足 100% 的位置（与 Dart Task.progress 语义一致，须两侧同步）
        if (status == "finished" && total > 0) {
            processed = total
        }

        val remaining = if (processed > 0 && total > processed) {
            (elapsed.toDouble() * (total - processed) / processed).toInt()
        } else -1

        return TaskSnapshot(
            taskName = taskName,
            status = status,
            progress = processed,
            total = total,
            elapsed = elapsed,
            remaining = remaining,
            errorMessage = errorMessage,
        )
    }

    private fun pickCurrentRun(runs: JSONArray?): JSONObject? {
        if (runs == null || runs.length() == 0) return null
        for (i in runs.length() - 1 downTo 0) {
            val run = runs.optJSONObject(i) ?: continue
            if (run.optString("status") in LiveNotificationBuilder.ACTIVE_RUN_STATUSES) {
                return run
            }
        }
        return runs.optJSONObject(runs.length() - 1)
    }

    /** progressLog.time 序列末条 [t, value] 的 value（已处理媒体秒，转毫秒）。 */
    private fun lastProgressTime(log: JSONObject?): Int {
        if (log == null) return 0
        val time = log.optJSONArray("time") ?: return 0
        if (time.length() == 0) return 0
        val last = time.optJSONArray(time.length() - 1) ?: return 0
        if (last.length() < 2) return 0
        return (last.optDouble(1) * 1000).toInt()
    }

    private fun parseConfig(json: String?): LiveActivityConfig? {
        if (json.isNullOrBlank()) return null
        return try {
            LiveActivityConfig.fromJson(JSONObject(json))
        } catch (e: Exception) {
            Log.e(TAG, "配置解析失败", e)
            null
        }
    }
}
