/// 服务端转码配置（对应后端 `/api/v1/settings/server` 的 ServerSettingsData）。
class ServerSettings {
  /// 最大并发转码任务数。
  final int maxThreads;

  /// FFmpeg 可执行文件所在目录（空则按 PATH 查找；内置服务自动指向内置二进制）。
  final String customFFmpegPath;

  /// 保留未完成任务（服务重启后继续转码）。
  final bool preserveUnfinishedTasks;

  /// 自动删除已完成任务。
  final bool deleteFinishedTasks;

  const ServerSettings({
    this.maxThreads = 1,
    this.customFFmpegPath = '',
    this.preserveUnfinishedTasks = true,
    this.deleteFinishedTasks = false,
  });

  /// 从后端返回的 JSON 构造。
  factory ServerSettings.fromJson(Map<String, dynamic> json) {
    return ServerSettings(
      maxThreads: (json['maxThreads'] as num?)?.toInt() ?? 1,
      customFFmpegPath: json['customFFmpegPath'] as String? ?? '',
      // 与 FFBox 前端一致：preserveUnfinishedTasks 缺失/undefined 视为 true
      preserveUnfinishedTasks:
          json['preserveUnfinishedTasks'] as bool? ?? true,
      deleteFinishedTasks: json['deleteFinishedTasks'] as bool? ?? false,
    );
  }

  /// 序列化为请求体 JSON。
  Map<String, dynamic> toJson() => {
    'maxThreads': maxThreads,
    'customFFmpegPath': customFFmpegPath,
    'preserveUnfinishedTasks': preserveUnfinishedTasks,
    'deleteFinishedTasks': deleteFinishedTasks,
  };

  /// 复制并替换部分字段。
  ServerSettings copyWith({
    int? maxThreads,
    String? customFFmpegPath,
    bool? preserveUnfinishedTasks,
    bool? deleteFinishedTasks,
  }) {
    return ServerSettings(
      maxThreads: maxThreads ?? this.maxThreads,
      customFFmpegPath: customFFmpegPath ?? this.customFFmpegPath,
      preserveUnfinishedTasks:
          preserveUnfinishedTasks ?? this.preserveUnfinishedTasks,
      deleteFinishedTasks:
          deleteFinishedTasks ?? this.deleteFinishedTasks,
    );
  }
}
