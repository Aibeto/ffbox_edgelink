import 'dart:async';

import 'package:ffbox_edgelink/core/network/local_node_channel.dart';

/// 内置 FFBox 服务状态。
enum LocalNodeState {
  /// 未运行。
  stopped,

  /// 启动中（Node 引擎加载 + 服务初始化）。
  starting,

  /// 运行中（HTTP/WS 服务已就绪）。
  running,

  /// 停止中（停止任务 + 终止引擎）。
  stopping,
}

/// 内置 FFBox 服务运行时状态快照。
class LocalNodeStatus {
  final LocalNodeState state;

  /// 服务就绪后的访问地址（运行中非空）。
  final String? baseUrl;

  const LocalNodeStatus({required this.state, this.baseUrl});

  static const stopped = LocalNodeStatus(state: LocalNodeState.stopped);
}

/// 内置 FFBox 服务：状态机 + 日志环形缓冲。
///
/// 纯 Dart 应用服务（不依赖 Riverpod），由 provider 层包装暴露给 UI。
/// 日志缓冲上限 [maxLogLines]，超出丢弃最旧，避免长驻内存增长。
class LocalNodeService {
  /// 日志环形缓冲上限。
  static const maxLogLines = 500;

  /// FFBox 后端默认监听端口。
  static const int defaultPort = 33269;

  /// 去除日志中的 ANSI 转义序列（`\x1b[...m` 颜色码）与残余控制字符。
  /// FFBox 以 ANSI 彩色日志输出，转发到本窗口时 ESC 控制字符在等宽字体下
  /// 无字形会渲染成“口”豆腐块，故统一剥离。
  static String sanitizeLog(String line) => line
      .replaceAll(RegExp(r'\x1B\[[0-9;?]*(?:[ -/]*[@-~])?'), '')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');

  final LocalNodeChannel _channel;

  final _statusController = StreamController<LocalNodeStatus>.broadcast();
  final _logsController = StreamController<String>.broadcast();

  LocalNodeStatus _status = LocalNodeStatus.stopped;
  final List<String> _logs = [];
  StreamSubscription<String>? _logSub;
  bool _initialized = false;

  LocalNodeService([LocalNodeChannel? channel])
    : _channel = channel ?? LocalNodeChannel();

  /// 状态流（UI 订阅）。
  Stream<LocalNodeStatus> get statusStream => _statusController.stream;

  /// 日志流（仅新产生的行；历史用 [snapshotLogs] 一次性读取）。
  Stream<String> get logStream => _logsController.stream;

  /// 当前状态快照。
  LocalNodeStatus get status => _status;

  /// 日志快照（含缓冲内历史）。
  List<String> get logs => List.unmodifiable(_logs);

  /// 服务基地址（登录页可直接填写连接）。
  String get baseUrl => 'http://127.0.0.1:$defaultPort';

  // --- 初始化 ---

  /// 首次使用时建立日志订阅并校准原生侧状态（幂等）。
  Future<void> initialize() async {
    if (_initialized) return;
    // 先校准 ABI（仅 Android arm64-v8a 支持），避免深链直达时误判
    await _channel.querySupported();
    if (!_channel.isSupported) return;
    _initialized = true;
    _logSub = _channel.logLines().listen(
      (raw) {
        final line = sanitizeLog(raw);
        _logs.add(line);
        if (_logs.length > maxLogLines) {
          _logs.removeRange(0, _logs.length - maxLogLines);
        }
        _logsController.add(line);
      },
      onError: (_) {},
    );
    await refresh();
  }

  // --- 状态同步 ---

  /// 向原生侧校准状态（App 重启/服务自停后调用）。
  Future<void> refresh() async {
    if (!_channel.isSupported) return;
    try {
      final running = await _channel.isRunning();
      _update(
        running
            ? LocalNodeStatus(
                state: LocalNodeState.running,
                baseUrl: baseUrl,
              )
            : LocalNodeStatus.stopped,
      );
    } catch (_) {
      // 通道异常时保持当前状态
    }
  }

  // --- 启动 / 停止 ---

  /// 启动本地服务。返回是否成功。
  Future<bool> start() async {
    if (!_channel.isSupported) return false;
    if (_status.state == LocalNodeState.running) return true;
    _update(
      LocalNodeStatus(state: LocalNodeState.starting, baseUrl: baseUrl),
    );
    try {
      final ok = await _channel.start();
      _update(
        ok
            ? LocalNodeStatus(
                state: LocalNodeState.running,
                baseUrl: baseUrl,
              )
            : LocalNodeStatus.stopped,
      );
      return ok;
    } catch (_) {
      _update(LocalNodeStatus.stopped);
      return false;
    }
  }

  /// 停止本地服务。返回是否成功。
  Future<bool> stop() async {
    if (!_channel.isSupported) return false;
    if (_status.state == LocalNodeState.stopped) return true;
    _update(LocalNodeStatus(state: LocalNodeState.stopping));
    try {
      final ok = await _channel.stop();
      _update(LocalNodeStatus.stopped);
      return ok;
    } catch (_) {
      _update(LocalNodeStatus.stopped);
      return false;
    }
  }

  // --- 内部 ---

  void _update(LocalNodeStatus next) {
    if (_status.state == next.state && _status.baseUrl == next.baseUrl) {
      return;
    }
    _status = next;
    _statusController.add(next);
  }

  /// 释放资源（App 退出时调用，不影响后台服务运行）。
  void dispose() {
    _logSub?.cancel();
    _statusController.close();
    _logsController.close();
  }
}
