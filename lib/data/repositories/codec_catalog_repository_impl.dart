/// CodecCatalogRepository 的具体实现。
///
/// 纯委托转发层：将接口调用直接转发给 [FFBoxApi]，不含额外业务逻辑。
library;

import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:ffbox_edgelink/domain/repositories/codec_catalog_repository.dart';

class CodecCatalogRepositoryImpl implements CodecCatalogRepository {
  final FFBoxApi _api;

  CodecCatalogRepositoryImpl(this._api);

  @override
  Future<Map<String, dynamic>> getCodecs() => _api.getCodecs();
}
