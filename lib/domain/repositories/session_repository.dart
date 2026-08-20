/// 会话数据。
class Session {
  final String baseUrl;
  final String username;
  final String sessionId;

  /// 登录用户是否拥有 FileSystem 权限（决定任务创建模式，随登录捕获）。
  final bool hasFileSystemPermission;

  const Session({
    required this.baseUrl,
    required this.username,
    required this.sessionId,
    this.hasFileSystemPermission = false,
  });
}

/// 会话存储抽象接口。用于持久化服务器地址与登录凭证。
abstract interface class SessionRepository {
  Future<Session?> load();
  Future<void> save(Session session);
  Future<void> clear();
}
