/// 文件上传仓储抽象接口：分片缓存检查、分片上传、合并、上传状态。
///
/// domain 层接口，供上传队列（application 层）依赖；
/// 具体实现见 data 层 [UploadRepositoryImpl]，委托 FFBoxApi。
abstract interface class UploadRepository {
  /// 批量检查哈希是否已缓存（1=已缓存，0=未缓存）。
  Future<List<int>> uploadCheck(List<String> hashs);

  /// 上传单个分片（[openStream] 每次调用产生一个新的分片数据流，供重试复用）。
  Future<void> uploadFile(
    String hash,
    int length,
    Stream<List<int>> Function() openStream, {
    void Function(int count, int total)? onProgress,
  });

  /// 合并分片并将任务输入占位符替换为真实缓存文件名。
  Future<void> mergeUpload(
    int taskId, {
    required List<String> hashs,
    required String fileBaseName,
    required String inputName,
    required Map<String, int> fileTime,
  });

  /// 设置任务上传状态（false 时后端触发媒体信息扫描）。
  Future<void> setUploadStatus(int taskId, bool isUploading);
}
