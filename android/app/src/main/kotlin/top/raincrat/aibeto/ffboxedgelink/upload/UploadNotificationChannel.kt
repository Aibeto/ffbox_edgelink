package top.raincrat.aibeto.ffboxedgelink.upload

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import top.raincrat.aibeto.ffboxedgelink.R

// 上传进度通知 MethodChannel：Dart 侧节流调用 show/cancel，固定 ID 3003。
// 普通进度通知（非前台服务、非 Live Updates），静默 channel 不打扰用户。
// 注意：3002 为内置本地服务前台通知（LocalNodeService），实时活动为 3001，
// 不可复用，否则上传进度会覆盖前台服务通知。
class UploadNotificationChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "top.raincrat.aibeto.ffboxedgelink/upload_notification"
        const val CHANNEL_ID = "upload"
        const val NOTIFICATION_ID = 3003
    }

    private val channel = MethodChannel(messenger, CHANNEL_NAME).also {
        it.setMethodCallHandler(this)
    }

    fun register() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "上传进度",
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "show" -> {
                show(
                    title = call.argument<String>("title") ?: "FFBox 上传任务",
                    content = call.argument<String>("content") ?: "",
                    progress = call.argument<Int>("progress") ?: 0,
                    indeterminate = call.argument<Boolean>("indeterminate") ?: false,
                )
                result.success(null)
            }
            "cancel" -> {
                NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun show(title: String, content: String, progress: Int, indeterminate: Boolean) {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_status_upload)
            .setContentTitle(title)
            .setContentText(content)
            .setProgress(100, progress.coerceIn(0, 100), indeterminate)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // 权限被撤销时静默跳过
        }
    }
}
