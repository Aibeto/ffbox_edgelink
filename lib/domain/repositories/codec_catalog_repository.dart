/// 编码目录仓储抽象接口。
library;

/// 提供服务器 ffmpeg 扫描的编码器/复用器原始数据。
abstract interface class CodecCatalogRepository {
  /// 获取扫描结果原始 JSON（GET /api/v1/system/codecs）。
  Future<Map<String, dynamic>> getCodecs();
}
