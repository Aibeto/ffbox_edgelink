import 'dart:convert';
import 'dart:io';

import 'package:ffbox_edgelink/core/utils/hash.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/core/utils/secret_cipher.dart';
import 'package:ffbox_edgelink/domain/entities/server_profile.dart';
import 'package:ffbox_edgelink/domain/repositories/server_repository.dart';
import 'package:path_provider/path_provider.dart';

/// ServerRepository 的具体实现。
///
/// 使用本地 JSON 文件持久化，不依赖 SharedPreferences，避免写盘权限问题。
/// - `load`/`save`：最新一次连接信息（回填用，不含密码）。
/// - `loadHistory`/`saveToHistory`：7 天内所有历史连接（快捷登录用，含密码）。
class ServerRepositoryImpl implements ServerRepository {
  static const _kMaxAge = Duration(days: 7);

  // --- 文件路径 ---

  Future<File> _storeFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/server_store.json');
  }

  Future<Map<String, dynamic>> _readStore() async {
    try {
      final file = await _storeFile();
      if (!await file.exists()) return {};
      final raw = await file.readAsString();
      if (raw.isEmpty) return {};
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      logDebug('serverStore: 读取失败 $e');
      return {};
    }
  }

  Future<void> _writeStore(Map<String, dynamic> store) async {
    try {
      final file = await _storeFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(store));
    } catch (e) {
      logDebug('serverStore: 写入失败 $e');
    }
  }

  // --- 最新连接（回填） ---

  @override
  Future<ServerProfile?> load() async {
    final store = await _readStore();
    final baseUrl = store['baseUrl'] as String?;
    if (baseUrl == null || baseUrl.isEmpty) return null;
    return ServerProfile(
      baseUrl: baseUrl,
      username: store['username'] as String? ?? '',
    );
  }

  @override
  Future<void> save(ServerProfile profile) async {
    final store = await _readStore();
    store['baseUrl'] = profile.baseUrl;
    store['username'] = profile.username;
    await _writeStore(store);
  }

  // --- 历史连接（7 天内） ---

  @override
  Future<List<ServerProfile>> loadHistory() async {
    final store = await _readStore();
    final raw = store['history'];
    if (raw == null) return const [];
    try {
      final list = <ServerProfile>[];
      for (final e in raw as List) {
        final map = e as Map<String, dynamic>;
        var p = ServerProfile.fromJson(map);
        // 迁移旧版 AES 密文：尝试解密，成功则转为 sha256: 前缀格式，
        // 解密失败（密钥丢失等）则清除密码，用户需重新输入。
        if (p.password.startsWith('enc:')) {
          final decrypted = await SecretCipher.decrypt(p.password);
          if (decrypted.isNotEmpty) {
            p = ServerProfile(
              baseUrl: p.baseUrl,
              username: p.username,
              password: 'sha256:${sha256Hex(decrypted)}',
              timestamp: p.timestamp,
            );
          } else {
            // 解密失败，清除损坏的密文
            p = ServerProfile(
              baseUrl: p.baseUrl,
              username: p.username,
              password: '',
              timestamp: p.timestamp,
            );
          }
        }
        list.add(p);
      }
      final cutoff = DateTime.now().subtract(_kMaxAge);
      final filtered = list.where((p) => p.timestamp.isAfter(cutoff)).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      logDebug('loadHistory: ${list.length} 条记录，过滤后 ${filtered.length} 条');
      return filtered;
    } catch (e) {
      logDebug('loadHistory: 解析失败 $e');
      return const [];
    }
  }

  @override
  Future<void> saveToHistory(ServerProfile profile) async {
    final store = await _readStore();
    final raw = store['history'];
    // 保留原有 JSON map（密文），避免解密/重新加密循环导致双重加密
    final list = <Map<String, dynamic>>[];
    if (raw != null) {
      try {
        for (final e in raw as List) {
          list.add(Map<String, dynamic>.from(e as Map));
        }
      } catch (_) {}
    }

    // 去重：相同 baseUrl + username 的旧记录移除，保留最新
    list.removeWhere(
      (m) =>
          m['baseUrl'] == profile.baseUrl && m['username'] == profile.username,
    );

    // 追加新记录到头部（存储 SHA-256 哈希，与服务器一致，不做本地 AES 加密）
    final newJson = profile.toJson();
    newJson['password'] = profile.password.isNotEmpty
        ? 'sha256:${sha256Hex(profile.password)}'
        : '';
    list.insert(0, newJson);

    // 清理超过 7 天的记录
    final cutoff = DateTime.now().subtract(_kMaxAge);
    list.removeWhere((m) {
      final ts = DateTime.tryParse(m['timestamp'] as String? ?? '');
      return ts == null || ts.isBefore(cutoff);
    });

    store['history'] = list;
    await _writeStore(store);
    logDebug('saveToHistory: 保存 ${list.length} 条记录');
  }

  @override
  Future<void> deleteFromHistory(ServerProfile profile) async {
    final store = await _readStore();
    final raw = store['history'];
    if (raw == null) return;
    try {
      List<ServerProfile> list = (raw as List)
          .map((e) => ServerProfile.fromJson(e as Map<String, dynamic>))
          .toList();
      list = list
          .where(
            (p) =>
                !(p.baseUrl == profile.baseUrl &&
                    p.username == profile.username),
          )
          .toList();
      store['history'] = list.map((p) => p.toJson()).toList();
      await _writeStore(store);
    } catch (e) {
      logDebug('deleteFromHistory: 失败 $e');
    }
  }
}
