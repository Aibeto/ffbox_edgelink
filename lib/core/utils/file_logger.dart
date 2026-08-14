import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 文件日志工具类，用于将诊断日志写入文件。
///
/// 功能：
/// - 将日志写入应用文档目录下的 logs 文件夹
/// - 原始响应数据（可能包含敏感信息）仅写入文件，不输出到控制台
/// - 在 release 模式下也可用于记录关键错误
/// - 在测试环境中，日志会写入内存缓冲区而不是文件
class FileLogger {
  static FileLogger? _instance;
  Directory? _logDir;
  File? _logFile;
  File? _rawDataFile;
  bool _initialized = false;

  /// 测试环境下的内存缓冲区
  final List<String> _logBuffer = [];
  final List<String> _rawDataBuffer = [];

  /// 获取单例实例。
  factory FileLogger() {
    _instance ??= FileLogger._();
    return _instance!;
  }

  FileLogger._();

  /// 将 [DateTime] 格式化为紧凑 ISO 8601 字符串（无分隔符）。
  /// 例：20260815T000232.111
  String _formatTimestamp(DateTime dt) {
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '${y}${m}${d}T${h}${min}${s}.$ms';
  }

  /// 初始化日志目录和文件。
  ///
  /// 必须在应用启动时调用，通常在 main() 中。
  ///
  /// 日志存储位置：
  /// - Windows：exe 同目录下的 logs 文件夹
  /// - Android：缓存目录下的 logs 文件夹
  /// - 其他平台：应用文档目录下的 logs 文件夹
  Future<void> init() async {
    if (_initialized) return;

    try {
      Directory appDir;

      if (Platform.isWindows) {
        // Windows：使用 exe 所在目录（非工作目录）
        final exePath = File(Platform.resolvedExecutable).parent;
        appDir = exePath;
      } else if (Platform.isAndroid) {
        // Android：使用缓存目录
        appDir = await getTemporaryDirectory();
      } else {
        // 其他平台：使用应用文档目录
        appDir = await getApplicationDocumentsDirectory();
      }

      _logDir = Directory('${appDir.path}/logs');
      if (!await _logDir!.exists()) {
        await _logDir!.create(recursive: true);
      }

      final timestamp = _formatTimestamp(DateTime.now());
      _logFile = File('${_logDir!.path}/app_$timestamp.log');
      _rawDataFile = File('${_logDir!.path}/raw_data_$timestamp.log');

      _initialized = true;

      // 写入启动日志
      await log('=== FFBox EdgeLink 日志启动 ===');
      await log('平台: ${Platform.operatingSystem}');
      await log('应用目录: ${appDir.path}');
      await log('日志文件: ${_logFile!.path}');
      await log('原始数据文件: ${_rawDataFile!.path}');
    } catch (e) {
      // ignore: avoid_print
      print('[FFBox EdgeLink] 文件日志初始化失败: $e');
      // 即使初始化失败，也标记为已初始化，以便使用内存缓冲区
      _initialized = true;
    }
  }

  /// 写入普通日志（同时输出到控制台和文件）。
  Future<void> log(String message) async {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[FFBox EdgeLink] $message');
    }

    final timestamp = _formatTimestamp(DateTime.now());
    final logEntry = '[$timestamp] $message';

    // 写入内存缓冲区
    _logBuffer.add(logEntry);

