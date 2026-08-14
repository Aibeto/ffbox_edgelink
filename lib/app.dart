import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/screens/login_screen.dart';
import 'package:ffbox_edgelink/presentation/screens/task_list_screen.dart';

class FFBoxApp extends ConsumerWidget {
  const FFBoxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return MaterialApp(
      title: 'FFBox EdgeLink',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: session == null ? const LoginScreen() : const TaskListScreen(),
    );
  }
}
