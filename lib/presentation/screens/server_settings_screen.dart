import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/core/analytics/clarity_analytics.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/domain/entities/server_settings.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';
import 'package:ffbox_edgelink/presentation/widgets/ak_button.dart';

/// 服务端配置页：读取/修改服务端转码配置（并发数、FFmpeg 路径、任务保留策略）。
///
/// 通过 `/api/v1/settings/server` 读写 ServerSettingsData；无 ServerSettings
/// 权限（403）时仅提示不可修改，不触发登出。
class ServerSettingsScreen extends ConsumerStatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  ConsumerState<ServerSettingsScreen> createState() =>
      _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends ConsumerState<ServerSettingsScreen> {
  // --- 表单状态 ---

  final _maxThreadsCtrl = TextEditingController();
  final _ffmpegPathCtrl = TextEditingController();
  bool _preserveUnfinished = true;
  bool _deleteFinished = false;
  AsyncValue<ServerSettings> _settings = const AsyncValue.loading();
  bool _busy = false;
  String? _actionError;

  // --- 生命周期 ---

  @override
  void initState() {
    super.initState();
    ClarityAnalytics.trackScreen('server_settings');
    _load();
  }

  @override
  void dispose() {
    _maxThreadsCtrl.dispose();
    _ffmpegPathCtrl.dispose();
    super.dispose();
  }

  // --- 加载 ---

  Future<void> _load() async {
    setState(() => _settings = const AsyncValue.loading());
    try {
      final s = await ref
          .read(serverSettingsRepositoryProvider)
          .getSettings();
      if (!mounted) return;
      _maxThreadsCtrl.text = '${s.maxThreads}';
      _ffmpegPathCtrl.text = s.customFFmpegPath;
      _preserveUnfinished = s.preserveUnfinishedTasks;
      _deleteFinished = s.deleteFinishedTasks;
      setState(() => _settings = AsyncValue.data(s));
    } on ApiException catch (e) {
      if (!mounted) return;
      logDebug('serverSettingsUI: 加载失败 ${e.friendlyMessage}');
      if (_handleAuthFailure(e)) return;
      setState(() => _settings = AsyncValue.error(e, StackTrace.current));
    } catch (e) {
      if (!mounted) return;
      setState(() => _settings = AsyncValue.error(e, StackTrace.current));
    }
  }

  // --- 保存 ---

  Future<void> _save() async {
    final maxThreads = int.tryParse(_maxThreadsCtrl.text.trim());
    if (maxThreads == null || maxThreads < 1) {
      setState(() => _actionError = '同时转码任务数量须为不小于 1 的整数');
      return;
    }
    ClarityAnalytics.trackEvent('server_settings_save');
    setState(() {
      _busy = true;
      _actionError = null;
    });
    final settings = ServerSettings(
      maxThreads: maxThreads,
      customFFmpegPath: _ffmpegPathCtrl.text.trim(),
      preserveUnfinishedTasks: _preserveUnfinished,
      deleteFinishedTasks: _deleteFinished,
    );
    try {
      await ref
          .read(serverSettingsRepositoryProvider)
          .updateSettings(settings);
      ClarityAnalytics.trackEvent('server_settings_save_ok');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('配置已保存', style: AkTheme.sans(fontSize: 13)),
          backgroundColor: AkColors.panel,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiException catch (e) {
      ClarityAnalytics.trackEvent('server_settings_save_failed');
      if (!mounted) return;
      logDebug('serverSettingsUI: 保存失败 ${e.friendlyMessage}');
      if (_handleAuthFailure(e)) return;
      setState(() => _actionError = e.friendlyMessage);
    } catch (e) {
      ClarityAnalytics.trackEvent('server_settings_save_failed');
      if (!mounted) return;
      setState(() => _actionError = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 401 → 会话失效登出；403 → 权限不足（仅提示，不登出）。
  bool _handleAuthFailure(ApiException e) {
    if (!e.isUnauthorized) return false;
    if (e.statusCode == 403) {
      setState(() => _actionError = '当前账号无权限修改服务器配置');
      return true;
    }
    logDebug('serverSettingsUI: 会话失效，登出');
    ref.read(sessionProvider.notifier).update(null);
    return true;
  }

  // --- 构建 ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务端配置')),
      body: _settings.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AkColors.info, strokeWidth: 2),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: AkColors.danger, size: 40),
              const SizedBox(height: 12),
              Text(
                '加载失败',
                style: AkTheme.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '$e',
                  style: AkTheme.sans(
                    fontSize: 12,
                    color: AkColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16, color: AkColors.info),
                label: Text('重试', style: AkTheme.sans(fontSize: 13, color: AkColors.info)),
              ),
            ],
          ),
        ),
        data: (_) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // --- 并发数与 FFmpeg 路径 ---
            TextField(
              controller: _maxThreadsCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '同时转码任务数量',
                hintText: '1',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ffmpegPathCtrl,
              decoration: const InputDecoration(
                labelText: 'ffmpeg 路径',
                hintText: '建议留空，自动检测',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '内置服务会自动指向应用内置的 ffmpeg/ffprobe；留空则按系统 PATH 查找。',
              style: AkTheme.sans(
                fontSize: 11,
                color: AkColors.textSecondary,
                height: 1.5,
              ),
            ),

            // --- 任务保留策略 ---
            const SizedBox(height: 8),
            _SwitchRow(
              title: '保留未完成任务',
              subtitle: '服务重启后继续转码未完成任务',
              value: _preserveUnfinished,
              onChanged: (v) => setState(() => _preserveUnfinished = v),
            ),
            _SwitchRow(
              title: '任务完成自动移除',
              subtitle: '转码完成后自动从任务列表删除',
              value: _deleteFinished,
              onChanged: (v) => setState(() => _deleteFinished = v),
            ),

            // --- 操作错误 ---
            if (_actionError != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AkColors.danger.withValues(alpha: 0.1),
                  border: Border(
                    left: BorderSide(
                      color: AkColors.danger,
                      width: AkTheme.signalBorder,
                    ),
                  ),
                ),
                child: Text(
                  _actionError!,
                  style: AkTheme.sans(fontSize: 12, color: AkColors.danger),
                ),
              ),
            ],

            const SizedBox(height: 20),
            AkButton(
              label: '保存配置',
              backgroundColor: AkColors.info,
              foregroundColor: AkColors.textInverse,
              loading: _busy,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 开关行
// ---------------------------------------------------------------------------

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AkColors.panel,
        border: Border.all(color: AkColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AkTheme.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AkTheme.sans(
                    fontSize: 11,
                    color: AkColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AkColors.info,
            activeTrackColor: AkColors.info.withValues(alpha: 0.3),
            inactiveThumbColor: AkColors.textSecondary,
            inactiveTrackColor: AkColors.border,
          ),
        ],
      ),
    );
  }
}
