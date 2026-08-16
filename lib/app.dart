import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/screens/login_screen.dart';
import 'package:ffbox_edgelink/presentation/screens/task_list_screen.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';

/// 根组件 MaterialApp：路由分发、主题配置。未登录→登录页，已登录→任务列表。
class FFBoxApp extends ConsumerStatefulWidget {
  const FFBoxApp({super.key});

  @override
  ConsumerState<FFBoxApp> createState() => _FFBoxAppState();
}

class _FFBoxAppState extends ConsumerState<FFBoxApp> {
  @override
  void initState() {
    super.initState();
    // 启动时恢复实时活动状态（原生服务可能仍在运行）
    Future.microtask(() => ref.read(liveActivityProvider.notifier).restore());
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return MaterialApp(
      title: 'FFBox EdgeLink',
      debugShowCheckedModeBanner: false,
      theme: AkTheme.dark,
      themeMode: ThemeMode.dark,
      builder: (context, child) => ColoredBox(
        color: AkColors.oledDark,
        child: SafeArea(
          top: true,
          bottom: false,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: session == null ? const LoginScreen() : const TaskListScreen(),
    );
  }
}
