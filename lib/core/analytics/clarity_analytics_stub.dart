/// Clarity 埋点 Web 桩实现：全量 no-op。
///
/// clarity_flutter SDK 不支持 Web（依赖 dart:io 与原生插件），
/// Web 构建经条件导出落到本文件，接口签名与 IO 实现保持一致。
library;

import 'package:flutter/widgets.dart';

class ClarityAnalytics {
  ClarityAnalytics._();

  /// 与真实现保持同名的项目 ID 常量（Web 下不使用）。
  static const String projectId = 'y3lh7wkt1u';

  /// Web 下恒为 false，所有埋点调用直接返回。
  static const bool enabled = false;

  static Widget wrapApp(Widget app) => app;

  static void trackEvent(String name) {}

  static void trackScreen(String name) {}

  static void identify(String hashedUserId) {}

  static void setTag(String key, String value) {}
}
