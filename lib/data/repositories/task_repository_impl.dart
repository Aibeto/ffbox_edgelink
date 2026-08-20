import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';

/// TaskRepository 的具体实现。
///
/// 纯委托转发层：将接口调用直接转发给 [FFBoxApi]，
/// 不含额外业务逻辑，便于未来替换数据源或添加拦截。
class TaskRepositoryImpl implements TaskRepository {
  final FFBoxApi _api;

  TaskRepositoryImpl(this._api);

  @override
  Future<List<int>> listTaskIds({
    int offset = 0,
    int size = 100,
    bool silent = false,
  }) => _api.listTaskIds(offset: offset, size: size, silent: silent);

  @override
  Future<Task> getTask(int id, {bool silent = false}) =>
      _api.getTask(id, silent: silent);

  @override
  Future<void> deleteTasks(List<int> ids) => _api.deleteTasks(ids);
  @override
  Future<void> startTasks(List<int> ids) => _api.startTasks(ids);
  @override
  Future<void> readyTasks(List<int> ids) => _api.readyTasks(ids);
  @override
  Future<void> pauseTasks(List<int> ids) => _api.pauseTasks(ids);
  @override
  Future<void> resumeTasks(List<int> ids) => _api.resumeTasks(ids);
  @override
  Future<void> resetTasks(List<int> ids) => _api.resetTasks(ids);

  @override
  Future<List<int>> createTasks(
    List<String> filePaths,
    Map<String, dynamic>? outputParams,
  ) => _api.createTasks(filePaths, outputParams);

  @override
  Future<void> downloadOutputFile({
    required int taskId,
    required int runIndex,
    required int outputIndex,
    required String savePath,
    void Function(int count, int total)? onProgress,
  }) => _api.downloadOutputFile(
    taskId: taskId,
    runIndex: runIndex,
    outputIndex: outputIndex,
    savePath: savePath,
    onProgress: onProgress,
  );
}
