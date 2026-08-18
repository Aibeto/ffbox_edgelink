import 'dart:async';
import 'dart:io';

import 'package:ffbox_edgelink/application/upload/chunk_hasher.dart';
import 'package:ffbox_edgelink/application/upload/upload_protocol.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/domain/repositories/upload_repository.dart';

/// 上传项状态。
enum UploadItemState { pending, hashing, uploading, merging, done, error }

/// 单个上传项的不可变快照。
class UploadItem {
  final int taskId;
  final String path;
  final String fileBaseName;
  final int size;
  final UploadItemState state;
  final int transferredBytes;
  final double speedBps;
  final String? error;
  final bool unauthorized;

  const UploadItem({
    required this.taskId,
    required this.path,
    required this.fileBaseName,
    required this.size,
    this.state = UploadItemState.pending,
    this.transferredBytes = 0,
    this.speedBps = 0,
    this.error,
    this.unauthorized = false,
  });

  /// 任务创建时的输入占位符名（`[uploading] 文件名`）。
  String get inputName => uploadPlaceholder(fileBaseName);

  UploadItem copyWith({
    UploadItemState? state,
    int? transferredBytes,
    double? speedBps,
    String? error,
    bool? unauthorized,
  }) => UploadItem(
    taskId: taskId,
    path: path,
    fileBaseName: fileBaseName,
    size: size,
    state: state ?? this.state,
    transferredBytes: transferredBytes ?? this.transferredBytes,
    speedBps: speedBps ?? this.speedBps,
    error: error ?? this.error,
    unauthorized: unauthorized ?? this.unauthorized,
  );
}

/// 队列整体快照（广播流每次变更发出）。
class UploadQueueSnapshot {
  final List<UploadItem> items;

  const UploadQueueSnapshot(this.items);

  bool get hasActive => items.any(
    (i) =>
        i.state == UploadItemState.pending ||
        i.state == UploadItemState.hashing ||
        i.state == UploadItemState.uploading ||
        i.state == UploadItemState.merging,
  );

  bool get hasError => items.any((i) => i.state == UploadItemState.error);

  bool get hasUnauthorizedError =>
      items.any((i) => i.state == UploadItemState.error && i.unauthorized);
}

/// 上传队列状态机：文件级串行调度、文件内分片并发 2、每片重试 3 次。
///
/// application 层纯 Dart 实现（不依赖 Flutter/Riverpod），由全局 Provider
/// 持有，生命周期独立于页面：入队后后台完成哈希 → 文件级秒传检查 →
/// 分片级检查 → 分片上传 → 合并 → 状态收尾，经 [states] 广播流发布快照；
/// 遇 401 停止调度（余下保持 pending），由 UI 层检测 [UploadQueueSnapshot.hasUnauthorizedError] 登出。
class UploadQueue {
  UploadQueue({required this.repository, required this.hasher});

  final UploadRepository repository;
  final ChunkHasher hasher;
  final List<UploadItem> _items = [];
  final _controller = StreamController<UploadQueueSnapshot>.broadcast();
  final Map<int, List<String>> _hashesByTask = {};
  final Map<int, ({int bytes, DateTime time})> _lastProgress = {};
  Completer<void>? _drainCompleter;
  bool _isPumping = false;

  static const _chunkConcurrency = 2;
  static const _maxChunkRetries = 3;

  // --- 状态流 ---

  Stream<UploadQueueSnapshot> get states => _controller.stream;

  /// 队列排空的 Future（测试与 UI 等待用）。
  Future<void> get done => _drainCompleter?.future ?? Future.value();

