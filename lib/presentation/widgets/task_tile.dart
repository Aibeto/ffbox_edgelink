import 'package:flutter/material.dart';
import 'package:ffbox_edgelink/application/task/task_state_machine.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_operation.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';
import 'package:ffbox_edgelink/presentation/widgets/marquee_text.dart';
import 'package:ffbox_edgelink/presentation/widgets/status_badge.dart';

const _basicOperations = {
  TaskOperation.start,
  TaskOperation.pause,
  TaskOperation.resume,
  TaskOperation.delete,
};

/// 任务卡片：状态信号 + 任务名（主导命令）+ 等宽遥测 + 进度 + 操作。
///
/// ak-ui system 模式：
/// - 左侧信号色边（状态）+ 右上切角几何
/// - 任务名为主导命令（过长时循环滚动），状态徽章为支撑信号
/// - 耗时/进度用等宽字体呈现真实数据
class TaskTile extends StatelessWidget {
  final Task task;
  final Future<void> Function(TaskOperation operation) onOperation;
  final bool disabled;
  final VoidCallback? onTap;

  /// 是否为当前实时活动任务（Android Live Updates 通知）。
  final bool live;

  const TaskTile({
    super.key,
    required this.task,
    required this.onOperation,
    this.disabled = false,
    this.onTap,
    this.live = false,
  });

  static const _labels = {
    TaskOperation.start: '启动',
    TaskOperation.pause: '暂停',
    TaskOperation.resume: '继续',
    TaskOperation.delete: '删除',
  };

