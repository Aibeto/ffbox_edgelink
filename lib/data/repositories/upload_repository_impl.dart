import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:ffbox_edgelink/domain/repositories/upload_repository.dart';

/// UploadRepository 的具体实现，纯委托转发给 [FFBoxApi]。
class UploadRepositoryImpl implements UploadRepository {
  final FFBoxApi _api;

  UploadRepositoryImpl(this._api);

  @override
  Future<List<int>> uploadCheck(List<String> hashs) => _api.uploadCheck(hashs);

  @override
  Future<void> uploadFile(
    String hash,
    int length,
    Stream<List<int>> Function() openStream, {
    void Function(int count, int total)? onProgress,
  }) => _api.uploadFile(hash, length, openStream, onProgress: onProgress);

  @override
  Future<void> mergeUpload(
    int taskId, {
    required List<String> hashs,
    required String fileBaseName,
    required String inputName,
    required Map<String, int> fileTime,
  }) => _api.mergeUpload(
    taskId,
    hashs: hashs,
    fileBaseName: fileBaseName,
    inputName: inputName,
    fileTime: fileTime,
  );

  @override
  Future<void> setUploadStatus(int taskId, bool isUploading) =>
      _api.setUploadStatus(taskId, isUploading);
}
