import 'package:ffbox_edgelink/domain/entities/task_operation.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';

/// 任务状态机：根据后端 API 文档中的状态迁移约束，
/// 给出某个状态下允许执行的操作集合。
///
/// 该逻辑为纯函数、与 Riverpod/Bloc 无关，可独立单测并在多种
/// 状态管理方案间复用。
class TaskStateMachine {
  TaskStateMachine._();

  static const Map<TaskStatus, Set<TaskOperation>> _allowed = {
    TaskStatus.initializing: {TaskOperation.delete},
    TaskStatus.idle: {TaskOperation.start, TaskOperation.ready, TaskOperation.delete},
    TaskStatus.idleQueued: {TaskOperation.start, TaskOperation.delete},
    TaskStatus.running: {TaskOperation.pause},
    TaskStatus.paused: {TaskOperation.resume, TaskOperation.ready, TaskOperation.reset},
    TaskStatus.pausedQueued: {TaskOperation.pause, TaskOperation.resume, TaskOperation.reset},
    TaskStatus.stopping: {TaskOperation.reset},
    TaskStatus.finishing: {},
    TaskStatus.finished: {TaskOperation.reset, TaskOperation.delete},
    TaskStatus.error: {TaskOperation.start, TaskOperation.reset, TaskOperation.delete},
    TaskStatus.deleted: {},
  };

  static Set<TaskOperation> allowedOperations(TaskStatus status) =>
      _allowed[status] ?? const {};

  static bool canExecute(TaskStatus status, TaskOperation operation) =>
      allowedOperations(status).contains(operation);
}