  @override
  Widget build(BuildContext context) {
    final allowed = TaskStateMachine.allowedOperations(task.status);
    final actions = _basicOperations.where(allowed.contains).toList();
    final statusColor = _statusColor(task.status);
    final isActive = task.status == TaskStatus.running;
    final showProgress = task.durationSeconds > 0 && task.progress >= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: GestureDetector(
        onTap: onTap,
        child: ClipPath(
          clipper: _TopRightCutClipper(cut: AkTheme.cornerCut),
          child: Container(
            decoration: BoxDecoration(
              color: AkColors.raised,
              border: Border(
                left: BorderSide(
                  color: statusColor,
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Row 1: 状态信号 + 任务名 + 操作 ---
                  Row(
                    children: [
                      StatusBadge(status: task.status),
                      const SizedBox(width: 10),
                      if (live) ...[
                        Icon(
                          Icons.notifications_active,
                          size: 15,
                          color: AkColors.info,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: MarqueeText(
                          text: task.taskName,
                          style: AkTheme.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AkColors.textPrimary,
                          ),
                        ),
                      ),
                      if (actions.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        for (final op in actions)
                          _OperationButton(
                            label: _labels[op]!,
                            operation: op,
                            isDestructive: op == TaskOperation.delete,
                            enabled: !disabled,
                            onPressed: () => onOperation(op),
                          ),
                      ],
                    ],
                  ),

                  if (showProgress) ...[
                    const SizedBox(height: 10),
                    // --- Row 2: 等宽遥测（已用/总长 · 进度/剩余） ---
                    _TelemetryLine(task: task, isActive: isActive),
                    const SizedBox(height: 6),
                    // --- Row 3: 细进度条 ---
                    _ProgressBar(progress: task.progress),
                  ] else if (task.elapsedSeconds > 0) ...[
                    const SizedBox(height: 10),
                    _TelemetryLine(task: task, isActive: isActive),
                  ],

                  // --- 完成 / 错误信息 ---
                  if (task.status == TaskStatus.finished &&
                      task.outputFiles.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _FinishedInfo(fileCount: task.outputFiles.length),
                  ],
                  if (task.status == TaskStatus.error &&
                      task.errorInfo.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _ErrorInfo(message: task.errorInfo.first),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Color _statusColor(TaskStatus status) {
    return switch (status) {
      TaskStatus.running => AkColors.info,
      TaskStatus.paused || TaskStatus.pausedQueued => AkColors.action,
      TaskStatus.finished => AkColors.success,
      TaskStatus.error => AkColors.danger,
      TaskStatus.stopping ||
      TaskStatus.finishing => AkColors.info.withValues(alpha: 0.5),
      _ => AkColors.border,
    };
  }
}

// ---------------------------------------------------------------------------
// 遥测行：ak-progress header 风格（标签 + 等宽数值）
// ---------------------------------------------------------------------------

class _TelemetryLine extends StatelessWidget {
  final Task task;
  final bool isActive;

  const _TelemetryLine({required this.task, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final elapsed = Task.formatDuration(task.elapsedSeconds);
    final duration = task.durationSeconds > 0
        ? Task.formatDuration(task.durationSeconds)
        : '--:--';

    final remaining = isActive ? task.estimatedRemaining : -1.0;

    return Row(
      children: [
        // 已用时间（label + value）
        Text(
          '已用',
          style: AkTheme.sans(
            fontSize: 10,
            color: AkColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          elapsed,
          style: AkTheme.mono(
            fontSize: 11,
            color: AkColors.info,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          ' / $duration',
          style: AkTheme.mono(
            fontSize: 10,
            color: AkColors.textSecondary.withValues(alpha: 0.6),
          ),
        ),
        const Spacer(),
        if (remaining > 0) ...[
          const SizedBox(width: 10),
          Text(
            '剩余 ${Task.formatDuration(remaining)}',
            style: AkTheme.sans(fontSize: 10, color: AkColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 进度条：ak-progress 风格（header + track + fill）
// ---------------------------------------------------------------------------

class _ProgressBar extends StatelessWidget {
  final double progress;

  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // header: label + value
        Row(
          children: [
            Text(
              '进度',
              style: AkTheme.sans(
                fontSize: 10,
                color: AkColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Text(
              '$pct%',
              style: AkTheme.mono(
                fontSize: 10,
                color: AkColors.info,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        // track + fill
        Container(
          height: 4,
          decoration: BoxDecoration(color: AkColors.muted),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(color: AkColors.info),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 完成信息
// ---------------------------------------------------------------------------

class _FinishedInfo extends StatelessWidget {
  final int fileCount;

  const _FinishedInfo({required this.fileCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.check_circle, size: 13, color: AkColors.success),
        const SizedBox(width: 4),
        Text(
          '$fileCount 个输出文件',
          style: AkTheme.sans(fontSize: 11, color: AkColors.success),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 错误信息
// ---------------------------------------------------------------------------

class _ErrorInfo extends StatelessWidget {
  final String message;

  const _ErrorInfo({required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.error_outline, size: 13, color: AkColors.danger),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            message,
            style: AkTheme.sans(fontSize: 11, color: AkColors.danger),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 操作按钮：ak-button--card 风格（左侧信号边 + 切角 + hover）
// ---------------------------------------------------------------------------

class _OperationButton extends StatelessWidget {
  final String label;
  final TaskOperation operation;
  final bool isDestructive;
  final bool enabled;
  final VoidCallback onPressed;

  const _OperationButton({
    required this.label,
    required this.operation,
    required this.isDestructive,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final Color signalColor = _resolveSignalColor();

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          splashColor: Colors.transparent,
          highlightColor: signalColor.withValues(alpha: 0.08),
          hoverColor: signalColor.withValues(alpha: 0.05),
          child: ClipPath(
            clipper: _ButtonCutClipper(),
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: enabled ? AkColors.panel : AkColors.muted,
                border: Border(
                  left: BorderSide(
                    color: enabled ? signalColor : AkColors.disabled,
                    width: AkTheme.hairline,
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
              alignment: Alignment.center,
              child: Text(
                label,
                style: AkTheme.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: enabled
                      ? signalColor
                      : AkColors.textSecondary.withValues(alpha: 0.35),
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _resolveSignalColor() {
    return switch (operation) {
      TaskOperation.delete => AkColors.danger,
      TaskOperation.start => AkColors.success,
      _ => AkColors.info,
    };
  }
}

// ---------------------------------------------------------------------------
// 几何裁剪
// ---------------------------------------------------------------------------

/// 右上角切角（ak-ui 非对称几何）。
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

class _ButtonCutClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final cut = AkTheme.cutSm;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - cut, 0)
      ..lineTo(size.width, cut)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
