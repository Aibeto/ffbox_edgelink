import 'dart:async';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:ffbox_edgelink/application/log_export/log_export_service.dart';
import 'package:ffbox_edgelink/core/utils/file_logger.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';

class ExportLogsScreen extends StatefulWidget {
  const ExportLogsScreen({super.key});

  @override
  State<ExportLogsScreen> createState() => _ExportLogsScreenState();
}

class _ExportLogsScreenState extends State<ExportLogsScreen> {
  final _service = LogExportService();
  StreamSubscription<double>? _progressSub;
  DateTime _compressStartTime = DateTime.now();
  String _statusText = '正在扫描日志…';
  double _compressProgress = 0;
  bool _showProgress = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _progressSub?.cancel();
    _service.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _confirmAndExport());
  }

  Future<void> _confirmAndExport() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AkColors.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AkTheme.cutSm),
        ),
        title: Text(
          '导出日志',
          style: AkTheme.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AkColors.textPrimary,
          ),
        ),
        content: Text(
          '确定要将所有日志文件打包导出吗？',
          style: AkTheme.sans(fontSize: 14, color: AkColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              '取消',
              style: AkTheme.sans(fontSize: 14, color: AkColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '确定',
              style: AkTheme.sans(fontSize: 14, color: AkColors.info),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    _startExport();
  }

  Future<void> _startExport() async {
    try {
      // 1. 定位日志目录
      final logDir = await _service.resolveLogDir();
      await fileLogger.log('exportLogs: 日志目录=${logDir?.path ?? '(不存在)'}');
      if (logDir == null || !await logDir.exists()) {
        _finish('暂无日志文件');
        return;
      }

      // 2. 扫描文件
      setState(() => _statusText = '正在扫描日志…');
      final files = await _service.scanFiles(logDir);
      await fileLogger.log('exportLogs: 扫描到 ${files.length} 个日志文件');
      if (files.isEmpty) {
        _finish('暂无日志文件');
        return;
      }

      // 3. 压缩（在后台 Isolate 中执行，不阻塞 UI）
      setState(() {
        _statusText = '正在压缩 ${files.length} 个文件…';
        _showProgress = true;
        _compressProgress = 0;
        _compressStartTime = DateTime.now();
      });
      _service.startProgressTimer();
      _progressSub = _service.compressProgress.listen((v) {
        // -1 表示从定时器触发，使用估算进度
        if (v < 0) {
          final elapsed = DateTime.now()
              .difference(_compressStartTime)
              .inMilliseconds;
          final estimated = (elapsed / (elapsed + 3000)).clamp(0.0, 0.95);
          if (mounted) setState(() => _compressProgress = estimated);
        } else {
          if (mounted) setState(() => _compressProgress = v);
        }
      });
      final zipBytes = await _service.compressToZip(files, logDir);
      _service.stopProgressTimer();
      await _progressSub?.cancel();
      _progressSub = null;
      if (mounted) setState(() => _compressProgress = 1.0);
      await fileLogger.log(
        'exportLogs: 压缩完成，${files.length} 个文件共 ${zipBytes.length} 字节',
      );

      // 4. 保存（弹原生保存对话框）
      if (!mounted) return;
      setState(() {
        _showProgress = false;
        _statusText = '正在保存…';
      });

      final fileName = _service.generateFileName();
      final nameWithoutExt = fileName.replaceAll('.zip', '');
      final result = await FileSaver.instance.saveAs(
        name: nameWithoutExt,
        bytes: zipBytes,
        fileExtension: 'zip',
        mimeType: MimeType.zip,
      );

      if (!mounted) return;
      if (result == null) {
        // 用户取消
        await fileLogger.log('exportLogs: 用户取消保存');
        _finish('已取消');
      } else if (result.isEmpty) {
        // 保存失败（返回空串）
        await fileLogger.log('exportLogs: 保存失败，返回空路径');
        _finish('导出失败', isError: true);
      } else {
        await fileLogger.log('exportLogs: 导出成功，保存路径=$result');
        _finish('导出成功');
      }
    } catch (e) {
      await fileLogger.logError('exportLogs: 导出异常', e);
      logDebug('exportLogs: 导出失败 $e');
      _finish('导出失败：$e', isError: true);
    }
  }

  void _finish(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _done = true;
      _statusText = message;
      _showProgress = false;
      _error = isError ? message : null;
    });
    logDebug('exportLogs: $message');
    // 成功后 1.5s 自动返回，失败则等待手动返回
    if (!isError) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '导出日志',
          style: AkTheme.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AkColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: AkColors.textSecondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 状态图标
              Icon(
                _done
                    ? (_error != null
                          ? Icons.error_outline
                          : Icons.check_circle_outline)
                    : Icons.hourglass_top,
                size: 48,
                color: _done
                    ? (_error != null ? AkColors.danger : AkColors.success)
                    : AkColors.info,
              ),
              const SizedBox(height: 24),

              // 状态文字
              Text(
                _statusText,
                style: AkTheme.sans(
                  fontSize: 14,
                  color: _done
                      ? (_error != null ? AkColors.danger : AkColors.success)
                      : AkColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),

              // 进度条（仅压缩阶段）
              if (_showProgress) ...[
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AkTheme.cutSm),
                  child: LinearProgressIndicator(
                    value: _compressProgress,
                    minHeight: 6,
                    backgroundColor: AkColors.muted,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AkColors.info,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(_compressProgress * 100).toInt()}%',
                  style: AkTheme.sans(
                    fontSize: 12,
                    color: AkColors.textSecondary,
                  ),
                ),
              ],

              // 返回按钮（仅完成/失败时）
              if (_done && _error != null) ...[
                const SizedBox(height: 32),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    '返回',
                    style: AkTheme.sans(fontSize: 14, color: AkColors.info),
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
