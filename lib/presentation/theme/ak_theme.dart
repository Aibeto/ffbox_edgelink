import 'package:flutter/material.dart';

/// ak-ui color palette for Flutter dark theme.
///
/// 色值对齐 ak-ui 官方 token（https://ak-ui.yyj.moe/components/）。
class AkColors {
  AkColors._();

  // --- 裸色板（--ak-color-*）---

  /// LOW 低阶 #9c9c9c
  static const Color paletteLow = Color(0xFF9C9C9C);

  /// BASIC 基础 #d8dd5a
  static const Color paletteBasic = Color(0xFFD8DD5A);

  /// PRIMARY 初级 #4aabea
  static const Color palettePrimary = Color(0xFF4AABEA);

  /// SECONDARY 中级 #cfc2d1
  static const Color paletteSecondary = Color(0xFFCFC2D1);

  /// ADVANCED 高级 #f1c644
  static const Color paletteAdvanced = Color(0xFFF1C644);

  // --- 语义表面（--ak-surface-*）---

  /// 画布背景 --ak-surface-canvas
  static const Color canvas = Color(0x00000000);

  /// 浅面板 --ak-surface-panel
  static const Color panel = Color(0xFF161B22);

  /// 静默面板 --ak-surface-muted
  static const Color muted = Color(0xFF21262D);

  /// 凸起面板 --ak-surface-raised
  static const Color raised = Color(0xFF1C2128);

  /// 反色表面 --ak-surface-inverse
  static const Color inverse = Color(0xFFE6EDF3);

  // --- 信号色（--ak-signal-*）---

  /// 信息/主色 --ak-signal-info（cyan 蓝）
  static const Color info = Color(0xFF4AABEA);

  /// 行动/警告 --ak-signal-action（黄）
  static const Color action = Color(0xFFF1C644);

  /// 集中强调 --ak-signal-accent（橙）
  static const Color accent = Color(0xFFE88040);

  /// 成功 --ak-signal-success（绿）
  static const Color success = Color(0xFF3FB950);

  /// 危险 --ak-signal-danger（红）
  static const Color danger = Color(0xFFF85149);

  /// 禁用 --ak-signal-disabled
  static const Color disabled = Color(0xFF484F58);

  // --- 文字色 ---

  /// --ak-text-primary
  static const Color textPrimary = Color(0xFFE6EDF3);

  /// --ak-text-secondary
  static const Color textSecondary = Color(0xFF8B949E);

  /// --ak-text-inverse
  static const Color textInverse = Color(0xFF0D1117);

  // --- 边框 ---

  static const Color border = Color(0xFF30363D);
  static const Color borderMuted = Color(0xFF21262D);
}

/// ak-ui design language theme — system fonts for full CJK support.
///
/// 几何 token（--ak-cut-*）与动效 token（--ak-motion-*）均为 Dart 常量，
/// 供 widget / CustomPainter 在不依赖 CSS 的场景下使用。
class AkTheme {
  AkTheme._();

  // --- 几何（--ak-cut-* / --ak-line-*）---

  /// 小切角 --ak-cut-sm
  static const double cutSm = 8.0;

  /// 中切角 --ak-cut-md
  static const double cutMd = 16.0;

  /// 大切角 --ak-cut-lg
  static const double cutLg = 24.0;

  /// 卡片默认切角（= cutMd）
  static const double cornerCut = cutMd;

  /// 卡片圆角 --ak-radius-subtle
  static const double cardRadius = 0.0;

  /// 发丝线 --ak-line-hairline
  static const double hairline = 0.5;

  /// 强线 --ak-line-strong
  static const double strongLine = 1.0;

  /// 左侧信号边宽度（卡片/按钮）
  static const double signalBorder = 3.0;

  // --- 动效（--ak-motion-*）---

  /// 快速过渡 --ak-motion-fast
  static const Duration motionFast = Duration(milliseconds: 120);

  /// 标准过渡 --ak-motion-base
  static const Duration motionBase = Duration(milliseconds: 200);

  /// 慢速过渡 --ak-motion-slow
  static const Duration motionSlow = Duration(milliseconds: 350);

  // --- Const TextStyle 基底（供 CustomPainter / const 场景 / ThemeData 引用） ---

  static const TextStyle _sansBase = TextStyle(fontFamily: 'sans-serif');

  /// System font helpers — all platforms have built-in CJK support.
  /// Windows: Microsoft YaHei; Android: Noto Sans CJK; iOS: PingFang SC.
  static TextStyle sans({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AkColors.textPrimary,
    double letterSpacing = 0,
    double height = 1.5,
  }) => TextStyle(
    fontFamily: 'sans-serif',
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );

  static TextStyle mono({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AkColors.textPrimary,
    double letterSpacing = 0,
    double height = 1.4,
  }) => TextStyle(
    fontFamily: 'monospace',
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );

  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AkColors.canvas,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      surface: AkColors.panel,
      primary: AkColors.info,
      secondary: AkColors.action,
      error: AkColors.danger,
      onSurface: AkColors.textPrimary,
      onPrimary: AkColors.textInverse,
      onSecondary: AkColors.textInverse,
      onError: AkColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AkColors.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    textTheme: TextTheme(
      displayLarge: sans(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: sans(fontSize: 22, fontWeight: FontWeight.w700),
      titleLarge: sans(fontSize: 18, fontWeight: FontWeight.w600),
      titleMedium: sans(fontSize: 16, fontWeight: FontWeight.w600),
      bodyLarge: sans(fontSize: 16),
      bodyMedium: sans(fontSize: 14),
      bodySmall: sans(fontSize: 12, color: AkColors.textSecondary),
      labelLarge: sans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      labelMedium: sans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
      ),
      labelSmall: sans(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.0,
        color: AkColors.textSecondary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AkColors.panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: sans(
        fontSize: 14,
        color: AkColors.textSecondary.withValues(alpha: 0.6),
      ),
      labelStyle: sans(fontSize: 13, color: AkColors.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AkTheme.cutSm),
        borderSide: const BorderSide(color: AkColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AkTheme.cutSm),
        borderSide: const BorderSide(color: AkColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        borderSide: const BorderSide(color: AkColors.info, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        borderSide: const BorderSide(color: AkColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        borderSide: const BorderSide(color: AkColors.danger, width: 1.5),
      ),
    ),
    cardTheme: CardThemeData(
      color: AkColors.raised,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AkTheme.cardRadius),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AkColors.border,
      thickness: 1,
      space: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AkColors.raised,
      contentTextStyle: _sansBase.copyWith(color: AkColors.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
