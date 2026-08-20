import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 上传协议常量与纯函数：占位符、缓存键、分段、文件哈希、默认输出参数。
///
/// 语义与 FFBox web 前端 transferManager2.ts / defaultParams.ts 保持一致，
/// 供上传队列与新建任务页共同使用（application 层，纯 Dart）。

// --- 占位符与缓存键 ---

/// 服务端占位符前缀（taskAddBatch 会剥离该前缀作为任务名）。
const String uploadPlaceholderPrefix = '[uploading] ';

/// 缓存文件名分隔符（U+2B1D，与服务端 mergeUploaded 一致）。
const String uploadCacheSeparator = '⬝';

/// 生成任务创建时的输入占位符路径。
String uploadPlaceholder(String fileBaseName) =>
    '$uploadPlaceholderPrefix$fileBaseName';

/// 生成文件级秒传检查键：`文件名⬝文件哈希`。
String uploadCacheKey(String fileBaseName, String fileHash) =>
    '$fileBaseName$uploadCacheSeparator$fileHash';

// --- 分段 ---

/// 小于 1GB 用 4MB（十进制）分段，否则 20MB——与 web 端一致。
int segmentSizeFor(int fileSize) =>
    fileSize < 1 * 1000 * 1000 * 1000 ? 4 * 1000 * 1000 : 20 * 1000 * 1000;

/// 计算全文件分段方案（offset + length 列表）。
List<({int offset, int length})> segmentPlan(int fileSize) {
  final segmentSize = segmentSizeFor(fileSize);
  return [
    for (var offset = 0; offset < fileSize; offset += segmentSize)
      (offset: offset, length: fileSize - offset < segmentSize
          ? fileSize - offset
          : segmentSize),
  ];
}

// --- 文件哈希 ---

/// 文件哈希 = SHA1(全部分片哈希字符串按序拼接的 UTF-8 字节)。
String fileHashOf(List<String> chunkHashes) =>
    sha1.convert(utf8.encode(chunkHashes.join())).toString();

// --- 默认输出参数 ---

/// 构建 OutputParams：三段输出配置由输出参数表单（OutputParamsForm）构建，
/// 其余字段为 FFBox defaultParams 副本。
Map<String, dynamic> buildOutputParams({
  required Map<String, dynamic> video,
  required Map<String, dynamic> audio,
  required Map<String, dynamic> mux,
}) {
  return {
    'input': {
      'files': [
        {'filePath': '[输入文件路径]', 'demuxer': '自动'},
      ],
    },
    'filter': {
      'nodes': <dynamic>[],
      'lines': <dynamic>[],
    },
    'outputs': [
      {'video': video, 'audio': audio, 'mux': mux},
    ],
    'extra': {'presetName': '默认配置'},
  };
}
