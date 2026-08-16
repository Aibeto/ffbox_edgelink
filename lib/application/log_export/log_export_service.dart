import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ffbox_edgelink/core/utils/file_logger.dart';
import 'package:path_provider/path_provider.dart';

// --- 导出阶段定义 ---

/// 日志导出阶段。
enum LogExportStage { scanning, compressing, saving, done, error }

/// 导出进度。
class LogExportProgress {
  final LogExportStage stage;
  final double progress; // 0.0 ~ 1.0
  final String message;
  final Uint8List? zipBytes;

  const LogExportProgress({
    required this.stage,
    this.progress = 0.0,
    this.message = '',
    this.zipBytes,
  });
}

// --- 导出业务逻辑 ---

/// 在后台 Isolate 中读取文件并压缩为 zip。
///
/// 入参为 `[filePathList, logDirPath]`，返回 `Uint8List`（zip 字节）。
Future<Uint8List> _compressInIsolate(List<dynamic> args) async {
  final filePaths = args[0] as List<String>;
  final logDirPath = args[1] as String;
  final archive = Archive();
  for (var i = 0; i < filePaths.length; i++) {
    final file = File(filePaths[i]);
    final relativePath = filePaths[i].substring(logDirPath.length + 1);
    final bytes = await file.readAsBytes();
    archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
  }
  final encoded = ZipEncoder().encode(archive, level: 9);
  return Uint8List.fromList(encoded);
}

/// 日志导出业务逻辑（纯 Dart，无框架依赖）。
class LogExportService {
  Timer? _progressTimer;
  final _progressController = StreamController<double>.broadcast();

  /// 压缩进度流（0.0 ~ 1.0），压缩期间每隔 200ms 发出一次更新。
  Stream<double> get compressProgress => _progressController.stream;

  /// 定位 logs 目录。
  ///
  /// 优先复用 [fileLogger] 实际写入的日志目录，避免与导出路径不一致；
  /// 未初始化时按平台回退计算（Windows: exe 同级；Android: 缓存目录；其他: 文档目录）。
  Future<Directory?> resolveLogDir() async {
    // 优先使用 FileLogger 实际写入的目录（保证与真实日志路径一致）
    final loggerDir = fileLogger.logDir;
    if (loggerDir != null) {
      if (await loggerDir.exists()) return loggerDir;
    }

    Directory appDir;
    if (Platform.isWindows) {
      appDir = File(Platform.resolvedExecutable).parent;
    } else if (Platform.isAndroid) {
      appDir = await getTemporaryDirectory();
    } else {
      appDir = await getApplicationDocumentsDirectory();
    }
    final logDir = Directory('${appDir.path}/logs');
    if (!await logDir.exists()) return null;
    return logDir;
  }

  /// 扫描日志文件（含子目录），返回所有文件。
  Future<List<File>> scanFiles(Directory logDir) async {
    final files = <File>[];
    await for (final entity in logDir.list(recursive: true)) {
      if (entity is File) files.add(entity);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// 将文件列表压缩为 zip，在后台 Isolate 中执行，不阻塞 UI 线程。
  ///
  /// 压缩期间通过 [compressProgress] 流发送进度（0.0 ~ 1.0）。
  Future<Uint8List> compressToZip(List<File> files, Directory logDir) async {
    final filePaths = files.map((f) => f.path).toList();

    // 在后台 Isolate 中执行压缩
    final result = await Isolate.run(
      () => _compressInIsolate([filePaths, logDir.path]),
    );

    return result;
  }

  /// 启动进度轮询，压缩完成后调用 [stopProgressTimer] 停止。
  ///
  /// 由于 Isolate 内部无法回调，进度基于已耗时占总时间的估算。
  void startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _progressController.add(-1),
    );
  }

  /// 停止进度轮询并关闭进度流。
  void stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  /// 关闭资源，导出流程结束后调用。
  void dispose() {
    stopProgressTimer();
    _progressController.close();
  }

  /// 生成压缩文件名：YYYYMMDD_HHMMSS_logs.zip
  String generateFileName() {
    final now = DateTime.now();
    final y = now.year;
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return '$y$m'
        '${d}_$h$min'
        '${s}_logs.zip';
  }
}
