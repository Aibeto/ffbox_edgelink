import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffbox_edgelink/application/local_node/local_node_service.dart';
import 'package:ffbox_edgelink/core/analytics/clarity_analytics.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';
import 'package:ffbox_edgelink/presentation/widgets/ak_button.dart';

/// 内置服务页：在本机 Android 上启动/停止 FFBox 转码服务（nodejs-mobile），
/// 并展示实时日志。服务以前台服务形式后台运行，页面退出不影响运行。
class LocalServiceScreen extends ConsumerStatefulWidget {
  const LocalServiceScreen({super.key});

  @override
  ConsumerState<LocalServiceScreen> createState() => _LocalServiceScreenState();
}

class _LocalServiceScreenState extends ConsumerState<LocalServiceScreen> {
  // --- 滚动控制 ---

  final _logController = ScrollController();
  final _logKey = GlobalKey();

  // --- 订阅 ---

  StreamSubscription<LocalNodeStatus>? _statusSub;
  StreamSubscription<String>? _logSub;
  LocalNodeStatus _status = LocalNodeStatus.stopped;
  List<String> _logs = const [];
  bool _busy = false;

  // --- 生命周期 ---

  @override
  void initState() {
    super.initState();
    ClarityAnalytics.trackScreen('local_service');
    final service = ref.read(localNodeServiceProvider);
    _status = service.status;
    _logs = service.logs;
    _statusSub = service.statusStream.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _logSub = service.logStream.listen((_) {
      if (!mounted) return;
      // 更新日志快照触发列表重建（此前仅滚动不刷新，新日志不显示）
      setState(() => _logs = service.logs);
      _scheduleScroll();
    });
    service.initialize();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _logSub?.cancel();
    _logController.dispose();
    super.dispose();
  }

  // --- 日志滚动 ---

