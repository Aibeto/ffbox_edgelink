// 上传 400 问题复现客户端：复刻 App 的 FFBoxApi/UploadQueue 上传流程。
// 用法：dart run tool/debug/upload400_client.dart [baseUrl] [fileSizeBytes]
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'package:ffbox_edgelink/application/upload/upload_protocol.dart';

Future<void> main(List<String> args) async {
  final baseUrl = args.isNotEmpty ? args[0] : 'http://127.0.0.1:33269';
  final fileSize = args.length > 1 ? int.parse(args[1]) : 5 * 1000 * 1000;

  // 构造含随机二进制（含非法 UTF-8 序列）的测试文件
  final testFile = File('${Directory.systemTemp.path}/upload400_test.bin');
  final rng = Random(42);
  final sink = testFile.openSync(mode: FileMode.write);
  const chunk = 64 * 1024;
  for (var written = 0; written < fileSize; written += chunk) {
    final n = fileSize - written < chunk ? fileSize - written : chunk;
    sink.writeFromSync(List<int>.generate(n, (_) => rng.nextInt(256)));
  }
  sink.closeSync();
  stdout.writeln('测试文件: ${testFile.path} (${testFile.lengthSync()} bytes)');

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 10),
  ));

  Future<Response<dynamic>> post(String path, {Object? data, Options? options}) =>
      dio.request<dynamic>(baseUrl + path, data: data, options: options ?? Options(method: 'POST'));

  try {
    // 1. 创建任务
    final outputParams = buildOutputParams(
      video: {
        'vcodec': 'libx265',
        'resolution': '不改变',
        'framerate': '不改变',
        'ratecontrol': 'CRF',
        'detail': {'crf': 24},
      },
      audio: {'acodec': 'copy', 'detail': <String, dynamic>{}},
      mux: {
        'format': 'mp4',
        'moveflags': false,
        'filePath': '[filedir]/[filename]_converted.[fileext]',
        'begin': '',
        'end': '',
        'detail': <String, dynamic>{},
      },
    );
    final r1 = await post('/api/v1/tasks',
        data: {'filePaths': [uploadPlaceholder('upload400_test.bin')], 'outputParams': outputParams});
    stdout.writeln('1. createTasks -> ${r1.statusCode} ${r1.data}');

    // 2. 哈希与分片
    final segments = segmentPlan(testFile.lengthSync());
    final chunkHashes = <String>[];
    for (final seg in segments) {
      final bytes = await testFile.openRead(seg.offset, seg.offset + seg.length).expand((b) => b).toList();
      chunkHashes.add(sha1.convert(bytes).toString());
    }
    final fileHash = fileHashOf(chunkHashes);
    final cacheKey = uploadCacheKey('upload400_test.bin', fileHash);

    // 3. uploadCheck（文件级）
    final r2 = await post('/api/v1/upload/check', data: {'hashs': [cacheKey]});
    stdout.writeln('2. uploadCheck(file) -> ${r2.statusCode} ${r2.data}');

    // 4. uploadCheck（分片级）
    final r3 = await post('/api/v1/upload/check', data: {'hashs': chunkHashes});
    stdout.writeln('3. uploadCheck(chunks) -> ${r3.statusCode} ${r3.data}');

    // 5. uploadFile —— 与 App 完全一致：MultipartFile.fromStream 无 filename
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final form = FormData()
        ..fields.add(MapEntry('name', chunkHashes[i]))
        ..files.add(MapEntry('file',
            MultipartFile.fromStream(() => testFile.openRead(seg.offset, seg.offset + seg.length), seg.length)));
      final r4 = await post('/api/v1/upload/file',
          data: form, options: Options(method: 'POST', sendTimeout: const Duration(minutes: 10)));
      stdout.writeln('4. uploadFile[$i] -> ${r4.statusCode} ${r4.data}');
    }

    // 6. mergeUpload —— 与 App 完全一致
    final stat = await testFile.stat();
    final r5 = await post('/api/v1/tasks/1/merge-upload', data: {
      'hashs': chunkHashes,
      'fileBaseName': 'upload400_test.bin',
      'inputName': uploadPlaceholder('upload400_test.bin'),
      'fileTime': {
        'accessTime': stat.accessed.millisecondsSinceEpoch,
        'createTime': stat.changed.millisecondsSinceEpoch,
        'modifyTime': stat.modified.millisecondsSinceEpoch,
      },
    });
    stdout.writeln('5. mergeUpload -> ${r5.statusCode} ${r5.data}');

    // 7. setUploadStatus
    final r6 = await dio.request<dynamic>(
        '$baseUrl/api/v1/tasks/1/upload-status',
        data: {'isUploading': false}, options: Options(method: 'PUT'));
    stdout.writeln('6. setUploadStatus -> ${r6.statusCode} ${r6.data}');

    stdout.writeln('全部通过：未复现 400');
  } on DioException catch (e) {
    stdout.writeln('FAILED at: ${e.requestOptions.uri}');
    stdout.writeln('  status=${e.response?.statusCode} body=${e.response?.data}');
    stdout.writeln('  type=${e.type} message=${e.message}');
    rethrow;
  } finally {
    dio.close();
    testFile.deleteSync();
  }
}
