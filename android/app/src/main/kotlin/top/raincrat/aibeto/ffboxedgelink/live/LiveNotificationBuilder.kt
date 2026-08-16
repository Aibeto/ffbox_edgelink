package top.raincrat.aibeto.ffboxedgelink.live

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import androidx.core.app.NotificationCompat
import top.raincrat.aibeto.ffboxedgelink.MainActivity
import top.raincrat.aibeto.ffboxedgelink.R
import java.net.URI
import java.util.Locale

/**
 * 实时活动通知构建器（v5）。
 *
 * 布局：
 *  - title：运行/暂停 恒显示 "状态 · 百分比"，其他状态仅 0<x<100 的中间进度显示
 *  - contentText：任务名（主导信息）
 *  - subText：服务器 IP · 剩余时间
 *  - API < 36 额外 contentText 拼接进度百分比
 *  - Actions：运行→暂停、暂停/暂停排队→继续、等待(idle)→启动（其余状态不显示按钮）
 *  - 图标：右上角 smallIcon 用形状标识区分状态（颜色会被系统单色化，见 statusIconFor）；
 *    trackerIcon（进度条）用状态色圆点（能变色）；setColor 强调色随状态变化
 *
 * Android 16 (API 36) 使用 [Notification.ProgressStyle]（Live Updates）。
 * 暂停状态下通知保留（ongoing），不停止前台服务。
 */
class LiveNotificationBuilder(private val context: Context) {

    companion object {
        const val CHANNEL_ID = "live_task_progress"
        const val CHANNEL_NAME = "实时任务进度"
        const val NOTIFICATION_ID = 3001

        /** 真正终态集合：轮询命中后才停止前台服务。 */
        val TERMINAL_STATUSES = setOf("finished", "error", "deleted")

        /** 活跃 run 状态集合。 */
        val ACTIVE_RUN_STATUSES = setOf(
            "running", "paused", "paused_queued", "stopping", "finishing", "error",
        )

        const val REQUEST_PAUSE = 2001
        const val REQUEST_RESUME = 2002
        const val REQUEST_START = 2003
    }

    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    // --- 通知渠道 ---

    fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "任务实时转码进度"
            setShowBadge(false)
        }
        notificationManager.createNotificationChannel(channel)
    }

    // --- 主构建入口 ---

    fun build(snapshot: TaskSnapshot, baseUrl: String): Notification {
        val percent = if (snapshot.total > 0) {
            snapshot.progress.toDouble() / snapshot.total * 100
        } else -1.0
        val terminal = snapshot.status in TERMINAL_STATUSES
        val serverIp = extractServerIp(baseUrl)

        // --- title：运行/暂停 恒显示精确百分比；其他状态仅中间进度（0<x<100）显示 ---
        val statusLabel = statusText(snapshot.status)
        val percentText = if (percent >= 0) String.format(Locale.US, "%.1f%%", percent) else null
        val showPercent = percentText != null && (
            snapshot.status == "running" || snapshot.status == "paused" ||
                (percent > 0.0 && percent < 100.0)
            )
        val title = if (showPercent) "$statusLabel · $percentText" else statusLabel
        // 状态栏芯片文本（Live Updates 折叠态）遵循同一规则，保留一位小数精度
        val shortText = if (showPercent) String.format(Locale.US, "%.1f%%", percent) else statusLabel

        // --- contentText：任务名（主导信息）+ 错误 ---
        val taskName = snapshot.taskName.ifEmpty { "FFBox 转码任务" }
        val etaText = if (snapshot.remaining > 0) "剩余 ${formatDuration(snapshot.remaining)}" else null
        val contentText = buildString {
            append(taskName)
            // API < 36 没有 Live Updates 进度芯片，把百分比拼到正文
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.BAKLAVA) {
                if (percentText != null) append(" · $percentText")
            }
            if (snapshot.status == "error" && snapshot.errorMessage.isNotEmpty()) {
                append("\n${snapshot.errorMessage}")
            }
        }

        // --- subText：服务器 IP + 剩余时间（剩余时间拼接在 IP 后面） ---
        val subText = buildString {
            append(serverIp)
            if (etaText != null) {
                if (serverIp.isNotEmpty()) append(" · ")
                append(etaText)
            }
        }

        // BigTextStyle expanded（仅 API < 36 使用）
        val bigText = buildBigText(snapshot, percent)

        // --- 构建通知（各分支独立，Builder 类型不同） ---
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            buildApi36(snapshot, title, shortText, contentText, subText, terminal)
        } else {
            buildFallback(snapshot, title, contentText, bigText, subText, terminal)
        }
    }

    fun show(snapshot: TaskSnapshot, baseUrl: String) {
        notificationManager.notify(NOTIFICATION_ID, build(snapshot, baseUrl))
    }

    fun cancel() {
        notificationManager.cancel(NOTIFICATION_ID)
    }

    // --- API 36+：Live Updates ProgressStyle ---

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.BAKLAVA)
    private fun buildApi36(
        snapshot: TaskSnapshot,
        title: String,
        shortText: String,
        contentText: String,
        subText: String,
        terminal: Boolean,
    ): Notification {
        // 进度条：tracker 圆点颜色随状态变化
        val style = Notification.ProgressStyle()
            .setStyledByProgress(true)
            .setProgress(snapshot.progress.coerceAtLeast(0))
            .setProgressTrackerIcon(Icon.createWithResource(context, dotForStatus(snapshot.status)))
        if (snapshot.total > 0) {
            style.setProgressSegments(
                listOf(Notification.ProgressStyle.Segment(snapshot.total)),
            )
        }

        val builder = Notification.Builder(context, CHANNEL_ID)
            // 右上角小图标：用形状标识区分状态（颜色会被系统单色化）
            .setSmallIcon(statusIconFor(snapshot.status))
            .setContentTitle(title)
            .setContentText(contentText)
            .setSubText(subText)
            .setColor(statusColor(snapshot.status))
            .setStyle(style)
            .setContentIntent(contentIntent())
            .setOngoing(!terminal)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
            .setOnlyAlertOnce(true)
        if (!terminal) {
            builder.extras.putBoolean("android.requestPromotedOngoing", true)
        }
        if (!terminal) {
            builder.setShortCriticalText(shortText)
        }
        // 按钮按状态语义显示：运行→暂停、暂停/暂停排队→继续、等待(idle)→启动
        when (snapshot.status) {
            "running" -> builder.addAction(buildPauseAction())
            "paused", "paused_queued" -> builder.addAction(buildResumeAction())
            "idle" -> builder.addAction(buildStartAction())
        }
        return builder.build()
    }

    // --- API < 36：BigTextStyle + 普通进度通知 ---

    private fun buildFallback(
        snapshot: TaskSnapshot,
        title: String,
        contentText: String,
        bigText: String,
        subText: String,
        terminal: Boolean,
    ): Notification {
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            // 右上角小图标：用形状标识区分状态（颜色会被系统单色化）
            .setSmallIcon(statusIconFor(snapshot.status))
            .setContentTitle(title)
            .setContentText(contentText)
            .setSubText(subText)
            .setColor(statusColor(snapshot.status))
            .setContentIntent(contentIntent())
            .setOngoing(!terminal)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
            .setStyle(NotificationCompat.BigTextStyle().bigText(bigText))
            .setOnlyAlertOnce(true)
        if (snapshot.total > 0) {
            builder.setProgress(
                snapshot.total,
                snapshot.progress.coerceAtLeast(0),
                false,
            )
        }
        // 按钮按状态语义显示：运行→暂停、暂停/暂停排队→继续、等待(idle)→启动
        when (snapshot.status) {
            "running" -> builder.addAction(startActionCompat("暂停", R.drawable.ic_action_pause, LiveTaskService.ACTION_PAUSE, REQUEST_PAUSE))
            "paused", "paused_queued" -> builder.addAction(startActionCompat("继续", R.drawable.ic_action_play, LiveTaskService.ACTION_RESUME, REQUEST_RESUME))
            "idle" -> builder.addAction(startActionCompat("启动", R.drawable.ic_action_play, LiveTaskService.ACTION_START_TASK, REQUEST_START))
        }
        return builder.build()
    }

    /** API<36 构造操作按钮 Action。 */
    private fun startActionCompat(
        label: String,
        iconRes: Int,
        action: String,
        requestCode: Int,
    ): NotificationCompat.Action {
        return NotificationCompat.Action(
            iconRes,
            label,
            buildActionPendingIntent(action, requestCode),
        )
    }

    // --- 操作按钮 ---

    private fun buildPauseAction(): Notification.Action {
        val pi = buildActionPendingIntent(LiveTaskService.ACTION_PAUSE, REQUEST_PAUSE)
        return Notification.Action.Builder(
            Icon.createWithResource(context, R.drawable.ic_action_pause),
            "暂停",
            pi,
        ).build()
    }

    private fun buildResumeAction(): Notification.Action {
        val pi = buildActionPendingIntent(LiveTaskService.ACTION_RESUME, REQUEST_RESUME)
        return Notification.Action.Builder(
            Icon.createWithResource(context, R.drawable.ic_action_play),
            "继续",
            pi,
        ).build()
    }

    private fun buildStartAction(): Notification.Action {
        val pi = buildActionPendingIntent(LiveTaskService.ACTION_START_TASK, REQUEST_START)
        return Notification.Action.Builder(
            Icon.createWithResource(context, R.drawable.ic_action_play),
            "启动",
            pi,
        ).build()
    }

    private fun buildActionPendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, LiveTaskService::class.java).apply {
            this.action = action
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        // 前台服务用 getForegroundService，保证后台点击按钮也能投递 intent
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(context, requestCode, intent, flags)
        } else {
            PendingIntent.getService(context, requestCode, intent, flags)
        }
    }

    // --- 辅助 ---

    private fun buildBigText(snapshot: TaskSnapshot, percent: Double): String {
        val parts = mutableListOf<String>()
        if (snapshot.elapsed > 0 || snapshot.total > 0) {
            val elapsed = if (snapshot.elapsed > 0) formatDuration(snapshot.elapsed) else "--"
            val total = if (snapshot.total > 0) formatDuration(snapshot.total) else "--"
            parts.add("已用 $elapsed / $total")
        }
        if (percent >= 0) {
            parts.add("进度 ${String.format(Locale.US, "%.1f%%", percent)}")
        }
        if (snapshot.remaining > 0) {
            parts.add("剩余 ${formatDuration(snapshot.remaining)}")
        }
        if (snapshot.status == "error" && snapshot.errorMessage.isNotEmpty()) {
            parts.add("错误：${snapshot.errorMessage}")
        }
        return parts.joinToString("\n")
    }

    private fun contentIntent(): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** 从 baseUrl 提取服务器 IP:port。 */
    fun extractServerIp(baseUrl: String): String {
        if (baseUrl.isEmpty()) return ""
        return try {
            val uri = URI(baseUrl)
            val host = uri.host ?: return baseUrl
            val port = uri.port
            if (port > 0 && port != 80 && port != 443) "$host:$port" else host
        } catch (_: Exception) {
            val stripped = baseUrl.removePrefix("http://").removePrefix("https://")
            stripped.substringBefore("/").substringBefore("?")
        }
    }

    fun formatDuration(seconds: Int): String {
        if (seconds <= 0) return "0:00"
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val sec = seconds % 60
        return if (h > 0) {
            String.format(Locale.US, "%d:%02d:%02d", h, m, sec)
        } else {
            String.format(Locale.US, "%d:%02d", m, sec)
        }
    }

    /** 状态中文文案：与应用内 StatusBadge.labelFor 完全一致。 */
    fun statusText(status: String): String = when (status) {
        "initializing" -> "初始化"
        "idle" -> "等待"
        "idle_queued" -> "排队"
        "running" -> "运行"
        "paused" -> "暂停"
        "paused_queued" -> "暂停排队"
        "stopping" -> "停止中"
        "finishing" -> "完成中"
        "finished" -> "完成"
        "error" -> "错误"
        "deleted" -> "删除"
        "unknown" -> "连接中…"
        else -> "处理中"
    }

    /** 状态信号色：与应用内 StatusBadge.colorFor 一致（通知强调色/圆点颜色）。 */
    fun statusColor(status: String): Int = when (status) {
        "paused", "paused_queued" -> 0xFFF1C644.toInt()
        "finished" -> 0xFF3FB950.toInt()
        "error", "deleted" -> 0xFFF85149.toInt()
        else -> 0xFF4AABEA.toInt()
    }

    /** 状态对应彩色圆点图标（进度条 tracker 用，能随状态变色）。 */
    fun dotForStatus(status: String): Int = when (status) {
        "paused", "paused_queued" -> R.drawable.ic_dot_action
        "finished" -> R.drawable.ic_dot_success
        "error", "deleted" -> R.drawable.ic_dot_danger
        else -> R.drawable.ic_dot_info
    }

    /**
     * 状态对应形状标识图标（右上角 smallIcon 用）。
     *
     * Android 会对 smallIcon 强制单色化（部分 ROM 如 ColorOS 恒为白色），
     * 无法用颜色区分状态，故用不同形状标识：运行→播放、暂停→双竖条、
     * 排队→时钟、完成→对勾、错误→感叹号、等待/其他→圆点。
     */
    fun statusIconFor(status: String): Int = when (status) {
        "running" -> R.drawable.ic_status_play
        "paused", "paused_queued" -> R.drawable.ic_status_pause
        "idle_queued" -> R.drawable.ic_status_clock
        "finished" -> R.drawable.ic_status_done
        "error", "deleted" -> R.drawable.ic_status_warn
        else -> R.drawable.ic_status_dot
    }
}
