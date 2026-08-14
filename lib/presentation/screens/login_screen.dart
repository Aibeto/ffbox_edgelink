import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/domain/entities/server_profile.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _baseUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(serverRepositoryProvider).load().then((profile) {
      if (profile != null && mounted) {
        setState(() {
          _baseUrlController.text = profile.baseUrl;
          _usernameController.text = profile.username;
        });
      }
    });
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final baseUrl = _baseUrlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (baseUrl.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入服务器地址、用户名和密码');
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
            ? '连接超时，无法确认是否登录成功，请重试'
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
      appBar: AppBar(title: const Text('FFBox EdgeLink')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'http://192.168.1.100:33269',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: '用户名'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const CircularProgressIndicator()
                    : const Text('登录'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