  bool get hasUnfinished =>
      _isPumping ||
      _items.any((i) => i.state == UploadItemState.pending);

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(UploadQueueSnapshot(List.unmodifiable(_items)));
    }
  }

  // --- 入队与重试 ---

  Future<void> enqueue({
    required int taskId,
    required String path,
    required String fileBaseName,
    required int size,
  }) async {
    _items.add(
      UploadItem(
        taskId: taskId,
        path: path,
        fileBaseName: fileBaseName,
        size: size,
      ),
    );
    logDebug('uploadQueue: enqueue $fileBaseName (task $taskId)');
    _emit();
    _pump();
  }

  /// 重试失败项（复位为 pending 并重新调度；服务端分片缓存生效，等效断点续传）。
  Future<void> retryItem(int taskId) async {
    final index = _items.indexWhere((i) => i.taskId == taskId);
    if (index < 0) return;
    final old = _items[index];
    _items[index] = UploadItem(
      taskId: old.taskId,
      path: old.path,
      fileBaseName: old.fileBaseName,
      size: old.size,
    );
    _lastProgress.remove(taskId);
    logDebug('uploadQueue: retry task $taskId');
    _emit();
    _pump();
  }

  // --- 调度 ---

  Future<void> _pump() async {
    if (_isPumping) return;
    _isPumping = true;
    _drainCompleter = Completer<void>();
    try {
      while (true) {
        final index = _items.indexWhere(
          (i) => i.state == UploadItemState.pending,
        );
        if (index < 0) break;
        final stop = await _processItem(_items[index]);
        if (stop) break; // 401：停止调度，余下保持 pending
      }
    } finally {
      _isPumping = false;
      _drainCompleter?.complete();
      _drainCompleter = null;
      _emit();
    }
  }

  void _updateWhere(int taskId, UploadItem Function(UploadItem) transform) {
    final index = _items.indexWhere((i) => i.taskId == taskId);
    if (index >= 0) {
      _items[index] = transform(_items[index]);
      _emit();
    }
  }

  /// 处理单个上传项。返回 true 表示遇到 401 需停止调度。
  Future<bool> _processItem(UploadItem item) async {
    try {
      await _processPhases(item);
      return false;
    } on ApiException catch (e) {
      logDebug('uploadQueue: item ${item.taskId} error ${e.friendlyMessage}');
      _updateWhere(item.taskId, (i) => i.copyWith(
        state: UploadItemState.error,
        error: e.friendlyMessage,
        unauthorized: e.isUnauthorized,
        speedBps: 0,
      ));
      return e.isUnauthorized;
    } catch (e) {
      // 非 ApiException（如本地文件被移除导致的 io 异常）：同样标记 error，避免队列卡死
      logDebug('uploadQueue: item ${item.taskId} error $e');
      _updateWhere(item.taskId, (i) => i.copyWith(
        state: UploadItemState.error,
        error: e.toString(),
        speedBps: 0,
      ));
      return false;
    }
  }

  // --- 上传阶段 ---

  Future<void> _processPhases(UploadItem item) async {
    // 哈希
    _updateWhere(item.taskId, (i) => i.copyWith(state: UploadItemState.hashing));
    final segments = segmentPlan(item.size);
    final chunkHashes = await hasher.hashSegments(item.path, segments);
    _hashesByTask[item.taskId] = chunkHashes;
    final fileHash = fileHashOf(chunkHashes);
    final cacheKey = uploadCacheKey(item.fileBaseName, fileHash);

    // 文件级秒传检查：命中则跳过分片上传
    final fileCached = await repository.uploadCheck([cacheKey]);
    if (fileCached.isEmpty || fileCached.first != 1) {
      // 分片级检查：已缓存分片计入进度，未缓存分片进入上传
      final chunkCached = await repository.uploadCheck(chunkHashes);
      final pendingIndices = [
        for (var i = 0; i < segments.length; i++)
          if (i >= chunkCached.length || chunkCached[i] != 1) i,
      ];
      final completedBytes = <int>{
        for (var i = 0; i < segments.length; i++)
          if (i < chunkCached.length && chunkCached[i] == 1) segments[i].length,
      };
      _updateWhere(item.taskId, (i) => i.copyWith(
        state: UploadItemState.uploading,
        transferredBytes: completedBytes.fold<int>(0, (a, b) => a + b),
      ));

      await _forEachLimited(pendingIndices, _chunkConcurrency, (index) async {
        final segment = segments[index];
        await _uploadChunkWithRetry(item, index, segment, completedBytes);
      });
    }

    // 合并与收尾
    _updateWhere(item.taskId, (i) => i.copyWith(state: UploadItemState.merging));
    final stat = await File(item.path).stat();
    await repository.mergeUpload(
      item.taskId,
      hashs: chunkHashes,
      fileBaseName: item.fileBaseName,
      inputName: item.inputName,
      fileTime: {
        'accessTime': stat.accessed.millisecondsSinceEpoch,
        'createTime': stat.changed.millisecondsSinceEpoch,
        'modifyTime': stat.modified.millisecondsSinceEpoch,
      },
    );
    await repository.setUploadStatus(item.taskId, false);
    _updateWhere(item.taskId, (i) => i.copyWith(
      state: UploadItemState.done,
      transferredBytes: item.size,
      speedBps: 0,
    ));
    logDebug('uploadQueue: item ${item.taskId} done');
  }

  // --- 分片上传（并发 worker 内调用，带 3 次重试与进度） ---

  Future<void> _uploadChunkWithRetry(
    UploadItem item,
    int index,
    ({int offset, int length}) segment,
    Set<int> completedBytes,
  ) async {
    for (var attempt = 1; attempt <= _maxChunkRetries; attempt++) {
      try {
        await repository.uploadFile(
          _chunkHashOf(item, index),
          segment.length,
          () => File(item.path).openRead(
            segment.offset,
            segment.offset + segment.length,
          ),
          onProgress: (count, total) =>
              _onChunkProgress(item, completedBytes, count),
        );
        completedBytes.add(segment.length);
        _onChunkProgress(item, completedBytes, 0);
        return;
      } on ApiException catch (e) {
        if (e.isUnauthorized || attempt == _maxChunkRetries) rethrow;
        logDebug('uploadQueue: chunk $index attempt $attempt failed');
      }
    }
    throw ApiException('分片重试 $_maxChunkRetries 次仍失败');
  }

  String _chunkHashOf(UploadItem item, int index) =>
      _hashesByTask[item.taskId]![index];

  // --- 进度与速度 ---

  void _onChunkProgress(UploadItem item, Set<int> completedBytes, int chunkSent) {
    final base = completedBytes.fold<int>(0, (a, b) => a + b) + chunkSent;
    final now = DateTime.now();
    final last = _lastProgress[item.taskId];
    final index = _items.indexWhere((i) => i.taskId == item.taskId);
    final historySpeed = index >= 0 ? _items[index].speedBps : item.speedBps;
    var speed = 0.0;
    if (last != null) {
      final dt = now.difference(last.time).inMicroseconds;
      if (dt > 0) {
        final instant = (base - last.bytes) * 1000 * 1000 / dt;
        // EMA：0.4 瞬时 + 0.6 历史平滑，抑制单次抖动
        speed = last.bytes > 0 ? instant * 0.4 + historySpeed * 0.6 : instant;
      }
    }
    _lastProgress[item.taskId] = (bytes: base, time: now);
    _updateWhere(item.taskId, (i) => i.copyWith(
      transferredBytes: base.clamp(0, i.size).toInt(),
      speedBps: speed,
    ));
  }

  // --- 并发限流 ---

  /// 游标式并发限流：[limit] 个 worker 抢占任务；任一 worker 失败后其余
  /// worker 停止接新任务，全部结束后重抛首个异常。
  Future<void> _forEachLimited<T>(
    List<T> items,
    int limit,
    Future<void> Function(T) task,
  ) async {
    var cursor = 0;
    final errors = <Object>[];
    Future<void> worker() async {
      while (cursor < items.length && errors.isEmpty) {
        final current = items[cursor++];
        try {
          await task(current);
        } catch (e) {
          errors.add(e);
        }
      }
    }

    await Future.wait([for (var i = 0; i < limit; i++) worker()]);
    if (errors.isNotEmpty) throw errors.first;
  }

  // --- 释放 ---

  void dispose() {
    _controller.close();
  }
}
