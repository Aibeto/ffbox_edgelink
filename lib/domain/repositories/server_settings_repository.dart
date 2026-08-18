import 'package:ffbox_edgelink/domain/entities/server_settings.dart';

/// 服务器配置仓储抽象接口。
abstract interface class ServerSettingsRepository {
  /// 获取当前服务器配置。
  Future<ServerSettings> getSettings();

  /// 更新服务器配置（PUT /api/v1/settings/server）。
  Future<void> updateSettings(ServerSettings settings);
}
