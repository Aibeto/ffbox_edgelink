/// 应用运行时配置。服务器地址可变，由登录页写入。
class AppConfig {
  String baseUrl;

  AppConfig({this.baseUrl = ''});

  // --- 地址规范化 ---

  /// 规范化地址，确保无尾部斜杠。
  String get normalizedBaseUrl {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  // --- 本机检测 ---

  /// 判断当前地址是否为本机（允许匿名登录）。
  bool get isLocalhost {
    try {
      final uri = Uri.parse(normalizedBaseUrl);
      final host = uri.host.toLowerCase();
      return host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0';
    } catch (_) {
      return false;
    }
  }
}
