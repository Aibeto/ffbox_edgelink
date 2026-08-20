import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/domain/entities/server_profile.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';
import 'package:ffbox_edgelink/core/analytics/clarity_analytics.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/core/utils/hash.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/presentation/screens/device_info_screen.dart';
import 'package:ffbox_edgelink/presentation/screens/export_logs_screen.dart';
import 'package:ffbox_edgelink/presentation/screens/local_service_screen.dart';
import 'package:ffbox_edgelink/presentation/widgets/ak_button.dart';

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
  List<ServerProfile> _history = const [];
  Map<String, int> _latency = {};
  Timer? _latencyTimer;

  // --- 初始化与销毁 ---

  @override
  void initState() {
    super.initState();
    ClarityAnalytics.trackScreen('login');
    _loadProfile();
    _loadHistory();
    _latencyTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pingAll(),
    );
  }

  @override
  void dispose() {
    _latencyTimer?.cancel();
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
        // _checkLocalhost(profile.baseUrl);
      });
    }
  }

  Future<void> _loadHistory() async {
    final history = await ref.read(serverRepositoryProvider).loadHistory();
    if (mounted) setState(() => _history = history);
  }

  // --- 延迟探测 ---

  Future<void> _pingAll() async {
    if (_history.isEmpty) return;
    final urls = _history.map((p) => p.baseUrl).toSet();
    final results = <String, int>{};
    await Future.wait([
      for (final url in urls)
        _pingUrl(url).then((ms) {
          if (ms != null) results[url] = ms;
        }),
    ]);
    if (mounted) setState(() => _latency = results);
  }

  Future<int?> _pingUrl(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final sw = Stopwatch()..start();
      final req = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 3));
      await req.close().timeout(const Duration(seconds: 3));
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // --- 本机检测（已禁用） ---

  bool get _needsPassword => _baseUrlController.text.trim().isNotEmpty;

  // --- 历史快捷登录 ---

  void _quickLogin(ServerProfile entry) {
    setState(() {
      _baseUrlController.text = entry.baseUrl;
      _usernameController.text = entry.username;
      _passwordController.text = entry.password;
      _error = null;
    });
    // _checkLocalhost(entry.baseUrl);
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

    // 检测 sha256: 前缀：历史记录自动填入时已是哈希值，直接发送到服务器，
    // 避免 AuthService 再做一次 SHA256 导致双重哈希。
    final isHashed = password.startsWith('sha256:');
    final directPasskey = isHashed
        ? password.substring('sha256:'.length)
        : null;
    final plainPassword = isHashed ? '' : password;

    try {
      final outcome = await ref
          .read(authServiceProvider)
          .login(
            baseUrl: baseUrl,
            username: username,
            password: plainPassword,
            directPasskey: directPasskey,
          );

      if (!mounted) return;

      if (outcome.error != null) {
        logDebug('loginUI: 登录失败 - ${outcome.error}');
        ClarityAnalytics.trackEvent('login_failed');
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
      // 仅手动输入密码时保存历史；从历史自动填入时密码已是 sha256:hex，跳过。
      if (!isHashed) {
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
      }
      await ref.read(sessionRepositoryProvider).save(session);
      logDebug('loginUI: 登录成功，保存会话并切换到任务列表');
      // Clarity 埋点：用户标识用不可逆哈希（避免 PII），服务器仅记录主机名
      final host = Uri.tryParse(baseUrl)?.host ?? baseUrl;
      ClarityAnalytics.identify(sha256Hex('$username@$host'));
      ClarityAnalytics.setTag('server', host);
      ClarityAnalytics.trackEvent('login_success');
      ref.read(sessionProvider.notifier).update(session);
    } on ApiException catch (e) {
      if (!mounted) return;
      logDebug(
        'loginUI: 登录异常 ApiException kind=${e.kind} msg=${e.friendlyMessage}',
      );
      ClarityAnalytics.trackEvent('login_failed');
      setState(() {
        _loading = false;
        _error = e.kind == ApiErrorKind.timeout ? '连接超时' : e.friendlyMessage;
      });
    } catch (e) {
      if (!mounted) return;
      logDebug('loginUI: 登录异常 $e');
      ClarityAnalytics.trackEvent('login_failed');
      setState(() {
        _loading = false;
        _error = '登录失败：$e';
      });
    }
  }

  // --- 删除历史记录 ---

  Future<void> _deleteHistory(ServerProfile entry) async {
    await ref.read(serverRepositoryProvider).deleteFromHistory(entry);
    setState(() {
      _history = _history
          .where(
            (p) =>
                !(p.baseUrl == entry.baseUrl && p.username == entry.username),
          )
          .toList();
    });
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
    // 内置本地服务仅 Android arm64-v8a 可用（校准后决定是否显示入口）
    final localNodeSupported =
        ref.watch(localNodeSupportedProvider).value ?? false;
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
                  tooltip: '接口与IP',
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
                  label: 'LOG',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ExportLogsScreen(),
                      ),
                    );
                  },
                ),
                // 内置服务入口仅支持设备显示（Android arm64-v8a，依赖 nodejs-mobile 原生引擎）
                if (localNodeSupported)
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: _CornerButton(
                      icon: Icons.dns_outlined,
                      tooltip: '本地服务',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LocalServiceScreen(),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // --- 主体内容 ---
          Positioned.fill(
            child: SafeArea(
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
                            decoration: const InputDecoration(
                              hintText: '密码（选填）',
                            ),
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
                        AkButton(
                          label: _loading ? null : 'LOGIN',
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
                    const SizedBox(height: 16),
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

                  // --- 历史连接列表（最多显示 20 条） ---
                  if (_history.isNotEmpty)
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                        itemCount: _history.length.clamp(0, 20),
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final entry = _history[i];
                          return _SwipeReveal(
                            onDeleted: () => _deleteHistory(entry),
                            child: _HistoryTile(
                              entry: entry,
                              timeLabel: _formatTime(entry.timestamp),
                              latency: _latency[entry.baseUrl],
                              onTap: () => _quickLogin(entry),
                            ),
                          );
                        },
                      ),
                    ),
                ],
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

