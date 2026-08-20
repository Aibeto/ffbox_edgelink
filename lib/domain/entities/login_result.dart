/// 登录结果实体。
class LoginResult {
  final bool isUserExist;
  final bool isSuccess;
  final String sessionId;
  final int functionLevel;

  /// 用户权限列表（如 fileSystem）。undefined/空表示未配置权限（全部开放）。
  final List<String> permissions;

  const LoginResult({
    required this.isUserExist,
    required this.isSuccess,
    this.sessionId = '',
    this.functionLevel = 0,
    this.permissions = const [],
  });

  /// 是否拥有 FileSystem 权限（服务端据此决定任务走原路径还是上传托管）。
  bool get hasFileSystemPermission => permissions.isEmpty || permissions.contains('fileSystem');

  factory LoginResult.fromJson(Map<String, dynamic> json) => LoginResult(
        isUserExist: json['isUserExist'] as bool? ?? false,
        isSuccess: json['isSuccess'] as bool? ?? false,
        sessionId: json['sessionId'] as String? ?? '',
        functionLevel: (json['functionLevel'] as num?)?.toInt() ?? 0,
        permissions: (json['permissions'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
      );
}
