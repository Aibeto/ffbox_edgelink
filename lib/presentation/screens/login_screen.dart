import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/domain/entities/server_profile.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/presentation/screens/device_info_screen.dart';
import 'package:ffbox_edgelink/presentation/screens/export_logs_screen.dart';

/// 登录页：全屏布局，上方表单输入，下方历史连接列表支持快捷登录。
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // --- 状态与控制器 ---

  final _baseUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _baseUrlFocus = FocusNode();
  bool _loading = false;
  String? _error;
  bool _isLocalhost = false;
  Timer? _debounce;
  List<ServerProfile> _history = const [];

  // --- 初始化与销毁 ---

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadHistory();
    _baseUrlController.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) _checkLocalhost(_baseUrlController.text);
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _baseUrlFocus.dispose();
    super.dispose();
  }

  // --- 数据加载 ---

  Future<void> _loadProfile() async {
    final profile = await ref.read(serverRepositoryProvider).load();
    if (profile != null && mounted) {
      setState(() {
        _baseUrlController.text = profile.baseUrl;
        _usernameController.text = profile.username;
        _checkLocalhost(profile.baseUrl);
      });
    }
  }

  Future<void> _loadHistory() async {
    final history = await ref.read(serverRepositoryProvider).loadHistory();
    if (mounted) setState(() => _history = history);
  }

  // --- 本机检测 ---

  void _checkLocalhost(String url) {
    final isLocal = AppConfig(baseUrl: url).isLocalhost;
    if (isLocal != _isLocalhost) {
      setState(() => _isLocalhost = isLocal);
    }
  }

  bool get _needsPassword {
    final baseUrl = _baseUrlController.text.trim();
    return baseUrl.isNotEmpty && !_isLocalhost;
  }

  // --- 历史快捷登录 ---

  void _quickLogin(ServerProfile entry) {
    setState(() {
      _baseUrlController.text = entry.baseUrl;
      _usernameController.text = entry.username;
      _passwordController.text = entry.password;
      _error = null;
    });
    _checkLocalhost(entry.baseUrl);
    // 非本机且有密码时自动提交
    if (entry.password.isNotEmpty) {
      _submit();
    }
  }

  // --- 登录提交 ---

  Future<void> _submit() async {
    final baseUrl = _baseUrlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (baseUrl.isEmpty) {
      setState(() => _error = '请输入服务器地址');
      return;
    }

    logDebug('loginUI: 提交登录 baseUrl=$baseUrl username=$username');
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final outcome = await ref
          .read(authServiceProvider)
          .login(baseUrl: baseUrl, username: username, password: password);

      if (!mounted) return;

      if (outcome.error != null) {
        logDebug('loginUI: 登录失败 - ${outcome.error}');
        setState(() {
          _loading = false;
          _error = outcome.error;
        });
        return;
      }

      final session = outcome.session!;
      await ref
          .read(serverRepositoryProvider)
          .save(ServerProfile(baseUrl: baseUrl, username: username));
      await ref
          .read(serverRepositoryProvider)
          .saveToHistory(
            ServerProfile(
              baseUrl: baseUrl,
              username: username,
              password: password,
              timestamp: DateTime.now(),
            ),
          );
      await ref.read(sessionRepositoryProvider).save(session);
      logDebug('loginUI: 登录成功，保存会话并切换到任务列表');
      ref.read(sessionProvider.notifier).update(session);
    } on ApiException catch (e) {
      if (!mounted) return;
      logDebug(
        'loginUI: 登录异常 ApiException kind=${e.kind} msg=${e.friendlyMessage}',
      );
      setState(() {
        _loading = false;
        _error = e.kind == ApiErrorKind.timeout ? '连接超时' : e.friendlyMessage;
      });
    } catch (e) {
      if (!mounted) return;
      logDebug('loginUI: 登录异常 $e');
      setState(() {
        _loading = false;
        _error = '登录失败：$e';
      });
    }
  }

  // --- 格式化时间 ---

  String _formatTime(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$m-$d $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // --- 背景网格 ---
          CustomPaint(
            painter: _GridPainter(
              color: AkColors.border.withValues(alpha: 0.15),
            ),
            size: Size.infinite,
          ),

          // --- 右上角按钮组 ---
          Positioned(
            top: 12,
            right: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CornerButton(
                  icon: Icons.info_outline,
                  tooltip: '设备信息',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DeviceInfoScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 2),
                _CornerButton(
                  icon: Icons.save_alt,
                  tooltip: '导出日志',
                  label: 'DEBUG LOGOS',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ExportLogsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // --- 主体内容 ---
          SafeArea(
            child: Column(
              children: [
                // --- 标题 ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FFBox',
                          style: AkTheme.sans(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: AkColors.textPrimary,
                            letterSpacing: 2.0,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'EdgeLink',
                          style: AkTheme.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: AkColors.textSecondary,
                            letterSpacing: 4.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // --- 表单 ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- 服务器地址 ---
                      Text(
                        'SERVER',
                        style: AkTheme.sans(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AkColors.textSecondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _baseUrlController,
                        focusNode: _baseUrlFocus,
                        style: AkTheme.mono(
                          fontSize: 14,
                          color: AkColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'http(s)://server-address:port',
                        ),
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) {
                          if (_needsPassword) {
                            FocusScope.of(context).nextFocus();
                          }
                        },
                      ),

                      // --- 本机连接提示 ---
                      if (_isLocalhost) ...[
                        const SizedBox(height: 12),
                        const _LocalConnectionBanner(),
                      ],

                      // --- 凭据输入 ---
                      if (_needsPassword) ...[
                        const SizedBox(height: 20),
                        Text(
                          'CREDENTIALS',
                          style: AkTheme.sans(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AkColors.textSecondary,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _usernameController,
                          style: AkTheme.sans(color: AkColors.textPrimary),
                          decoration: const InputDecoration(
                            hintText: '用户名（选填）',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          style: AkTheme.sans(color: AkColors.textPrimary),
                          decoration: const InputDecoration(hintText: '密码（选填）'),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                        ),
                      ],

                      // --- 错误信息 ---
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AkColors.danger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AkTheme.cutSm),
                            border: Border(
                              left: BorderSide(
                                color: AkColors.danger,
                                width: AkTheme.signalBorder,
                              ),
                            ),
                          ),
                          child: Text(
                            _error!,
                            style: AkTheme.sans(
                              fontSize: 13,
                              color: AkColors.danger,
                            ),
                          ),
                        ),
                      ],

                      // --- 提交按钮 ---
                      const SizedBox(height: 24),
                      _AkButton(
                        label: _loading ? null : '登录',
                        backgroundColor: AkColors.info,
                        foregroundColor: AkColors.textInverse,
                        loading: _loading,
                        onPressed: _loading ? null : _submit,
                      ),
                    ],
                  ),
                ),

                // --- 分割线 ---
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Text(
                          'RECENT',
                          style: AkTheme.sans(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AkColors.textSecondary,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Divider(height: 1, color: AkColors.border),
                        ),
                      ],
                    ),
                  ),
                ],

                // --- 历史连接列表 ---
                if (_history.isNotEmpty)
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                      itemCount: _history.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _HistoryTile(
                        entry: _history[i],
                        timeLabel: _formatTime(_history[i].timestamp),
                        onTap: () => _quickLogin(_history[i]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Local connection banner
// ---------------------------------------------------------------------------

class _LocalConnectionBanner extends StatelessWidget {
  const _LocalConnectionBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AkColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AkTheme.cutSm),
        border: Border(
          left: BorderSide(
            color: AkColors.success,
            width: AkTheme.signalBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 16, color: AkColors.success),
          const SizedBox(width: 8),
          Text(
            '本机连接，免密登录',
            style: AkTheme.sans(
              fontSize: 13,
              color: AkColors.success,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card corner button (icon + optional label)
// ---------------------------------------------------------------------------

class _CornerButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final String? label;
  final VoidCallback onTap;

  const _CornerButton({
    required this.icon,
    required this.tooltip,
    this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AkTheme.cutSm),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: label != null ? 8 : 6,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AkColors.textSecondary),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: AkTheme.sans(
                    fontSize: 12,
                    color: AkColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 历史连接条目
// ---------------------------------------------------------------------------

class _HistoryTile extends StatelessWidget {
  final ServerProfile entry;
  final String timeLabel;
  final VoidCallback onTap;

  const _HistoryTile({
    required this.entry,
    required this.timeLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AkTheme.cutSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AkColors.panel,
            border: Border.all(color: AkColors.border),
          ),
          child: Row(
            children: [
              // --- 连接信息 ---
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.baseUrl,
                      style: AkTheme.mono(
                        fontSize: 13,
                        color: AkColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.username.isNotEmpty ? entry.username : '免密',
                      style: AkTheme.sans(
                        fontSize: 12,
                        color: AkColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // --- 时间 ---
              Text(
                timeLabel,
                style: AkTheme.sans(
                  fontSize: 11,
                  color: AkColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ak-ui clipped corner button
// ---------------------------------------------------------------------------

class _AkButton extends StatelessWidget {
  final String? label;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool loading;
  final VoidCallback? onPressed;

  const _AkButton({
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
// Clipper: asymmetric top-right cut
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

// ---------------------------------------------------------------------------
// Background grid pattern painter
// ---------------------------------------------------------------------------

class _GridPainter extends CustomPainter {
  final Color color;

  _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 40.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = AkTheme.hairline;

    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      color != oldDelegate.color;
}
