import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffbox_edgelink/application/task/task_service.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/screens/task_detail_screen.dart';
import 'package:ffbox_edgelink/presentation/widgets/status_badge.dart';

class _FakeTaskRepo implements TaskRepository {
  int getTaskCalls = 0;

  @override
  Future<List<int>> listTaskIds({
    int offset = 0,
    int size = 100,
    bool silent = false,
  }) async => const [0];

  @override
  Future<Task> getTask(int id, {bool silent = false}) async {
    getTaskCalls++;
    return Task(
      id: id,
      taskName: 'demo-task',
      status: TaskStatus.running,
      elapsedSeconds: 100,
      durationSeconds: 1000,
      processedSeconds: 100,
      outputFiles: const ['E:/out.mp4'],
      inputs: const [
        TaskInputInfo(
          filePath: 'E:/in.flv',
          demuxer: 'flv',
          duration: 1000,
          streams: [
            TaskStreamInfo(
              type: 'Video',
              codec: 'h264',
              resolution: '1920x1080',
              bitrate: 4096000,
              fps: 30,
            ),
            TaskStreamInfo(
              type: 'Audio',
              codec: 'aac',
              sampleRate: 48000,
              channel: 'stereo',
            ),
          ],
        ),
      ],
      runs: const [
        TaskRunInfo(
          status: 'running',
          elapsed: 100,
          vcodec: 'hevc_nvenc',
          muxFormat: 'mp4',
          outputPath: 'E:/out.mp4',
          paraArray: ['ffmpeg', '-i', 'in.flv', '-vcodec', 'hevc_nvenc'],
          cmdData: 'frame= 100 fps= 30',
          progressTime: [
            [0, 0],
            [10, 50],
          ],
          progressFrame: [
            [0, 0],
            [10, 500],
          ],
          progressSize: [
            [0, 0],
            [10, 1024],
          ],
        ),
      ],
    );
  }

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

class _ErrorTaskRepo implements TaskRepository {
  @override
  Future<List<int>> listTaskIds({
    int offset = 0,
    int size = 100,
    bool silent = false,
  }) async => const [0];

  @override
  Future<Task> getTask(int id, {bool silent = false}) async => Task(
    id: id,
    taskName: 'err-task',
    status: TaskStatus.error,
    elapsedSeconds: 50,
    errorInfo: const [],
    inputs: const [TaskInputInfo(filePath: 'in.flv', duration: 100)],
    runs: const [
      TaskRunInfo(status: 'idle'),
      TaskRunInfo(status: 'error', elapsed: 50, errorInfo: []),
    ],
  );

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

Widget _buildApp(_FakeTaskRepo repo) {
  return ProviderScope(
    overrides: [
      taskRepositoryProvider.overrideWith((ref) => repo),
      taskServiceProvider.overrideWith((ref) => TaskService(repo)),
    ],
    child: const MaterialApp(home: TaskDetailScreen(taskId: 0)),
  );
}

void main() {
  testWidgets('renders full task details', (tester) async {
    // 详情页内容多，放大窗口避免 ListView 懒加载不渲染视口外卡片
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _FakeTaskRepo();
    await tester.pumpWidget(_buildApp(repo));
    await tester.pump(); // 完成首次加载
    await tester.pump(
      const Duration(milliseconds: 200),
    ); // 等待 StatefulWidget 动画初始化

    expect(find.text('demo-task'), findsOneWidget);
    expect(find.byType(StatusBadge), findsWidgets);
    // expect(find.text('任务 #0'), findsWidgets);

    // 遥测
    expect(find.textContaining('进度 10.0%'), findsOneWidget);
    // 输入媒体
    expect(find.text('E:/in.flv'), findsWidgets);
    expect(find.text('h264 · 1920x1080 · 30 fps · 4096'), findsOneWidget);
    expect(find.text('aac · 48.0 kHz · stereo'), findsOneWidget);
    // 输出配置
    expect(find.text('hevc_nvenc'), findsOneWidget);
    expect(find.textContaining('ffmpeg -i in.flv'), findsOneWidget);
    // 输出文件
    expect(find.text('输出文件（1）'), findsOneWidget);
    // 遥测曲线与日志
    expect(find.text('转码遥测'), findsOneWidget);
    expect(find.text('转码日志'), findsOneWidget);
  });

  testWidgets('error task with empty errorInfo still shows error card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _ErrorTaskRepo();
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

    expect(find.text('历史错误'), findsOneWidget);
    expect(find.text('任务失败，请查看转码日志'), findsOneWidget);
  });

  testWidgets('polls task detail every second', (tester) async {
    final repo = _FakeTaskRepo();
    await tester.pumpWidget(_buildApp(repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final initial = repo.getTaskCalls;

    // 推进 2 秒，应触发至少 2 次定时刷新
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(repo.getTaskCalls, greaterThanOrEqualTo(initial + 2));

    // 清理定时器
    await tester.pumpWidget(const SizedBox());
  });
}
