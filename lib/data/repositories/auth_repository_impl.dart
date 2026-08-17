import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/core/utils/hash.dart';
import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:ffbox_edgelink/domain/entities/login_result.dart';
import 'package:ffbox_edgelink/domain/repositories/auth_repository.dart';

/// AuthRepository 的具体实现。
///
/// 若提供 [directPasskey]（已 SHA256 哈希），直接发送到服务器；
/// 否则将明文密码 SHA256 哈希后委托给 [FFBoxApi] 执行登录请求。
class AuthRepositoryImpl implements AuthRepository {
  final FFBoxApi _api;
  final AppConfig _config;

  AuthRepositoryImpl({required this._api, required this._config});

  @override
  Future<LoginResult> login({
    required String baseUrl,
    required String username,
    String password = '',
    String? directPasskey,
  }) async {
    _config.baseUrl = baseUrl;
    final passkey = directPasskey ?? sha256Hex(password);
    return _api.login(username, passkey);
  }
}
