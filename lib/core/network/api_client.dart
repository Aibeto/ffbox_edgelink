import 'package:dio/dio.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/core/utils/file_logger.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';

/// HTTP 客户端封装（基于 Dio）：超时、Bearer 令牌注入、幂等 GET 有限重试、响应日志记录。
class ApiClient {
  final Dio _dio;
  final String Function() _tokenProvider;
  final int _maxRetries;

  // --- 构造与拦截器 ---

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

  // --- 请求方法 ---

  Future<T> request<T>({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? data,
    bool retryOnFailure = false,
    bool silent = false,
    Options? options,
    void Function(int count, int total)? onSendProgress,
  }) async {
    if (!silent) logDebug('$method $path');
    var attempt = 0;
    while (true) {
      try {
        final response = await _dio.request<dynamic>(
          path,
          queryParameters: query,
          data: data,
          options: options ?? Options(method: method),
          onSendProgress: onSendProgress,
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
      } catch (e) {
        // 非 Dio 异常（如 response.data as T 强转 TypeError、日志写入失败）统一包装，
        // 避免穿透到只捕获 ApiException 的调用方形成未处理异常
        logDebug('$method $path -> 非网络异常: $e');
        throw ApiException(e.toString(), kind: ApiErrorKind.unknown);
      }
    }
  }

  // --- 错误分类 ---

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

  // --- 重试策略 ---

  bool _isRetryable(ApiErrorKind kind) =>
      kind == ApiErrorKind.timeout || kind == ApiErrorKind.connectionFailed;
}
