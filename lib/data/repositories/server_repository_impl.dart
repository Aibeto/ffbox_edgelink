import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffbox_edgelink/domain/entities/server_profile.dart';
import 'package:ffbox_edgelink/domain/repositories/server_repository.dart';

/// ServerRepository 的具体实现。
///
/// - `load`/`save`：最新一次连接信息（回填用，不含密码）。
/// - `loadHistory`/`saveToHistory`：7 天内所有历史连接（快捷登录用，含密码）。
class ServerRepositoryImpl implements ServerRepository {
  static const _kBaseUrl = 'server_base_url';
  static const _kUsername = 'server_username';
  static const _kHistory = 'server_connection_history';
  static const _kMaxAge = Duration(days: 7);

  // --- 最新连接（回填） ---

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

  // --- 历史连接（7 天内） ---

  @override
  Future<List<ServerProfile>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kHistory);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => ServerProfile.fromJson(e as Map<String, dynamic>))
          .toList();
      final cutoff = DateTime.now().subtract(_kMaxAge);
      return list.where((p) => p.timestamp.isAfter(cutoff)).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> saveToHistory(ServerProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kHistory);
    List<ServerProfile> list = const [];
    if (raw != null && raw.isNotEmpty) {
      try {
        list = (jsonDecode(raw) as List)
            .map((e) => ServerProfile.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    // 去重：相同 baseUrl + username 的旧记录移除，保留最新
    list = list
        .where(
          (p) => !(p.baseUrl == profile.baseUrl && p.username == profile.username),
        )
        .toList();

    // 追加新记录到头部
    list.insert(0, profile);

    // 清理超过 7 天的记录
    final cutoff = DateTime.now().subtract(_kMaxAge);
    list = list.where((p) => p.timestamp.isAfter(cutoff)).toList();

    await prefs.setString(_kHistory, jsonEncode(list.map((p) => p.toJson()).toList()));
  }
}
