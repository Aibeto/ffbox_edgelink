import 'package:dio/dio.dart';
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/core/network/api_client.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/domain/entities/login_result.dart';
import 'package:ffbox_edgelink/domain/entities/server_settings.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';

/// FFBox 后端 HTTP 端点。仅负责原始 JSON 请求/响应，不含业务逻辑。
class FFBoxApi {
  final ApiClient _client;
  final AppConfig _config;

  // --- 构造 ---

  FFBoxApi(this._client, this._config);

  String _url(String path) => '${_config.normalizedBaseUrl}$path';

  // --- 认证 ---

  Future<LoginResult> login(String username, String passkeySha256) async {
    final json = await _client.request<Map<String, dynamic>>(
      method: 'POST',
      path: _url('/api/v1/auth/login'),
      data: {'username': username, 'passkey': passkeySha256},
    );
    return LoginResult.fromJson(json);
  }

  // --- 任务查询 ---

  /// 获取任务 ID 列表（分页）。
  /// [offset] 起始条目（从 0 开始），[size] 每页返回数量。
  Future<List<int>> listTaskIds({
    int offset = 0,
    int size = 100,
    bool silent = false,
  }) async {
    final data = await _client.request<Map<String, dynamic>>(
      method: 'GET',
      path: _url('/api/v1/tasks'),
      query: {'offset': offset, 'size': size, 'idOnly': true},
      retryOnFailure: true,
      silent: silent,
    );
    if (!silent) {
      logDebug(
        'listTaskIds: offset=$offset, size=$size, totalCount=${data['totalCount']}',
      );
    }
    // 格式 1: {taskIds: [1, 2, 3], totalCount: N}
    final taskIds = data['taskIds'];
    if (taskIds is List) {
      return taskIds.map((e) => (e as num).toInt()).toList();
    }
    // 格式 2: {tasks: [{id:1,...}, {id:2,...}], totalCount: N}
    final tasks = data['tasks'];
    if (tasks is List) {
      return tasks
          .whereType<Map>()
          .map((t) => (t['id'] as num?)?.toInt())
          .whereType<int>()
          .toList();
    }
    logDebug('listTaskIds: 无法解析 taskIds, keys=${data.keys.toList()}');
    return [];
  }

  // --- 任务详情 ---

  Future<Task> getTask(int id, {bool silent = false}) async {
    final json = await _client.request<Map<String, dynamic>>(
      method: 'GET',
      path: _url('/api/v1/tasks/$id'),
      retryOnFailure: true,
      silent: silent,
    );
    return Task.fromJson(json);
  }

  // --- 任务创建 ---

  Future<List<int>> createTasks(
    List<String> filePaths,
    Map<String, dynamic>? outputParams,
  ) async {
    final json = await _client.request<List<dynamic>>(
      method: 'POST',
      path: _url('/api/v1/tasks'),
      data: {'filePaths': filePaths, 'outputParams': outputParams},
    );
    return json.map((e) => (e as num).toInt()).toList();
  }

  // --- 文件上传 ---

  /// 批量检查哈希是否已缓存（1=已缓存，0=未缓存）。
  Future<List<int>> uploadCheck(List<String> hashs) async {
    final json = await _client.request<List<dynamic>>(
      method: 'POST',
      path: _url('/api/v1/upload/check'),
      data: {'hashs': hashs},
    );
    return json.map((e) => (e as num).toInt()).toList();
  }

  /// 上传单个分片：multipart 字段 name=分片哈希、file=分片数据。
  /// 发送超时放宽到 10 分钟（大分片慢网）；[onProgress] 回调 (已发送, 分片总长)。
  Future<void> uploadFile(
    String hash,
    int length,
    Stream<List<int>> Function() openStream, {
    void Function(int count, int total)? onProgress,
  }) async {
    final form =
        FormData()
          ..fields.add(MapEntry('name', hash))
          ..files.add(
            MapEntry('file', MultipartFile.fromStream(openStream, length)),
          );
    await _client.request<dynamic>(
      method: 'POST',
      path: _url('/api/v1/upload/file'),
      data: form,
      options: Options(
        method: 'POST',
        sendTimeout: const Duration(minutes: 10),
      ),
      onSendProgress: onProgress,
    );
  }

  /// 合并已上传分片，将任务输入占位符替换为真实缓存文件名。
  Future<void> mergeUpload(
    int taskId, {
    required List<String> hashs,
    required String fileBaseName,
    required String inputName,
    required Map<String, int> fileTime,
  }) async {
    await _client.request<dynamic>(
      method: 'POST',
      path: _url('/api/v1/tasks/$taskId/merge-upload'),
      data: {
        'hashs': hashs,
        'fileBaseName': fileBaseName,
        'inputName': inputName,
        'fileTime': fileTime,
      },
    );
  }

  /// 设置任务上传状态（false 时 initializing→idle 并触发媒体信息扫描）。
  Future<void> setUploadStatus(int taskId, bool isUploading) async {
    await _client.request<dynamic>(
      method: 'PUT',
      path: _url('/api/v1/tasks/$taskId/upload-status'),
      data: {'isUploading': isUploading},
    );
  }

  // --- 批量操作 ---

  Future<void> _batchRequest(String path, List<int> ids) async {
    await _client.request<dynamic>(
      method: 'POST',
      path: _url(path),
      data: {'ids': ids},
    );
  }

  Future<void> deleteTasks(List<int> ids) =>
      _batchRequest('/api/v1/tasks/delete', ids);
  Future<void> startTasks(List<int> ids) =>
      _batchRequest('/api/v1/tasks/start', ids);
  Future<void> readyTasks(List<int> ids) =>
      _batchRequest('/api/v1/tasks/ready', ids);
  Future<void> pauseTasks(List<int> ids) =>
      _batchRequest('/api/v1/tasks/pause', ids);
  Future<void> resumeTasks(List<int> ids) =>
      _batchRequest('/api/v1/tasks/resume', ids);
  Future<void> resetTasks(List<int> ids) =>
      _batchRequest('/api/v1/tasks/reset', ids);

  // --- 转码配置 ---

  /// 获取服务器 ffmpeg 扫描结果（编码器/复用器/滤镜，原始 JSON）。
  ///
  /// 响应结构：`{codecs: {video: [...], audio: [...]},
  /// formats: {muxer: [...], demuxer: [...]}, filters: [...]}`；
  /// 由应用层解析器转换为编码目录（web parseFFmpegCodecsToCodecsList 语义）。
  Future<Map<String, dynamic>> getCodecs({bool silent = true}) {
    return _client.request<Map<String, dynamic>>(
      method: 'GET',
      path: _url('/api/v1/system/codecs'),
      retryOnFailure: true,
      silent: silent,
    );
  }

  // --- 服务器配置 ---

  /// 获取服务器配置（并发/FFmpeg 路径/任务保留策略等）。
  Future<ServerSettings> getServerSettings() async {
    final json = await _client.request<Map<String, dynamic>>(
      method: 'GET',
      path: _url('/api/v1/settings/server'),
    );
    return ServerSettings.fromJson(json);
  }

  /// 更新服务器配置并使其生效。
  Future<void> updateServerSettings(ServerSettings settings) async {
    await _client.request<dynamic>(
      method: 'PUT',
      path: _url('/api/v1/settings/server'),
      data: settings.toJson(),
    );
  }
}
