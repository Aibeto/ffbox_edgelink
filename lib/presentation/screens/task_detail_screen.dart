import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffbox_edgelink/application/local_node/local_output_service.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_operation.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';
import 'package:ffbox_edgelink/core/analytics/clarity_analytics.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';
import 'package:ffbox_edgelink/presentation/widgets/marquee_text.dart';
import 'package:ffbox_edgelink/presentation/widgets/status_badge.dart';

/// 任务详情页：完整展示转码详情，每 500ms 轮询刷新。
class TaskDetailScreen extends ConsumerStatefulWidget {
  final int taskId;
  final Task? initialTask;

  const TaskDetailScreen({super.key, required this.taskId, this.initialTask});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  // --- 状态 ---

  Task? _task;
  int _latencyMs = 0;
  String? _error;
  Timer? _pollTimer;
  bool _refreshing = false;
  final Set<TaskOperation> _busyOps = {};
  String? _statusMessage;

  /// 正在导出的输出文件路径（同时仅一个导出任务）。
  String? _exportingPath;

  /// 远程下载进度 [0,1]；null 表示不确定进度（本机解析/保存拷贝阶段）。
  double? _exportProgress;

  static const _pollInterval = Duration(milliseconds: 500);

  // --- 初始化与销毁 ---

  @override
  void initState() {
    super.initState();
    ClarityAnalytics.trackScreen('task_detail');
    _task = widget.initialTask;
    logDebug('taskDetailUI: initState id=${widget.taskId}');
    _refresh();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    logDebug('taskDetailUI: dispose id=${widget.taskId}');
    super.dispose();
  }

  // --- 数据刷新 ---

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final sw = Stopwatch()..start();
    try {
      final task = await ref
          .read(taskRepositoryProvider)
          .getTask(widget.taskId, silent: true);
      sw.stop();
      if (!mounted) return;
      logDebug(
        'taskDetailUI: refresh ok id=${task.id} status=${task.status.apiValue} '
        'latency=${sw.elapsedMilliseconds}ms',
      );
      setState(() {
        _task = task;
        _latencyMs = sw.elapsedMilliseconds;
        _error = null;
        _statusMessage = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        logDebug('taskDetailUI: 401 -> 登出');
        await _logout();
        return;
      }
      logDebug(
        'taskDetailUI: refresh error kind=${e.kind} ${e.friendlyMessage}',
      );
      setState(() => _error = e.friendlyMessage);
      _stopPolling();
    } catch (e) {
      if (!mounted) return;
      logDebug('taskDetailUI: refresh error $e');
      setState(() => _error = '$e');
      _stopPolling();
    } finally {
      _refreshing = false;
    }
  }

  /// 连接丢失后停止自动轮询，等待用户手动重试，避免无效请求每秒重发。
  void _stopPolling() {
    if (_pollTimer != null) {
      logDebug('taskDetailUI: 连接丢失');
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  /// 手动重试：恢复 500ms 轮询并立即刷新。
  void _retry() {
    logDebug('taskDetailUI: 手动重试 id=${widget.taskId}');
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refresh());
    _refresh();
  }

  // --- 登出 ---

  Future<void> _logout() async {
    logDebug('taskDetailUI: 用户登出');
    await ref.read(sessionRepositoryProvider).clear();
    // 清空会话后由 FFBoxApp 根路由自动切回登录页；详情页是 push 出来的，
    // 只需弹回根路由，不要手动 push 登录页替换根路由。
    ref.read(sessionProvider.notifier).update(null);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // --- 任务操作 ---

  Future<void> _onOperation(TaskOperation op) async {
    if (_busyOps.contains(op) || _task == null) return;
    _busyOps.add(op);
    setState(() {
      _statusMessage = '正在${_verb(op)}...';
    });
    final outcome = await ref
        .read(taskServiceProvider)
        .executeOperation(
          widget.taskId,
          op,
          onStatus: (msg) {
            if (!mounted) return;
            setState(() => _statusMessage = msg);
          },
        );
    _busyOps.remove(op);
    if (!mounted) return;
    // Clarity 埋点：任务操作三态（success/failed/unconfirmed）
    ClarityAnalytics.trackEvent('task_${op.name}_${outcome.status.name}');
    if (outcome.unauthorized) {
      setState(() => _statusMessage = outcome.message);
      await _logout();
      return;
    }
    setState(() => _statusMessage = outcome.message);
    await _refresh();
    // 兜底：refresh 失败时清除过期操作提示，避免与错误横幅同时显示
    if (!mounted) return;
    if (_statusMessage == outcome.message) {
      setState(() => _statusMessage = null);
    }
  }

  String _verb(TaskOperation op) => switch (op) {
    TaskOperation.start => '启动',
    TaskOperation.pause => '暂停',
    TaskOperation.resume => '继续',
    TaskOperation.delete => '删除',
    _ => '操作',
  };

  Color _latencyColor(int ms) {
    if (ms <= 0) return AkColors.textSecondary;
    if (ms < 100) return AkColors.success;
    if (ms < 500) return AkColors.action;
    return AkColors.danger;
  }

  // --- 格式化工具 ---

  String _formatDateTime(num? timestampMs) {
    if (timestampMs == null || timestampMs <= 0) return '--';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs.toInt());
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} '
        '${pad(dt.hour)}:${pad(dt.minute)}:${pad(dt.second)}';
  }

