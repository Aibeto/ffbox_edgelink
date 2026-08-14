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

  /// 分页加载每页的任务数量。
  static const int _pageSize = 100;

  /// 拉取全部任务：分页获取 ID 列表，再逐条取详情。
  Future<TaskLoadResult> loadTasks() async {
    final sw = Stopwatch()..start();

    // 分页获取所有任务 ID
    final allIds = <int>[];
    var offset = 0;
    while (true) {
      final ids = await _repository.listTaskIds(
        offset: offset,
        size: _pageSize,
      );
      allIds.addAll(ids);
      logDebug(
        'loadTasks: offset=$offset, 本页${ids.length}项, 累计${allIds.length}项',
      );
      if (ids.length < _pageSize) break;
      offset += _pageSize;
    }

    sw.stop();
    final latencyMs = sw.elapsedMilliseconds;
    logDebug('loadTasks: 共${allIds.length}项, latency=${latencyMs}ms');

    final tasks = <Task>[];
    var failed = 0;
    for (final id in allIds) {
      try {
        tasks.add(await _repository.getTask(id));
      } catch (e) {
        failed++;
        logDebug('loadTasks: task $id failed: $e');
      }
    }
    logDebug('loadTasks done: ${tasks.length} ok, $failed failed');
    return TaskLoadResult(
      tasks: tasks,
      failedCount: failed,
      latencyMs: latencyMs,
    );
  }

  /// 分页获取所有任务 ID（用于操作确认等场景）。
  Future<List<int>> _fetchAllIds() async {
    final allIds = <int>[];
    var offset = 0;
    while (true) {
      final ids = await _repository.listTaskIds(
        offset: offset,
        size: _pageSize,
      );
      allIds.addAll(ids);
      if (ids.length < _pageSize) break;
      offset += _pageSize;
    }
    return allIds;
  }

  /// 判断某状态是否可执行某操作。
  bool canExecute(TaskStatus status, TaskOperation operation) =>
      TaskStateMachine.canExecute(status, operation);

  Future<void> start(int id) {
    logDebug('task.start id=$id');
    return _repository.startTasks([id]);
  }

  Future<void> pause(int id) {
    logDebug('task.pause id=$id');
    return _repository.pauseTasks([id]);
  }

  Future<void> resume(int id) {
    logDebug('task.resume id=$id');
    return _repository.resumeTasks([id]);
  }

  Future<void> delete(int id) {
    logDebug('task.delete id=$id');
    return _repository.deleteTasks([id]);
  }

  Future<void> ready(int id) {
    logDebug('task.ready id=$id');
    return _repository.readyTasks([id]);
  }

  Future<void> reset(int id) {
    logDebug('task.reset id=$id');
    return _repository.resetTasks([id]);
  }

  /// 执行任务操作并给出三态结果。
  ///
  /// [onStatus] 用于向 UI 回传阶段提示（等待中 / 确认中）。
  Future<TaskOperationOutcome> executeOperation(
    int id,
    TaskOperation op, {
    void Function(String message)? onStatus,
  }) async {
    try {
      await _execute(op, id);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        logDebug('executeOperation id=$id op=$op -> unauthorized (401/403)');
        return TaskOperationOutcome.failed(
          e.friendlyMessage,
          unauthorized: true,
        );
      }
      if (e.statusCode != null) {
        logDebug(
          'executeOperation id=$id op=$op -> rejected (${e.statusCode}) ${e.friendlyMessage}',
        );
        return TaskOperationOutcome.failed(e.friendlyMessage);
      }
      logDebug(
        'executeOperation id=$id op=$op -> uncertain (timeout/connection), confirming...',
      );
      onStatus?.call('请求超时，正在确认任务状态...');
      return _confirmOperation(id, op);
    } catch (e) {
      logDebug('executeOperation id=$id op=$op -> unexpected error: $e');
      onStatus?.call('请求异常，正在确认任务状态...');
      return _confirmOperation(id, op);
    }

    logDebug('executeOperation id=$id op=$op -> 200 OK, confirming...');
    onStatus?.call('正在确认任务状态...');
    return _confirmOperation(id, op);
  }

  Future<void> _execute(TaskOperation op, int id) => switch (op) {
    TaskOperation.start => _repository.startTasks([id]),
    TaskOperation.pause => _repository.pauseTasks([id]),
    TaskOperation.resume => _repository.resumeTasks([id]),
    TaskOperation.delete => _repository.deleteTasks([id]),
    TaskOperation.ready => _repository.readyTasks([id]),
    TaskOperation.reset => _repository.resetTasks([id]),
    _ => Future.value(),
  };

  bool _tookEffect(TaskOperation op, TaskStatus status) => switch (op) {
    TaskOperation.start => status == TaskStatus.running,
    TaskOperation.pause => status == TaskStatus.paused,
    TaskOperation.resume => status == TaskStatus.running,
    TaskOperation.ready =>
      status == TaskStatus.idleQueued || status == TaskStatus.pausedQueued,
    TaskOperation.reset => status == TaskStatus.idle,
    TaskOperation.delete => false,
    _ => true,
  };

  Future<TaskOperationOutcome> _confirmOperation(
    int id,
    TaskOperation op,
  ) async {
    if (op == TaskOperation.delete) {
      try {
        final ids = await _fetchAllIds();
        if (!ids.contains(id)) {
          logDebug('confirm delete id=$id -> success (removed)');
          return TaskOperationOutcome.success('删除已生效');
        }
        logDebug('confirm delete id=$id -> failed (still exists)');
        return TaskOperationOutcome.failed('删除未生效，任务仍存在');
      } catch (e) {
        logDebug('confirm delete id=$id -> unconfirmed: $e');
        return TaskOperationOutcome.unconfirmed('操作结果未知，请手动刷新确认');
      }
    }

    try {
      final task = await _repository.getTask(id);
      if (_tookEffect(op, task.status)) {
        logDebug(
          'confirm op=$op id=$id -> success (status=${task.status.apiValue})',
        );
        return TaskOperationOutcome.success(
          '操作已生效，当前状态：${task.status.apiValue}',
          confirmedTask: task,
        );
      }
      logDebug(
        'confirm op=$op id=$id -> failed (status=${task.status.apiValue})',
      );
      return TaskOperationOutcome.failed('操作未生效，当前状态：${task.status.apiValue}');
    } catch (e) {
      logDebug('confirm op=$op id=$id -> unconfirmed: $e');
      return TaskOperationOutcome.unconfirmed('操作结果未知，请手动刷新确认');
    }
  }
}
