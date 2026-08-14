/// 登录结果实体。
class LoginResult {
  final bool isUserExist;
  final bool isSuccess;
  final String sessionId;
  final int functionLevel;

  const LoginResult({
    required this.isUserExist,
    required this.isSuccess,
    this.sessionId = '',
    this.functionLevel = 0,
  });

  factory LoginResult.fromJson(Map<String, dynamic> json) => LoginResult(
        isUserExist: json['isUserExist'] as bool? ?? false,
        isSuccess: json['isSuccess'] as bool? ?? false,
        sessionId: json['sessionId'] as String? ?? '',
        functionLevel: (json['functionLevel'] as num?)?.toInt() ?? 0,
      );
}
