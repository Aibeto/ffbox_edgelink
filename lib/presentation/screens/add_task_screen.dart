/// 远程新建任务页：选择本机视频文件 + 基础输出配置，
/// 提交后先以占位符创建任务再入队后台上传。
///
/// presentation 层页面，依赖全局 uploadQueueProvider（生命周期
/// 独立于本页），离开页面后上传继续进行。
library;

import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/application/local_node/local_output_service.dart';
import 'package:ffbox_edgelink/application/upload/upload_protocol.dart';
import 'package:ffbox_edgelink/application/upload/upload_queue.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';
import 'package:ffbox_edgelink/presentation/widgets/output_params_form.dart';

/// 新建任务页：文件选择、输出配置与提交，附带队列状态区。
class AddTaskScreen extends ConsumerStatefulWidget {
  /// 预填文件（测试/外部入口用），元素为 (path, name, size)。
  final List<({String path, String name, int size})> initialFiles;

  const AddTaskScreen({super.key, this.initialFiles = const []});

  @override
  ConsumerState<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends ConsumerState<AddTaskScreen> {
  final List<({String path, String name, int size})> _files = [];
  final GlobalKey<OutputParamsFormState> _formKey =
      GlobalKey<OutputParamsFormState>();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _files.addAll(widget.initialFiles);
  }