  void _scheduleScroll() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_logController.hasClients) return;
      _logController.animateTo(
        _logController.position.maxScrollExtent,
        duration: AkTheme.motionFast,
        curve: Curves.easeOut,
      );
    });
  }

  // --- 启动 / 停止 ---

  Future<void> _toggle() async {
    final service = ref.read(localNodeServiceProvider);
    final wasStopped = _status.state == LocalNodeState.stopped;
    ClarityAnalytics.trackEvent(
      wasStopped ? 'local_service_start' : 'local_service_stop',
    );
    // 启动前必须先获得读取用户文件的存储权限（转码需按真实路径读视频文件）
    if (wasStopped && !await _ensureStoragePermission()) return;
    setState(() => _busy = true);
    try {
      final ok = wasStopped ? await service.start() : await service.stop();
      ClarityAnalytics.trackEvent(
        '${wasStopped ? 'local_service_start' : 'local_service_stop'}_${ok ? 'ok' : 'failed'}',
      );
    } catch (_) {
      ClarityAnalytics.trackEvent(
        '${wasStopped ? 'local_service_start' : 'local_service_stop'}_failed',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 检查存储权限；未授权时弹窗引导去系统设置页开启“所有文件访问权”。
  /// 返回是否已具备权限（可直接启动服务）。
  Future<bool> _ensureStoragePermission() async {
    final channel = ref.read(localNodeChannelProvider);
    if (await channel.hasStoragePermission()) return true;
    if (!mounted) return false;
    // 确认弹窗
    final goGrant = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AkColors.panel,
        title: Text(
          '需要“所有文件访问”权限',
          style: AkTheme.sans(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: Text(
          '内置 FFBox 服务需要读取您手机中的视频/媒体文件进行转码。\n'
          '请授予“所有文件访问”权限（系统设置页开启）。',
          style: AkTheme.sans(
            fontSize: 13,
            color: AkColors.textSecondary,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              '取消',
              style: AkTheme.sans(color: AkColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('去授权', style: AkTheme.sans(color: AkColors.info)),
          ),
        ],
      ),
    );
    if (goGrant != true) return false;
    // 打开系统授权页；返回后重新检查，已授权则直接继续启动
    await channel.requestStoragePermission();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return await channel.hasStoragePermission();
  }

  // --- 构建 ---

  @override
  Widget build(BuildContext context) {
    final running = _status.state == LocalNodeState.running;
    final transitional =
        _status.state == LocalNodeState.starting ||
        _status.state == LocalNodeState.stopping;

    return Scaffold(
      appBar: AppBar(title: const Text('本地服务')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- 状态卡 ---
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _StatusCard(
                status: _status,
                port: LocalNodeService.defaultPort,
              ),
            ),

            // --- 操作按钮 ---
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: AkButton(
                label: _status.state == LocalNodeState.stopped
                    ? '启动服务'
                    : _status.state == LocalNodeState.starting
                    ? '启动中'
                    : _status.state == LocalNodeState.stopping
                    ? '停止中'
                    : '停止服务',
                backgroundColor: running ? AkColors.danger : AkColors.info,
                foregroundColor: AkColors.textInverse,
                loading: _busy || transitional,
                onPressed: (_busy || transitional) ? null : _toggle,
              ),
            ),

            // --- 提示 ---
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Text(
                running
                    ? '服务正在后台运行，返回登录页或任务列表不会中断；'
                          '登录页地址栏输入 ${_status.baseUrl ?? 'http://127.0.0.1:${LocalNodeService.defaultPort}'} 即可连接。'
                    : '启动后 FFBox 服务将运行于本机，可在后台持续转码，'
                          '直到手动停止或应用被系统终止。',
                style: AkTheme.sans(
                  fontSize: 12,
                  color: AkColors.textSecondary,
                  height: 1.6,
                ),
              ),
            ),

            // --- 运行环境目录（缓存/配置实际落盘位置） ---
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: _RuntimeEnvCard(),
            ),

            // --- 输出文件缓存（默认输出目录，可导出/清理） ---
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: _OutputCacheCard(),
            ),

            // --- 日志面板（固定高度，内容超长时列表内部滚动） ---
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: _LogPanel(
                key: _logKey,
                controller: _logController,
                logs: _logs,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 状态卡
// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  final LocalNodeStatus status;
  final int port;

  const _StatusCard({required this.status, required this.port});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status.state) {
      LocalNodeState.stopped => ('已停止', AkColors.textSecondary),
      LocalNodeState.starting => ('启动中', AkColors.action),
      LocalNodeState.running => ('运行中', AkColors.success),
      LocalNodeState.stopping => ('停止中', AkColors.action),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AkColors.panel,
        border: Border.all(color: AkColors.border),
      ),
      child: Row(
        children: [
          // --- 状态点 ---
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: AkTheme.sans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AkColors.textPrimary,
            ),
          ),
          const Spacer(),
          // --- 地址 ---
          Text(
            '127.0.0.1:$port',
            style: AkTheme.mono(
              fontSize: 13,
              color: status.state == LocalNodeState.running
                  ? AkColors.textPrimary
                  : AkColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 日志面板
// ---------------------------------------------------------------------------

class _LogPanel extends StatefulWidget {
  final ScrollController controller;
  final List<String> logs;

  const _LogPanel({super.key, required this.controller, required this.logs});

  @override
  State<_LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<_LogPanel> {
  /// 用户是否已向上滚动离开底部（此时显示“跳转最后一行”按钮）
  bool _awayFromBottom = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final controller = widget.controller;
    if (!controller.hasClients) return;
    final away =
        controller.position.pixels < controller.position.maxScrollExtent - 24;
    if (_awayFromBottom != away) {
      setState(() => _awayFromBottom = away);
    }
  }

  void _jumpToBottom() {
    final controller = widget.controller;
    if (!controller.hasClients) return;
    controller.animateTo(
      controller.position.maxScrollExtent,
      duration: AkTheme.motionBase,
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: AkColors.panel,
        border: Border.all(color: AkColors.border),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: widget.logs.isEmpty
                ? Center(
                    child: Text(
                      '暂无日志',
                      style: AkTheme.sans(
                        fontSize: 12,
                        color: AkColors.textSecondary,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: widget.controller,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    itemCount: widget.logs.length,
                    itemBuilder: (_, i) => Text(
                      widget.logs[i],
                      style: AkTheme.mono(
                        fontSize: 11,
                        color: widget.logs[i].startsWith('[error]')
                            ? AkColors.danger
                            : AkColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
          ),
          if (_awayFromBottom)
            Positioned(
              right: 10,
              bottom: 10,
              child: _JumpToBottomButton(onTap: _jumpToBottom),
            ),
        ],
      ),
    );
  }
}

/// 日志面板右下角的“跳转至最后一行”圆形按钮
class _JumpToBottomButton extends StatelessWidget {
  final VoidCallback onTap;

  const _JumpToBottomButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AkColors.panel,
      shape: const CircleBorder(side: BorderSide(color: AkColors.border)),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(
            Icons.keyboard_arrow_down,
            size: 20,
            color: AkColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 运行环境目录卡（缓存/配置实际落盘位置）
// ---------------------------------------------------------------------------

/// 展示内置服务运行环境目录：宿主 main.js 将 TMPDIR 指向应用私有
/// filesDir/cache、XDG_CONFIG_HOME 指向 filesDir/config，FFBox 的
/// “/tmp/FFBoxUploadCache”“/tmp/FFBoxDownloadCache” 实际创建于此。
class _RuntimeEnvCard extends StatelessWidget {
  const _RuntimeEnvCard();

  Future<Map<String, String>> _loadPaths() async {
    final filesDir = (await getApplicationSupportDirectory()).path;
    return {
      'config': '$filesDir/config',
      'cache': '$filesDir/cache',
      'uploadCache': '$filesDir/cache/FFBoxUploadCache',
      'downloadCache': '$filesDir/cache/FFBoxDownloadCache',
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _loadPaths(),
      builder: (context, snapshot) {
        final paths = snapshot.data;
        if (paths == null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AkColors.panel,
            border: Border.all(color: AkColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '运行环境目录',
                style: AkTheme.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AkColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              _EnvRow(label: '配置文件目录', path: paths['config']!),
              _EnvRow(label: '缓存 / 临时目录', path: paths['cache']!),
              _EnvRow(label: '上传缓存', path: paths['uploadCache']!),
              _EnvRow(label: '下载缓存', path: paths['downloadCache']!),
              const SizedBox(height: 6),
              Text(
                'FFBox 代码中的 /tmp/FFBoxUploadCache 与 /tmp/FFBoxDownloadCache '
                '即上述两个目录（nodejs-mobile 的 os.tmpdir() 被重定向到应用私有缓存）。',
                style: AkTheme.sans(
                  fontSize: 10,
                  color: AkColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EnvRow extends StatelessWidget {
  final String label;
  final String path;

  const _EnvRow({required this.label, required this.path});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: AkTheme.sans(fontSize: 11, color: AkColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              path,
              style: AkTheme.mono(
                fontSize: 11,
                color: AkColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 输出文件缓存卡（默认输出目录与清理）
// ---------------------------------------------------------------------------

/// 内置服务的默认输出目录（filesDir/cache/FFBoxOutput）：新建任务默认把
/// 输出写到这里（可在任务详情页导出），此处展示占用并支持一键清理。
class _OutputCacheCard extends ConsumerStatefulWidget {
  const _OutputCacheCard();

  @override
  ConsumerState<_OutputCacheCard> createState() => _OutputCacheCardState();
}

class _OutputCacheCardState extends ConsumerState<_OutputCacheCard> {
  String? _dirPath;
  int _sizeBytes = 0;
  bool _loading = true;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final service = ref.read(localOutputServiceProvider);
      final dir = await service.outputDir();
      final size = await service.outputCacheSize();
      if (!mounted) return;
      setState(() {
        _dirPath = dir.path;
        _sizeBytes = size;
      });
    } catch (_) {
      // 路径不可用时保持空态
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AkColors.panel,
        title: Text(
          '清理输出缓存？',
          style: AkTheme.sans(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: Text(
          '将删除输出目录中的全部转码产物（未导出的文件将丢失），不影响任务本身。',
          style: AkTheme.sans(
            fontSize: 13,
            color: AkColors.textSecondary,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              '取消',
              style: AkTheme.sans(color: AkColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('清理', style: AkTheme.sans(color: AkColors.danger)),
          ),
        ],
      ),
    );
    if (go != true) return;
    setState(() => _clearing = true);
    try {
      await ref.read(localOutputServiceProvider).clearOutputCache();
      await _refresh();
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  String _humanSize(int bytes) {
    if (bytes >= 1000 * 1000 * 1000) {
      return '${(bytes / 1000 / 1000 / 1000).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1000 * 1000) {
      return '${(bytes / 1000 / 1000).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1000) return '${(bytes / 1000).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AkColors.panel,
        border: Border.all(color: AkColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '输出文件缓存',
                style: AkTheme.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AkColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                _loading ? '统计中…' : _humanSize(_sizeBytes),
                style: AkTheme.mono(
                  fontSize: 12,
                  color: AkColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: (_clearing || _loading) ? null : _clear,
                child: Text(
                  '清理',
                  style: AkTheme.sans(fontSize: 12, color: AkColors.danger),
                ),
              ),
            ],
          ),
          if (_dirPath != null) ...[
            const SizedBox(height: 4),
            Text(
              _dirPath!,
              style: AkTheme.mono(
                fontSize: 10,
                color: AkColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '新建任务默认输出到上述目录，转码完成后可在任务详情页导出；'
            '建议及时导出并定期清理。',
            style: AkTheme.sans(
              fontSize: 10,
              color: AkColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
