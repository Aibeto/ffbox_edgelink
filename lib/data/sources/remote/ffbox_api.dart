import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/core/network/api_client.dart';
import 'package:ffbox_edgelink/domain/entities/login_result.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';

/// FFBox 后端 HTTP 端点。仅负责原始 JSON 请求/响应，不含业务逻辑。
class FFBoxApi {
  final ApiClient _client;
  final AppConfig _config;

  FFBoxApi(this._client, this._config);

  String _url(String path) => '${_config.normalizedBaseUrl}$path';

  Future<LoginResult> login(String username, String passkeySha256) async {
    final json = await _client.request<Map<String, dynamic>>(
      method: 'POST',
      path: _url('/api/v1/auth/login'),
      data: {'username': username, 'passkey': passkeySha256},
    );
    return LoginResult.fromJson(json);
  }

  Future<List<int>> listTaskIds() async {
    final data = await _client.request<List<dynamic>>(
      method: 'GET',
      path: _url('/api/v1/tasks'),
      retryOnFailure: true,
    );
    return data.map((e) => (e as num).toInt()).toList();
  }

  Future<Task> getTask(int id) async {
    final json = await _client.request<Map<String, dynamic>>(
      method: 'GET',
      path: _url('/api/v1/tasks/$id'),
      retryOnFailure: true,
    );
    return Task.fromJson(json);
  }

  Future<int> createTask(String taskName, Map<String, dynamic>? outputParams) async {
    final json = await _client.request<Map<String, dynamic>>(
      method: 'POST',
      path: _url('/api/v1/tasks'),
      data: {'taskName': taskName, if (outputParams != null) 'outputParams': outputParams},
    );
    return (json['taskId'] as num).toInt();
  }

  Future<void> _request(String method, String path) async {
    await _client.request<dynamic>(method: method, path: _url(path));
  }

  Future<void> deleteTask(int id) =>
      _request('DELETE', '/api/v1/tasks/$id');
  Future<void> startTask(int id) =>
      _request('POST', '/api/v1/tasks/$id/start');
  Future<void> readyTask(int id) =>
      _request('POST', '/api/v1/tasks/$id/ready');
  Future<void> pauseTask(int id) =>
      _request('POST', '/api/v1/tasks/$id/pause');
  Future<void> resumeTask(int id) =>
      _request('POST', '/api/v1/tasks/$id/resume');
  Future<void> resetTask(int id) =>
      _request('POST', '/api/v1/tasks/$id/reset');
}
