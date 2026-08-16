import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffbox_edgelink/application/task/task_service.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/screens/task_detail_screen.dart';

class _ErrRepo implements TaskRepository {
  final bool emptyErrorInfo;
  _ErrRepo({this.emptyErrorInfo = false});

  @override
  Future<List<int>> listTaskIds({
    int offset = 0,
    int size = 100,
    bool silent = false,
  }) async => const [0];

  @override
  Future<Task> getTask(int id, {bool silent = false}) async => Task.fromJson({
    'id': id,
    'taskName': 'err-task',
    'status': 'error',
    'before': [
      {'filePath': 'in.flv', 'duration': 100},
    ],
    'runs': [
      {'status': 'idle'},
      {
        'status': 'error',
        'elapsed': 50,
        'errorInfo': emptyErrorInfo ? [] : ['转码失败：编码器错误'],
        'outputFiles': [],
      },
    ],
  });

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
  testWidgets('error task detail shows error card', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _ErrRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskRepositoryProvider.overrideWith((ref) => repo),
          taskServiceProvider.overrideWith((ref) => TaskService(repo)),
        ],
        child: const MaterialApp(home: TaskDetailScreen(taskId: 0)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // ignore: avoid_print
    print(
      'DEBUG texts found: '
      '错误信息=${find.text('错误信息').evaluate().length} '
      '错误卡片=${find.text('转码失败：编码器错误').evaluate().length}',
    );
    expect(find.text('错误信息'), findsOneWidget);
    expect(find.text('转码失败：编码器错误'), findsOneWidget);
  });

  testWidgets('error task with empty errorInfo still shows error card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _ErrRepo(emptyErrorInfo: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskRepositoryProvider.overrideWith((ref) => repo),
          taskServiceProvider.overrideWith((ref) => TaskService(repo)),
        ],
        child: const MaterialApp(home: TaskDetailScreen(taskId: 0)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('错误信息'), findsOneWidget);
    expect(find.text('任务失败，请查看转码日志'), findsOneWidget);
  });
}
