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
  Session? session;
  try {
    session = await SessionRepositoryImpl().load();
  } catch (e) {
    // 会话读取失败不阻塞启动，按未登录处理
    logDebug('加载会话失败: $e');
  }

  runApp(
    ProviderScope(
      overrides: [
        if (session != null) ...[
          sessionProvider.overrideWith(
            () => SessionNotifier()..update(session!),
          ),
          appConfigProvider.overrideWith(
            (ref) => AppConfig(baseUrl: session!.baseUrl),
          ),
        ],
      ],
      child: const FFBoxApp(),
    ),
  );
}
