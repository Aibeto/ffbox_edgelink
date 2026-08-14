import 'package:flutter_test/flutter_test.dart';
import 'package:ffbox_edgelink/application/task/task_service.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';

class _FakeTaskRepo implements TaskRepository {
  @override
  Future<List<int>> listTaskIds() async => [1, 2];
  @override
  Future<Task> getTask(int id) async =>
      Task(taskName: 't$id', status: TaskStatus.idle);
  @override
  Future<int> createTask({required String taskName, Map<String, dynamic>? outputParams}) async => 99;
  @override
  Future<void> deleteTask(int id) async {}
  @override
  Future<void> startTask(int id) async {}
  @override
  Future<void> readyTask(int id) async {}
  @override
  Future<void> pauseTask(int id) async {}
  @override
  Future<void> resumeTask(int id) async {}
  @override
  Future<void> resetTask(int id) async {}
}

void main() {
  test('loadTasks fetches each task detail', () async {
    final service = TaskService(_FakeTaskRepo());
    final result = await service.loadTasks();
    expect(result.tasks.length, 2);
    expect(result.tasks[0].taskName, 't1');
    expect(result.tasks[1].taskName, 't2');
    expect(result.latencyMs, greaterThanOrEqualTo(0));
  });
}
