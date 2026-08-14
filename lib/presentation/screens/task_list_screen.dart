import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_operation.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/screens/login_screen.dart';
import 'package:ffbox_edgelink/presentation/widgets/task_tile.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  AsyncValue<List<Task>> _tasks = const AsyncValue.loading();
  int _failedCount = 0;
  int _latencyMs = 0;
  Timer? _pollTimer;
  bool _refreshing = false;

  /// 正在执行操作的任务 ID 集合，防止重复点击导致并发请求。
  final Set<int> _busyTaskIds = {};

  static const _pollInterval = Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    _refresh();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    if (_tasks.hasError) {
      setState(() => _tasks = const AsyncValue.loading());
    }
    try {
      final result = await ref.read(taskServiceProvider).loadTasks();
      if (!mounted) return;
      setState(() {
        _tasks = AsyncValue.data(result.tasks);
        _failedCount = result.failedCount;
        _latencyMs = result.latencyMs;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        await _logout();
        return;
      }
      setState(() => _tasks = AsyncValue.error(e, StackTrace.current));
    } catch (e) {
      if (!mounted) return;
      setState(() => _tasks = AsyncValue.error(e, StackTrace.current));
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _logout() async {
    await ref.read(sessionRepositoryProvider).clear();
    ref.read(sessionProvider.notifier).update(null);
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  String _hostOf(String? baseUrl) {
    if (baseUrl == null || baseUrl.isEmpty) return '未连接';
    final uri = Uri.tryParse(baseUrl);
    return uri?.host ?? baseUrl;
  }

  Color _latencyColor(int ms) {
    if (ms <= 0) return Colors.grey;
    if (ms < 100) return Colors.green;
    if (ms < 500) return Colors.orange;
    return Colors.red;
  }

  Future<void> _onOperation(Task task, TaskOperation op) async {
    if (_busyTaskIds.contains(task.id)) return;
    _busyTaskIds.add(task.id);
    setState(() {}); // 刷新按钮禁用态

    final service = ref.read(taskServiceProvider);
    final outcome = await service.executeOperation(
      task.id,
      op,
      onStatus: (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      },
    );

    _busyTaskIds.remove(task.id);
    if (!mounted) return;

    if (outcome.unauthorized) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(outcome.message)));
      await _logout();
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(outcome.message)));
    setState(() {}); // 恢复按钮可用态
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final deviceName = _hostOf(session?.baseUrl);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('任务列表'),
            Text(
              '$deviceName · $_latencyMs ms',
              style: TextStyle(fontSize: 12, color: _latencyColor(_latencyMs)),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
          if (_failedCount > 0)
            Container(
              width: double.infinity,
              color: Colors.orange.shade100,
              padding: const EdgeInsets.all(8),
              child: Text('$_failedCount 个任务加载失败，已自动重试'),
            ),
          Expanded(
            child: _tasks.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (tasks) => tasks.isEmpty
                  ? const Center(child: Text('暂无任务'))
                  : ListView.builder(
                      itemCount: tasks.length,
                      itemBuilder: (_, i) {
                        final task = tasks[i];
                        return TaskTile(
                          task: task,
                          disabled: _busyTaskIds.contains(task.id),
                          onOperation: (op) => _onOperation(task, op),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
