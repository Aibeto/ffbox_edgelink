import 'package:ffbox_edgelink/domain/entities/login_result.dart';

/// 认证仓储抽象接口。
abstract interface class AuthRepository {
  /// 登录远端服务器。
  ///
  /// - [password]：明文密码，仓储内部负责 SHA256 哈希后发送。
  /// - [directPasskey]：已哈希的 passkey，直接发送到服务器（不做 SHA256）。
  ///   优先级高于 [password]；历史记录自动填入时使用。
  Future<LoginResult> login({
    required String baseUrl,
    required String username,
    String password,
    String? directPasskey,
  });
}
