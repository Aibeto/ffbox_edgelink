/// Clarity 埋点真实现（原生平台）：包装 clarity_flutter SDK。
///
/// 位于 core 层，供 main.dart 包装根组件与 presentation 层埋点调用。
/// 仅在 Android/iOS 上生效；Windows 等其余原生平台 SDK 不支持
/// （其内部自带平台门控），这里同样直接跳过，保证零开销、零内存累积。
/// 所有 SDK 调用均捕获异常，任何情况下不影响业务流程。
library;

import 'dart:io';

import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:flutter/widgets.dart';

import 'package:ffbox_edgelink/core/utils/log.dart';

class ClarityAnalytics {
  ClarityAnalytics._();

  /// Clarity 项目 ID（Clarity 控制台 Settings 页可查）。
  static const String projectId = 'y3lh7wkt1u';

  /// SDK 仅支持 Android/iOS，其余平台全部静默跳过。
  static final bool enabled = Platform.isAndroid || Platform.isIOS;

  // --- 初始化与包装 ---

  /// 条件包装根组件：受支持平台包 ClarityWidget（会话捕获 + 手势监听），
  /// 其余平台原样返回，不引入任何 widget 开销。
  static Widget wrapApp(Widget app) {
    if (!enabled) return app;
    return ClarityWidget(
      app: app,
      clarityConfig: ClarityConfig(
        projectId: projectId,
        // 关闭 SDK 日志，避免污染控制台；调试初始化问题可临时改 LogLevel.Verbose
        logLevel: LogLevel.None,
      ),
    );
  }

  // --- 埋点 API ---

  /// 上报自定义事件（如 login_success、task_start_failed）。
  static void trackEvent(String name) {
    if (!enabled) return;
    try {
      Clarity.sendCustomEvent(name);
    } catch (e) {
      logDebug('clarity: 上报事件失败 $name: $e');
    }
  }

  /// 设置当前屏幕名；Clarity 以屏幕名变化开启新页面。
  static void trackScreen(String name) {
    if (!enabled) return;
    try {
      Clarity.setCurrentScreenName(name);
    } catch (e) {
      logDebug('clarity: 设置屏幕名失败 $name: $e');
    }
  }

  /// 设置自定义用户标识（调用方应传入不可逆哈希，避免 PII）。
  static void identify(String hashedUserId) {
    if (!enabled) return;
    try {
      Clarity.setCustomUserId(hashedUserId);
    } catch (e) {
      logDebug('clarity: 设置用户标识失败: $e');
    }
  }

  /// 设置会话级自定义标签（如 server=主机名）。
  static void setTag(String key, String value) {
    if (!enabled) return;
    try {
      Clarity.setCustomTag(key, value);
    } catch (e) {
      logDebug('clarity: 设置标签失败 $key=$value: $e');
    }
  }
}
