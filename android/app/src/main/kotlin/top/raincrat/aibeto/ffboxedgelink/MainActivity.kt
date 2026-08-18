package top.raincrat.aibeto.ffboxedgelink

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import top.raincrat.aibeto.ffboxedgelink.live.LiveActivityChannel
import top.raincrat.aibeto.ffboxedgelink.upload.UploadNotificationChannel

// Flutter 宿主 Activity：注册实时活动与上传通知 MethodChannel，转发通知权限结果。
class MainActivity : FlutterActivity() {
    private lateinit var liveActivityChannel: LiveActivityChannel
    private lateinit var uploadNotificationChannel: UploadNotificationChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        liveActivityChannel = LiveActivityChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        ).also { it.register() }
        uploadNotificationChannel = UploadNotificationChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        ).also { it.register() }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        liveActivityChannel.onRequestPermissionsResult(requestCode, grantResults)
    }
}
