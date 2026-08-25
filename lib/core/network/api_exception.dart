/// 网络错误分类与统一异常。ApiException 把 Dio 异常归类为错误码和面向用户的文案。
library;

// --- 错误分类枚举 ---

/// 网络错误分类。
enum ApiErrorKind {
  timeout, // 连接/发送/接收超时（含「单通」：发出后无响应）
  connectionFailed, // 无法建立连接（拒绝/复位/DNS 失败）
  unauthorized, // 401/403，会话失效
  badStatus, // 其他非 2xx
  unknown,
}

// --- 异常类 ---

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final ApiErrorKind kind;

  const ApiException(
    this.message, {
    this.statusCode,
    this.kind = ApiErrorKind.unknown,
  });

  bool get isUnauthorized => kind == ApiErrorKind.unauthorized;

  /// 面向用户的友好文案。
  String get friendlyMessage => switch (kind) {
    ApiErrorKind.timeout => '服务器无响应，请检查网络或服务器地址',
    ApiErrorKind.connectionFailed => '无法连接服务器，请检查地址和网络',
    ApiErrorKind.unauthorized => '登录已失效，请重新登录',
    ApiErrorKind.badStatus => '服务器错误($statusCode)：$message',
    ApiErrorKind.unknown => message,
  };

  @override
  String toString() => friendlyMessage;
}
