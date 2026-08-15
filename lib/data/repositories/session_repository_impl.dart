import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/domain/repositories/session_repository.dart';

/// SessionRepository 的具体实现。
///
/// 使用 SharedPreferences 持久化会话数据（服务器地址+用户名+sessionId），
/// 登录成功写入，登出清空，启动时恢复以实现免重新登录。
class SessionRepositoryImpl implements SessionRepository {
  static const _kBaseUrl = 'session_base_url';
  static const _kUsername = 'session_username';
  static const _kSessionId = 'session_id';

  @override
  Future<Session?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_kBaseUrl);
    final sessionId = prefs.getString(_kSessionId);
    if (baseUrl == null ||
        baseUrl.isEmpty ||
        sessionId == null ||
        sessionId.isEmpty) {
      logDebug('session.load: 无已保存会话');
      return null;
    }
    final username = prefs.getString(_kUsername) ?? '';
    logDebug('session.load: baseUrl=$baseUrl username=$username');
    return Session(baseUrl: baseUrl, username: username, sessionId: sessionId);
  }

  @override
  Future<void> save(Session session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, session.baseUrl);
    await prefs.setString(_kUsername, session.username);
    await prefs.setString(_kSessionId, session.sessionId);
    logDebug(
      'session.save: baseUrl=${session.baseUrl} username=${session.username}',
    );
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBaseUrl);
    await prefs.remove(_kUsername);
    await prefs.remove(_kSessionId);
    logDebug('session.clear: 会话已清除');
  }
}
