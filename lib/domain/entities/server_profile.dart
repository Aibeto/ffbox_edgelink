/// 最近使用过的服务器连接信息，用于登录页回填和历史记录。
class ServerProfile {
  final String baseUrl;
  final String username;
  final String password;
  final DateTime timestamp;

  ServerProfile({
    required this.baseUrl,
    required this.username,
    this.password = '',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// 从 JSON 构造（历史记录反序列化用）。
  factory ServerProfile.fromJson(Map<String, dynamic> json) {
    return ServerProfile(
      baseUrl: json['baseUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  /// 序列化为 JSON（历史记录持久化用）。
  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'username': username,
    'password': password,
    'timestamp': timestamp.toIso8601String(),
  };

  /// 用于回填的简化副本（不含密码和时间戳）。
  ServerProfile get latest =>
      ServerProfile(baseUrl: baseUrl, username: username);
}
