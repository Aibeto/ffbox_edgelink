import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// 分片哈希器：在独立 Isolate 中顺序读取文件分段并计算 SHA1。
///
/// 主 isolate 仅做调度，不接触分片字节，避免哈希大文件时阻塞 UI。
class ChunkHasher {
  /// 对 [segments]（offset/length 列表）逐片计算 SHA1，返回与分段同序的十六进制哈希。
  Future<List<String>> hashSegments(
    String path,
    List<({int offset, int length})> segments,
  ) async {
    final hashes = <String>[];
    for (final segment in segments) {
      hashes.add(
        await Isolate.run(
          () => _sha1Range(path, segment.offset, segment.length),
        ),
      );
    }
    return hashes;
  }
}

/// Isolate 入口：同步读取文件区间并求 SHA1（闭包仅捕获基本类型）。
String _sha1Range(String path, int offset, int length) {
  final handle = File(path).openSync();
  try {
    handle.setPositionSync(offset);
    final bytes = handle.readSync(length);
    return sha1.convert(bytes).toString();
  } finally {
    handle.closeSync();
  }
}
