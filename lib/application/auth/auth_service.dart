import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/domain/repositories/auth_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/session_repository.dart';

/// 登录结果。
class AuthOutcome {
  final Session? session;
  final String? error;

  const AuthOutcome.success(Session this.session) : error = null;
  const AuthOutcome.failure(String this.error) : session = null;
}

/// 登录业务逻辑（纯 Dart，不依赖 UI 框架）。
class AuthService {
  final AuthRepository _authRepository;

  AuthService(this._authRepository);

  Future<AuthOutcome> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    logDebug('auth.login baseUrl=$baseUrl username=$username');
    final result = await _authRepository.login(
      baseUrl: baseUrl,
      username: username,
      password: password,
    );

    if (!result.isSuccess) {
      final message = result.isUserExist ? '密码错误' : '用户名错误';
      logDebug(
        'auth.login failed: $message (isUserExist=${result.isUserExist})',
      );
      return AuthOutcome.failure(message);
    }

    logDebug('auth.login success: sessionId=${result.sessionId}');
    return AuthOutcome.success(
      Session(
        baseUrl: baseUrl,
        username: username,
        sessionId: result.sessionId,
      ),
    );
  }
}
