import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/application/auth/auth_service.dart';
import 'package:ffbox_edgelink/application/live/live_activity_service.dart';
import 'package:ffbox_edgelink/application/local_node/local_node_service.dart';
import 'package:ffbox_edgelink/application/task/task_service.dart';
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/core/network/api_client.dart';
import 'package:ffbox_edgelink/core/network/local_node_channel.dart';
import 'package:ffbox_edgelink/core/notifications/live_activity_channel.dart';
import 'package:ffbox_edgelink/data/repositories/auth_repository_impl.dart';
import 'package:ffbox_edgelink/data/repositories/server_repository_impl.dart';
import 'package:ffbox_edgelink/data/repositories/server_settings_repository_impl.dart';
import 'package:ffbox_edgelink/data/repositories/session_repository_impl.dart';
import 'package:ffbox_edgelink/data/repositories/task_repository_impl.dart';
import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:ffbox_edgelink/domain/entities/live_activity_config.dart';
import 'package:ffbox_edgelink/domain/repositories/auth_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/server_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/server_settings_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/session_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';

// --- 服务器配置 ---

/// 服务器地址配置（单一事实来源）。
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig());

// --- 会话管理 ---

/// 当前会话（登录成功写入，登出清空）。
class SessionNotifier extends Notifier<Session?> {
  Session? _initial;

  /// 默认构造（未登录状态）。
  SessionNotifier();

  /// 恢复会话：通过传入初始值，由 build() 直接返回，
  /// 避免在 Notifier 未初始化时调用 state。
  SessionNotifier.initial(Session session) : _initial = session;

  @override
  Session? build() => _initial;

  void update(Session? session) {
    _initial = null; // 仅首次 build 使用
    state = session;
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(
  SessionNotifier.new,
);

// --- 仓储层 ---

/// 会话持久化。
final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepositoryImpl(),
);

/// 服务器连接信息持久化。
final serverRepositoryProvider = Provider<ServerRepository>(
  (ref) => ServerRepositoryImpl(),
);

// --- 网络层 ---

/// HTTP 客户端：请求时从会话读取 token。
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    tokenProvider: () => ref.read(sessionProvider)?.sessionId ?? '',
  ),
);

// --- 数据源 ---

/// FFBox 远端数据源。
final ffboxApiProvider = Provider<FFBoxApi>(
  (ref) => FFBoxApi(ref.watch(apiClientProvider), ref.watch(appConfigProvider)),
);

/// 认证仓储。
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(
    api: ref.watch(ffboxApiProvider),
    config: ref.watch(appConfigProvider),
  ),
);

/// 任务仓储。
final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepositoryImpl(ref.watch(ffboxApiProvider)),
);

/// 服务器配置仓储。
final serverSettingsRepositoryProvider = Provider<ServerSettingsRepository>(
  (ref) => ServerSettingsRepositoryImpl(ref.watch(ffboxApiProvider)),
);

// --- 业务服务 ---

/// 认证服务。
final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(authRepositoryProvider)),
);

/// 任务服务。
final taskServiceProvider = Provider<TaskService>(
  (ref) => TaskService(ref.watch(taskRepositoryProvider)),
);

// --- 实时活动（Android Live Updates） ---

/// 实时活动原生通道。
final liveActivityChannelProvider = Provider<LiveActivityChannel>(
  (ref) => LiveActivityChannel(),
);

/// 实时活动业务服务。
final liveActivityServiceProvider = Provider<LiveActivityService>(
  (ref) => LiveActivityService(ref.watch(liveActivityChannelProvider)),
);

/// 实时活动状态（当前实时通知任务，至多一条）。
class LiveActivityNotifier extends Notifier<LiveActivityState> {
  bool _restored = false;

  @override
  LiveActivityState build() => LiveActivityState.none;

  /// App 启动时恢复原生服务状态（仅执行一次）。
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    final service = ref.read(liveActivityServiceProvider);
    if (!service.isSupported) return;
    try {
      state = await service.query();
    } catch (_) {
      // 原生通道异常时保持关闭态，不阻塞启动
      state = LiveActivityState.none;
    }
  }

  /// 校准原生服务状态（任务完成/删除后服务自停，用于纠正 UI 标记）。
  Future<void> refresh() async {
    final service = ref.read(liveActivityServiceProvider);
    if (!service.isSupported) return;
    try {
      state = await service.query();
    } catch (_) {
      // 通道异常保持当前状态
    }
  }

  /// 启动/替换实时活动（原生只保留一条，切换任务即替换）。
  Future<bool> start({
    required String baseUrl,
    required String sessionId,
    required int taskId,
    required String taskName,
  }) async {
    final config = LiveActivityConfig(
      baseUrl: baseUrl,
      sessionId: sessionId,
      taskId: taskId,
      taskName: taskName,
    );
    final ok = await ref.read(liveActivityServiceProvider).start(config);
    if (ok) state = LiveActivityState(config: config, running: true);
    return ok;
  }

  /// 停止实时活动并清空状态。
  Future<void> stop() async {
    await ref.read(liveActivityServiceProvider).stop();
    state = LiveActivityState.none;
  }
}

final liveActivityProvider =
    NotifierProvider<LiveActivityNotifier, LiveActivityState>(
      LiveActivityNotifier.new,
    );

// --- 内置 FFBox 服务（仅 Android arm64-v8a，nodejs-mobile 本机后端） ---

/// 内置服务原生通道。
final localNodeChannelProvider = Provider<LocalNodeChannel>(
  (ref) => LocalNodeChannel(),
);

/// 当前设备是否支持内置服务（仅 Android 且主 ABI 为 arm64-v8a）。
/// UI 据此决定是否显示「本地服务」入口。
final localNodeSupportedProvider = FutureProvider<bool>((ref) async {
  return ref.watch(localNodeChannelProvider).querySupported();
});

/// 内置服务业务服务（状态机 + 日志缓冲）。
final localNodeServiceProvider = Provider<LocalNodeService>(
  (ref) => LocalNodeService(ref.watch(localNodeChannelProvider)),
);