  // --- 文件选择 ---

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    if (result == null) return;
    final picked = result.paths
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .map((p) => _fileEntryOf(p))
        .whereType<({String path, String name, int size})>()
        .toList();
    if (picked.isEmpty) return;
    setState(() {
      for (final f in picked) {
        if (!_files.any((e) => e.path == f.path)) _files.add(f);
      }
    });
  }

  ({String path, String name, int size})? _fileEntryOf(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final size = _fileSizeOf(path);
    if (size <= 0) return null;
    return (path: path, name: name, size: size);
  }

  int _fileSizeOf(String path) {
    try {
      final stat = io.File(path).statSync();
      return stat.type == io.FileSystemEntityType.file ? stat.size : 0;
    } catch (_) {
      return 0;
    }
  }

  void _remove(String path) =>
      setState(() => _files.removeWhere((f) => f.path == path));

  // --- 任务创建模式 ---

  /// 本机回环 + FileSystem 权限时使用直接路径模式：
  /// 与 FFBox web 前端语义一致——服务端按原路径创建本地任务，
  /// 文件与服务器同机（内置服务/同机桌面版），无需分片上传。
  bool get _directMode {
    final session = ref.read(sessionProvider);
    return LocalOutputService.useDirectPaths(
      baseUrl: ref.read(appConfigProvider).normalizedBaseUrl,
      hasFileSystemPermission:
          session?.hasFileSystemPermission ?? false,
    );
  }

  /// 有 FileSystem 权限但连接非本机回环：服务端对该会话一律按原路径
  /// 创建本地任务（remoteTask=false），上传占位符任务无法被服务端解析，
  /// 转码必然失败。与 web 版浏览器行为一致：阻止提交并说明原因。
  bool get _blockedByPrivilegedRemote {
    final session = ref.read(sessionProvider);
    final hasPerm = session?.hasFileSystemPermission ?? false;
    return hasPerm &&
        !LocalOutputService.isLoopbackUrl(
          ref.read(appConfigProvider).normalizedBaseUrl,
        );
  }

  Future<void> _showPrivilegedRemoteBlock() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AkColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AkTheme.cutMd),
        ),
        title: Text(
          '无法通过上传创建任务',
          style: AkTheme.sans(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: Text(
          '当前账号具有文件系统权限，服务端会以原路径创建任务，'
          '不接收上传文件。\n\n'
          '请改用不具有文件系统权限的账号，'
          '或在本机服务（127.0.0.1）下新建任务。',
          style: AkTheme.sans(
            fontSize: 13,
            color: AkColors.textSecondary,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('知道了', style: AkTheme.sans(color: AkColors.info)),
          ),
        ],
      ),
    );
  }

  // --- 提交 ---

  Future<void> _submit() async {
    if (_files.isEmpty || _submitting) return;
    if (_blockedByPrivilegedRemote) {
      await _showPrivilegedRemoteBlock();
      return;
    }
    final form = _formKey.currentState;
    if (form == null) return;
    setState(() => _submitting = true);
    try {
      final outputParams = buildOutputParams(
        video: form.videoSection,
        audio: form.audioSection,
        mux: form.muxSection,
      );
      if (_directMode) {
        // 直接路径模式：真实路径建任务，跳过上传队列；
        // Android 下确保输出缓存目录存在（ffmpeg 不会自动建目录）
        if (io.Platform.isAndroid) {
          await ref.read(localOutputServiceProvider).outputDir();
        }
        final filePaths = _files.map((f) => f.path).toList();
        logDebug('addTaskUI: create ${filePaths.length} task(s) [direct]');
        await ref
            .read(taskRepositoryProvider)
            .createTasks(filePaths, outputParams);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已创建任务，可在任务列表启动')),
        );
        Navigator.of(context).pop();
        return;
      }
      final filePaths = _files.map((f) => uploadPlaceholder(f.name)).toList();
      logDebug('addTaskUI: create ${filePaths.length} task(s)');
      final ids = await ref
          .read(taskRepositoryProvider)
          .createTasks(filePaths, outputParams);
      final queue = ref.read(uploadQueueProvider);
      for (var i = 0; i < ids.length && i < _files.length; i++) {
        await queue.enqueue(
          taskId: ids[i],
          path: _files[i].path,
          fileBaseName: _files[i].name,
          size: _files[i].size,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已创建任务并开始上传，可离开页面')),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      // 401 交给列表页轮询登出；此处提示后返回
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.friendlyMessage)),
      );
      if (e.isUnauthorized) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // --- 构建 ---

  @override
  Widget build(BuildContext context) {
    ref.watch(uploadNotificationBridgeProvider);
    final queueSnap = ref.watch(uploadQueueStateProvider).value;

    return Scaffold(
      backgroundColor: AkColors.canvas,
      appBar: AppBar(
        title: Text(
          '新建任务',
          style: AkTheme.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AkColors.textPrimary,
          ),
        ),
        backgroundColor: AkColors.oledDark,
        iconTheme: const IconThemeData(color: AkColors.textSecondary),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AkTheme.cutMd),
        children: [
          _FilePickerCard(onPick: _pickFiles, files: _files, onRemove: _remove),
          const SizedBox(height: AkTheme.cutMd),
          OutputParamsForm(key: _formKey),
          const SizedBox(height: AkTheme.cutMd),
          if (queueSnap != null && queueSnap.items.isNotEmpty) ...[
            _QueueSection(snapshot: queueSnap),
            const SizedBox(height: AkTheme.cutMd),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AkTheme.cutMd),
          child: ElevatedButton(
            onPressed: (_files.isEmpty || _submitting) ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AkColors.action,
              disabledBackgroundColor: AkColors.disabled,
              foregroundColor: AkColors.textInverse,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AkTheme.cutSm),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AkColors.textInverse,
                    ),
                  )
                : Text(
                    _directMode ? '添加任务' : '添加并上传',
                    style: AkTheme.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AkColors.textInverse,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// --- 文件选择卡片 ---

/// 输入文件卡片：选择按钮 + 已选文件列表（名称/大小/移除）。
class _FilePickerCard extends StatelessWidget {
  final VoidCallback onPick;
  final List<({String path, String name, int size})> files;
  final void Function(String path) onRemove;

  const _FilePickerCard({
    required this.onPick,
    required this.files,
    required this.onRemove,
  });

  String _humanSize(int bytes) {
    if (bytes >= 1000 * 1000 * 1000) {
      return '${(bytes / 1000 / 1000 / 1000).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1000 * 1000) {
      return '${(bytes / 1000 / 1000).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1000).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AkColors.panel,
        border: Border.all(color: AkColors.border, width: AkTheme.hairline),
      ),
      padding: const EdgeInsets.all(AkTheme.cutMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.movie_outlined, size: 16, color: AkColors.info),
              const SizedBox(width: 8),
              Text(
                '输入文件',
                style: AkTheme.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AkColors.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.add, size: 16, color: AkColors.info),
                label: Text(
                  '选择文件',
                  style: AkTheme.sans(fontSize: 13, color: AkColors.info),
                ),
              ),
            ],
          ),
          if (files.isEmpty)
            Text(
              '从本设备选择要转码的视频文件',
              style: AkTheme.sans(fontSize: 12, color: AkColors.textSecondary),
            )
          else
            for (final f in files)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      f.name,
                      style: AkTheme.sans(
                        fontSize: 13,
                        color: AkColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _humanSize(f.size),
                    style: AkTheme.mono(
                      fontSize: 11,
                      color: AkColors.textSecondary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 16,
                      color: AkColors.textSecondary,
                    ),
                    onPressed: () => onRemove(f.path),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

// --- 队列状态区 ---

/// 后台上传队列状态列表：每项显示状态/进度，失败项可重试。
class _QueueSection extends ConsumerWidget {
  final UploadQueueSnapshot snapshot;

  const _QueueSection({required this.snapshot});

  String _stateLabel(UploadItemState state) {
    switch (state) {
      case UploadItemState.pending:
        return '排队中';
      case UploadItemState.hashing:
        return '计算哈希';
      case UploadItemState.uploading:
        return '上传中';
      case UploadItemState.merging:
        return '合并中';
      case UploadItemState.done:
        return '已完成';
      case UploadItemState.error:
        return '失败';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AkColors.panel,
        border: Border.all(color: AkColors.border, width: AkTheme.hairline),
      ),
      padding: const EdgeInsets.all(AkTheme.cutMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '上传队列',
            style: AkTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AkColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in snapshot.items)
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.fileBaseName,
                    style: AkTheme.sans(
                      fontSize: 12,
                      color: AkColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  item.state == UploadItemState.error
                      ? (item.error ?? '失败')
                      : item.state == UploadItemState.done
                      ? '已完成'
                      : '${_stateLabel(item.state)} ${item.size > 0 ? (item.transferredBytes * 100 / item.size).clamp(0, 100).toStringAsFixed(0) : 0}%',
                  style: AkTheme.mono(
                    fontSize: 11,
                    color: item.state == UploadItemState.error
                        ? AkColors.danger
                        : item.state == UploadItemState.done
                        ? AkColors.success
                        : AkColors.textSecondary,
                  ),
                ),
                if (item.state == UploadItemState.error)
                  TextButton(
                    onPressed: () => ref
                        .read(uploadQueueProvider)
                        .retryItem(item.taskId),
                    child: Text(
                      '重试',
                      style: AkTheme.sans(fontSize: 12, color: AkColors.info),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
