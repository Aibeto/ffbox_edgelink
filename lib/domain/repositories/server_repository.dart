import 'package:ffbox_edgelink/domain/entities/server_profile.dart';

/// 服务器连接信息持久化（独立于会话，登出后仍保留）。
///
/// `load`/`save` 为最新一次连接信息（回填用）；
/// `loadHistory`/`saveToHistory` 为 7 天内所有历史连接（快捷登录用）。
abstract interface class ServerRepository {
  Future<ServerProfile?> load();
  Future<void> save(ServerProfile profile);

  /// 加载 7 天内的历史连接记录（按时间倒序）。
  Future<List<ServerProfile>> loadHistory();

  /// 追加一条历史记录（含密码），自动清理超过 7 天的旧记录。
  Future<void> saveToHistory(ServerProfile profile);
}
