import 'package:flutter/material.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';

/// 状态标记：ak-status 风格 —— 信号圆点 + 文字标签。
///
/// 运行中状态的信号圆点带低频脉冲动画（尊重 prefers-reduced-motion）。
/// 颜色非唯一指示器，配合文字标签共同表达状态。
class StatusBadge extends StatefulWidget {
  final TaskStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  State<StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<StatusBadge>
    with TickerProviderStateMixin {
  AnimationController? _pulseController;

  bool get _isPulsing =>
      widget.status == TaskStatus.running ||
      widget.status == TaskStatus.stopping ||
      widget.status == TaskStatus.finishing;

  @override
  void initState() {
    super.initState();
    if (_isPulsing) _startPulse();
  }

  @override
  void didUpdateWidget(covariant StatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isPulsing && _pulseController == null) {
      _startPulse();
    } else if (!_isPulsing && _pulseController != null) {
      _pulseController!.stop();
      _pulseController!.dispose();
      _pulseController = null;
    }
  }

  void _startPulse() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(widget.status);
    final label = labelFor(widget.status);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 信号圆点
        if (_pulseController != null)
          AnimatedBuilder(
            animation: _pulseController!,
            builder: (context, _) {
              final opacity = 0.4 + 0.6 * _pulseController!.value;
              return Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: opacity),
                  shape: BoxShape.circle,
                ),
              );
            },
          )
        else
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 6),
        // 文字标签
        Text(
          label,
          style: AkTheme.sans(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  /// 状态对应的信号色（供卡片边条等复用）。
  static Color colorFor(TaskStatus s) {
    return switch (s) {
      TaskStatus.running => AkColors.info,
      TaskStatus.paused || TaskStatus.pausedQueued => AkColors.action,
      TaskStatus.finished => AkColors.success,
      TaskStatus.error => AkColors.danger,
      TaskStatus.stopping || TaskStatus.finishing => AkColors.info,
      _ => AkColors.textSecondary,
    };
  }

  /// 状态对应的中文标签。
  static String labelFor(TaskStatus s) {
    return switch (s) {
      TaskStatus.deleted => '删除',
      TaskStatus.initializing => '初始化',
      TaskStatus.idle => '空闲',
      TaskStatus.idleQueued => '排队',
      TaskStatus.running => '运行',
      TaskStatus.paused => '暂停',
      TaskStatus.pausedQueued => '暂停排队',
      TaskStatus.stopping => '停止中',
      TaskStatus.finishing => '完成中',
      TaskStatus.finished => '完成',
      TaskStatus.error => '错误',
    };
  }
}
