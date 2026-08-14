import 'package:flutter_test/flutter_test.dart';
import 'package:ffbox_edgelink/application/task/task_service.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';

class _FakeTaskRepo implements TaskRepository {
  @override
  Future<List<int>> listTaskIds({int offset = 0, int size = 100}) async => [
    1,
    2,
  ];
  @override
  Future<Task> getTask(int id) async =>
      Task(taskName: 't$id', status: TaskStatus.idle);
  @override
  Future<void> deleteTasks(List<int> ids) async {}
  @override
  Future<void> startTasks(List<int> ids) async {}
  @override
  Future<void> readyTasks(List<int> ids) async {}
  @override
  Future<void> pauseTasks(List<int> ids) async {}
  @override
  Future<void> resumeTasks(List<int> ids) async {}
  @override
  Future<void> resetTasks(List<int> ids) async {}
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
