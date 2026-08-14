import 'package:ffbox_edgelink/domain/entities/server_profile.dart';

/// 服务器连接信息持久化（独立于会话，登出后仍保留）。
abstract interface class ServerRepository {
  Future<ServerProfile?> load();
  Future<void> save(ServerProfile profile);
}
