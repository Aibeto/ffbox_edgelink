import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_operation.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';
import 'package:ffbox_edgelink/application/task/task_state_machine.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';

class TaskLoadResult {
  final List<Task> tasks;
  final int failedCount;
  final int latencyMs;

  const TaskLoadResult({
    required this.tasks,
    this.failedCount = 0,
    this.latencyMs = 0,
  });
}

/// 任务操作结果状态。
enum OperationOutcomeStatus { success, failed, unconfirmed }

/// 任务操作结果（三态，处理超时后的不确定性）。
class TaskOperationOutcome {
  final OperationOutcomeStatus status;
  final String message;
  final Task? confirmedTask;

  /// 会话失效（401/403），UI 应触发登出跳转。
  final bool unauthorized;

  const TaskOperationOutcome._(
    this.status,
    this.message, {
    this.confirmedTask,
    this.unauthorized = false,
  });

  factory TaskOperationOutcome.success(String message, {Task? confirmedTask}) =>
      TaskOperationOutcome._(
        OperationOutcomeStatus.success,
        message,
        confirmedTask: confirmedTask,
      );

  factory TaskOperationOutcome.failed(
    String message, {
    bool unauthorized = false,
  }) => TaskOperationOutcome._(
    OperationOutcomeStatus.failed,
    message,
    unauthorized: unauthorized,
  );

  factory TaskOperationOutcome.unconfirmed(String message) =>
      TaskOperationOutcome._(OperationOutcomeStatus.unconfirmed, message);
}

/// 任务业务逻辑（纯 Dart）。UI 通过它执行任务操作并判断可用性。
class TaskService {
  final TaskRepository _repository;

  TaskService(this._repository);

  /// 拉取全部任务：先取 ID 列表，再逐条取详情。
  Future<TaskLoadResult> loadTasks() async {
    final sw = Stopwatch()..start();
    final ids = await _repository.listTaskIds();
    sw.stop();
    final latencyMs = sw.elapsedMilliseconds;

    final tasks = <Task>[];
    var failed = 0;
    for (final id in ids) {
      try {
        tasks.add(await _repository.getTask(id));
      } catch (e) {
        failed++;
        logDebug('loadTasks: task $id failed: $e');
      }
    }
    return TaskLoadResult(
      tasks: tasks,
      failedCount: failed,
      latencyMs: latencyMs,
    );
  }

  /// 判断某状态是否可执行某操作。
  bool canExecute(TaskStatus status, TaskOperation operation) =>
      TaskStateMachine.canExecute(status, operation);

  Future<void> start(int id) {
    logDebug('task.start id=$id');
    return _repository.startTask(id);
  }

  Future<void> pause(int id) {
    logDebug('task.pause id=$id');
    return _repository.pauseTask(id);
  }

  Future<void> resume(int id) {
    logDebug('task.resume id=$id');
    return _repository.resumeTask(id);
  }

  Future<void> delete(int id) {
    logDebug('task.delete id=$id');
    return _repository.deleteTask(id);
  }

  Future<void> ready(int id) {
    logDebug('task.ready id=$id');
    return _repository.readyTask(id);
  }

  Future<void> reset(int id) {
    logDebug('task.reset id=$id');
    return _repository.resetTask(id);
  }

  Future<int> create({
    required String taskName,
    Map<String, dynamic>? outputParams,
  }) => _repository.createTask(taskName: taskName, outputParams: outputParams);

  /// 执行任务操作并给出三态结果。
  ///
  /// [onStatus] 用于向 UI 回传阶段提示（等待中 / 确认中）。
  Future<TaskOperationOutcome> executeOperation(
    int id,
    TaskOperation op, {
    void Function(String message)? onStatus,
  }) async {
    onStatus?.call('正在${_verb(op)}...');
    try {
      await _execute(op, id);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        // 会话失效：标记为需登出，由 UI 统一处理跳转
        return TaskOperationOutcome.failed(
          e.friendlyMessage,
          unauthorized: true,
        );
      }
      // 确定性失败：服务器明确拒绝（400/403/500...）
      if (e.statusCode != null) {
        return TaskOperationOutcome.failed(e.friendlyMessage);
      }
      // 不确定性失败：超时/连接错误 → 查询确认
      onStatus?.call('请求超时，正在确认任务状态...');
      return _confirmOperation(id, op);
    } catch (_) {
      onStatus?.call('请求异常，正在确认任务状态...');
      return _confirmOperation(id, op);
    }

    // POST 返回 200：服务器总是返回 success，仍需查询确认实际状态
    onStatus?.call('正在确认任务状态...');
    return _confirmOperation(id, op);
  }

  Future<void> _execute(TaskOperation op, int id) => switch (op) {
    TaskOperation.start => _repository.startTask(id),
    TaskOperation.pause => _repository.pauseTask(id),
    TaskOperation.resume => _repository.resumeTask(id),
    TaskOperation.delete => _repository.deleteTask(id),
    TaskOperation.ready => _repository.readyTask(id),
    TaskOperation.reset => _repository.resetTask(id),
    _ => Future.value(),
  };

  String _verb(TaskOperation op) => switch (op) {
    TaskOperation.start => '启动',
    TaskOperation.pause => '暂停',
    TaskOperation.resume => '继续',
    TaskOperation.delete => '删除',
    TaskOperation.ready => '排队',
    TaskOperation.reset => '重置',
    _ => '操作',
  };

  bool _tookEffect(TaskOperation op, TaskStatus status) => switch (op) {
    TaskOperation.start => status == TaskStatus.running,
    TaskOperation.pause => status == TaskStatus.paused,
    TaskOperation.resume => status == TaskStatus.running,
    TaskOperation.ready =>
      status == TaskStatus.idleQueued || status == TaskStatus.pausedQueued,
    TaskOperation.reset => status == TaskStatus.idle,
    TaskOperation.delete => false, // delete 单独处理
    _ => true,
  };

  Future<TaskOperationOutcome> _confirmOperation(
    int id,
    TaskOperation op,
  ) async {
    // 删除：通过「任务是否还在列表中」确认
    if (op == TaskOperation.delete) {
      try {
        final ids = await _repository.listTaskIds();
        if (!ids.contains(id)) {
          return TaskOperationOutcome.success('删除已生效');
        }
        return TaskOperationOutcome.failed('删除未生效，任务仍存在');
      } catch (_) {
        return TaskOperationOutcome.unconfirmed('操作结果未知，请手动刷新确认');
      }
    }

    // 其他操作：重新拉取任务，比对状态
    try {
      final task = await _repository.getTask(id);
      if (_tookEffect(op, task.status)) {
        return TaskOperationOutcome.success(
          '操作已生效，当前状态：${task.status.apiValue}',
          confirmedTask: task,
        );
      }
      return TaskOperationOutcome.failed('操作未生效，当前状态：${task.status.apiValue}');
    } catch (_) {
      return TaskOperationOutcome.unconfirmed('操作结果未知，请手动刷新确认');
    }
  }
}
