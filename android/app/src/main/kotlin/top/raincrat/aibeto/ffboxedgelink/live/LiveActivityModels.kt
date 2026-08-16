package top.raincrat.aibeto.ffboxedgelink.live

import org.json.JSONObject

/** 任务状态快照：前台服务轮询解析结果，驱动通知渲染。 */
data class TaskSnapshot(
    val taskName: String,
    val status: String,
    /** 已处理媒体时长（毫秒）。 */
    val progress: Int,
    /** 输入媒体总时长（毫秒），未知为 0。 */
    val total: Int,
    /** 已用时长（毫秒）。 */
    val elapsed: Int,
    /** 预估剩余（毫秒），未知为 -1。 */
    val remaining: Int,
    /** 错误信息首行（仅 error 状态展示）。 */
    val errorMessage: String,
)

/** 实时活动配置：由 Flutter 侧经 MethodChannel 下发。 */
data class LiveActivityConfig(
    val baseUrl: String,
    val sessionId: String,
    val taskId: Int,
    val taskName: String,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("baseUrl", baseUrl)
        put("sessionId", sessionId)
        put("taskId", taskId)
        put("taskName", taskName)
    }

    companion object {
        fun fromJson(json: JSONObject): LiveActivityConfig = LiveActivityConfig(
            baseUrl = json.optString("baseUrl"),
            sessionId = json.optString("sessionId"),
            taskId = json.optInt("taskId"),
            taskName = json.optString("taskName"),
        )
    }
}
