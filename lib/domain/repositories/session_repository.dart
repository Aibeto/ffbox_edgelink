/// 会话数据。
class Session {
  final String baseUrl;
  final String username;
  final String sessionId;

  const Session({
    required this.baseUrl,
    required this.username,
    required this.sessionId,
  });
}

/// 会话存储抽象接口。用于持久化服务器地址与登录凭证。
abstract interface class SessionRepository {
  Future<Session?> load();
  Future<void> save(Session session);
  Future<void> clear();
}
