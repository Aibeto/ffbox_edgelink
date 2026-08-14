import 'package:ffbox_edgelink/domain/entities/task_status.dart';

class Task {
  final int id;
  final String taskName;
  final TaskStatus status;
  final double elapsedSeconds;
  final List<String> errorInfo;
  final List<String> outputFiles;

  const Task({
    this.id = 0,
    required this.taskName,
    required this.status,
    this.elapsedSeconds = 0,
    this.errorInfo = const [],
    this.outputFiles = const [],
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    // errorInfo 和 outputFiles 在 Run 对象上，取第一个 Run 的值
    final runs = json['runs'] as List<dynamic>?;
    final firstRun = (runs != null && runs.isNotEmpty)
        ? runs[0] as Map<String, dynamic>
        : null;

    return Task(
      taskName: json['taskName'] as String? ?? '',
      status: _parseStatus(json['status']),
      elapsedSeconds: _parseElapsed(firstRun),
      errorInfo: _toStringList(firstRun?['errorInfo']),
      outputFiles: _toStringList(firstRun?['outputFiles']),
    );
  }

  /// 安全地解析 elapsed，容忍 num 或 null。
  static double _parseElapsed(Map<String, dynamic>? run) {
    if (run == null) return 0;
    final elapsed = run['elapsed'];
    if (elapsed is num) return elapsed.toDouble();
    return 0;
  }

  /// 安全地解析状态，容忍字符串、数字或 null。
  static TaskStatus _parseStatus(dynamic value) {
    if (value is String) {
      try {
        return TaskStatus.parse(value);
      } catch (_) {
        return TaskStatus.idle;
      }
    }
    if (value is num) {
      const values = TaskStatus.values;
      final index = value.toInt();
      if (index >= 0 && index < values.length) return values[index];
    }
    return TaskStatus.idle;
  }

  /// 安全地将动态值转为 String 列表，容忍 List、Map 或 null。
  static List<String> _toStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }

  Task copyWith({int? id}) => Task(
    id: id ?? this.id,
    taskName: taskName,
    status: status,
    elapsedSeconds: elapsedSeconds,
    errorInfo: errorInfo,
    outputFiles: outputFiles,
  );
}
