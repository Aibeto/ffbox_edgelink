import 'package:ffbox_edgelink/core/notifications/live_activity_channel.dart';
import 'package:ffbox_edgelink/domain/entities/live_activity_config.dart';

/// 实时活动状态：当前进入实时通知模式的任务（同一时刻至多一条）。
class LiveActivityState {
  final LiveActivityConfig? config;
  final bool running;

  const LiveActivityState({this.config, this.running = false});

  static const none = LiveActivityState();

  /// 是否有正在运行的实时活动。
  bool get isActive => running && config != null;

  /// 指定任务是否为当前实时活动。
  bool isActiveFor(int taskId) => isActive && config!.taskId == taskId;
}

/// 实时活动业务服务：封装原生通道，管理「只允许一条」的启动/停止语义。
///
/// 实际唯一性由 Android 单例前台服务 + 固定通知 ID 保证：
/// 启动新任务即替换旧任务，无需显式先停止。
class LiveActivityService {
  final LiveActivityChannel _channel;

  LiveActivityService(this._channel);

  /// 是否支持（仅 Android）。
  bool get isSupported => _channel.isSupported;

  /// 启动/替换实时活动。返回 false 表示未启动（如通知权限被拒）。
  Future<bool> start(LiveActivityConfig config) => _channel.start(config);

  /// 停止实时活动并移除通知。
  Future<void> stop() => _channel.stop();

  /// 查询当前实时活动状态（App 启动恢复用）。
  Future<LiveActivityState> query() async {
    if (!_channel.isSupported) return LiveActivityState.none;
    final running = await _channel.isRunning();
    final config = await _channel.getActiveConfig();
    return LiveActivityState(config: config, running: running);
  }
}
