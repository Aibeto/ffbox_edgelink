/// 本地输出与直连路径决策服务（application 层）。
///
/// 职责：
/// 1. 判断当前连接是否为本机回环（内置服务 / 同机桌面 FFBox），
///    据此决定任务创建模式与输出文件的可访问性；
/// 2. 管理内置服务的输出缓存目录 `filesDir/cache/FFBoxOutput`
///    （与宿主 main.js 的 TMPDIR 重定向一致，Node 侧同名可见），
///    提供默认输出模板、容量统计与清理；
/// 3. 为任务详情页解析输出文件的可导出路径（绝对路径直取，
///    上传托管任务的裸文件名回退到 FFBoxDownloadCache）。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

// --- 直连路径决策 ---

/// 本地输出与直连路径决策服务。
class LocalOutputService {
  /// 内置服务输出目录名（位于 filesDir/cache 下，Node 侧 TMPDIR 同源）。
  static const String outputDirName = 'FFBoxOutput';

  /// 判断地址是否为本机回环（127.0.0.1 / localhost / [::1] / 0.0.0.0）。
  static bool isLoopbackUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '0.0.0.0' ||
        host == '[::1]' ||
        host == '::1';
  }

  /// 是否应以「直接路径模式」创建任务。
  ///
  /// 语义对齐 FFBox web 前端（appStore / AddTasks）：会话拥有 FileSystem
  /// 权限时服务端按原路径创建本地任务（不走上传托管）；此时只有当文件
  /// 与服务器同机（本机回环连接）时，客户端真实路径才是合法的输入路径。
  static bool useDirectPaths({
    required String baseUrl,
    required bool hasFileSystemPermission,
  }) =>
      hasFileSystemPermission && isLoopbackUrl(baseUrl);

  // --- 输出缓存目录 ---

  /// 输出缓存目录：`filesDir/cache/FFBoxOutput`（不存在则创建）。
  Future<Directory> outputDir() async {
    final filesDir = await getApplicationSupportDirectory();
    final dir = Directory('${filesDir.path}/cache/$outputDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 本机模式默认输出文件名模板（绝对路径写入应用缓存目录）。
  Future<String> localOutputTemplate() async =>
      '${(await outputDir()).path}/[filename]_converted.[fileext]';

  /// 输出缓存占用字节数（目录不存在视为 0）。
  Future<int> outputCacheSize() async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/cache/$outputDirName',
    );
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  /// 清空输出缓存目录（仅删除文件，保留目录本身）。
  Future<void> clearOutputCache() async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/cache/$outputDirName',
    );
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }

  // --- 输出文件解析 ---

  /// 解析输出文件的可访问本地路径（仅本机回环连接有意义）。
  ///
  /// - 绝对路径：直接返回（内置服务直接路径模式任务的输出）；
  /// - 裸文件名：上传托管任务的输出位于服务端 FFBoxDownloadCache，
  ///   Android 上即 `filesDir/cache/FFBoxDownloadCache/<文件名>`。
  /// 返回 null 表示无法定位或文件不存在。
  Future<File?> resolveOutputFile(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return null;
    File? file;
    if (normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(normalized)) {
      file = File(normalized);
    } else if (Platform.isAndroid) {
      final filesDir = await getApplicationSupportDirectory();
      file = File('${filesDir.path}/cache/FFBoxDownloadCache/$normalized');
    }
    if (file == null) return null;
    return await file.exists() ? file : null;
  }
}
