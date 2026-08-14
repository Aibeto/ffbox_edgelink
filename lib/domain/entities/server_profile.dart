/// 最近使用过的服务器连接信息（不含 sessionId），用于登录页回填。
class ServerProfile {
  final String baseUrl;
  final String username;

  const ServerProfile({required this.baseUrl, required this.username});
}
