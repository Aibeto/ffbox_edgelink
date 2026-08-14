/// 应用运行时配置。服务器地址可变，由登录页写入。
class AppConfig {
  String baseUrl;

  AppConfig({this.baseUrl = ''});

  /// 规范化地址，确保无尾部斜杠。
  String get normalizedBaseUrl {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
}
