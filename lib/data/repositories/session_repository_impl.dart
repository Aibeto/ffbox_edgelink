import 'dart:convert';
import 'dart:io';

import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/domain/repositories/session_repository.dart';
import 'package:path_provider/path_provider.dart';

/// SessionRepository 的具体实现。
///
/// 使用本地 JSON 文件（`session_store.json`）持久化会话数据
/// （服务器地址+用户名+sessionId），登录成功写入，登出清空，
/// 启动时恢复以实现免重新登录。
///
/// 历史兼容：启动时检测旧文件 `server_store.json`，若存在会话数据
/// 则自动迁移到 `session_store.json`，迁移后不再读写旧文件。
class SessionRepositoryImpl implements SessionRepository {
  static bool _migrated = false;

  Future<File> _storeFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/session_store.json');
  }

  // --- 旧文件迁移 ---

  Future<void> _migrateFromOldStore() async {
    if (_migrated) return;
    final file = await _storeFile();
    if (await file.exists()) {
      _migrated = true;
      return;
    }
    try {
      final dir = await getApplicationSupportDirectory();
      final oldFile = File('${dir.path}/server_store.json');
      if (!await oldFile.exists()) {
        _migrated = true;
        return;
      }
      final raw = await oldFile.readAsString();
      if (raw.isEmpty) {
        _migrated = true;
        return;
      }
      final store = jsonDecode(raw) as Map<String, dynamic>;
      if (store.containsKey('session_baseUrl')) {
        await file.parent.create(recursive: true);
        await file.writeAsString(
          jsonEncode({
            'session_baseUrl': store['session_baseUrl'],
            'session_username': store['session_username'],
            'session_sessionId': store['session_sessionId'],
          }),
        );
        logDebug('sessionStore: 从 server_store.json 迁移会话数据');
      }
    } catch (e) {
      logDebug('sessionStore: 迁移失败 $e');
    }
    _migrated = true;
  }

  // --- 文件读写 ---

  Future<Map<String, dynamic>> _readStore() async {
    try {
      final file = await _storeFile();
      if (!await file.exists()) return {};
      final raw = await file.readAsString();
      if (raw.isEmpty) return {};
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      logDebug('sessionStore: 读取失败 $e');
      return {};
    }
  }

  Future<void> _writeStore(Map<String, dynamic> store) async {
    try {
      final file = await _storeFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(store));
    } catch (e) {
      logDebug('sessionStore: 写入失败 $e');
    }
  }

  @override
  Future<Session?> load() async {
    await _migrateFromOldStore();
    final store = await _readStore();
    final baseUrl = store['session_baseUrl'] as String?;
    final sessionId = store['session_sessionId'] as String?;
    if (baseUrl == null ||
        baseUrl.isEmpty ||
        sessionId == null ||
        sessionId.isEmpty) {
      logDebug('session.load: 无已保存会话');
      return null;
    }
    final username = store['session_username'] as String? ?? '';
    final hasFileSystemPermission =
        store['session_hasFileSystemPermission'] as bool? ?? false;
    logDebug('session.load: baseUrl=$baseUrl username=$username');
    return Session(
      baseUrl: baseUrl,
      username: username,
      sessionId: sessionId,
      hasFileSystemPermission: hasFileSystemPermission,
    );
  }

  @override
  Future<void> save(Session session) async {
    final store = await _readStore();
    store['session_baseUrl'] = session.baseUrl;
    store['session_username'] = session.username;
    store['session_sessionId'] = session.sessionId;
    store['session_hasFileSystemPermission'] = session.hasFileSystemPermission;
    await _writeStore(store);
    logDebug(
      'session.save: baseUrl=${session.baseUrl} username=${session.username}',
    );
  }

  @override
  Future<void> clear() async {
    final store = await _readStore();
    store.remove('session_baseUrl');
    store.remove('session_username');
    store.remove('session_sessionId');
    store.remove('session_hasFileSystemPermission');
    await _writeStore(store);
    logDebug('session.clear: 会话已清除');
  }
}
