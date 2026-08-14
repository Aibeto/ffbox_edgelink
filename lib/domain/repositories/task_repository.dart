import 'package:ffbox_edgelink/domain/entities/task.dart';

/// 任务仓储抽象接口。声明全部后端任务操作，
/// 首版 UI 仅暴露基本操作，其余操作供后续功能接入。
abstract interface class TaskRepository {
  /// 获取任务 ID 列表。
  Future<List<int>> listTaskIds();

  /// 获取单个任务详情。
  Future<Task> getTask(int id);

  /// 创建新任务（预留，当前 UI 不暴露）。
  Future<int> createTask({required String taskName, Map<String, dynamic>? outputParams});

  Future<void> deleteTask(int id);
  Future<void> startTask(int id);
  Future<void> readyTask(int id);
  Future<void> pauseTask(int id);
  Future<void> resumeTask(int id);
  Future<void> resetTask(int id);
}
