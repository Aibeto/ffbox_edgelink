import 'package:dio/dio.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/core/utils/file_logger.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';

class ApiClient {
  final Dio _dio;
  final String Function() _tokenProvider;
  final int _maxRetries;

  ApiClient({Dio? dio, String Function()? tokenProvider, this._maxRetries = 2})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 10),
            ),
          ),
      _tokenProvider = tokenProvider ?? (() => '') {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _tokenProvider();
          if (token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  Future<T> request<T>({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? data,
    bool retryOnFailure = false,
    bool silent = false,
  }) async {
    if (!silent) logDebug('$method $path');
    var attempt = 0;
    while (true) {
      try {
        final response = await _dio.request<dynamic>(
          path,
          queryParameters: query,
          data: data,
          options: Options(method: method),
        );
        if (!silent) {
          logDebug(
            '$method $path -> ${response.statusCode} (${response.data.runtimeType})',
          );
        }

        // 将原始响应数据写入文件日志（不输出到控制台，避免敏感信息泄露）
        await fileLogger.logRawData(
          endpoint: path,
          method: method,
          responseData: response.data,
          statusCode: response.statusCode,
          headers: response.headers.map,
        );

        return response.data as T;
      } on DioException catch (e) {
        final kind = _mapKind(e);
        if (retryOnFailure && attempt < _maxRetries && _isRetryable(kind)) {
          attempt++;
          logDebug('$method $path retry $attempt (kind=$kind)');
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        logDebug('$method $path -> ERROR kind=$kind');
        throw ApiException(
          e.response?.data?.toString() ?? e.message ?? '网络请求失败',
          statusCode: e.response?.statusCode,
          kind: kind,
        );
      }
    }
  }

  ApiErrorKind _mapKind(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiErrorKind.timeout;
      case DioExceptionType.connectionError:
        return ApiErrorKind.connectionFailed;
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 401 || code == 403) return ApiErrorKind.unauthorized;
        return ApiErrorKind.badStatus;
      default:
        return ApiErrorKind.unknown;
    }
  }

  bool _isRetryable(ApiErrorKind kind) =>
      kind == ApiErrorKind.timeout || kind == ApiErrorKind.connectionFailed;
}
