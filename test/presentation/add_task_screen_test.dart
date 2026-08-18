/// 新建任务页 AddTaskScreen 的 widget 测试。
///
/// 覆盖：配置行渲染与无文件禁用提交、初始文件移除/提交时
/// 以占位符调用 createTasks 并携带输出配置。上传队列以
/// _NoopQueue 覆写（不执行真实哈希与网络请求）。
library;

import 'package:ffbox_edgelink/application/upload/chunk_hasher.dart';
import 'package:ffbox_edgelink/application/upload/upload_queue.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/upload_repository.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/screens/add_task_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTaskRepo implements TaskRepository {
  List<String>? lastFilePaths;
  Map<String, dynamic>? lastOutputParams;

  @override
  Future<List<int>> createTasks(
    List<String> filePaths,
    Map<String, dynamic>? outputParams,
  ) async {
    lastFilePaths = filePaths;
    lastOutputParams = outputParams;
    return [101, 102];
  }

  @override
  Future<List<int>> listTaskIds({
    int offset = 0,
    int size = 100,
    bool silent = false,
  }) async => [];
  @override
  Future<Task> getTask(int id, {bool silent = false}) async =>
      Task(id: id, taskName: 't', status: TaskStatus.idle);
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

class _FakeUploadRepo implements UploadRepository {
  int enqueued = 0;

  @override
  Future<List<int>> uploadCheck(List<String> hashs) async => [0];
  @override
  Future<void> uploadFile(
    String hash,
    int length,
    Stream<List<int>> Function() openStream, {
    void Function(int count, int total)? onProgress,
  }) async {}
  @override
  Future<void> mergeUpload(
    int taskId, {
    required List<String> hashs,
    required String fileBaseName,
    required String inputName,
    required Map<String, int> fileTime,
  }) async {
    enqueued++;
  }

  @override
  Future<void> setUploadStatus(int taskId, bool isUploading) async {}
}

/// 空哈希器：_NoopQueue 不执行真实流程，仅满足构造依赖。
class _NoopHasher extends ChunkHasher {}

/// 队列覆写：enqueue 为空操作，避免真实哈希（读取不存在的本地文件）。
class _NoopQueue extends UploadQueue {
  _NoopQueue() : super(repository: _FakeUploadRepo(), hasher: _NoopHasher());

  @override
  Future<void> enqueue({
    required int taskId,
    required String path,
    required String fileBaseName,
    required int size,
  }) async {}
}

void main() {
  testWidgets('渲染配置行与文件列表，无文件时禁用提交', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskRepositoryProvider.overrideWith((ref) => _FakeTaskRepo()),
          uploadRepositoryProvider.overrideWith((ref) => _FakeUploadRepo()),
          uploadQueueProvider.overrideWith((ref) => _NoopQueue()),
        ],
        child: const MaterialApp(home: AddTaskScreen()),
      ),
    );
    expect(find.text('视频编码器'), findsOneWidget);
    expect(find.text('输出格式'), findsOneWidget);
    expect(find.text('添加并上传'), findsOneWidget);
    // 无文件时按钮禁用
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '添加并上传'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('初始文件可移除，提交发送占位符与配置并调用 createTasks',
      (tester) async {
    final taskRepo = _FakeTaskRepo();
    final uploadRepo = _FakeUploadRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskRepositoryProvider.overrideWith((ref) => taskRepo),
          uploadRepositoryProvider.overrideWith((ref) => uploadRepo),
          uploadQueueProvider.overrideWith((ref) => _NoopQueue()),
        ],
        child: const MaterialApp(
          home: AddTaskScreen(
            initialFiles: [
              (path: '/tmp/a.mp4', name: 'a.mp4', size: 1024),
            ],
          ),
        ),
      ),
    );
    expect(find.text('a.mp4'), findsOneWidget);

    await tester.tap(find.text('添加并上传'));
    await tester.pumpAndSettle();

    expect(taskRepo.lastFilePaths, ['[uploading] a.mp4']);
    expect(taskRepo.lastOutputParams!['outputs'][0]['video']['vcodec'],
        'libx265');
    expect(
        taskRepo.lastOutputParams!['outputs'][0]['video']['detail']['crf'], 24);
    expect(taskRepo.lastOutputParams!['outputs'][0]['mux']['format'], 'mp4');
  });
}
