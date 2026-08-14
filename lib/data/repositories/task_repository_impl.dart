import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';

class TaskRepositoryImpl implements TaskRepository {
  final FFBoxApi _api;

  TaskRepositoryImpl(this._api);

  @override
  Future<List<int>> listTaskIds() => _api.listTaskIds();

  @override
  Future<Task> getTask(int id) async {
    final task = await _api.getTask(id);
    return task.copyWith(id: id);
  }

  @override
  Future<int> createTask({required String taskName, Map<String, dynamic>? outputParams}) =>
      _api.createTask(taskName, outputParams);

  @override
  Future<void> deleteTask(int id) => _api.deleteTask(id);

  @override
  Future<void> startTask(int id) => _api.startTask(id);

  @override
  Future<void> readyTask(int id) => _api.readyTask(id);

  @override
  Future<void> pauseTask(int id) => _api.pauseTask(id);

  @override
  Future<void> resumeTask(int id) => _api.resumeTask(id);

  @override
  Future<void> resetTask(int id) => _api.resetTask(id);
}
