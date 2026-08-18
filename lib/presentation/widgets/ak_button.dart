import 'package:flutter/material.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';

/// ak-ui 切角按钮：右上切角矩形，支持加载态与禁用态。
///
/// 从登录页 `_AkButton` 提取为共用组件，供登录页与内置服务页等复用。
class AkButton extends StatelessWidget {
  final String? label;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool loading;
  final VoidCallback? onPressed;

  const AkButton({
    super.key,
    this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.loading = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Color bgColor = enabled
        ? backgroundColor
        : AkColors.disabled.withValues(alpha: 0.3);
    final Color fgColor = enabled
        ? foregroundColor
        : AkColors.textSecondary.withValues(alpha: 0.5);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        splashColor: Colors.transparent,
        highlightColor: backgroundColor.withValues(alpha: 0.12),
        child: ClipPath(
          clipper: _TopRightCutClipper(cut: AkTheme.cornerCut),
          child: Container(
            height: 48,
            decoration: BoxDecoration(color: bgColor),
            alignment: Alignment.center,
            child: loading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(fgColor),
                    ),
                  )
                : Text(
                    label ?? '',
                    style: AkTheme.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: fgColor,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Clipper：右上不对称切角
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
