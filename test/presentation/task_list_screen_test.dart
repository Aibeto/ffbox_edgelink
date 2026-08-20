/// 任务列表页 TaskListScreen 的 widget 测试。
///
/// 覆盖：任务名/状态渲染、上传横幅随队列状态显隐。
/// 上传队列以 _FakeQueueImpl 注入可控流，避免真实网络请求。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffbox_edgelink/application/task/task_service.dart';
import 'package:ffbox_edgelink/application/upload/chunk_hasher.dart';
import 'package:ffbox_edgelink/application/upload/upload_queue.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/upload_repository.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/screens/task_list_screen.dart';

class _FakeTaskRepo implements TaskRepository {
  @override
  Future<List<int>> listTaskIds({
    int offset = 0,
    int size = 100,
    bool silent = false,
  }) async => [1];
  @override
  Future<Task> getTask(int id, {bool silent = false}) async =>
      Task(id: id, taskName: 'demo', status: TaskStatus.idle);
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
  @override
  Future<List<int>> createTasks(
    List<String> filePaths,
    Map<String, dynamic>? outputParams,
  ) async => [1];
  @override
  Future<void> downloadOutputFile({
    required int taskId,
    required int runIndex,
    required int outputIndex,
    required String savePath,
    void Function(int count, int total)? onProgress,
  }) async {}
}

// --- 上传队列测试替身 ---

/// 空上传仓储：_FakeQueueImpl 仅满足构造依赖，不执行真实请求。
class _NoopUploadRepo implements UploadRepository {
  @override
  Future<List<int>> uploadCheck(List<String> hashs) async => [];
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
  }) async {}
  @override
  Future<void> setUploadStatus(int taskId, bool isUploading) async {}
}

/// 空哈希器：不执行真实文件读取。
class _NoopHasher extends ChunkHasher {}

/// 队列替身：states 返回注入的可控流。
class _FakeQueueImpl extends UploadQueue {
  _FakeQueueImpl(this.streamController)
    : super(repository: _NoopUploadRepo(), hasher: _NoopHasher());

  final StreamController<UploadQueueSnapshot> streamController;

  @override
  Stream<UploadQueueSnapshot> get states => streamController.stream;
}

UploadItem _item(UploadItemState state) => UploadItem(
  taskId: 1,
  path: '/tmp/a.mp4',
  fileBaseName: 'a.mp4',
  size: 100,
  state: state,
  transferredBytes: 40,
);

void main() {
  testWidgets('renders task name and status', (tester) async {
    final controller = StreamController<UploadQueueSnapshot>.broadcast();
    addTearDown(controller.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskServiceProvider.overrideWith(
            (ref) => TaskService(_FakeTaskRepo()),
          ),
          uploadQueueProvider.overrideWith((ref) => _FakeQueueImpl(controller)),
        ],
        child: const MaterialApp(home: TaskListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('demo'), findsOneWidget);
    expect(find.text('等待'), findsOneWidget);
  });

  testWidgets('活跃上传时显示横幅，无上传时不显示', (tester) async {
    final controller = StreamController<UploadQueueSnapshot>.broadcast();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskServiceProvider.overrideWith(
            (ref) => TaskService(_FakeTaskRepo()),
          ),
          uploadQueueProvider.overrideWith((ref) => _FakeQueueImpl(controller)),
        ],
        child: const MaterialApp(home: TaskListScreen()),
      ),
    );

    // 初始无上传：无横幅
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('upload_banner')), findsNothing);

    // 有上传：显示横幅
    controller.add(UploadQueueSnapshot([_item(UploadItemState.uploading)]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('upload_banner')), findsOneWidget);
    expect(find.textContaining('a.mp4'), findsWidgets);

    // 全部完成：横幅消失
    controller.add(UploadQueueSnapshot([_item(UploadItemState.done)]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('upload_banner')), findsNothing);

    await controller.close();
  });
}
