import 'package:flutter/foundation.dart';

/// 调试开关：debug 构建为 true，release 构建为 false。
const bool KDEBUGMODE = kDebugMode;

/// 仅当 [KDEBUGMODE] 为 true 时输出日志（带时间戳）。
void logDebug(String message) {
  if (KDEBUGMODE) {
    final time = DateTime.now().toIso8601String();
    // ignore: avoid_print
    print('[FFBox EdgeLink] $time $message');
  }
}
