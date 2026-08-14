import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/core/utils/hash.dart';
import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:ffbox_edgelink/domain/entities/login_result.dart';
import 'package:ffbox_edgelink/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final FFBoxApi _api;
  final AppConfig _config;

  AuthRepositoryImpl({required this._api, required this._config});

  @override
  Future<LoginResult> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    _config.baseUrl = baseUrl;
    return _api.login(username, sha256Hex(password));
  }
}
