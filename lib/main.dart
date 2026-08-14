import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/app.dart';
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/data/repositories/session_repository_impl.dart';
import 'package:ffbox_edgelink/domain/repositories/session_repository.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  logDebug('main: 应用启动');
  Session? session;
  try {
    session = await SessionRepositoryImpl().load();
    if (session != null) {
      logDebug(
        'main: 恢复会话 baseUrl=${session.baseUrl} username=${session.username}',
      );
    }
  } catch (e) {
    // 会话读取失败不阻塞启动，按未登录处理
    logDebug('main: 加载会话失败: $e');
  }

  runApp(
    ProviderScope(
      overrides: [
        if (session != null) ...[
          sessionProvider.overrideWith(() => SessionNotifier.initial(session!)),
          appConfigProvider.overrideWith(
            (ref) => AppConfig(baseUrl: session!.baseUrl),
          ),
        ],
      ],
      child: const FFBoxApp(),
    ),
  );
}
