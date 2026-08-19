import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:ffbox_edgelink/domain/entities/server_settings.dart';
import 'package:ffbox_edgelink/domain/repositories/server_settings_repository.dart';

/// ServerSettingsRepository 的具体实现。
///
/// 纯委托转发层：将接口调用直接转发给 [FFBoxApi]，不含额外业务逻辑。
class ServerSettingsRepositoryImpl implements ServerSettingsRepository {
  final FFBoxApi _api;

  ServerSettingsRepositoryImpl(this._api);

  @override
  Future<ServerSettings> getSettings() => _api.getServerSettings();

  @override
  Future<void> updateSettings(ServerSettings settings) =>
      _api.updateServerSettings(settings);
}
