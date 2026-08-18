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
