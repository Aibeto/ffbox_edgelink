import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffbox_edgelink/domain/entities/server_profile.dart';
import 'package:ffbox_edgelink/domain/repositories/server_repository.dart';

class ServerRepositoryImpl implements ServerRepository {
  static const _kBaseUrl = 'server_base_url';
  static const _kUsername = 'server_username';

  @override
  Future<ServerProfile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_kBaseUrl);
    if (baseUrl == null || baseUrl.isEmpty) return null;
    return ServerProfile(
      baseUrl: baseUrl,
      username: prefs.getString(_kUsername) ?? '',
    );
  }

  @override
  Future<void> save(ServerProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, profile.baseUrl);
    await prefs.setString(_kUsername, profile.username);
  }
}
