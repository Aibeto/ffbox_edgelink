import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 上传进度 MethodChannel 封装。
///
/// 桥接 Android 原生进度通知（固定 ID 3002，channel upload，静默）。
/// 非 Android 平台 [isSupported] 返回 false，调用侧跳过。
class UploadNotificationChannel {
  static const MethodChannel _channel = MethodChannel(
    'top.raincrat.aibeto.ffboxedgelink/upload_notification',
  );

  static const int notificationId = 3002;

  /// 是否支持上传通知（仅 Android）。
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 显示/更新进度通知。progress 0-100，indeterminate 为 true 时不显示具体刻度。
  Future<void> show({
    required String title,
    required String content,
    required int progress,
    bool indeterminate = false,
  }) async {
    await _channel.invokeMethod<void>('show', {
      'title': title,
      'content': content,
      'progress': progress,
      'indeterminate': indeterminate,
    });
  }

  /// 移除上传通知。
  Future<void> cancel() async {
    await _channel.invokeMethod<void>('cancel');
  }
}
