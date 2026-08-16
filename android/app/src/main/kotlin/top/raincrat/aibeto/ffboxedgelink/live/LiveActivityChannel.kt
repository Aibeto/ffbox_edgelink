package top.raincrat.aibeto.ffboxedgelink.live

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * 实时活动 MethodChannel：桥接 Flutter 侧开关与原生前台服务。
 *
 * 方法：
 *  - startLiveActivity(config): 校验通知权限 → 启动/替换前台服务（只允许一条）
 *  - stopLiveActivity(): 停止前台服务并移除通知
 *  - isLiveActivityRunning(): 查询服务是否在运行
 *  - getActiveConfig(): 读取当前活跃配置（App 重启后恢复 UI 状态）
 */
class LiveActivityChannel(
    private val activity: Activity,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "LiveActivityChannel"
        const val CHANNEL = "top.raincrat.aibeto.ffboxedgelink/live_activity"
        private const val REQUEST_NOTIFICATION_PERMISSION = 9001
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    /** 权限异步请求中挂起的 result。 */
    private var pendingPermissionResult: MethodChannel.Result? = null

    fun register() {
        channel.setMethodCallHandler(this)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_NOTIFICATION_PERMISSION) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startLiveActivity" -> start(call.arguments as? Map<*, *>, result)
            "stopLiveActivity" -> {
                stopService()
                result.success(null)
            }
            "isLiveActivityRunning" -> result.success(LiveTaskService.isServiceRunning)
            "getActiveConfig" -> result.success(loadStoredConfig()?.toJson()?.let(JSONObject::toString))
            else -> result.notImplemented()
        }
    }

    private fun start(args: Map<*, *>?, result: MethodChannel.Result) {
        val config = parseConfig(args)
        if (config == null) {
            result.success(false)
            return
        }
        if (!hasNotificationPermission()) {
            pendingPermissionResult = result
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_NOTIFICATION_PERMISSION,
            )
            return
        }
        startService(config)
        result.success(true)
    }

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun startService(config: LiveActivityConfig) {
        val intent = Intent(activity, LiveTaskService::class.java).apply {
            action = LiveTaskService.ACTION_START
            putExtra(LiveTaskService.EXTRA_CONFIG, config.toJson().toString())
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startForegroundService(intent)
        } else {
            activity.startService(intent)
        }
    }

    private fun stopService() {
        val intent = Intent(activity, LiveTaskService::class.java).apply {
            action = LiveTaskService.ACTION_STOP
        }
        activity.startService(intent)
    }

    private fun parseConfig(args: Map<*, *>?): LiveActivityConfig? {
        if (args == null) return null
        return try {
            val json = JSONObject()
            for ((k, v) in args) {
                if (k is String && v != null) json.put(k, v)
            }
            LiveActivityConfig.fromJson(json)
        } catch (e: Exception) {
            Log.e(TAG, "配置解析失败", e)
            null
        }
    }

    /** 从 SharedPreferences 读取上次的活跃配置（App 重启恢复用）。 */
    private fun loadStoredConfig(): LiveActivityConfig? {
        return try {
            val prefs = activity.getSharedPreferences(
                LiveTaskService.PREFS_NAME,
                Context.MODE_PRIVATE,
            )
            val json = prefs.getString(LiveTaskService.KEY_CONFIG, null) ?: return null
            LiveActivityConfig.fromJson(JSONObject(json))
        } catch (e: Exception) {
            Log.e(TAG, "读取存储配置失败", e)
            null
        }
    }
}
