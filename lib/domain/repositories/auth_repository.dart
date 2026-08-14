import 'package:ffbox_edgelink/domain/entities/login_result.dart';

/// 认证仓储抽象接口。
abstract interface class AuthRepository {
  /// 登录远端服务器。[password] 为明文，仓储内部负责 SHA256 哈希。
  Future<LoginResult> login({
    required String baseUrl,
    required String username,
    required String password,
  });
}