// ---------------------------------------------------------------------------
// 左滑露出删除按钮
// ---------------------------------------------------------------------------

class _SwipeReveal extends StatefulWidget {
  final VoidCallback onDeleted;
  final Widget child;

  const _SwipeReveal({required this.onDeleted, required this.child});

  @override
  State<_SwipeReveal> createState() => _SwipeRevealState();
}

class _SwipeRevealState extends State<_SwipeReveal>
    with SingleTickerProviderStateMixin {
  static const _deleteWidth = 64.0;
  static const _threshold = 0.5;

  /// 滑动进度 0（收起）~ 1（完全露出删除按钮）。
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _slide = Tween(
      begin: Offset.zero,
      end: const Offset(-1, 0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // 左滑 delta.dx 为负，将像素位移折算为 0~1 进度
    _controller.value = (_controller.value + d.delta.dx / -_deleteWidth).clamp(
      0.0,
      1.0,
    );
    setState(() {});
  }

  void _onDragEnd(DragEndDetails _) {
    if (_controller.value > _threshold) {
      _controller.animateTo(1);
    } else {
      _controller.animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // --- 删除背景（Positioned 固定在右侧，垂直拉伸与内容同高） ---
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: _deleteWidth,
          child: GestureDetector(
            onTap: () {
              widget.onDeleted();
              _controller.value = 0;
            },
            child: Container(
              color: AkColors.danger.withValues(alpha: 0.15),
              alignment: Alignment.center,
              child: Icon(
                Icons.delete_outline,
                color: AkColors.danger,
                size: 20,
              ),
            ),
          ),
        ),
        // --- 内容层（非 Positioned，作为 Stack 尺寸来源；ListView 高度无界时必须如此） ---
        SlideTransition(
          position: _slide,
          child: GestureDetector(
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            child: widget.child,
          ),
        ),
      ],
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
  final int? latency;
  final VoidCallback onTap;

  const _HistoryTile({
    required this.entry,
    required this.timeLabel,
    this.latency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
                      entry.username.isNotEmpty ? entry.username : '匿名',
                      style: AkTheme.sans(
                        fontSize: 12,
                        color: AkColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // --- 时间 + 延迟 ---
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeLabel,
                    style: AkTheme.sans(
                      fontSize: 11,
                      color: AkColors.textSecondary,
                    ),
                  ),
                  if (latency != null)
                    Text(
                      '${latency}ms',
                      style: AkTheme.sans(
                        fontSize: 11,
                        color: latency! < 200
                            ? AkColors.success
                            : latency! < 500
                            ? AkColors.action
                            : AkColors.danger,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
