import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';

class TaskRepositoryImpl implements TaskRepository {
  final FFBoxApi _api;

  TaskRepositoryImpl(this._api);

  @override
  Future<List<int>> listTaskIds({int offset = 0, int size = 100}) =>
      _api.listTaskIds(offset: offset, size: size);

  @override
  Future<Task> getTask(int id) => _api.getTask(id);

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
}