  String _formatBytes(num? bytes) {
    if (bytes == null || bytes <= 0) return '--';
    if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  /// 判断输入封装是否为图片格式（基于 FFmpeg demuxer 名称）。
  bool _isImageDemuxer(String demuxer) {
    const imageDemuxers = {
      'image2',
      'image2pipe',
      'mjpeg',
      'mjpeg_pipe',
      'png',
      'png_pipe',
      'bmp',
      'bmp_pipe',
      'tiff',
      'tiff_pipe',
      'webp',
      'webp_pipe',
      'gif',
      'apng',
      'rawvideo',
    };
    return imageDemuxers.contains(demuxer);
  }

  String _formatBitrate(num? bps) {
    if (bps == null || bps <= 0) return '--';
    if (bps >= 1 << 20) return '${(bps / (1 << 20)).toStringAsFixed(1)} Mb/s';
    if (bps >= 1 << 10) return '${(bps / (1 << 10)).toStringAsFixed(0)} Kb/s';
    return '$bps b/s';
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    return Scaffold(
      appBar: _buildAppBar(task),
      body: task == null
          ? (_error != null
                ? _buildInitialError()
                : const Center(
                    child: CircularProgressIndicator(
                      color: AkColors.info,
                      strokeWidth: 2,
                    ),
                  ))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (_error != null)
                  _ErrorBanner(message: _error!, onRetry: _retry),
                _buildHeader(task),
                _buildInputCard(task),
                _buildOutputConfigCard(task),
                _buildProgressCard(task),
                _buildOutputFilesCard(task),
                // 任务处于 error 状态时强制显示错误卡片（即使 errorInfo 为空），
                // 或展示 reset 后保留的历史报错（error 活跃态，见 AGENTS.md）
                if (task.status == TaskStatus.error ||
                    task.errorInfo.isNotEmpty)
                  _buildErrorCard(task),
                _buildLogCard(task),
              ],
            ),
    );
  }

  /// 首次加载失败（_task 为 null）时显示的居中错误视图。
  Widget _buildInitialError() {
    return Center(
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
            '$_error',
            style: AkTheme.sans(fontSize: 12, color: AkColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh, size: 16, color: AkColors.info),
            label: Text(
              '重试',
              style: AkTheme.sans(
                fontSize: 13,
                color: AkColors.info,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              backgroundColor: AkColors.info.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(Task? task) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
          color: AkColors.oledDark,
          border: Border(
            bottom: BorderSide(
              color: AkColors.border,
              width: AkTheme.strongLine,
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: AkColors.textSecondary,
                ),
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 20,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '任务 #${widget.taskId}',
                      style: AkTheme.mono(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AkColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$_latencyMs ms',
                      style: AkTheme.mono(
                        fontSize: 11,
                        color: _latencyColor(_latencyMs),
                      ),
                    ),
                  ],
                ),
              ),
              if (task != null) StatusBadge(status: task.status),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 头部：任务名（滚动）+ 状态 + 遥测 + 进度条
  // -------------------------------------------------------------------------

  Widget _buildHeader(Task task) {
    final isActive = task.status == TaskStatus.running;
    final showProgress = task.durationSeconds > 0 && task.progress >= 0;
    final remaining = isActive ? task.estimatedRemaining : -1.0;
    final actions = _buildOperationActions();

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: MarqueeText(
                  text: task.taskName,
                  style: AkTheme.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AkColors.textPrimary,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // StatusBadge(status: task.status),
              // const SizedBox(width: 10),
              // Text(
              //   '任务 #${task.id}',
              //   style: AkTheme.mono(
              //     fontSize: 11,
              //     color: AkColors.textSecondary,
              //   ),
              // ),
            ],
          ),
          if (showProgress) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '已用 ',
                  style: AkTheme.sans(
                    fontSize: 12,
                    color: AkColors.textSecondary,
                  ),
                ),
                Text(
                  Task.formatDuration(task.elapsedSeconds),
                  style: AkTheme.mono(
                    fontSize: 12,
                    color: AkColors.info,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  ' / ${Task.formatDuration(task.durationSeconds)}',
                  style: AkTheme.mono(
                    fontSize: 12,
                    color: AkColors.textSecondary.withValues(alpha: 0.6),
                  ),
                ),
                const Spacer(),
                Text(
                  '进度 ${(task.progress * 100).toStringAsFixed(1)}%',
                  style: AkTheme.mono(
                    fontSize: 12,
                    color: AkColors.info,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (remaining > 0) ...[
                  const SizedBox(width: 12),
                  Text(
                    '剩余 ${Task.formatDuration(remaining)}',
                    style: AkTheme.sans(
                      fontSize: 12,
                      color: AkColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: task.progress.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AkColors.border,
              valueColor: const AlwaysStoppedAnimation<Color>(AkColors.info),
            ),
          ] else if (task.elapsedSeconds > 0) ...[
            const SizedBox(height: 10),
            Text(
              '已用 ${Task.formatDuration(task.elapsedSeconds)}'
              '${task.durationSeconds > 0 ? ' / ${Task.formatDuration(task.durationSeconds)}' : ''}',
              style: AkTheme.mono(fontSize: 12, color: AkColors.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          ?actions,
          if (ref.read(liveActivityServiceProvider).isSupported) ...[
            const SizedBox(height: 8),
            _LiveActivityToggleRow(
              taskId: widget.taskId,
              taskName: task.taskName,
            ),
          ],
          if (_statusMessage != null) ...[
            const SizedBox(height: 8),
            Row(
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
          ],
        ],
      ),
    );
  }

  Widget? _buildOperationActions() {
    final task = _task;
    if (task == null) return null;
    const labels = {
      TaskOperation.start: '启动',
      TaskOperation.pause: '暂停',
      TaskOperation.resume: '继续',
      TaskOperation.delete: '删除',
    };
    final service = ref.read(taskServiceProvider);
    final ops = labels.keys
        .where((op) => service.canExecute(task.status, op))
        .toList();
    if (ops.isEmpty) return null;

    return Wrap(
      spacing: 8,
      children: [
        for (final op in ops)
          OutlinedButton.icon(
            key: ValueKey(op),
            onPressed: _busyOps.contains(op) ? null : () => _onOperation(op),
            style: OutlinedButton.styleFrom(
              foregroundColor: op == TaskOperation.delete
                  ? AkColors.danger
                  : AkColors.textSecondary,
              side: BorderSide(
                color: op == TaskOperation.delete
                    ? AkColors.danger.withValues(alpha: 0.5)
                    : AkColors.border,
                width: AkTheme.hairline,
              ),
              backgroundColor: AkColors.panel,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            ),
            icon: Icon(switch (op) {
              TaskOperation.start => Icons.play_arrow,
              TaskOperation.pause => Icons.pause,
              TaskOperation.resume => Icons.play_arrow,
              TaskOperation.delete => Icons.delete_outline,
              _ => Icons.chevron_right,
            }, size: 16),
            label: Text(
              labels[op]!,
              style: AkTheme.sans(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 输入媒体信息
  // -------------------------------------------------------------------------

  Widget _buildInputCard(Task task) {
    if (task.inputs.isEmpty) return const SizedBox.shrink();
    final input = task.inputs.first;

    return _SectionCard(
      title: '输入媒体',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KeyValueRow(label: '路径', value: input.filePath, mono: true),
          _KeyValueRow(label: '封装', value: input.demuxer),
          _KeyValueRow(
            label: '时长',
            value: input.duration > 0
                ? Task.formatDuration(input.duration)
                : '--',
            mono: true,
          ),
          _KeyValueRow(
            label: '码率',
            value: _formatBitrate(input.bitrate),
            mono: true,
          ),
          if (input.createTime > 0)
            _KeyValueRow(
              label: '创建时间',
              value: _formatDateTime(input.createTime),
              mono: true,
            ),
          if (input.modifyTime > 0)
            _KeyValueRow(
              label: '修改时间',
              value: _formatDateTime(input.modifyTime),
              mono: true,
            ),
          const Divider(color: AkColors.border, height: 18),
          for (final stream in input.streams)
            _StreamRow(stream: stream, isImage: _isImageDemuxer(input.demuxer)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 输出配置（活跃 run 的 after 摘要 + 命令参数）
  // -------------------------------------------------------------------------

  Widget _buildOutputConfigCard(Task task) {
    final run = task.activeRun;
    if (run == null || (run.vcodec.isEmpty && run.muxFormat.isEmpty)) {
      return const SizedBox.shrink();
    }
    final hasCmd = run.paraArray.isNotEmpty;
    final isImage =
        task.inputs.isNotEmpty && _isImageDemuxer(task.inputs.first.demuxer);

    return _SectionCard(
      title: '输出配置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (run.hwaccel.isNotEmpty)
            _KeyValueRow(label: '解码硬件加速', value: run.hwaccel, mono: true),
          _KeyValueRow(label: '状态', value: run.status),
          if (run.vcodec.isNotEmpty)
            _KeyValueRow(
              label: isImage ? '图片编码' : '视频编码',
              value: run.vcodec,
              mono: true,
            ),
          if (run.acodec.isNotEmpty)
            _KeyValueRow(label: '音频编码', value: run.acodec, mono: true),
          if (run.muxFormat.isNotEmpty)
            _KeyValueRow(label: '封装格式', value: run.muxFormat, mono: true),
          if (run.elapsed > 0)
            _KeyValueRow(
              label: '已运行',
              value: Task.formatDuration(run.elapsed),
              mono: true,
            ),
          if (run.lastStarted > 0)
            _KeyValueRow(
              label: '上次开始时间',
              value: _formatDateTime(run.lastStarted * 1000),
              mono: true,
            ),
          if (run.lastPaused > 0)
            _KeyValueRow(
              label: '上次暂停时间',
              value: _formatDateTime(run.lastPaused * 1000),
              mono: true,
            ),
          if (run.outputPath.isNotEmpty)
            _KeyValueRow(label: '输出路径', value: run.outputPath, mono: true),
          if (hasCmd) ...[
            const Divider(color: AkColors.border, height: 18),
            Text(
              '命令参数',
              style: AkTheme.sans(
                fontSize: 11,
                color: AkColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AkColors.canvas,
                border: Border.all(
                  color: AkColors.border,
                  width: AkTheme.hairline,
                ),
              ),
              child: Text(
                run.paraArray.join(' '),
                style: AkTheme.mono(
                  fontSize: 11,
                  color: AkColors.info.withValues(alpha: 0.9),
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 进度曲线
  // -------------------------------------------------------------------------

  Widget _buildProgressCard(Task task) {
    final run = task.activeRun;
    if (run == null) return const SizedBox.shrink();
    final time = run.progressTime;
    final frame = run.progressFrame;
    final size = run.progressSize;
    if (time.isEmpty && frame.isEmpty && size.isEmpty) {
      return const SizedBox.shrink();
    }

    String latest(num? v, String Function(num) format) =>
        v == null || v <= 0 ? '--' : format(v);

    return _SectionCard(
      title: '图表',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProgressCurve(time: time, frame: frame, size: size),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              // _LegendDot(color: AkColors.info, label: '媒体进度'),
              _LegendDot(color: AkColors.action, label: '帧数'),
              _LegendDot(color: AkColors.success, label: '输出大小'),
            ],
          ),
          if (time.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '进度 ${Task.formatDuration(time.last.last.toDouble())}'
              ' / ${task.durationSeconds > 0 ? Task.formatDuration(task.durationSeconds) : '--'}'
              '  样本 ${time.length} 点',
              style: AkTheme.mono(fontSize: 11, color: AkColors.textSecondary),
            ),
          ],
          if (frame.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '当前帧 ${latest(frame.last.last.toDouble(), (v) => '${v.toStringAsFixed(0)} 帧')}'
              '  已输出 ${latest(size.isNotEmpty ? size.last.last.toDouble() : 0, _formatBytes)}',
              style: AkTheme.mono(fontSize: 11, color: AkColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 输出文件
  // -------------------------------------------------------------------------

  Widget _buildOutputFilesCard(Task task) {
    final files = task.outputFiles.isNotEmpty
        ? task.outputFiles
        : task.activeRun?.outputFiles ?? const <String>[];
    if (files.isEmpty) return const SizedBox.shrink();

    // 本机回环连接（内置服务/同机服务器）直接读本地文件导出；
    // 远程连接经后端下载接口导出（需服务端支持 output-file 路由）
    final loopback = LocalOutputService.isLoopbackUrl(
      ref.read(appConfigProvider).normalizedBaseUrl,
    );

    return _SectionCard(
      title: '输出文件（${files.length}）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loopback ? '输出文件位于本机，可导出到系统下载目录' : '输出文件位于服务器，导出时将先下载到本机',
            style: AkTheme.sans(
              fontSize: 10,
              color: AkColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < files.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      files[i],
                      style: AkTheme.mono(
                        fontSize: 11,
                        color: AkColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                  _buildExportButton(task, files[i], i),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 单个输出文件的导出按钮：远程下载阶段显示百分比，其余阶段显示进度指示。
  Widget _buildExportButton(Task task, String path, int outputIndex) {
    final exporting = _exportingPath == path;
    final progress = exporting ? _exportProgress : null;
    return SizedBox(
      height: 28,
      width: progress != null ? 52 : 28,
      child: exporting
          ? progress != null
                ? Center(
                    child: Text(
                      '${(progress * 100).round()}%',
                      style: AkTheme.mono(fontSize: 10, color: AkColors.info),
                      textAlign: TextAlign.right,
                    ),
                  )
                : const Padding(
                    padding: EdgeInsets.all(6),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AkColors.info,
                    ),
                  )
          : IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              splashRadius: 16,
              tooltip: '导出',
              icon: const Icon(Icons.save_alt, color: AkColors.info),
              onPressed: _exportingPath == null
                  ? () => _exportOutputFile(task, path, outputIndex)
                  : null,
            ),
    );
  }

  // --- 输出文件导出 ---

  /// 常见输出容器/音频格式的 MIME 映射（导出保存时使用）。
  static const Map<String, String> _outputMimeTypes = {
    'mp4': 'video/mp4',
    'm4v': 'video/mp4',
    'mov': 'video/quicktime',
    'mkv': 'video/x-matroska',
    'webm': 'video/webm',
    'avi': 'video/x-msvideo',
    'flv': 'video/x-flv',
    'ts': 'video/mp2t',
    'mpg': 'video/mpeg',
    'mpeg': 'video/mpeg',
    'wmv': 'video/x-ms-wmv',
    'gif': 'image/gif',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'flac': 'audio/flac',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'opus': 'audio/opus',
  };

  String _mimeOf(String ext) =>
      _outputMimeTypes[ext.toLowerCase()] ?? 'application/octet-stream';

  /// 导出单个输出文件到用户选择的位置（系统保存对话框）。
  ///
  /// 本机回环连接：按路径解析本地文件直接拷贝；远程连接：先经
  /// `GET /api/v1/tasks/{id}/output-file` 下载到临时文件（按钮上显示
  /// 百分比进度），保存完成后删除临时文件。
  Future<void> _exportOutputFile(
    Task task,
    String path,
    int outputIndex,
  ) async {
    if (_exportingPath != null) return;
    setState(() {
      _exportingPath = path;
      _exportProgress = null;
    });
    File? tempFile;
    try {
      final loopback = LocalOutputService.isLoopbackUrl(
        ref.read(appConfigProvider).normalizedBaseUrl,
      );
      File? file;
      if (loopback) {
        file = await ref
            .read(localOutputServiceProvider)
            .resolveOutputFile(path);
        if (!mounted) return;
        if (file == null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('输出文件不存在或已被清理')));
          return;
        }
      } else {
        final runIndex = task.activeRunIndex;
        if (runIndex == null) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('任务运行记录缺失，无法导出')));
          }
          return;
        }
        final base = path.split(RegExp(r'[\\/]')).last;
        final dir = await getTemporaryDirectory();
        tempFile = File('${dir.path}/ffbox_export_$base');
        try {
          await ref
              .read(taskRepositoryProvider)
              .downloadOutputFile(
                taskId: task.id,
                runIndex: runIndex,
                outputIndex: outputIndex,
                savePath: tempFile.path,
                onProgress: (count, total) {
                  if (!mounted || total <= 0) return;
                  final p = (count / total).clamp(0.0, 1.0);
                  // 1% 步进更新，避免高频 setState
                  if (p >= 1 || (p - (_exportProgress ?? 0)).abs() >= 0.01) {
                    setState(() => _exportProgress = p);
                  }
                },
              );
        } on ApiException catch (e) {
          logDebug('taskDetailUI: download output failed ${e.statusCode}');
          if (!mounted) return;
          final msg = e.statusCode == 404
              ? '输出文件不存在或已被清理（旧版服务器不支持远程下载）'
              : e.friendlyMessage;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
          return;
        }
        if (!mounted) return;
        // 下载完成，转入保存阶段（不确定进度）
        setState(() => _exportProgress = null);
        file = tempFile;
      }
      final base = path.split(RegExp(r'[\\/]')).last;
      final dot = base.lastIndexOf('.');
      final name = dot > 0 ? base.substring(0, dot) : base;
      final ext = dot > 0 ? base.substring(dot + 1) : '';
      final result = await FileSaver.instance.saveAs(
        name: name,
        filePath: file.path,
        fileExtension: ext,
        mimeType: MimeType.custom,
        customMimeType: _mimeOf(ext),
      );
      if (!mounted || result == null) return; // null = 用户取消
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导出到 $result')));
    } catch (e) {
      logDebug('taskDetailUI: export failed $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    } finally {
      // 临时文件用完即删（saveAs 已完成拷贝；失败路径同样清理）
      if (tempFile != null) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _exportingPath = null;
          _exportProgress = null;
        });
      }
    }
  }

  // -------------------------------------------------------------------------
  // 错误信息
  // -------------------------------------------------------------------------

  Widget _buildErrorCard(Task task) {
    // 任务当前处于 error 状态为当前报错，否则为 reset 后保留的历史报错
    final isCurrentError = task.status == TaskStatus.error;
    final errors = task.errorInfo.isEmpty
        ? const ['任务失败，请查看转码日志']
        : task.errorInfo;
    return _SectionCard(
      title: isCurrentError ? '错误信息' : '历史报错',
      borderColor: AkColors.danger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final err in errors)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                err,
                style: AkTheme.mono(
                  fontSize: 11,
                  color: AkColors.danger,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 转码日志（cmdData）
  // -------------------------------------------------------------------------

  Widget _buildLogCard(Task task) {
    final logText = task.activeRun?.cmdData ?? '';
    if (logText.isEmpty) return const SizedBox.shrink();

    return _SectionCard(
      title: '转码日志',
      child: Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          color: AkColors.canvas,
          border: Border.all(color: AkColors.border, width: AkTheme.hairline),
        ),
        child: _LogViewer(
          text: _cleanLogInsertLines(logText),
          style: AkTheme.mono(
            fontSize: 10,
            color: AkColors.textSecondary.withValues(alpha: 0.85),
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 面板卡片
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Color? borderColor;

  const _SectionCard({this.title, required this.child, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ClipPath(
        clipper: _TopRightCutClipper(cut: AkTheme.cornerCut),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AkColors.raised,
            border: Border(
              left: BorderSide(
                color: borderColor ?? AkColors.border,
                width: AkTheme.signalBorder,
              ),
              top: const BorderSide(
                color: AkColors.border,
                width: AkTheme.hairline,
              ),
              right: const BorderSide(
                color: AkColors.border,
                width: AkTheme.hairline,
              ),
              bottom: const BorderSide(
                color: AkColors.border,
                width: AkTheme.hairline,
              ),
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    title!,
                    style: AkTheme.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AkColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _KeyValueRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = mono
        ? AkTheme.mono(fontSize: 11, color: AkColors.textPrimary)
        : AkTheme.sans(fontSize: 11.5, color: AkColors.textPrimary);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: AkTheme.sans(
                fontSize: 11,
                color: AkColors.textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: valueStyle, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _StreamRow extends StatelessWidget {
  final TaskStreamInfo stream;
  final bool isImage;

  const _StreamRow({required this.stream, this.isImage = false});

  @override
  Widget build(BuildContext context) {
    final isVideo = stream.isVideo;
    final color = isVideo ? AkColors.info : AkColors.success;
    final details = <String?>[
      stream.codec.isNotEmpty ? stream.codec : null,
      isVideo
          ? stream.resolution.isNotEmpty
                ? stream.resolution
                : null
          : stream.sampleRate > 0
          ? '${(stream.sampleRate / 1000).toStringAsFixed(1)} kHz'
          : null,
      isVideo
          ? stream.fps > 0
                ? '${stream.fps.toStringAsFixed(0)} fps'
                : null
          : stream.channel.isNotEmpty
          ? stream.channel
          : null,
      stream.bitrate > 0 ? (stream.bitrate / 1000).toStringAsFixed(0) : null,
    ].whereType<String>().join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            padding: const EdgeInsets.symmetric(vertical: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(
              isVideo ? (isImage ? '图片' : '视频') : '音频',
              style: AkTheme.sans(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (details.isNotEmpty)
                  Text(
                    details,
                    style: AkTheme.mono(
                      fontSize: 11,
                      color: AkColors.textPrimary,
                    ),
                  ),
                if (stream.infoText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    stream.infoText,
                    style: AkTheme.mono(
                      fontSize: 9.5,
                      color: AkColors.textSecondary.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AkTheme.sans(fontSize: 10.5, color: AkColors.textSecondary),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ErrorBanner({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AkColors.danger.withValues(alpha: 0.12),
        border: Border(
          left: BorderSide(color: AkColors.danger, width: AkTheme.signalBorder),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 14, color: AkColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '刷新失败：$message',
              style: AkTheme.sans(fontSize: 12, color: AkColors.danger),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 14, color: AkColors.info),
              label: Text(
                '重试',
                style: AkTheme.sans(
                  fontSize: 12,
                  color: AkColors.info,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: AkColors.info.withValues(alpha: 0.1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 进度曲线（CustomPaint 绘制 mediaTime / frame / size 三条归一化折线）
// ---------------------------------------------------------------------------

class _ProgressCurve extends StatelessWidget {
  final List<List<num>> time;
  final List<List<num>> frame;
  final List<List<num>> size;

  const _ProgressCurve({
    required this.time,
    required this.frame,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AkColors.canvas,
        border: Border.all(color: AkColors.border, width: AkTheme.hairline),
      ),
      child: ClipRect(
        child: CustomPaint(
          painter: _CurvePainter(time: time, frame: frame, size: size),
        ),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  final List<List<num>> time;
  final List<List<num>> frame;
  final List<List<num>> size;

  _CurvePainter({required this.time, required this.frame, required this.size});

  static const _padL = 34.0;
  static const _padR = 10.0;
  static const _padT = 10.0;
  static const _padB = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final plotW = w - _padL - _padR;
    final plotH = h - _padT - _padB;

    // 网格
    final gridPaint = Paint()
      ..color = AkColors.border.withValues(alpha: 0.4)
      ..strokeWidth = AkTheme.hairline;
    final labelStyle = AkTheme.mono(
      fontSize: 9,
      color: AkColors.textSecondary.withValues(alpha: 0.7),
    );

    // 纵轴：以媒体进度为基准标注真实时间刻度（time 序列为空时回退到百分比）
    final maxTime = _maxValue(time);
    final hasTime = maxTime > 0;
    const rows = 4;
    for (var i = 0; i <= rows; i++) {
      final y = _padT + plotH * i / rows;
      canvas.drawLine(Offset(_padL, y), Offset(w - _padR, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: hasTime
              ? _fmtTick(maxTime * (rows - i) / rows)
              : '${(rows - i) * 25}%',
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_padL - tp.width - 6, y - tp.height / 2));
    }

    // x 轴基准线
    canvas.drawLine(
      Offset(_padL, _padT + plotH),
      Offset(w - _padR, _padT + plotH),
      gridPaint,
    );

    // 三条曲线（各按自身最大值归一化）
    _drawSeries(canvas, time, plotW, plotH, AkColors.info);
    _drawSeries(canvas, frame, plotW, plotH, AkColors.action);
    _drawSeries(canvas, this.size, plotW, plotH, AkColors.success);

    // 横轴：0 / 50% / 100% 处标注真实运行秒数
    final maxX = _maxX(time, frame, this.size);
    if (maxX > 0) {
      final tickStyle = AkTheme.mono(
        fontSize: 9,
        color: AkColors.textSecondary.withValues(alpha: 0.5),
      );
      for (final f in const [0.0, 0.5, 1.0]) {
        final x = _padL + plotW * f;
        final tp = TextPainter(
          text: TextSpan(text: _fmtTick(maxX * f), style: tickStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelX = math.max(0.0, math.min(w - tp.width, x - tp.width / 2));
        tp.paint(canvas, Offset(labelX, _padT + plotH + 3));
      }
    }
  }

  /// 序列中最大的数值（y 方向）。
  static double _maxValue(List<List<num>> series) {
    var m = 0.0;
    for (final p in series) {
      m = math.max(m, p[1].toDouble());
    }
    return m;
  }

  double _maxX(List<List<num>> a, List<List<num>> b, List<List<num>> c) {
    var m = 0.0;
    for (final s in [a, b, c]) {
      for (final p in s) {
        m = math.max(m, p[0].toDouble());
      }
    }
    return m;
  }

  /// 紧凑时间刻度：<60s 显示 "45s"，<1h 显示 "m:ss"，否则 "h:mm"。
  static String _fmtTick(num v) {
    final s = v < 0 ? 0 : v.round();
    if (s >= 3600) {
      return '${s ~/ 3600}:${((s % 3600) ~/ 60).toString().padLeft(2, '0')}';
    }
    if (s >= 60) return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return '${s}s';
  }

  void _drawSeries(
    Canvas canvas,
    List<List<num>> series,
    double plotW,
    double plotH,
    Color color,
  ) {
    if (series.length < 2) return;
    final maxX = _maxX(time, frame, size);
    var maxY = 0.0;
    for (final p in series) {
      maxY = math.max(maxY, p[1].toDouble());
    }
    if (maxX <= 0 || maxY <= 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (var i = 0; i < series.length; i++) {
      final x = _padL + series[i][0].toDouble() / maxX * plotW;
      final y = _padT + plotH - series[i][1].toDouble() / maxY * plotH;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.time != time || old.frame != frame || old.size != size;
}

// ---------------------------------------------------------------------------
// 转码日志查看器：自动滚动到底部 + ak-ui 风格滚动条
// ---------------------------------------------------------------------------

class _LogViewer extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _LogViewer({required this.text, required this.style});

  @override
  State<_LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<_LogViewer> {
  final ScrollController _controller = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didUpdateWidget(covariant _LogViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 内容更新且用户停留在底部附近时，自动跟随到最后一行
    if (oldWidget.text != widget.text && _autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom();
      });
    }
  }

  void _onScroll() {
    final pos = _controller.position;
    _autoScroll = pos.maxScrollExtent - pos.pixels < 24;
  }

  void _scrollToBottom() {
    if (!_controller.hasClients) return;
    final target = _controller.position.maxScrollExtent;
    if (_controller.offset < target) _controller.jumpTo(target);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          AkColors.textSecondary.withValues(alpha: 0.35),
        ),
        trackColor: WidgetStatePropertyAll(
          AkColors.border.withValues(alpha: 0.5),
        ),
        radius: const Radius.circular(AkTheme.cutSm),
        thickness: const WidgetStatePropertyAll(5.0),
        thumbVisibility: const WidgetStatePropertyAll(true),
      ),
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _controller,
          padding: const EdgeInsets.all(10),
          child: SelectableText(widget.text, style: widget.style),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 几何裁剪（ak-ui 非对称切角）
// ---------------------------------------------------------------------------

class _TopRightCutClipper extends CustomClipper<Path> {
  final double cut;

  const _TopRightCutClipper({this.cut = AkTheme.cornerCut});

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - cut, 0)
      ..lineTo(size.width, cut)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _TopRightCutClipper oldClipper) =>
      cut != oldClipper.cut;
}

/// 去除服务端插入状态行（如「▶️ 任务已于 xxx 暂停。」）的开头符号与结尾句号。
String _cleanLogInsertLines(String text) {
  final pattern = RegExp(
    r'^\s*[▶⏸🛑⛔✅❌](?:\uFE0F)?\s*(.+)[。.]\s*$',
    unicode: true,
  );
  return text
      .split('\n')
      .map((line) => pattern.firstMatch(line)?.group(1) ?? line)
      .join('\n');
}

// ---------------------------------------------------------------------------
// 实时活动开关：把当前任务推送到系统实时通知（Android 16 Live Updates）
// ---------------------------------------------------------------------------

/// 实时活动开关行。同一时刻全局仅允许一条实时活动：
/// 开启新任务会直接替换原生前台服务的当前任务（固定通知 ID 覆盖）。
class _LiveActivityToggleRow extends ConsumerStatefulWidget {
  final int taskId;
  final String taskName;

  const _LiveActivityToggleRow({required this.taskId, required this.taskName});

  @override
  ConsumerState<_LiveActivityToggleRow> createState() =>
      _LiveActivityToggleRowState();
}

class _LiveActivityToggleRowState
    extends ConsumerState<_LiveActivityToggleRow> {
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (on) {
        final session = ref.read(sessionProvider);
        if (session == null) return;
        final baseUrl = ref.read(appConfigProvider).normalizedBaseUrl;
        final ok = await ref
            .read(liveActivityProvider.notifier)
            .start(
              baseUrl: baseUrl,
              sessionId: session.sessionId,
              taskId: widget.taskId,
              taskName: widget.taskName,
            );
        // Clarity 埋点：区分成功开启与权限被拒
        ClarityAnalytics.trackEvent(
          ok ? 'live_activity_on' : 'live_activity_denied',
        );
        if (!ok && mounted) {
          _showSnack('实时通知需要通知权限，请在系统设置中开启');
        }
      } else {
        await ref.read(liveActivityProvider.notifier).stop();
        ClarityAnalytics.trackEvent('live_activity_off');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: AkTheme.sans(fontSize: 12)),
        backgroundColor: AkColors.raised,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveActivityProvider);
    final active = live.isActiveFor(widget.taskId);
    final otherActive = live.isActive && !active;

    return Container(
      decoration: BoxDecoration(
        color: active ? AkColors.info.withValues(alpha: 0.08) : AkColors.canvas,
        border: Border.all(
          color: active
              ? AkColors.info.withValues(alpha: 0.4)
              : AkColors.border,
          width: AkTheme.hairline,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          Icon(
            active ? Icons.notifications_active : Icons.notifications_none,
            size: 16,
            color: active ? AkColors.info : AkColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? '实时通知中' : '实时通知',
                  style: AkTheme.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: active ? AkColors.info : AkColors.textPrimary,
                  ),
                ),
                Text(
                  otherActive ? '将替换当前实时通知' : '在AOSP/ColorOS上启用实时通知/流体云',
                  style: AkTheme.sans(
                    fontSize: 10,
                    color: AkColors.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: active,
            onChanged: _busy ? null : _toggle,
            activeThumbColor: AkColors.info,
            activeTrackColor: AkColors.info.withValues(alpha: 0.35),
            inactiveThumbColor: AkColors.textSecondary,
            inactiveTrackColor: AkColors.muted,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
