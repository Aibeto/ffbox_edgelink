import 'package:flutter/foundation.dart';

/// 调试开关：debug 构建为 true，release 构建为 false。
// const bool kDebugMode = kDebugMode;

/// 仅当 [kDebugMode] 为 true 时输出日志（带时间戳）。
void logDebug(String message) {
  if (kDebugMode) {
    final now = DateTime.now();
    final date =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}'
        '.${now.millisecond.toString().padLeft(3, '0')}';
    // ignore: avoid_print
    print('[FFBox EdgeLink] ${date}T${time} $message');
  }
}
