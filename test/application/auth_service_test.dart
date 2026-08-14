import 'package:flutter_test/flutter_test.dart';
import 'package:ffbox_edgelink/application/auth/auth_service.dart';
import 'package:ffbox_edgelink/domain/entities/login_result.dart';
import 'package:ffbox_edgelink/domain/repositories/auth_repository.dart';

class _FakeAuthRepo implements AuthRepository {
  LoginResult result;
  _FakeAuthRepo(this.result);

  @override
  Future<LoginResult> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async => result;
}

void main() {
  test('login returns error message when user not exist', () async {
    final service = AuthService(_FakeAuthRepo(
      const LoginResult(isUserExist: false, isSuccess: false),
    ));
    final outcome = await service.login(
        baseUrl: 'http://x', username: 'u', password: 'p');
    expect(outcome.error, '用户名错误');
    expect(outcome.session, isNull);
  });

  test('login returns error message when password wrong', () async {
    final service = AuthService(_FakeAuthRepo(
      const LoginResult(isUserExist: true, isSuccess: false),
    ));
    final outcome = await service.login(
        baseUrl: 'http://x', username: 'u', password: 'p');
    expect(outcome.error, '密码错误');
  });

  test('login returns session on success', () async {
    final service = AuthService(_FakeAuthRepo(
      const LoginResult(isUserExist: true, isSuccess: true, sessionId: 'abc'),
    ));
    final outcome = await service.login(
        baseUrl: 'http://x', username: 'u', password: 'p');
    expect(outcome.error, isNull);
    expect(outcome.session?.sessionId, 'abc');
  });
}
