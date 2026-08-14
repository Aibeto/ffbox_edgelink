import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffbox_edgelink/domain/repositories/session_repository.dart';

class SessionRepositoryImpl implements SessionRepository {
  static const _kBaseUrl = 'session_base_url';
  static const _kUsername = 'session_username';
  static const _kSessionId = 'session_id';

  @override
  Future<Session?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_kBaseUrl);
    final sessionId = prefs.getString(_kSessionId);
    if (baseUrl == null || baseUrl.isEmpty || sessionId == null || sessionId.isEmpty) {
      return null;
    }
    return Session(
      baseUrl: baseUrl,
      username: prefs.getString(_kUsername) ?? '',
      sessionId: sessionId,
    );
  }

  @override
  Future<void> save(Session session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, session.baseUrl);
    await prefs.setString(_kUsername, session.username);
    await prefs.setString(_kSessionId, session.sessionId);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBaseUrl);
    await prefs.remove(_kUsername);
    await prefs.remove(_kSessionId);
  }
}
