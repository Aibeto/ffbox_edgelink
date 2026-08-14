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
    final progressLog = (json['progressLog'] as Map<String, dynamic>?) ?? const {};
    return Task(
      taskName: json['taskName'] as String? ?? '',
      status: TaskStatus.parse(json['status'] as String? ?? 'idle'),
      elapsedSeconds: (progressLog['elapsed'] as num?)?.toDouble() ?? 0,
      errorInfo: (json['errorInfo'] as List?)?.cast<String>() ?? const [],
      outputFiles: (json['outputFiles'] as List?)?.cast<String>() ?? const [],
    );
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
