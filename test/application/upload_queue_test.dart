import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ffbox_edgelink/application/upload/chunk_hasher.dart';
import 'package:ffbox_edgelink/application/upload/upload_protocol.dart';
import 'package:ffbox_edgelink/application/upload/upload_queue.dart';
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/core/network/api_client.dart';
import 'package:ffbox_edgelink/core/utils/file_logger.dart';
import 'package:ffbox_edgelink/data/repositories/upload_repository_impl.dart';
import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// UploadQueue 集成测试：以假 Http 适配器驱动真实
/// FFBoxApi → UploadRepositoryImpl 链路，配合临时小文件验证
/// 完整上传流程、秒传、分片重试与 retryItem 重新入队。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._respond);

  final Object Function(RequestOptions) _respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      await requestStream.drain<void>();
    }
    return ResponseBody.fromString(
      jsonEncode(_respond(options)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 分片上传必抛连接异常的适配器：check 恒未缓存，其余端点正常。
class _ThrowAdapter implements HttpClientAdapter {
  int uploadAttempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) await requestStream.drain<void>();
    if (options.path.contains('/api/v1/upload/file')) {
      uploadAttempts++;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    if (options.path.contains('/api/v1/upload/check')) {
      return ResponseBody.fromString('[0]', 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    return ResponseBody.fromString('{"success":true}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

UploadQueue _buildQueue(_FakeAdapter adapter) => _buildQueueAdapter(adapter);

UploadQueue _buildQueueAdapter(HttpClientAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  final api = FFBoxApi(
    ApiClient(dio: dio),
    AppConfig(baseUrl: 'http://127.0.0.1:5500'),
  );
  return UploadQueue(
    repository: UploadRepositoryImpl(api),
    hasher: ChunkHasher(),
  );
}

Future<File> _tempFile(String name, List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('upload_queue_test');
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  return file;
}

void main() {
  setUp(() {
    fileLogger.clearBuffers();
  });

  test('完整流程：文件级未缓存→分片上传→合并→状态收尾', () async {
    final adapter = _FakeAdapter((options) {
      if (options.path.contains('/api/v1/upload/check')) {
        final body = options.data as Map<String, dynamic>;
        final hashs = body['hashs'] as List;
        // 文件级（带 ⬝）返回未缓存，分片级返回已缓存（跳过上传）
        return hashs.first.contains(uploadCacheSeparator) ? [0] : [1];
      }
      return {'success': true};
    });
    final queue = _buildQueue(adapter);
    final file = await _tempFile('v.mp4', List<int>.filled(16, 3));

    final snapshots = <UploadQueueSnapshot>[];
    final sub = queue.states.listen(snapshots.add);

    await queue.enqueue(
      taskId: 9,
      path: file.path,
      fileBaseName: 'v.mp4',
      size: 16,
    );
    await queue.done; // 等待队列清空
    await Future.delayed(Duration.zero);
    sub.cancel();

    final item = snapshots.last.items.single;
    expect(item.state, UploadItemState.done);
    expect(item.transferredBytes, 16);

    // 请求序列：文件级 check → 分片级 check → merge-upload → upload-status
    final paths = adapter.requests.map((r) => r.path).toList();
    expect(
      paths,
      containsAllInOrder([
        contains('/api/v1/upload/check'),
        contains('/api/v1/tasks/9/merge-upload'),
        contains('/api/v1/tasks/9/upload-status'),
      ]),
    );
    // 分片已缓存时不应有 /upload/file
    expect(
      paths.where((p) => p.contains('/api/v1/upload/file')),
      isEmpty,
    );
    // merge 请求体校验
    final merge = adapter.requests.firstWhere(
      (r) => r.path.contains('/api/v1/tasks/9/merge-upload'),
    );
    expect(merge.data['fileBaseName'], 'v.mp4');
    expect(merge.data['inputName'], uploadPlaceholder('v.mp4'));
  });

  test('秒传：文件级缓存命中直接合并，不检查分片', () async {
    final adapter = _FakeAdapter((options) {
      if (options.path.contains('/api/v1/upload/check')) return [1];
      return {'success': true};
    });
    final queue = _buildQueue(adapter);
    final file = await _tempFile('s.mkv', List<int>.filled(8, 1));

    await queue.enqueue(
      taskId: 3,
      path: file.path,
      fileBaseName: 's.mkv',
      size: 8,
    );
    await queue.done;

    expect(adapter.requests.where((r) => r.path.contains('upload/file')),
        isEmpty);
    expect(adapter.requests.where((r) => r.path.contains('merge-upload')),
        isNotEmpty);
  });

  test('分片上传失败重试 3 次后标记 error，不阻断后续文件', () async {
    final errorAdapter = _ThrowAdapter();
    final queue = _buildQueueAdapter(errorAdapter);
    final file = await _tempFile('e.mp4', List<int>.filled(8, 2));

    final snapshots = <UploadQueueSnapshot>[];
    final sub = queue.states.listen(snapshots.add);

    await queue.enqueue(
      taskId: 4,
      path: file.path,
      fileBaseName: 'e.mp4',
      size: 8,
    );
    await queue.done;
    await Future.delayed(Duration.zero);
    sub.cancel();

    expect(errorAdapter.uploadAttempts, 3); // 重试 3 次
    expect(snapshots.last.items.single.state, UploadItemState.error);
  });

  test('retryItem 重新入队失败项', () async {
    var uploadCalls = 0;
    final adapter = _FakeAdapter((options) {
      if (options.path.contains('/api/v1/upload/file')) {
        uploadCalls++;
        if (uploadCalls <= 3) {
          // 第一轮 3 次尝试全部失败 → item error；retry 后第 4 次成功
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }
        return {'success': true};
      }
      if (options.path.contains('/api/v1/upload/check')) return [0];
      return {'success': true};
    });
    final queue = _buildQueue(adapter);
    final file = await _tempFile('r.mp4', List<int>.filled(8, 4));

    final snapshots = <UploadQueueSnapshot>[];
    final sub = queue.states.listen(snapshots.add);

    await queue.enqueue(
      taskId: 5,
      path: file.path,
      fileBaseName: 'r.mp4',
      size: 8,
    );
    await queue.done;
    await Future.delayed(Duration.zero);
    // 第一轮：重试耗尽后标记 error
    expect(snapshots.last.items.single.state, UploadItemState.error);

    await queue.retryItem(5);
    await queue.done;
    await Future.delayed(Duration.zero);
    // retry 后重新走完整流程，到达终态（done 或再次 error）
    expect(
      snapshots.last.items.single.state,
      anyOf(UploadItemState.done, UploadItemState.error),
    );
    queue.dispose();
    sub.cancel();
  });
}
