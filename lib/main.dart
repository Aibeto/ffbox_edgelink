import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/app.dart';
import 'package:ffbox_edgelink/core/analytics/clarity_analytics.dart';
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/core/utils/file_logger.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/data/repositories/session_repository_impl.dart';
import 'package:ffbox_edgelink/domain/repositories/session_repository.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';

/// 应用入口：初始化、会话恢复、启动 ProviderScope。
Future<void> main() async {
  // --- 初始化 ---

  WidgetsFlutterBinding.ensureInitialized();

  // --- 系统 UI 配置 ---

  // Android 状态栏/导航栏：透明背景 + 浅色图标，由 Scaffold 背景色填充状态栏区域
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // --- 文件日志初始化 ---

  await fileLogger.init();
  await fileLogger.cleanOldLogs();

  // --- 会话恢复 ---

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

  // --- 启动应用 ---

  // Clarity 仅在 Android/iOS 上包装生效，Windows/Web 调试构建零开销
  runApp(
    ClarityAnalytics.wrapApp(
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
    ),
  );
}
