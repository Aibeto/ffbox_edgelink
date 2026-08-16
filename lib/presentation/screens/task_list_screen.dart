import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_operation.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/screens/task_detail_screen.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';
import 'package:ffbox_edgelink/presentation/widgets/task_tile.dart';

/// 任务列表页：1s 轮询刷新、任务操作（启动/暂停/继续/删除）、设备名+延迟显示。
class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  // --- 状态与轮询 ---

  AsyncValue<List<Task>> _tasks = const AsyncValue.loading();
  int _failedCount = 0;
  int _latencyMs = 0;
  Timer? _pollTimer;
  bool _refreshing = false;
  String? _statusMessage;
  int? _statusTaskId;

  /// 正在执行操作的任务 ID 集合，防止重复点击导致并发请求。
  final Set<int> _busyTaskIds = {};

  static const _pollInterval = Duration(seconds: 1);

  // --- 初始化与销毁 ---

  @override
  void initState() {
    super.initState();
    logDebug('taskListUI: initState, 启动 1s 轮询');
    _refresh();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    logDebug('taskListUI: dispose, 停止轮询');
    super.dispose();
  }

  // --- 数据刷新 ---

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    if (_tasks.hasError) {
      setState(() => _tasks = const AsyncValue.loading());
    }
    try {
      final result = await ref
          .read(taskServiceProvider)
          .loadTasks(silent: true);
      if (!mounted) return;
      setState(() {
        _tasks = AsyncValue.data(result.tasks);
        _failedCount = result.failedCount;
        _latencyMs = result.latencyMs;
        _statusMessage = null;
        _statusTaskId = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        logDebug('taskListUI: refresh 401 -> 登出');
        await _logout();
        return;
      }
      logDebug(
        'taskListUI: refresh error ApiException kind=${e.kind} ${e.friendlyMessage}',
      );
      setState(() => _tasks = AsyncValue.error(e, StackTrace.current));
      _stopPolling();
    } catch (e) {
      if (!mounted) return;
      logDebug('taskListUI: refresh error $e');
      setState(() => _tasks = AsyncValue.error(e, StackTrace.current));
      _stopPolling();
    } finally {
      _refreshing = false;
    }
  }

  /// 连接丢失后停止自动轮询，等待用户手动重试，避免错误/加载中每秒交替闪烁。
  void _stopPolling() {
    if (_pollTimer != null) {
      logDebug('taskListUI: 连接丢失');
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  /// 手动重试：恢复 1s 轮询并立即刷新。
  void _retry() {
    logDebug('taskListUI: 重试');
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refresh());
    _refresh();
  }

  Future<void> _logout() async {
    logDebug('taskListUI: 用户登出');
    await ref.read(sessionRepositoryProvider).clear();
    // 清空会话后由 FFBoxApp 根路由自动切回登录页。不要手动 push 登录页，
    // 否则会替换掉根路由，导致重新登录后仍停留在登录页无法刷新。
    ref.read(sessionProvider.notifier).update(null);
  }

  // --- 任务操作 ---

  void _openDetail(Task task) {
    logDebug('taskListUI: 打开详情 id=${task.id}');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(taskId: task.id, initialTask: task),
      ),
    );
  }

  String _hostOf(String? baseUrl) {
    if (baseUrl == null || baseUrl.isEmpty) return '未连接';
    final uri = Uri.tryParse(baseUrl);
    return uri?.host ?? baseUrl;
  }

  Color _latencyColor(int ms) {
    if (ms <= 0) return AkColors.textSecondary;
    if (ms < 100) return AkColors.success;
    if (ms < 500) return AkColors.action;
    return AkColors.danger;
  }

  Future<void> _onOperation(Task task, TaskOperation op) async {
    if (_busyTaskIds.contains(task.id)) return;
    _busyTaskIds.add(task.id);
    logDebug('taskListUI: 执行操作 id=${task.id} op=$op');
    final verb = _verb(op);
    setState(() {
      _statusTaskId = task.id;
      _statusMessage = '正在$verb...';
    });

    final service = ref.read(taskServiceProvider);
    final outcome = await service.executeOperation(
      task.id,
      op,
      onStatus: (msg) {
        if (!mounted) return;
        setState(() => _statusMessage = msg);
      },
    );

    _busyTaskIds.remove(task.id);
    if (!mounted) return;

    if (outcome.unauthorized) {
      logDebug('taskListUI: 操作 id=${task.id} op=$op -> unauthorized, 登出');
      setState(() => _statusMessage = outcome.message);
      await _logout();
      return;
    }
    logDebug(
      'taskListUI: 操作 id=${task.id} op=$op -> ${outcome.status.name}: ${outcome.message}',
    );
    setState(() => _statusMessage = outcome.message);
    await _refresh();
    // 兜底：refresh 失败时清除过期操作提示，避免与错误横幅同时显示
    if (!mounted) return;
    if (_statusMessage == outcome.message) {
      setState(() {
        _statusMessage = null;
        _statusTaskId = null;
      });
    }
  }

  // --- 辅助方法 ---

  String _verb(TaskOperation op) => switch (op) {
    TaskOperation.start => '启动',
    TaskOperation.pause => '暂停',
    TaskOperation.resume => '继续',
    TaskOperation.delete => '删除',
    _ => '操作',
  };

  // --- 构建 UI ---

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final deviceName = _hostOf(session?.baseUrl);

    return Scaffold(
      appBar: _AkAppBar(
        title: deviceName,
        latencyMs: _latencyMs,
        latencyColor: _latencyColor(_latencyMs),
        onRefresh: _refresh,
        onLogout: _logout,
      ),
      body: Column(
        children: [
          // --- 内联操作状态 ---
          if (_statusMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: AkColors.oledDark,
                border: Border(
                  bottom: BorderSide(
                    color: AkColors.border,
                    width: AkTheme.hairline,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AkColors.info,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_statusTaskId != null) ...[
                    Text(
                      '#$_statusTaskId ',
                      style: AkTheme.mono(
                        fontSize: 11,
                        color: AkColors.textSecondary,
                      ),
                    ),
                  ],
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: AkTheme.sans(
                        fontSize: 11,
                        color: AkColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // --- Failed count warning bar ---
          if (_failedCount > 0) _FailedWarningBar(count: _failedCount),

          // --- Task list ---
          Expanded(
            child: _tasks.when(
              loading: () => Center(
                child: CircularProgressIndicator(
                  color: AkColors.info,
                  strokeWidth: 2,
                ),
              ),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: AkColors.danger, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      '加载失败',
                      style: AkTheme.sans(
                        fontSize: 16,
                        color: AkColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$e',
                      style: AkTheme.sans(
                        fontSize: 12,
                        color: AkColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _retry,
                      icon: const Icon(
                        Icons.refresh,
                        size: 16,
                        color: AkColors.info,
                      ),
                      label: Text(
                        '重试',
                        style: AkTheme.sans(
                          fontSize: 13,
                          color: AkColors.info,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        backgroundColor: AkColors.info.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AkTheme.cutSm),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              data: (tasks) => tasks.isEmpty
                  ? Center(
                      child: Text(
                        '暂无任务',
                        style: AkTheme.sans(
                          fontSize: 15,
                          color: AkColors.textSecondary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: tasks.length,
                      itemBuilder: (_, i) {
                        final task = tasks[i];
                        return TaskTile(
                          task: task,
                          disabled: _busyTaskIds.contains(task.id),
                          onOperation: (op) => _onOperation(task, op),
                          onTap: () => _openDetail(task),
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

// ---------------------------------------------------------------------------
// ak-ui AppBar: dark panel with hostname + monospace latency
// ---------------------------------------------------------------------------

class _AkAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final int latencyMs;
  final Color latencyColor;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;

  const _AkAppBar({
    required this.title,
    required this.latencyMs,
    required this.latencyColor,
    required this.onRefresh,
    required this.onLogout,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: preferredSize.height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AkColors.oledDark,
        border: Border(
          bottom: BorderSide(color: AkColors.border, width: AkTheme.strongLine),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Connection signal dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: latencyMs > 0 ? AkColors.success : AkColors.danger,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),

            // Server name
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AkTheme.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AkColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$latencyMs ms',
                    style: AkTheme.mono(fontSize: 11, color: latencyColor),
                  ),
                ],
              ),
            ),

            // Refresh
            _AppBarIconButton(
              icon: Icons.refresh,
              tooltip: '刷新',
              onPressed: onRefresh,
            ),

            // Logout
            _AppBarIconButton(
              icon: Icons.logout,
              tooltip: '登出',
              onPressed: onLogout,
            ),
          ],
        ),
      ),
    );
  }
}

class _AppBarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _AppBarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20, color: AkColors.textSecondary),
      tooltip: tooltip,
      onPressed: onPressed,
      splashRadius: 20,
      hoverColor: AkColors.border.withValues(alpha: 0.5),
    );
  }
}

// ---------------------------------------------------------------------------
// Failed count warning bar
// ---------------------------------------------------------------------------

class _FailedWarningBar extends StatelessWidget {
  final int count;

  const _FailedWarningBar({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AkColors.action.withValues(alpha: 0.12),
        border: Border(
          left: BorderSide(color: AkColors.action, width: AkTheme.signalBorder),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: AkColors.action),
          const SizedBox(width: 8),
          Text(
            '$count 个任务加载失败，已自动重试',
            style: AkTheme.sans(
              fontSize: 13,
              color: AkColors.action,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
