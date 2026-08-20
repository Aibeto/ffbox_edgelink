import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/application/auth/auth_service.dart';
import 'package:ffbox_edgelink/application/config/codec_catalog_service.dart';
import 'package:ffbox_edgelink/application/live/live_activity_service.dart';
import 'package:ffbox_edgelink/application/local_node/local_node_service.dart';
import 'package:ffbox_edgelink/application/local_node/local_output_service.dart';
import 'package:ffbox_edgelink/application/task/task_service.dart';
import 'package:ffbox_edgelink/application/upload/chunk_hasher.dart';
import 'package:ffbox_edgelink/application/upload/upload_queue.dart';
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/core/network/api_client.dart';
import 'package:ffbox_edgelink/core/network/local_node_channel.dart';
import 'package:ffbox_edgelink/core/notifications/live_activity_channel.dart';
import 'package:ffbox_edgelink/core/notifications/upload_notification_channel.dart';
import 'package:ffbox_edgelink/data/repositories/auth_repository_impl.dart';
import 'package:ffbox_edgelink/data/repositories/codec_catalog_repository_impl.dart';
import 'package:ffbox_edgelink/data/repositories/server_repository_impl.dart';
import 'package:ffbox_edgelink/data/repositories/server_settings_repository_impl.dart';
import 'package:ffbox_edgelink/data/repositories/session_repository_impl.dart';
import 'package:ffbox_edgelink/data/repositories/task_repository_impl.dart';
import 'package:ffbox_edgelink/data/repositories/upload_repository_impl.dart';
import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:ffbox_edgelink/domain/entities/codec_catalog.dart';
import 'package:ffbox_edgelink/domain/entities/live_activity_config.dart';
import 'package:ffbox_edgelink/domain/repositories/auth_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/codec_catalog_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/server_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/server_settings_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/session_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/upload_repository.dart';

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

/// 文件上传仓储。
final uploadRepositoryProvider = Provider<UploadRepository>(
  (ref) => UploadRepositoryImpl(ref.watch(ffboxApiProvider)),
);

/// 服务器配置仓储。
final serverSettingsRepositoryProvider = Provider<ServerSettingsRepository>(
  (ref) => ServerSettingsRepositoryImpl(ref.watch(ffboxApiProvider)),
);

// --- 转码配置目录 ---

/// 编码目录仓储。
final codecCatalogRepositoryProvider = Provider<CodecCatalogRepository>(
  (ref) => CodecCatalogRepositoryImpl(ref.watch(ffboxApiProvider)),
);

/// 编码目录应用服务。
final codecCatalogServiceProvider = Provider<CodecCatalogService>(
  (ref) => CodecCatalogService(ref.watch(codecCatalogRepositoryProvider)),
);

/// 编码目录状态：内置定义 + 服务端扫描合并；拉取失败回退仅内置。
final codecCatalogProvider = FutureProvider<CodecCatalog>((ref) async {
  final service = ref.watch(codecCatalogServiceProvider);
  try {
    return await service.refresh();
  } catch (_) {
    return service.builtinCatalog;
  }
});

// --- 业务服务 ---

/// 认证服务。
final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(authRepositoryProvider)),
);

// --- 本地输出（内置服务输出缓存与直连路径决策） ---

/// 本地输出服务：回环判断、输出缓存目录管理、输出文件路径解析。
final localOutputServiceProvider = Provider<LocalOutputService>(
  (ref) => LocalOutputService(),
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

// --- 远程上传（后台队列 + Android 进度通知） ---

/// 上传进度原生通道。
final uploadNotificationChannelProvider = Provider<UploadNotificationChannel>(
  (ref) => UploadNotificationChannel(),
);

/// 全局上传队列（生命周期独立于页面）。
final uploadQueueProvider = Provider<UploadQueue>((ref) {
  final queue = UploadQueue(
    repository: ref.watch(uploadRepositoryProvider),
    hasher: ChunkHasher(),
  );
  ref.onDispose(queue.dispose);
  return queue;
});

/// 队列状态流（列表页横幅与新建任务页共用）。
final uploadQueueStateProvider = StreamProvider<UploadQueueSnapshot>(
  (ref) => ref.watch(uploadQueueProvider).states,
);

/// 通知桥接：订阅队列状态，500ms 节流更新 Android 进度通知。
/// 需在任务列表页 build 中 watch 以激活。
final uploadNotificationBridgeProvider = Provider<void>((ref) {
  final channel = ref.watch(uploadNotificationChannelProvider);
  if (!channel.isSupported) return;
  Timer? throttle;
  var lastShown = false;
  final sub = ref.watch(uploadQueueProvider).states.listen((snap) {
    if (throttle?.isActive ?? false) return;
    throttle = Timer(const Duration(milliseconds: 500), () async {
      final active = snap.items
          .where(
            (i) =>
                i.state == UploadItemState.pending ||
                i.state == UploadItemState.hashing ||
                i.state == UploadItemState.uploading ||
                i.state == UploadItemState.merging,
          )
          .toList();
      if (active.isNotEmpty) {
        final current = active.firstWhere(
          (i) => i.state != UploadItemState.pending,
          orElse: () => active.first,
        );
        final percent = current.size > 0
            ? (current.transferredBytes * 100 / current.size)
                  .round()
                  .clamp(0, 100)
                  .toInt()
            : 0;
        await channel.show(
          title: 'FFBox 上传任务',
          content: '${current.fileBaseName} · $percent%',
          progress: percent,
          indeterminate: current.state == UploadItemState.hashing,
        );
        lastShown = true;
      } else if (lastShown) {
        await channel.cancel();
        lastShown = false;
      }
    });
  });
  ref.onDispose(() {
    throttle?.cancel();
    sub.cancel();
  });
});

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
