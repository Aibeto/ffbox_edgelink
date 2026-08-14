import 'package:flutter/material.dart';

/// 文本超宽时循环滚动显示（ak-ui 遥测风格）。
///
/// - 文本宽度小于容器时静态显示（不滚动）
/// - 超宽时以 [velocity] 像素/秒无缝循环滚动
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  /// 循环时两个文本副本之间的间距。
  final double gap;

  /// 滚动速度（像素/秒）。
  final double velocity;

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.gap = 48,
    this.velocity = 28,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double? _textWidth;
  TextScaler? _lastScaler;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 文本缩放变化时重新测量并复位动画
    final scaler = MediaQuery.textScalerOf(context);
    if (scaler != _lastScaler) {
      _lastScaler = scaler;
      _textWidth = null;
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _measure() {
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    _textWidth = tp.width;
  }

  @override
  Widget build(BuildContext context) {
    _measure();
    final textWidth = _textWidth ?? 0;
    final height = (widget.style.fontSize ?? 14) * (widget.style.height ?? 1.4);

    return LayoutBuilder(
      builder: (context, constraints) {
        final overflow = textWidth > constraints.maxWidth;
        if (!overflow) {
          _controller.stop();
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        // 超宽：启动/更新循环滚动
        final distance = textWidth + widget.gap;
        final duration = Duration(
          milliseconds: (distance / widget.velocity * 1000).round(),
        );
        if (_controller.duration != duration) {
          _controller
            ..duration = duration
            ..repeat();
        }

        return SizedBox(
          height: height,
          width: double.infinity,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final shift = -_controller.value * distance;
                return Stack(
                  children: [
                    Positioned(
                      left: shift,
                      top: 0,
                      child: Text(
                        widget.text,
                        style: widget.style,
                        maxLines: 1,
                      ),
                    ),
                    Positioned(
                      left: shift + distance,
                      top: 0,
                      child: Text(
                        widget.text,
                        style: widget.style,
                        maxLines: 1,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
