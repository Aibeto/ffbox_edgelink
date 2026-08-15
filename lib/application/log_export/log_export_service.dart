import 'dart:io';
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

/// 日志导出业务逻辑（纯 Dart，无框架依赖）。
class LogExportService {
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

  /// 将文件列表压缩为 zip，返回字节数组。
  ///
  /// [onProgress] 在压缩每个文件后回调，用于更新进度。
  Uint8List compressToZip(
    List<File> files,
    Directory logDir, {
    void Function(double progress)? onProgress,
  }) {
    final archive = Archive();
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      // 相对于 logs 目录的路径
      final relativePath = file.path.substring(logDir.path.length + 1);
      final bytes = file.readAsBytesSync();
      archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
      onProgress?.call((i + 1) / files.length);
    }
    final encoded = ZipEncoder().encode(archive, level: 9);
    return Uint8List.fromList(encoded);
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