    // 写入文件（如果已初始化）
    await _writeToFile(_logFile, logEntry);
  }

  /// 写入原始响应数据（仅写入文件，不输出到控制台）。
  ///
  /// 用于记录 API 返回的原始数据，避免敏感信息泄露到控制台。
  Future<void> logRawData({
    required String endpoint,
    required String method,
    required dynamic responseData,
    int? statusCode,
    Map<String, dynamic>? headers,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('=== 原始响应数据 ===');
    buffer.writeln('时间: ${_formatTimestamp(DateTime.now())}');
    buffer.writeln('端点: $endpoint');
    buffer.writeln('方法: $method');
    if (statusCode != null) {
      buffer.writeln('状态码: $statusCode');
    }
    if (headers != null) {
      buffer.writeln('响应头: $headers');
    }
    buffer.writeln('数据类型: ${responseData.runtimeType}');
    buffer.writeln('数据内容:');
    buffer.writeln(responseData.toString());
    buffer.writeln('=== 结束 ===\n');

    final content = buffer.toString();

    // 写入内存缓冲区
    _rawDataBuffer.add(content);

    // 写入文件（如果已初始化）
    await _writeToFile(_rawDataFile, content);
  }

  /// 写入错误日志（同时输出到控制台和文件）。
  Future<void> logError(
    String message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) async {
    final buffer = StringBuffer();
    buffer.writeln('=== 错误日志 ===');
    buffer.writeln('时间: ${_formatTimestamp(DateTime.now())}');
    buffer.writeln('消息: $message');
    if (error != null) {
      buffer.writeln('错误: $error');
    }
    if (stackTrace != null) {
      buffer.writeln('堆栈:\n$stackTrace');
    }
    buffer.writeln('=== 结束 ===\n');

    final content = buffer.toString();
    if (kDebugMode) {
      // ignore: avoid_print
      print('[FFBox EdgeLink] ERROR: $message');
    }

    // 写入内存缓冲区
    _logBuffer.add(content);

    // 写入文件（如果已初始化）
    await _writeToFile(_logFile, content);
  }

  /// 写入任务解析日志（仅写入文件，不输出到控制台）。
  Future<void> logTaskParsing({
    required String endpoint,
    required dynamic rawData,
    required String parseResult,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('=== 任务解析日志 ===');
    buffer.writeln('时间: ${_formatTimestamp(DateTime.now())}');
    buffer.writeln('端点: $endpoint');
    buffer.writeln('原始数据类型: ${rawData.runtimeType}');
    buffer.writeln('原始数据内容: $rawData');
    buffer.writeln('解析结果: $parseResult');
    buffer.writeln('=== 结束 ===\n');

    final content = buffer.toString();

    // 写入内存缓冲区
    _rawDataBuffer.add(content);

    // 写入文件（如果已初始化）
    await _writeToFile(_rawDataFile, content);
  }

  /// 写入文件（追加模式）。
  Future<void> _writeToFile(File? file, String content) async {
    if (file == null) return;

    try {
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      await file.writeAsString(
        '$content\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[FFBox EdgeLink] 写入日志文件失败: $e');
    }
  }

  /// 获取最近的日志文件路径（用于错误报告）。
  Future<String?> getLatestLogPath() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        return _logFile!.path;
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  /// 获取最近的原始数据文件路径（用于错误报告）。
  Future<String?> getLatestRawDataPath() async {
    try {
      if (_rawDataFile != null && await _rawDataFile!.exists()) {
        return _rawDataFile!.path;
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  /// 清理旧日志文件，仅保留最新 [keep] 套（每套 = 同时间戳的 app 日志与原始数据日志）。
  Future<void> cleanOldLogs({int keep = 5}) async {
    try {
      if (_logDir == null || !await _logDir!.exists()) return;

      final logFiles = (await _logDir!.list().toList())
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.log'))
          .toList();
      if (logFiles.length <= keep) return;

      // 按文件名时间戳分组：app_xxx.log 与 raw_data_xxx.log 共享同一时间戳
      final tsPattern = RegExp(r'^(?:app|raw_data)_(.*?)\.log$');
      final groups = <String, List<File>>{};
      for (final f in logFiles) {
        final name = f.uri.pathSegments.last;
        final m = tsPattern.firstMatch(name);
        if (m == null) continue;
        groups.putIfAbsent(m.group(1)!, () => []).add(f);
      }
      if (groups.length <= keep) return;

      // 字典序即时间序，删除最旧的超量组
      final timestamps = groups.keys.toList()..sort();
      final toDelete = timestamps.take(timestamps.length - keep);
      for (final ts in toDelete) {
        for (final f in groups[ts]!) {
          await f.delete();
        }
      }
    } catch (e) {
      // ignore
    }
  }

  /// 获取内存缓冲区中的日志内容（用于测试）。
  List<String> getLogBuffer() => List.unmodifiable(_logBuffer);

  /// 获取内存缓冲区中的原始数据内容（用于测试）。
  List<String> getRawDataBuffer() => List.unmodifiable(_rawDataBuffer);

  /// 清空内存缓冲区（用于测试）。
  void clearBuffers() {
    _logBuffer.clear();
    _rawDataBuffer.clear();
  }
}

/// 全局文件日志实例。
final fileLogger = FileLogger();
