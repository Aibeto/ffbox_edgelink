import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/domain/entities/server_profile.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/presentation/screens/export_logs_screen.dart';

/// 登录页：服务器地址输入、本机免密检测、用户名密码表单。登录成功保存会话并切换到任务列表。
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

  // --- 初始化与销毁 ---

  @override
  void initState() {
    super.initState();
    ref.read(serverRepositoryProvider).load().then((profile) {
      if (profile != null && mounted) {
        setState(() {
          _baseUrlController.text = profile.baseUrl;
          _usernameController.text = profile.username;
          _checkLocalhost(profile.baseUrl);
        });
      }
    });
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

  // --- 登录提交 ---

  Future<void> _submit() async {
    final baseUrl = _baseUrlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (baseUrl.isEmpty) {
      setState(() => _error = '请输入服务器地址');
      return;
    }

    // if (_needsPassword && (username.isEmpty || password.isEmpty)) {
    //   setState(() => _error = '请输入用户名和密码');
    //   return;
    // }

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
        _error = e.kind == ApiErrorKind.timeout
            ? '连接超时'
            : e.friendlyMessage;
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

          // --- 登录卡片 ---
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _AkCard(
                  signalColor: AkColors.info,
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // --- 标题 ---
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
                            const SizedBox(height: 32),

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

                            // --- 凭据输入（非本机时显示） ---
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
                                style: AkTheme.sans(
                                  color: AkColors.textPrimary,
                                ),
                                decoration: const InputDecoration(
                                  hintText: '用户名（选填）',
                                ),
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _passwordController,
                                obscureText: true,
                                style: AkTheme.sans(
                                  color: AkColors.textPrimary,
                                ),
                                decoration: const InputDecoration(
                                  hintText: '密码（选填）',
                                ),
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _submit(),
                              ),
                            ],

                            // --- Error message ---
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AkColors.danger.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AkTheme.cutSm,
                                  ),
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
                      // --- 导出日志按钮（右上角） ---
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Tooltip(
                          message: '导出日志',
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ExportLogsScreen(),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(AkTheme.cutSm),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.save_alt,
                                    size: 16,
                                    color: AkColors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'DEBUG LOGOS',
                                    style: AkTheme.sans(
                                      fontSize: 12,
                                      color: AkColors.textSecondary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
// ak-ui Card with left signal border and clipped top-right corner
// ---------------------------------------------------------------------------

class _AkCard extends StatelessWidget {
  final Widget child;
  final Color signalColor;

  const _AkCard({required this.child, required this.signalColor});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AkTheme.cardRadius),
      child: Container(
        decoration: BoxDecoration(
          color: AkColors.panel,
          border: Border(
            left: BorderSide(color: signalColor, width: AkTheme.signalBorder),
            top: const BorderSide(color: AkColors.border),
            right: const BorderSide(color: AkColors.border),
            bottom: const BorderSide(color: AkColors.border),
          ),
        ),
        child: ClipPath(
          clipper: _TopRightCutClipper(cut: AkTheme.cornerCut),
          child: child,
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
