import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/core/network/api_client.dart';
import 'package:ffbox_edgelink/core/utils/file_logger.dart';
import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// 返回固定 JSON 的假 HTTP 适配器。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._respond);

  final Object Function(RequestOptions) _respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
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

FFBoxApi _buildApi(Object Function(RequestOptions) respond) {
  final dio = Dio()..httpClientAdapter = _FakeAdapter(respond);
  return FFBoxApi(
    ApiClient(dio: dio),
    AppConfig(baseUrl: 'http://127.0.0.1:5500'),
  );
}

void main() {
  setUp(() {
    fileLogger.clearBuffers();
  });

  group('FFBoxApi.listTaskIds', () {
    test('解析 {taskIds: [...]} 格式', () async {
      final api = _buildApi(
        (_) => {
          'taskIds': [1, 2, 3],
          'totalCount': 3,
        },
      );
      expect(await api.listTaskIds(), [1, 2, 3]);
    });

    test('解析 {tasks: [...]} 格式（提取 id）', () async {
      final api = _buildApi(
        (_) => {
          'tasks': [
            {'id': 1, 'taskName': 'a'},
            {'id': 2, 'taskName': 'b'},
          ],
          'totalCount': 2,
        },
      );
      expect(await api.listTaskIds(), [1, 2]);
    });

    test('传递 offset, size, idOnly 查询参数', () async {
      late Map<String, dynamic>? receivedQuery;
      final api = _buildApi((options) {
        receivedQuery = options.queryParameters;
        return {
          'taskIds': [10, 20],
          'totalCount': 2,
        };
      });

      final result = await api.listTaskIds(offset: 10, size: 5);
      expect(result, [10, 20]);
      expect(receivedQuery, {'offset': 10, 'size': 5, 'idOnly': true});
    });

    test('空列表返回空数组', () async {
      final api = _buildApi((_) => {'taskIds': [], 'totalCount': 0});
      expect(await api.listTaskIds(), isEmpty);
    });
  });

  group('FileLogger', () {
    test('记录原始响应数据到内存缓冲区', () async {
      fileLogger.clearBuffers();
      await fileLogger.logRawData(
        endpoint: '/api/v1/tasks',
        method: 'GET',
        responseData: <dynamic>[1, 2, 3],
        statusCode: 200,
      );

      final buffer = fileLogger.getRawDataBuffer();
      expect(buffer.length, 1);
      expect(buffer[0], contains('/api/v1/tasks'));
    });

    test('记录普通日志到内存缓冲区', () async {
      fileLogger.clearBuffers();
      await fileLogger.log('测试日志消息');

      final buffer = fileLogger.getLogBuffer();
      expect(buffer.length, 1);
      expect(buffer[0], contains('测试日志消息'));
    });
  });
}
