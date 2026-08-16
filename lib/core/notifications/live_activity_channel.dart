import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ffbox_edgelink/domain/entities/live_activity_config.dart';

/// 实时活动 MethodChannel 封装。
///
/// 桥接 Android 原生前台服务（LiveTaskService）。非 Android 平台
/// [isSupported] 返回 false，调用侧应隐藏开关、不发起调用。
class LiveActivityChannel {
  static const MethodChannel _channel = MethodChannel(
    'top.raincrat.aibeto.ffboxedgelink/live_activity',
  );

  /// 是否支持实时活动（仅 Android 真机/模拟器）。
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 启动/替换实时活动（原生保证只存在一条）。返回是否成功（可能因权限拒绝）。
  Future<bool> start(LiveActivityConfig config) async {
    final ok = await _channel.invokeMethod<bool>(
      'startLiveActivity',
      config.toMap(),
    );
    return ok ?? false;
  }

  /// 停止实时活动并移除通知。
  Future<void> stop() async {
    await _channel.invokeMethod<void>('stopLiveActivity');
  }

  /// 查询实时活动服务是否在运行。
  Future<bool> isRunning() async {
    final running = await _channel.invokeMethod<bool>('isLiveActivityRunning');
    return running ?? false;
  }

  /// 读取原生保存的当前活跃配置（App 重启后恢复 UI 状态）。
  Future<LiveActivityConfig?> getActiveConfig() async {
    final json = await _channel.invokeMethod<String>('getActiveConfig');
    if (json == null || json.isEmpty) return null;
    return LiveActivityConfig.fromJsonString(json);
  }
}
