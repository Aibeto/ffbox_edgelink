import 'dart:convert';

/// 实时活动配置：描述「哪台服务器、哪个任务」进入实时通知模式。
///
/// 由 Flutter 侧经 MethodChannel 下发到 Android 原生前台服务，
/// 原生服务据此轮询任务详情并渲染 Live Updates 通知。
class LiveActivityConfig {
  final String baseUrl;
  final String sessionId;
  final int taskId;
  final String taskName;

  const LiveActivityConfig({
    required this.baseUrl,
    required this.sessionId,
    required this.taskId,
    required this.taskName,
  });

  Map<String, dynamic> toMap() => {
    'baseUrl': baseUrl,
    'sessionId': sessionId,
    'taskId': taskId,
    'taskName': taskName,
  };

  factory LiveActivityConfig.fromJsonString(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return LiveActivityConfig(
      baseUrl: map['baseUrl'] as String? ?? '',
      sessionId: map['sessionId'] as String? ?? '',
      taskId: (map['taskId'] as num?)?.toInt() ?? 0,
      taskName: map['taskName'] as String? ?? '',
    );
  }
}
