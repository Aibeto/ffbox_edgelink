import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/application/auth/auth_service.dart';
import 'package:ffbox_edgelink/application/task/task_service.dart';
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/core/network/api_client.dart';
import 'package:ffbox_edgelink/data/repositories/auth_repository_impl.dart';
import 'package:ffbox_edgelink/data/repositories/server_repository_impl.dart';
import 'package:ffbox_edgelink/data/repositories/session_repository_impl.dart';
import 'package:ffbox_edgelink/data/repositories/task_repository_impl.dart';
import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:ffbox_edgelink/domain/repositories/auth_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/server_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/session_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';

/// 服务器地址配置（单一事实来源）。
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig());

/// 当前会话（登录成功写入，登出清空）。
class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() => null;

  void update(Session? session) => state = session;
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(
  SessionNotifier.new,
);

/// 会话持久化。
final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepositoryImpl(),
);

/// 服务器连接信息持久化。
final serverRepositoryProvider = Provider<ServerRepository>(
  (ref) => ServerRepositoryImpl(),
);

/// HTTP 客户端：请求时从会话读取 token。
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    tokenProvider: () => ref.read(sessionProvider)?.sessionId ?? '',
  ),
);

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

/// 认证服务。
final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(authRepositoryProvider)),
);

/// 任务服务。
final taskServiceProvider = Provider<TaskService>(
  (ref) => TaskService(ref.watch(taskRepositoryProvider)),
);
