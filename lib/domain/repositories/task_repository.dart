import 'package:ffbox_edgelink/domain/entities/task.dart';

/// 任务仓储抽象接口。声明全部后端任务操作，
/// 首版 UI 仅暴露基本操作，其余操作供后续功能接入。
abstract interface class TaskRepository {
  /// 获取任务 ID 列表（支持分页）。
  /// [offset] 起始条目（从 0 开始），[size] 每页返回数量。
  /// [silent] 为 true 时不记录请求/响应日志。
  Future<List<int>> listTaskIds({
    int offset = 0,
    int size = 100,
    bool silent = false,
  });

  /// 获取单个任务详情。
  /// [silent] 为 true 时不记录请求/响应日志。
  Future<Task> getTask(int id, {bool silent = false});

  /// 批量操作（启动、暂停、继续、删除、排队、重置）。
  Future<void> deleteTasks(List<int> ids);
  Future<void> startTasks(List<int> ids);
  Future<void> readyTasks(List<int> ids);
  Future<void> pauseTasks(List<int> ids);
  Future<void> resumeTasks(List<int> ids);
  Future<void> resetTasks(List<int> ids);
}
