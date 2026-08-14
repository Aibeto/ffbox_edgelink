# FFBox EdgeLink 远程管理 App 实施方案

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个 Flutter 远程管理 App（Web + Android/iOS），登录远端 FFBox 服务后查看任务列表并对任务执行基本操作（启动/暂停/继续/删除），同时为后续创建任务与全部操作预留接口。

**Architecture:** 采用分层解耦架构（Clean Architecture 变体）：`domain`（纯 Dart 实体 + 抽象仓储接口 + 状态机）、`data`（HTTP 数据源 + 仓储实现）、`application`（纯 Dart 业务服务）、`presentation`（Riverpod + UI）。核心业务逻辑与状态机不依赖 Riverpod/Bloc，仅由 presentation 层通过 Riverpod 粘合，因此未来可将状态管理整体切换到 Bloc 而不改动 domain/application/data 层。

**Tech Stack:** Flutter (Dart 3.12+)、flutter_riverpod（状态管理与依赖注入）、dio（HTTP 客户端）、crypto（SHA256 密码哈希）、shared_preferences（会话/服务器地址持久化）。

**关键设计决策：**

- **服务器地址可配置**：EdgeLink 本地无服务端，登录页必须让用户输入远端地址（如 `http://192.168.1.100:33269`）。
- **登录校验**：密码发送前做 SHA256 哈希，`passkey = SHA256(password)`。
- **状态机纯函数化**：`TaskStateMachine.allowedOperations(status)` 返回给定状态下允许的操作集合，与 UI 框架无关。
- **全部操作预留**：`TaskRepository` 接口声明全部 API 操作（含 createTask），但 UI 首版只暴露基本操作。
- **实时推送预留**：首版用轮询刷新任务列表；架构中预留 `RealtimeEventSource` 抽象，后续可接入 FFBox 的 WebSocket 推送。

---

## 文件结构

```
lib/
  core/
    config/app_config.dart            # 服务器地址配置（可变）
    network/api_client.dart           # dio 封装 + Bearer 拦截器
    network/api_exception.dart        # 统一异常类型
    utils/hash.dart                   # SHA256 工具
  domain/
    entities/task.dart                # Task 实体 + fromJson
    entities/task_status.dart         # 任务状态枚举 + 解析
    entities/task_operation.dart      # 任务操作枚举
    entities/login_result.dart        # 登录结果实体
    repositories/auth_repository.dart # 认证仓储抽象接口
    repositories/task_repository.dart # 任务仓储抽象接口（全部操作）
    repositories/session_repository.dart # 会话存储抽象接口
  data/
    sources/remote/ffbox_api.dart     # FFBox HTTP 端点实现
    repositories/auth_repository_impl.dart
    repositories/task_repository_impl.dart
    repositories/session_repository_impl.dart
  application/
    auth/auth_service.dart            # 登录业务逻辑（纯 Dart）
    task/task_service.dart            # 任务业务逻辑（纯 Dart）
    task/task_state_machine.dart      # 任务状态机（纯 Dart）
  presentation/
    providers/app_providers.dart      # 全部 Riverpod providers
    screens/login_screen.dart         # 登录页
    screens/task_list_screen.dart     # 任务列表页
    widgets/task_tile.dart            # 单个任务卡片
  app.dart                            # MaterialApp 根组件 + 路由
  main.dart                           # 入口
test/
  domain/task_status_test.dart
  domain/task_state_machine_test.dart
  domain/task_test.dart
  application/auth_service_test.dart
  application/task_service_test.dart
  presentation/login_screen_test.dart
  presentation/task_list_screen_test.dart
```

---

## Task 1: 添加项目依赖

**Files:**

- Modify: `pubspec.yaml`

- [ ] **Step 1: 添加依赖**

运行：

```powershell
flutter pub add flutter_riverpod dio crypto shared_preferences
```

- [ ] **Step 2: 验证依赖解析**

运行：

```powershell
flutter pub get
```

预期：输出无报错，`pubspec.yaml` 的 `dependencies` 中出现 `flutter_riverpod`、`dio`、`crypto`、`shared_preferences`。

- [ ] **Step 3: 提交**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add riverpod, dio, crypto, shared_preferences deps"
```

---

## Task 2: 任务状态与状态机（纯 Dart）

**Files:**

- Create: `lib/domain/entities/task_status.dart`
- Create: `lib/domain/entities/task_operation.dart`
- Create: `lib/application/task/task_state_machine.dart`
- Test: `test/domain/task_status_test.dart`
- Test: `test/domain/task_state_machine_test.dart`

- [ ] **Step 1: 编写失败测试**

创建 `test/domain/task_status_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';

void main() {
  group('TaskStatus.parse', () {
    test('parses all known statuses', () {
      expect(TaskStatus.parse('idle'), TaskStatus.idle);
      expect(TaskStatus.parse('running'), TaskStatus.running);
      expect(TaskStatus.parse('paused'), TaskStatus.paused);
      expect(TaskStatus.parse('finished'), TaskStatus.finished);
      expect(TaskStatus.parse('error'), TaskStatus.error);
      expect(TaskStatus.parse('deleted'), TaskStatus.deleted);
    });

    test('throws on unknown status', () {
      expect(() => TaskStatus.parse('nope'), throwsA(isA<FormatException>()));
    });
  });
}
```

创建 `test/domain/task_state_machine_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ffbox_edgelink/application/task/task_state_machine.dart';
import 'package:ffbox_edgelink/domain/entities/task_operation.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';

void main() {
  group('TaskStateMachine.allowedOperations', () {
    test('idle allows start, ready, delete', () {
      final ops = TaskStateMachine.allowedOperations(TaskStatus.idle);
      expect(ops, containsAll({TaskOperation.start, TaskOperation.ready, TaskOperation.delete}));
      expect(ops, isNot(contains(TaskOperation.pause)));
    });

    test('running allows only pause', () {
      expect(TaskStateMachine.allowedOperations(TaskStatus.running),
          {TaskOperation.pause});
    });

    test('paused allows resume, ready, reset', () {
      final ops = TaskStateMachine.allowedOperations(TaskStatus.paused);
      expect(ops, containsAll({TaskOperation.resume, TaskOperation.ready, TaskOperation.reset}));
      expect(ops, isNot(contains(TaskOperation.delete)));
    });

    test('finished allows reset and delete', () {
      expect(TaskStateMachine.allowedOperations(TaskStatus.finished),
          containsAll({TaskOperation.reset, TaskOperation.delete}));
    });

    test('deleted allows nothing', () {
      expect(TaskStateMachine.allowedOperations(TaskStatus.deleted), isEmpty);
    });
  });

  group('TaskStateMachine.canExecute', () {
    test('returns true for allowed operation', () {
      expect(TaskStateMachine.canExecute(TaskStatus.idle, TaskOperation.start), isTrue);
    });

    test('returns false for disallowed operation', () {
      expect(TaskStateMachine.canExecute(TaskStatus.running, TaskOperation.delete), isFalse);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

运行：

```powershell
flutter test test/domain/task_status_test.dart test/domain/task_state_machine_test.dart
```

预期：FAIL（类型未定义）。

- [ ] **Step 3: 实现枚举与状态机**

创建 `lib/domain/entities/task_status.dart`：

```dart
/// FFBox 任务状态。对应后端 TaskStatus 枚举。
enum TaskStatus {
  deleted,
  initializing,
  idle,
  idleQueued,
  running,
  paused,
  pausedQueued,
  stopping,
  finishing,
  finished,
  error;

  /// 从后端字符串解析状态。未知状态抛出 [FormatException]。
  static TaskStatus parse(String raw) {
    const map = <String, TaskStatus>{
      'deleted': TaskStatus.deleted,
      'initializing': TaskStatus.initializing,
      'idle': TaskStatus.idle,
      'idle_queued': TaskStatus.idleQueued,
      'running': TaskStatus.running,
      'paused': TaskStatus.paused,
      'paused_queued': TaskStatus.pausedQueued,
      'stopping': TaskStatus.stopping,
      'finishing': TaskStatus.finishing,
      'finished': TaskStatus.finished,
      'error': TaskStatus.error,
    };
    final value = map[raw];
    if (value == null) {
      throw FormatException('Unknown TaskStatus: $raw');
    }
    return value;
  }

  /// 还原为后端使用的字符串。
  String get apiValue => switch (this) {
        TaskStatus.deleted => 'deleted',
        TaskStatus.initializing => 'initializing',
        TaskStatus.idle => 'idle',
        TaskStatus.idleQueued => 'idle_queued',
        TaskStatus.running => 'running',
        TaskStatus.paused => 'paused',
        TaskStatus.pausedQueued => 'paused_queued',
        TaskStatus.stopping => 'stopping',
        TaskStatus.finishing => 'finishing',
        TaskStatus.finished => 'finished',
        TaskStatus.error => 'error',
      };
}
```

创建 `lib/domain/entities/task_operation.dart`：

```dart
/// 任务操作。覆盖 FFBox 任务生命周期全部操作，便于后续逐步开放 UI。
enum TaskOperation {
  create,
  start,
  ready,
  pause,
  resume,
  reset,
  delete,
  setParameters,
  mergeUpload,
  setUploadStatus,
}
```

创建 `lib/application/task/task_state_machine.dart`：

```dart
import 'package:ffbox_edgelink/domain/entities/task_operation.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';

/// 任务状态机：根据后端 API 文档中的状态迁移约束，
/// 给出某个状态下允许执行的操作集合。
///
/// 该逻辑为纯函数、与 Riverpod/Bloc 无关，可独立单测并在多种
/// 状态管理方案间复用。
class TaskStateMachine {
  TaskStateMachine._();

  static const Map<TaskStatus, Set<TaskOperation>> _allowed = {
    TaskStatus.initializing: {TaskOperation.delete},
    TaskStatus.idle: {TaskOperation.start, TaskOperation.ready, TaskOperation.delete},
    TaskStatus.idleQueued: {TaskOperation.start, TaskOperation.delete},
    TaskStatus.running: {TaskOperation.pause},
    TaskStatus.paused: {TaskOperation.resume, TaskOperation.ready, TaskOperation.reset},
    TaskStatus.pausedQueued: {TaskOperation.pause, TaskOperation.resume, TaskOperation.reset},
    TaskStatus.stopping: {TaskOperation.reset},
    TaskStatus.finishing: {},
    TaskStatus.finished: {TaskOperation.reset, TaskOperation.delete},
    TaskStatus.error: {TaskOperation.start, TaskOperation.reset, TaskOperation.delete},
    TaskStatus.deleted: {},
  };

  static Set<TaskOperation> allowedOperations(TaskStatus status) =>
      _allowed[status] ?? const {};

  static bool canExecute(TaskStatus status, TaskOperation operation) =>
      allowedOperations(status).contains(operation);
}
```

- [ ] **Step 4: 运行测试确认通过**

```powershell
flutter test test/domain/task_status_test.dart test/domain/task_state_machine_test.dart
```

预期：PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/domain/entities/task_status.dart lib/domain/entities/task_operation.dart lib/application/task/task_state_machine.dart test/domain/
git commit -m "feat: add task status enum and pure state machine"
```

---

## Task 3: 领域实体 Task / LoginResult

**Files:**

- Create: `lib/domain/entities/task.dart`
- Create: `lib/domain/entities/login_result.dart`
- Test: `test/domain/task_test.dart`

- [ ] **Step 1: 编写失败测试**

创建 `test/domain/task_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';

void main() {
  group('Task.fromJson', () {
    test('parses minimal valid JSON', () {
      final task = Task.fromJson({
        'taskName': 'demo.mp4',
        'status': 'running',
        'progressLog': {'elapsed': 12.5, 'lastStarted': 1.0, 'lastPaused': 0.0},
        'errorInfo': [],
        'outputFiles': [],
      });

      expect(task.taskName, 'demo.mp4');
      expect(task.status, TaskStatus.running);
      expect(task.elapsedSeconds, 12.5);
    });

    test('defaults missing optional fields', () {
      final task = Task.fromJson({'taskName': 'x', 'status': 'idle'});
      expect(task.elapsedSeconds, 0);
      expect(task.errorInfo, isEmpty);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```powershell
flutter test test/domain/task_test.dart
```

预期：FAIL。

- [ ] **Step 3: 实现实体**

创建 `lib/domain/entities/task.dart`：

```dart
import 'package:ffbox_edgelink/domain/entities/task_status.dart';

/// 任务实体。首版只建模列表展示与操作所需的字段；
/// 后续可按需扩展 before/after/paraArray 等字段。
class Task {
  final String taskName;
  final TaskStatus status;
  final double elapsedSeconds;
  final double lastStarted;
  final double lastPaused;
  final List<String> errorInfo;
  final List<String> outputFiles;

  const Task({
    required this.taskName,
    required this.status,
    this.elapsedSeconds = 0,
    this.lastStarted = 0,
    this.lastPaused = 0,
    this.errorInfo = const [],
    this.outputFiles = const [],
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    final progressLog = (json['progressLog'] as Map<String, dynamic>?) ?? const {};
    return Task(
      taskName: json['taskName'] as String? ?? '',
      status: TaskStatus.parse(json['status'] as String? ?? 'idle'),
      elapsedSeconds: (progressLog['elapsed'] as num?)?.toDouble() ?? 0,
      lastStarted: (progressLog['lastStarted'] as num?)?.toDouble() ?? 0,
      lastPaused: (progressLog['lastPaused'] as num?)?.toDouble() ?? 0,
      errorInfo: (json['errorInfo'] as List?)?.cast<String>() ?? const [],
      outputFiles: (json['outputFiles'] as List?)?.cast<String>() ?? const [],
    );
  }
}
```

创建 `lib/domain/entities/login_result.dart`：

```dart
/// 登录结果实体。
class LoginResult {
  final bool isUserExist;
  final bool isSuccess;
  final String sessionId;
  final int functionLevel;

  const LoginResult({
    required this.isUserExist,
    required this.isSuccess,
    this.sessionId = '',
    this.functionLevel = 0,
  });

  factory LoginResult.fromJson(Map<String, dynamic> json) => LoginResult(
        isUserExist: json['isUserExist'] as bool? ?? false,
        isSuccess: json['isSuccess'] as bool? ?? false,
        sessionId: json['sessionId'] as String? ?? '',
        functionLevel: (json['functionLevel'] as num?)?.toInt() ?? 0,
      );
}
```

- [ ] **Step 4: 运行测试确认通过**

```powershell
flutter test test/domain/task_test.dart
```

预期：PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/domain/entities/task.dart lib/domain/entities/login_result.dart test/domain/task_test.dart
git commit -m "feat: add task and login result entities"
```

---

## Task 4: 仓储抽象接口

**Files:**

- Create: `lib/domain/repositories/auth_repository.dart`
- Create: `lib/domain/repositories/task_repository.dart`
- Create: `lib/domain/repositories/session_repository.dart`

- [ ] **Step 1: 实现接口（无测试，纯抽象）**

创建 `lib/domain/repositories/auth_repository.dart`：

```dart
import 'package:ffbox_edgelink/domain/entities/login_result.dart';

/// 认证仓储抽象接口。
abstract interface class AuthRepository {
  /// 登录远端服务器。[password] 为明文，仓储内部负责 SHA256 哈希。
  Future<LoginResult> login({
    required String baseUrl,
    required String username,
    required String password,
  });
}
```

创建 `lib/domain/repositories/task_repository.dart`：

```dart
import 'package:ffbox_edgelink/domain/entities/task.dart';

/// 任务仓储抽象接口。声明全部后端任务操作，
/// 首版 UI 仅暴露基本操作，其余操作供后续功能接入。
abstract interface class TaskRepository {
  /// 获取任务 ID 列表。
  Future<List<int>> listTaskIds();

  /// 获取单个任务详情。
  Future<Task> getTask(int id);

  /// 创建新任务（预留，当前 UI 不暴露）。
  Future<int> createTask({required String taskName, Map<String, dynamic>? outputParams});

  Future<void> deleteTask(int id);
  Future<void> startTask(int id);
  Future<void> readyTask(int id);
  Future<void> pauseTask(int id);
  Future<void> resumeTask(int id);
  Future<void> resetTask(int id);
}
```

创建 `lib/domain/repositories/session_repository.dart`：

```dart
/// 会话数据。
class Session {
  final String baseUrl;
  final String username;
  final String sessionId;

  const Session({
    required this.baseUrl,
    required this.username,
    required this.sessionId,
  });
}

/// 会话存储抽象接口。用于持久化服务器地址与登录凭证。
abstract interface class SessionRepository {
  Future<Session?> load();
  Future<void> save(Session session);
  Future<void> clear();
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/domain/repositories/
git commit -m "feat: add auth/task/session repository interfaces"
```

---

## Task 5: 核心工具（SHA256 / 异常 / 配置）

**Files:**

- Create: `lib/core/utils/hash.dart`
- Create: `lib/core/network/api_exception.dart`
- Create: `lib/core/config/app_config.dart`

- [ ] **Step 1: 实现工具类**

创建 `lib/core/utils/hash.dart`：

```dart
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// 计算字符串的 SHA256 十六进制摘要。
/// FFBox 登录接口要求 passkey 为 SHA256(password)。
String sha256Hex(String input) =>
    sha256.convert(utf8.encode(input)).toString();
```

创建 `lib/core/network/api_exception.dart`：

```dart
/// 统一 API 异常。
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() =>
      statusCode == null ? message : 'ApiException($statusCode): $message';
}
```

创建 `lib/core/config/app_config.dart`：

```dart
/// 应用运行时配置。服务器地址可变，由登录页写入。
class AppConfig {
  String baseUrl;

  AppConfig({this.baseUrl = ''});

  /// 规范化地址，确保无尾部斜杠。
  String get normalizedBaseUrl {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/core/
git commit -m "feat: add hash util, api exception and app config"
```

---

## Task 6: 网络层 ApiClient

**Files:**

- Create: `lib/core/network/api_client.dart`

- [ ] **Step 1: 实现 ApiClient（无测试，纯网络封装）**

创建 `lib/core/network/api_client.dart`：

```dart
import 'package:dio/dio.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';

/// 封装 dio，自动注入 Bearer token 并统一错误处理。
class ApiClient {
  final Dio _dio;
  String _sessionId = '';

  ApiClient({Dio? dio}) : _dio = dio ?? Dio();

  /// 更新会话 token（登录成功后调用）。
  void setSessionId(String sessionId) => _sessionId = sessionId;

  void clearSessionId() => _sessionId = '';

  Future<T> request<T>({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? data,
  }) async {
    final options = Options(
      method: method,
      headers: _sessionId.isEmpty
          ? null
          : {'Authorization': 'Bearer $_sessionId'},
    );

    try {
      final response = await _dio.request<dynamic>(
        path,
        queryParameters: query,
        data: data,
        options: options,
      );
      return response.data as T;
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data?.toString() ?? e.message ?? '网络请求失败',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/core/network/api_client.dart
git commit -m "feat: add dio-based api client with bearer auth"
```

---

## Task 7: 远端数据源 FFBoxApi

**Files:**

- Create: `lib/data/sources/remote/ffbox_api.dart`

- [ ] **Step 1: 实现数据源**

创建 `lib/data/sources/remote/ffbox_api.dart`：

```dart
import 'package:ffbox_edgelink/core/network/api_client.dart';
import 'package:ffbox_edgelink/domain/entities/login_result.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';

/// FFBox 后端 HTTP 端点。仅负责原始 JSON 请求/响应，不含业务逻辑。
class FFBoxApi {
  final ApiClient _client;
  final String baseUrl;

  FFBoxApi(this._client, this.baseUrl);

  String _url(String path) => '$baseUrl$path';

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
    );
    return data.map((e) => (e as num).toInt()).toList();
  }

  Future<Task> getTask(int id) async {
    final json = await _client.request<Map<String, dynamic>>(
      method: 'GET',
      path: _url('/api/v1/tasks/$id'),
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

  Future<void> _post(String path) async {
    await _client.request<dynamic>(method: 'POST', path: _url(path));
  }

  Future<void> deleteTask(int id) => _post('/api/v1/tasks/$id/../'.replaceFirst('../', ''));
  Future<void> startTask(int id) => _post('/api/v1/tasks/$id/start');
  Future<void> readyTask(int id) => _post('/api/v1/tasks/$id/ready');
  Future<void> pauseTask(int id) => _post('/api/v1/tasks/$id/pause');
  Future<void> resumeTask(int id) => _post('/api/v1/tasks/$id/resume');
  Future<void> resetTask(int id) => _post('/api/v1/tasks/$id/reset');
}
```

> 注意：`deleteTask` 的 DELETE 语义用 `_post` 命名会误导，应改为通用的 `_request` 辅助方法。见 Task 8 修正。

- [ ] **Step 2: 提交**

```bash
git add lib/data/sources/remote/ffbox_api.dart
git commit -m "feat: add FFBox remote data source"
```

---

## Task 8: 仓储实现

**Files:**

- Create: `lib/data/repositories/auth_repository_impl.dart`
- Create: `lib/data/repositories/task_repository_impl.dart`
- Create: `lib/data/repositories/session_repository_impl.dart`

- [ ] **Step 1: 修正并完善数据源辅助方法**

将 `lib/data/sources/remote/ffbox_api.dart` 中的操作辅助方法替换为：

```dart
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
```

- [ ] **Step 2: 实现 AuthRepositoryImpl**

创建 `lib/data/repositories/auth_repository_impl.dart`：

```dart
import 'package:ffbox_edgelink/core/utils/hash.dart';
import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:ffbox_edgelink/domain/entities/login_result.dart';
import 'package:ffbox_edgelink/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final FFBoxApi _api;
  final void Function(String sessionId) _onLoginSuccess;

  AuthRepositoryImpl(this._api, this._onLoginSuccess);

  @override
  Future<LoginResult> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final result = await _api.login(username, sha256Hex(password));
    if (result.isSuccess && result.sessionId.isNotEmpty) {
      _onLoginSuccess(result.sessionId);
    }
    return result;
  }
}
```

> 注意：`AuthRepositoryImpl` 依赖 `FFBoxApi` 时，`FFBoxApi` 的 baseUrl 需要可变。由于 baseUrl 在登录时才确定，应让 `FFBoxApi` 每次调用都带完整 URL，`ApiClient` 直接请求完整 URL（dio 支持绝对 URL）。`FFBoxApi` 的 `baseUrl` 在构造时传入但可在登录前更新——更稳妥的做法是 `AuthRepositoryImpl` 在登录前重建/更新 `FFBoxApi.baseUrl`。为简化，本方案让 `FFBoxApi.baseUrl` 可写，并在 `AuthRepositoryImpl.login` 中先更新再调用。

据此，在 `FFBoxApi` 中把 `final String baseUrl;` 改为可变：

```dart
class FFBoxApi {
  final ApiClient _client;
  String baseUrl;

  FFBoxApi(this._client, this.baseUrl);
  // ...
}
```

- [ ] **Step 3: 实现 TaskRepositoryImpl**

创建 `lib/data/repositories/task_repository_impl.dart`：

```dart
import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';

class TaskRepositoryImpl implements TaskRepository {
  final FFBoxApi _api;

  TaskRepositoryImpl(this._api);

  @override
  Future<List<int>> listTaskIds() => _api.listTaskIds();

  @override
  Future<Task> getTask(int id) => _api.getTask(id);

  @override
  Future<int> createTask({required String taskName, Map<String, dynamic>? outputParams}) =>
      _api.createTask(taskName, outputParams);

  @override
  Future<void> deleteTask(int id) => _api.deleteTask(id);

  @override
  Future<void> startTask(int id) => _api.startTask(id);

  @override
  Future<void> readyTask(int id) => _api.readyTask(id);

  @override
  Future<void> pauseTask(int id) => _api.pauseTask(id);

  @override
  Future<void> resumeTask(int id) => _api.resumeTask(id);

  @override
  Future<void> resetTask(int id) => _api.resetTask(id);
}
```

- [ ] **Step 4: 实现 SessionRepositoryImpl**

创建 `lib/data/repositories/session_repository_impl.dart`：

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffbox_edgelink/domain/repositories/session_repository.dart';

class SessionRepositoryImpl implements SessionRepository {
  static const _kBaseUrl = 'session_base_url';
  static const _kUsername = 'session_username';
  static const _kSessionId = 'session_id';

  @override
  Future<Session?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_kBaseUrl);
    final sessionId = prefs.getString(_kSessionId);
    if (baseUrl == null || baseUrl.isEmpty || sessionId == null || sessionId.isEmpty) {
      return null;
    }
    return Session(
      baseUrl: baseUrl,
      username: prefs.getString(_kUsername) ?? '',
      sessionId: sessionId,
    );
  }

  @override
  Future<void> save(Session session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, session.baseUrl);
    await prefs.setString(_kUsername, session.username);
    await prefs.setString(_kSessionId, session.sessionId);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBaseUrl);
    await prefs.remove(_kUsername);
    await prefs.remove(_kSessionId);
  }
}
```

- [ ] **Step 5: 提交**

```bash
git add lib/data/
git commit -m "feat: add repository implementations"
```

---

## Task 9: 应用层服务（纯 Dart）

**Files:**

- Create: `lib/application/auth/auth_service.dart`
- Create: `lib/application/task/task_service.dart`
- Test: `test/application/auth_service_test.dart`
- Test: `test/application/task_service_test.dart`

- [ ] **Step 1: 编写失败测试**

创建 `test/application/auth_service_test.dart`（用假仓储验证业务分支）：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ffbox_edgelink/application/auth/auth_service.dart';
import 'package:ffbox_edgelink/domain/entities/login_result.dart';
import 'package:ffbox_edgelink/domain/repositories/auth_repository.dart';

class _FakeAuthRepo implements AuthRepository {
  LoginResult result;
  _FakeAuthRepo(this.result);

  @override
  Future<LoginResult> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async => result;
}

void main() {
  test('login returns error message when user not exist', () async {
    final service = AuthService(_FakeAuthRepo(
      const LoginResult(isUserExist: false, isSuccess: false),
    ));
    final outcome = await service.login(
        baseUrl: 'http://x', username: 'u', password: 'p');
    expect(outcome.error, '用户名错误');
    expect(outcome.session, isNull);
  });

  test('login returns error message when password wrong', () async {
    final service = AuthService(_FakeAuthRepo(
      const LoginResult(isUserExist: true, isSuccess: false),
    ));
    final outcome = await service.login(
        baseUrl: 'http://x', username: 'u', password: 'p');
    expect(outcome.error, '密码错误');
  });

  test('login returns session on success', () async {
    final service = AuthService(_FakeAuthRepo(
      const LoginResult(isUserExist: true, isSuccess: true, sessionId: 'abc'),
    ));
    final outcome = await service.login(
        baseUrl: 'http://x', username: 'u', password: 'p');
    expect(outcome.error, isNull);
    expect(outcome.session?.sessionId, 'abc');
  });
}
```

创建 `test/application/task_service_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ffbox_edgelink/application/task/task_service.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';

class _FakeTaskRepo implements TaskRepository {
  @override
  Future<List<int>> listTaskIds() async => [1, 2];
  @override
  Future<Task> getTask(int id) async =>
      Task(taskName: 't$id', status: TaskStatus.idle);
  @override
  Future<int> createTask({required String taskName, Map<String, dynamic>? outputParams}) async => 99;
  @override
  Future<void> deleteTask(int id) async {}
  @override
  Future<void> startTask(int id) async {}
  @override
  Future<void> readyTask(int id) async {}
  @override
  Future<void> pauseTask(int id) async {}
  @override
  Future<void> resumeTask(int id) async {}
  @override
  Future<void> resetTask(int id) async {}
}

void main() {
  test('loadTasks fetches each task detail', () async {
    final service = TaskService(_FakeTaskRepo());
    final tasks = await service.loadTasks();
    expect(tasks.length, 2);
    expect(tasks[0].taskName, 't1');
    expect(tasks[1].taskName, 't2');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```powershell
flutter test test/application/
```

预期：FAIL。

- [ ] **Step 3: 实现服务**

创建 `lib/application/auth/auth_service.dart`：

```dart
import 'package:ffbox_edgelink/domain/entities/login_result.dart';
import 'package:ffbox_edgelink/domain/repositories/auth_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/session_repository.dart';

/// 登录结果。
class AuthOutcome {
  final Session? session;
  final String? error;

  const AuthOutcome.success(Session this.session) : error = null;
  const AuthOutcome.failure(String this.error) : session = null;
}

/// 登录业务逻辑（纯 Dart，不依赖 UI 框架）。
class AuthService {
  final AuthRepository _authRepository;

  AuthService(this._authRepository);

  Future<AuthOutcome> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final result = await _authRepository.login(
      baseUrl: baseUrl,
      username: username,
      password: password,
    );

    if (!result.isSuccess) {
      final message = result.isUserExist ? '密码错误' : '用户名错误';
      return AuthOutcome.failure(message);
    }

    return AuthOutcome.success(Session(
      baseUrl: baseUrl,
      username: username,
      sessionId: result.sessionId,
    ));
  }
}
```

创建 `lib/application/task/task_service.dart`：

```dart
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_operation.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';
import 'package:ffbox_edgelink/application/task/task_state_machine.dart';

/// 任务业务逻辑（纯 Dart）。UI 通过它执行任务操作并判断可用性。
class TaskService {
  final TaskRepository _repository;

  TaskService(this._repository);

  /// 拉取全部任务：先取 ID 列表，再逐条取详情。
  Future<List<Task>> loadTasks() async {
    final ids = await _repository.listTaskIds();
    final tasks = <Task>[];
    for (final id in ids) {
      tasks.add(await _repository.getTask(id));
    }
    return tasks;
  }

  /// 判断某状态是否可执行某操作。
  bool canExecute(TaskStatus status, TaskOperation operation) =>
      TaskStateMachine.canExecute(status, operation);

  Future<void> start(int id) => _repository.startTask(id);
  Future<void> pause(int id) => _repository.pauseTask(id);
  Future<void> resume(int id) => _repository.resumeTask(id);
  Future<void> delete(int id) => _repository.deleteTask(id);

  // 以下操作已预留，供后续功能接入：
  Future<void> ready(int id) => _repository.readyTask(id);
  Future<void> reset(int id) => _repository.resetTask(id);
  Future<int> create({required String taskName, Map<String, dynamic>? outputParams}) =>
      _repository.createTask(taskName: taskName, outputParams: outputParams);
}
```

- [ ] **Step 4: 运行测试确认通过**

```powershell
flutter test test/application/
```

预期：PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/application/ test/application/
git commit -m "feat: add auth and task application services"
```

---

## Task 10: Riverpod Providers（依赖注入）

**Files:**

- Create: `lib/presentation/providers/app_providers.dart`

- [ ] **Step 1: 实现 providers**

创建 `lib/presentation/providers/app_providers.dart`：

> **一致性说明（重要）**：本任务统一 baseUrl 与 token 的处理方式，取代 Task 6/7/8 中的零散写法。最终约定：
>
> - `AppConfig.baseUrl` 是服务器地址的唯一事实来源（可变）。
> - `ApiClient` 通过 `tokenProvider` 回调在每次请求时读取当前 sessionId，不再使用 `setSessionId`。
> - `FFBoxApi` 依赖 `AppConfig`，在请求时拼接 `config.normalizedBaseUrl`。
> - `AuthRepositoryImpl.login` 先更新 `AppConfig.baseUrl`，再调用登录接口。

据此重构 `ApiClient`（替换 Task 6 实现）：

```dart
import 'package:dio/dio.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';

class ApiClient {
  final Dio _dio;
  final String Function() _tokenProvider;

  ApiClient({Dio? dio, String Function()? tokenProvider})
      : _dio = dio ?? Dio(),
        _tokenProvider = tokenProvider ?? (() => '') {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _tokenProvider();
        if (token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  Future<T> request<T>({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? data,
  }) async {
    try {
      final response = await _dio.request<dynamic>(
        path,
        queryParameters: query,
        data: data,
        options: Options(method: method),
      );
      return response.data as T;
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data?.toString() ?? e.message ?? '网络请求失败',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
```

重构 `FFBoxApi`（替换 Task 7 的构造，改为依赖 `AppConfig`）：

```dart
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/core/network/api_client.dart';
// ...其余 import 不变

class FFBoxApi {
  final ApiClient _client;
  final AppConfig _config;

  FFBoxApi(this._client, this._config);

  String _url(String path) => '${_config.normalizedBaseUrl}$path';
  // ...其余方法体不变（login/listTaskIds/getTask/createTask 等）
}
```

重构 `AuthRepositoryImpl`（替换 Task 8 实现，移除 `_onLoginSuccess` 回调）：

```dart
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/core/utils/hash.dart';
import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:ffbox_edgelink/domain/entities/login_result.dart';
import 'package:ffbox_edgelink/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final FFBoxApi _api;
  final AppConfig _config;

  AuthRepositoryImpl({required FFBoxApi api, required AppConfig config})
      : _api = api,
        _config = config;

  @override
  Future<LoginResult> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    _config.baseUrl = baseUrl;
    return _api.login(username, sha256Hex(password));
  }
}
```

创建 `lib/presentation/providers/app_providers.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/application/auth/auth_service.dart';
import 'package:ffbox_edgelink/application/task/task_service.dart';
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/core/network/api_client.dart';
import 'package:ffbox_edgelink/data/repositories/auth_repository_impl.dart';
import 'package:ffbox_edgelink/data/repositories/session_repository_impl.dart';
import 'package:ffbox_edgelink/data/repositories/task_repository_impl.dart';
import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:ffbox_edgelink/domain/repositories/auth_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/session_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';

/// 服务器地址配置（单一事实来源）。
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig());

/// 当前会话（登录成功写入，登出清空）。
final sessionProvider = StateProvider<Session?>((ref) => null);

/// 会话持久化。
final sessionRepositoryProvider =
    Provider<SessionRepository>((ref) => SessionRepositoryImpl());

/// HTTP 客户端：请求时从会话读取 token。
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(
      tokenProvider: () => ref.read(sessionProvider)?.sessionId ?? '',
    ));

/// FFBox 远端数据源。
final ffboxApiProvider = Provider<FFBoxApi>((ref) =>
    FFBoxApi(ref.watch(apiClientProvider), ref.watch(appConfigProvider)));

/// 认证仓储。
final authRepositoryProvider = Provider<AuthRepository>((ref) =>
    AuthRepositoryImpl(
      api: ref.watch(ffboxApiProvider),
      config: ref.watch(appConfigProvider),
    ));

/// 任务仓储。
final taskRepositoryProvider = Provider<TaskRepository>((ref) =>
    TaskRepositoryImpl(ref.watch(ffboxApiProvider)));

/// 认证服务。
final authServiceProvider =
    Provider<AuthService>((ref) => AuthService(ref.watch(authRepositoryProvider)));

/// 任务服务。
final taskServiceProvider =
    Provider<TaskService>((ref) => TaskService(ref.watch(taskRepositoryProvider)));
```

- [ ] **Step 2: 提交**

```bash
git add lib/presentation/providers/app_providers.dart lib/core/network/api_client.dart lib/data/sources/remote/ffbox_api.dart lib/data/repositories/auth_repository_impl.dart
git commit -m "feat: add riverpod providers and consolidate baseUrl/token wiring"
```

---

## Task 11: 登录页 UI

**Files:**

- Create: `lib/presentation/screens/login_screen.dart`
- Test: `test/presentation/login_screen_test.dart`

- [ ] **Step 1: 编写失败测试**

创建 `test/presentation/login_screen_test.dart`（验证控件存在与表单校验）：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/presentation/screens/login_screen.dart';

void main() {
  testWidgets('shows server, username and password fields', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LoginScreen()));
    expect(find.text('服务器地址'), findsOneWidget);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets('shows error when submitting empty form', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LoginScreen()));
    await tester.tap(find.text('登录'));
    await tester.pump();
    expect(find.text('请输入服务器地址、用户名和密码'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```powershell
flutter test test/presentation/login_screen_test.dart
```

预期：FAIL（LoginScreen 未定义）。

- [ ] **Step 3: 实现登录页**

创建 `lib/presentation/screens/login_screen.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/application/auth/auth_service.dart';
import 'package:ffbox_edgelink/domain/repositories/session_repository.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/screens/task_list_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _baseUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final baseUrl = _baseUrlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (baseUrl.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入服务器地址、用户名和密码');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final outcome = await ref.read(authServiceProvider).login(
          baseUrl: baseUrl,
          username: username,
          password: password,
        );

    if (!mounted) return;

    if (outcome.error != null) {
      setState(() {
        _loading = false;
        _error = outcome.error;
      });
      return;
    }

    final session = outcome.session!;
    await ref.read(sessionRepositoryProvider).save(session);
    ref.read(sessionProvider.notifier).state = session;

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const TaskListScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FFBox EdgeLink')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'http://192.168.1.100:33269',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: '用户名'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const CircularProgressIndicator()
                    : const Text('登录'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```powershell
flutter test test/presentation/login_screen_test.dart
```

预期：PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/presentation/screens/login_screen.dart test/presentation/login_screen_test.dart
git commit -m "feat: add login screen"
```

---

## Task 12: 任务列表页 UI + 任务卡片

**Files:**

- Create: `lib/presentation/widgets/task_tile.dart`
- Create: `lib/presentation/screens/task_list_screen.dart`
- Test: `test/presentation/task_list_screen_test.dart`
- Modify: `lib/domain/entities/task.dart`（补充 id）
- Modify: `lib/data/repositories/task_repository_impl.dart`（注入 id）

> **修正说明**：后端 `GET /tasks/{id}` 返回的 Task 不含 id，而操作任务需要 id。因此给 `Task` 增加 `id` 字段，并由 `TaskRepositoryImpl.getTask` 注入。

- [ ] **Step 1: 补充 Task.id 并注入**

替换 `lib/domain/entities/task.dart` 为：

```dart
import 'package:ffbox_edgelink/domain/entities/task_status.dart';

class Task {
  final int id;
  final String taskName;
  final TaskStatus status;
  final double elapsedSeconds;
  final List<String> errorInfo;
  final List<String> outputFiles;

  const Task({
    this.id = 0,
    required this.taskName,
    required this.status,
    this.elapsedSeconds = 0,
    this.errorInfo = const [],
    this.outputFiles = const [],
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    final progressLog = (json['progressLog'] as Map<String, dynamic>?) ?? const {};
    return Task(
      taskName: json['taskName'] as String? ?? '',
      status: TaskStatus.parse(json['status'] as String? ?? 'idle'),
      elapsedSeconds: (progressLog['elapsed'] as num?)?.toDouble() ?? 0,
      errorInfo: (json['errorInfo'] as List?)?.cast<String>() ?? const [],
      outputFiles: (json['outputFiles'] as List?)?.cast<String>() ?? const [],
    );
  }

  Task copyWith({int? id}) => Task(
        id: id ?? this.id,
        taskName: taskName,
        status: status,
        elapsedSeconds: elapsedSeconds,
        errorInfo: errorInfo,
        outputFiles: outputFiles,
      );
}
```

替换 `lib/data/repositories/task_repository_impl.dart` 中的 `getTask`：

```dart
  @override
  Future<Task> getTask(int id) async {
    final task = await _api.getTask(id);
    return task.copyWith(id: id);
  }
```

- [ ] **Step 2: 实现任务卡片**

创建 `lib/presentation/widgets/task_tile.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:ffbox_edgelink/application/task/task_state_machine.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_operation.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';

/// 首版暴露的基本操作。
const _basicOperations = {
  TaskOperation.start,
  TaskOperation.pause,
  TaskOperation.resume,
  TaskOperation.delete,
};

class TaskTile extends StatelessWidget {
  final Task task;
  final Future<void> Function(TaskOperation operation) onOperation;

  const TaskTile({super.key, required this.task, required this.onOperation});

  static const _labels = {
    TaskOperation.start: '启动',
    TaskOperation.pause: '暂停',
    TaskOperation.resume: '继续',
    TaskOperation.delete: '删除',
  };

  @override
  Widget build(BuildContext context) {
    final allowed = TaskStateMachine.allowedOperations(task.status);
    final actions = _basicOperations.where(allowed.contains).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.taskName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('状态：${task.status.apiValue}'),
                  if (task.status == TaskStatus.running)
                    Text('已运行 ${task.elapsedSeconds.toStringAsFixed(1)}s'),
                ],
              ),
            ),
            for (final op in actions)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: TextButton(
                  onPressed: () => onOperation(op),
                  child: Text(_labels[op]!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: 实现任务列表页**

创建 `lib/presentation/screens/task_list_screen.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_operation.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/screens/login_screen.dart';
import 'package:ffbox_edgelink/presentation/widgets/task_tile.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  AsyncValue<List<Task>> _tasks = const AsyncValue.loading();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _tasks = const AsyncValue.loading());
    try {
      final tasks = await ref.read(taskServiceProvider).loadTasks();
      if (!mounted) return;
      setState(() => _tasks = AsyncValue.data(tasks));
    } catch (e) {
      if (!mounted) return;
      setState(() => _tasks = AsyncValue.error(e, StackTrace.current));
    }
  }

  Future<void> _run(Future<void> Function() op) async {
    try {
      await op();
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败：$e')));
    }
  }

  Future<void> _logout() async {
    await ref.read(sessionRepositoryProvider).clear();
    ref.read(sessionProvider.notifier).state = null;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _onOperation(Task task, TaskOperation op) {
    final service = ref.read(taskServiceProvider);
    return _run(() => switch (op) {
          TaskOperation.start => service.start(task.id),
          TaskOperation.pause => service.pause(task.id),
          TaskOperation.resume => service.resume(task.id),
          TaskOperation.delete => service.delete(task.id),
          _ => Future.value(),
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务列表'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: _tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(child: Text('暂无任务'));
          }
          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (_, i) {
              final task = tasks[i];
              return TaskTile(
                task: task,
                onOperation: (op) => _onOperation(task, op),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: 编写测试**

创建 `test/presentation/task_list_screen_test.dart`（用假仓储覆盖 provider 验证渲染）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffbox_edgelink/application/task/task_service.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/screens/task_list_screen.dart';

class _FakeTaskRepo implements TaskRepository {
  @override
  Future<List<int>> listTaskIds() async => [1];
  @override
  Future<Task> getTask(int id) async =>
      Task(id: id, taskName: 'demo', status: TaskStatus.idle);
  @override
  Future<int> createTask({required String taskName, Map<String, dynamic>? outputParams}) async => 0;
  @override
  Future<void> deleteTask(int id) async {}
  @override
  Future<void> startTask(int id) async {}
  @override
  Future<void> readyTask(int id) async {}
  @override
  Future<void> pauseTask(int id) async {}
  @override
  Future<void> resumeTask(int id) async {}
  @override
  Future<void> resetTask(int id) async {}
}

void main() {
  testWidgets('renders task name and status', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        taskServiceProvider
            .overrideWith((ref) => TaskService(_FakeTaskRepo())),
      ],
      child: const MaterialApp(home: TaskListScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('demo'), findsOneWidget);
    expect(find.text('状态：idle'), findsOneWidget);
  });
}
```

- [ ] **Step 5: 运行测试确认通过**

```powershell
flutter test test/presentation/task_list_screen_test.dart
```

预期：PASS。

- [ ] **Step 6: 提交**

```bash
git add lib/presentation/widgets/task_tile.dart lib/presentation/screens/task_list_screen.dart test/presentation/task_list_screen_test.dart lib/domain/entities/task.dart lib/data/repositories/task_repository_impl.dart
git commit -m "feat: add task list screen and task tile"
```

---

## Task 13: App 根组件与入口

**Files:**

- Create: `lib/app.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: 实现根组件**

创建 `lib/app.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/screens/login_screen.dart';
import 'package:ffbox_edgelink/presentation/screens/task_list_screen.dart';

class FFBoxApp extends ConsumerWidget {
  const FFBoxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return MaterialApp(
      title: 'FFBox EdgeLink',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: session == null ? const LoginScreen() : const TaskListScreen(),
    );
  }
}
```

- [ ] **Step 2: 重写入口**

替换 `lib/main.dart` 为：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/app.dart';
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/data/repositories/session_repository_impl.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await SessionRepositoryImpl().load();
  runApp(ProviderScope(
    overrides: [
      if (session != null)
        sessionProvider.overrideWith((ref) => session),
      if (session != null)
        appConfigProvider
            .overrideWith((ref) => AppConfig(baseUrl: session.baseUrl)),
    ],
    child: const FFBoxApp(),
  ));
}
```

- [ ] **Step 3: 提交**

```bash
git add lib/app.dart lib/main.dart
git commit -m "feat: add app root and entry with session restore"
```

---

## Task 14: 整体验证

- [ ] **Step 1: 静态分析**

```powershell
flutter analyze
```

预期：无 error（允许存在 lint warning，若为新增代码导致的 warning 应修复）。

- [ ] **Step 2: 运行全部测试**

```powershell
flutter test
```

预期：全部 PASS。

- [ ] **Step 3: 删除旧默认测试（若仍存在且引用旧 Counter）**

检查 `test/widget_test.dart`。若仍引用默认 Counter demo，删除或替换为简单 smoke test：

```powershell
flutter test test/widget_test.dart
```

若失败，将 `test/widget_test.dart` 替换为：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/app.dart';

void main() {
  testWidgets('app boots to login screen when no session', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FFBoxApp()));
    expect(find.text('FFBox EdgeLink'), findsOneWidget);
  });
}
```

- [ ] **Step 4: 手动验证（需一台运行中的 FFBox 服务）**

1. 启动 FFBox 服务（`../FFBox`），确认监听 `http://localhost:33269`。
2. 运行 `flutter run -d chrome`（Web）或 `flutter run`（Android/iOS）。
3. 输入服务器地址 `http://localhost:33269`（真机/模拟器用宿主机局域网 IP）、用户名、密码。
4. 验证登录成功后进入任务列表，任务卡片显示名称与状态。
5. 验证「启动/暂停/继续/删除」按钮随状态正确显示，操作后列表刷新。

- [ ] **Step 5: 提交最终状态**

```bash
git status
git add -A
git commit -m "feat: FFBox EdgeLink remote management app"
```

---

## 追加需求与任务（2026-08-14）

以下为后续追加的 4 项需求，插入到原方案中执行。

### 追加 A：调试日志工具（kDebugMode）

**Files:**

- Create: `lib/core/utils/log.dart`
- Modify: `lib/core/network/api_client.dart`、`lib/data/repositories/auth_repository_impl.dart`、`lib/application/task/task_service.dart`（关键流程埋点）

- [ ] **Step 1: 创建日志工具**

创建 `lib/core/utils/log.dart`：

```dart
import 'package:flutter/foundation.dart';

/// 调试开关：debug 构建为 true，release 构建为 false。
const bool kDebugMode = kDebugMode;

/// 仅当 [kDebugMode] 为 true 时输出日志。
void logDebug(String message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[FFBox EdgeLink] $message');
  }
}
```

- [ ] **Step 2: 关键流程埋点**

在 `ApiClient.request` 中请求前后打印：

```dart
  Future<T> request<T>({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? data,
  }) async {
    logDebug('$method $path');
    try {
      final response = await _dio.request<dynamic>(
        path,
        queryParameters: query,
        data: data,
        options: Options(method: method),
      );
      logDebug('$method $path -> ${response.statusCode}');
      return response.data as T;
    } on DioException catch (e) {
      logDebug('$method $path -> ERROR ${e.response?.statusCode}');
      throw ApiException(
        e.response?.data?.toString() ?? e.message ?? '网络请求失败',
        statusCode: e.response?.statusCode,
      );
    }
  }
```

在 `AuthRepositoryImpl.login` 成功时打印：

```dart
    final result = await _api.login(username, sha256Hex(password));
    logDebug('login isSuccess=${result.isSuccess} isUserExist=${result.isUserExist}');
    return result;
```

在 `TaskService` 各操作前打印：

```dart
  Future<void> start(int id) {
    logDebug('task.start id=$id');
    return _repository.startTask(id);
  }
  // pause/resume/delete/ready/reset 同理
```

- [ ] **Step 3: 提交**

```bash
git add lib/core/utils/log.dart lib/core/network/api_client.dart lib/data/repositories/auth_repository_impl.dart lib/application/task/task_service.dart
git commit -m "feat: add kDebugMode-gated debug logging"
```

### 追加 B：服务器数据持久化增强

**Files:**

- Create: `lib/domain/entities/server_profile.dart`
- Create: `lib/domain/repositories/server_repository.dart`
- Create: `lib/data/repositories/server_repository_impl.dart`
- Modify: `lib/presentation/providers/app_providers.dart`
- Modify: `lib/presentation/screens/login_screen.dart`

- [ ] **Step 1: 定义 ServerProfile 与仓储接口**

创建 `lib/domain/entities/server_profile.dart`：

```dart
/// 最近使用过的服务器连接信息（不含 sessionId），用于登录页回填。
class ServerProfile {
  final String baseUrl;
  final String username;

  const ServerProfile({required this.baseUrl, required this.username});
}
```

创建 `lib/domain/repositories/server_repository.dart`：

```dart
import 'package:ffbox_edgelink/domain/entities/server_profile.dart';

/// 服务器连接信息持久化（独立于会话，登出后仍保留）。
abstract interface class ServerRepository {
  Future<ServerProfile?> load();
  Future<void> save(ServerProfile profile);
}
```

- [ ] **Step 2: 实现仓储**

创建 `lib/data/repositories/server_repository_impl.dart`：

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffbox_edgelink/domain/entities/server_profile.dart';
import 'package:ffbox_edgelink/domain/repositories/server_repository.dart';

class ServerRepositoryImpl implements ServerRepository {
  static const _kBaseUrl = 'server_base_url';
  static const _kUsername = 'server_username';

  @override
  Future<ServerProfile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_kBaseUrl);
    if (baseUrl == null || baseUrl.isEmpty) return null;
    return ServerProfile(
      baseUrl: baseUrl,
      username: prefs.getString(_kUsername) ?? '',
    );
  }

  @override
  Future<void> save(ServerProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, profile.baseUrl);
    await prefs.setString(_kUsername, profile.username);
  }
}
```

- [ ] **Step 3: 注册 provider**

在 `lib/presentation/providers/app_providers.dart` 中追加：

```dart
import 'package:ffbox_edgelink/data/repositories/server_repository_impl.dart';
import 'package:ffbox_edgelink/domain/repositories/server_repository.dart';

final serverRepositoryProvider =
    Provider<ServerRepository>((ref) => ServerRepositoryImpl());
```

- [ ] **Step 4: 登录页回填并在登录成功后保存**

在 `_LoginScreenState` 增加 `initState` 回填：

```dart
  @override
  void initState() {
    super.initState();
    ref.read(serverRepositoryProvider).load().then((profile) {
      if (profile != null && mounted) {
        setState(() {
          _baseUrlController.text = profile.baseUrl;
          _usernameController.text = profile.username;
        });
      }
    });
  }
```

在 `_submit` 登录成功后保存服务器信息：

```dart
    await ref.read(serverRepositoryProvider).save(ServerProfile(
      baseUrl: baseUrl,
      username: username,
    ));
    await ref.read(sessionRepositoryProvider).save(session);
```

- [ ] **Step 5: 提交**

```bash
git add lib/domain/entities/server_profile.dart lib/domain/repositories/server_repository.dart lib/data/repositories/server_repository_impl.dart lib/presentation/providers/app_providers.dart lib/presentation/screens/login_screen.dart
git commit -m "feat: persist server profile for login prefill"
```

### 追加 C：Windows 桌面平台支持

**Files:**

- Create: `windows/`（由 flutter 生成）

- [ ] **Step 1: 生成 Windows 平台**

```powershell
flutter create --platforms=windows .
```

预期：生成 `windows/` 目录，且不覆盖现有 `lib/`、`pubspec.yaml` 等文件。

- [ ] **Step 2: 确认 Windows 桌面可用**

```powershell
flutter devices
```

预期：设备列表中出现 `Windows (desktop)`。

- [ ] **Step 3: 提交**

```bash
git add windows/
git commit -m "feat: add Windows desktop platform"
```

### 追加 D：验证与测试调整

将 Task 14 的验证方式调整为：

- **默认本机调试**：`flutter run -d windows`（debug 模式，打印 kDebugMode 日志）。
- **Web**：`flutter run -d chrome`（可选）。
- **Android**：由人工在真机/模拟器手动验证，不做自动化设备测试。
- 手动验证登录时，服务器地址在 Windows 本机调试可填 `http://localhost:33269` 或宿主机局域网 IP。

### 追加 E：网络健壮性（超时 / 重试 / 单通 / 会话失效）

**背景**：远端管理需容忍网络延迟、丢包与「单通」（请求发出但响应不回/被丢，或仅单向可达）。单通在 HTTP 上表现为连接建立但 `receiveTimeout` 超时；高延迟/丢包表现为偶发超时。需通过超时配置、幂等请求重试、错误分类与部分失败容忍应对。

**Files:**

- Modify: `lib/core/network/api_exception.dart`
- Modify: `lib/core/network/api_client.dart`（最终版，取代 Task 6/10 版本）
- Modify: `lib/data/sources/remote/ffbox_api.dart`（GET 请求标记可重试）
- Modify: `lib/application/task/task_service.dart`（`loadTasks` 返回 `TaskLoadResult`）
- Modify: `lib/presentation/screens/task_list_screen.dart`（部分失败提示 + 友好错误 + 401 跳转）
- Modify: `test/application/task_service_test.dart`

- [ ] **Step 1: 扩展 ApiException 增加错误分类**

替换 `lib/core/network/api_exception.dart`：

```dart
/// 网络错误分类。
enum ApiErrorKind {
  timeout, // 连接/发送/接收超时（含「单通」：发出后无响应）
  connectionFailed, // 无法建立连接（拒绝/复位/DNS 失败）
  unauthorized, // 401/403，会话失效
  badStatus, // 其他非 2xx
  unknown,
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final ApiErrorKind kind;

  const ApiException(this.message, {this.statusCode, this.kind = ApiErrorKind.unknown});

  bool get isUnauthorized => kind == ApiErrorKind.unauthorized;

  /// 面向用户的友好文案。
  String get friendlyMessage => switch (kind) {
        ApiErrorKind.timeout => '服务器无响应，请检查网络或服务器地址',
        ApiErrorKind.connectionFailed => '无法连接服务器，请检查地址和网络',
        ApiErrorKind.unauthorized => '登录已失效，请重新登录',
        ApiErrorKind.badStatus => '服务器错误($statusCode)：$message',
        ApiErrorKind.unknown => message,
      };

  @override
  String toString() => friendlyMessage;
}
```

- [ ] **Step 2: ApiClient 最终版（超时 + 重试 + 分类映射）**

替换 `lib/core/network/api_client.dart`：

```dart
import 'package:dio/dio.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';

class ApiClient {
  final Dio _dio;
  final String Function() _tokenProvider;
  final int _maxRetries;

  ApiClient({Dio? dio, String Function()? tokenProvider, int maxRetries = 2})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 10),
            )),
        _tokenProvider = tokenProvider ?? (() => ''),
        _maxRetries = maxRetries {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _tokenProvider();
        if (token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  Future<T> request<T>({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? data,
    bool retryOnFailure = false,
  }) async {
    logDebug('$method $path');
    var attempt = 0;
    while (true) {
      try {
        final response = await _dio.request<dynamic>(
          path,
          queryParameters: query,
          data: data,
          options: Options(method: method),
        );
        logDebug('$method $path -> ${response.statusCode}');
        return response.data as T;
      } on DioException catch (e) {
        final kind = _mapKind(e);
        if (retryOnFailure && attempt < _maxRetries && _isRetryable(kind)) {
          attempt++;
          logDebug('$method $path retry $attempt (kind=$kind)');
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        logDebug('$method $path -> ERROR kind=$kind');
        throw ApiException(
          e.response?.data?.toString() ?? e.message ?? '网络请求失败',
          statusCode: e.response?.statusCode,
          kind: kind,
        );
      }
    }
  }

  ApiErrorKind _mapKind(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiErrorKind.timeout;
      case DioExceptionType.connectionError:
        return ApiErrorKind.connectionFailed;
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 401 || code == 403) return ApiErrorKind.unauthorized;
        return ApiErrorKind.badStatus;
      default:
        return ApiErrorKind.unknown;
    }
  }

  bool _isRetryable(ApiErrorKind kind) =>
      kind == ApiErrorKind.timeout || kind == ApiErrorKind.connectionFailed;
}
```

- [ ] **Step 3: GET 请求标记可重试**

在 `FFBoxApi` 中，`listTaskIds` 与 `getTask` 增加 `retryOnFailure: true`：

```dart
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
```

（登录与 POST 操作不加 `retryOnFailure`，避免重复提交。）

- [ ] **Step 4: loadTasks 部分失败容忍**

在 `lib/application/task/task_service.dart` 中新增结果对象并改写 `loadTasks`：

```dart
class TaskLoadResult {
  final List<Task> tasks;
  final int failedCount;

  const TaskLoadResult({required this.tasks, this.failedCount = 0});
}
```

```dart
  Future<TaskLoadResult> loadTasks() async {
    final ids = await _repository.listTaskIds();
    final tasks = <Task>[];
    var failed = 0;
    for (final id in ids) {
      try {
        tasks.add(await _repository.getTask(id));
      } catch (e) {
        failed++;
        logDebug('loadTasks: task $id failed: $e');
      }
    }
    return TaskLoadResult(tasks: tasks, failedCount: failed);
  }
```

同步更新 `test/application/task_service_test.dart` 中的断言：`loadTasks` 返回 `TaskLoadResult`，改用 `result.tasks` 访问任务列表。

- [ ] **Step 5: 任务列表页处理部分失败 + 友好错误 + 401**

在 `TaskListScreen._refresh` 中处理 `TaskLoadResult`、`ApiException.friendlyMessage` 与未授权跳转：

```dart
  Future<void> _refresh() async {
    setState(() => _tasks = const AsyncValue.loading());
    try {
      final result = await ref.read(taskServiceProvider).loadTasks();
      if (!mounted) return;
      setState(() => _tasks = AsyncValue.data(result.tasks));
      if (result.failedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result.failedCount} 个任务加载失败，请刷新重试')),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        await _logout();
        return;
      }
      setState(() => _tasks = AsyncValue.error(e, StackTrace.current));
    } catch (e) {
      if (!mounted) return;
      setState(() => _tasks = AsyncValue.error(e, StackTrace.current));
    }
  }
```

（错误文案通过 `ApiException.toString()` 自动返回 `friendlyMessage`。）

- [ ] **Step 6: 提交**

```bash
git add lib/core/network/api_exception.dart lib/core/network/api_client.dart lib/data/sources/remote/ffbox_api.dart lib/application/task/task_service.dart lib/presentation/screens/task_list_screen.dart test/application/task_service_test.dart
git commit -m "feat: add network timeout, retry and one-way failure handling"
```

### 追加 F：写操作兜底与结果确认（超时不确定性）

**关键发现（来自参考服务端 `../FFBox/src/backend/FFBoxService.ts` 与 `../FFBox/src/backend/uiBridge.ts`）**：

- start/pause/resume/delete 端点**总是返回 HTTP 200 `{ success: true }`**，即使状态迁移不合法也「允许执行」；`taskPause` 在无 ffmpeg、任务不存在等边界会静默无操作。
- 因此：**成功响应（200）不等于操作必然生效**；**超时响应则完全不确定**（可能已执行也可能没执行）。

**设计原则：对写操作，「查询确认」优先于「盲目重试」。** 超时后不直接判失败，而是重新查询任务状态来确认真实结果。

**Files:**

- Modify: `lib/application/task/task_service.dart`（新增三态结果 + `executeOperation`）
- Modify: `lib/presentation/screens/task_list_screen.dart`（阶段提示 + 三态处理）

- [ ] **Step 1: 三态结果模型**

在 `lib/application/task/task_service.dart` 中新增：

```dart
/// 任务操作结果状态。
enum OperationOutcomeStatus { success, failed, unconfirmed }

/// 任务操作结果（三态，处理超时后的不确定性）。
class TaskOperationOutcome {
  final OperationOutcomeStatus status;
  final String message;
  final Task? confirmedTask;

  const TaskOperationOutcome._(this.status, this.message, {this.confirmedTask});

  factory TaskOperationOutcome.success(String message, {Task? confirmedTask}) =>
      TaskOperationOutcome._(OperationOutcomeStatus.success, message,
          confirmedTask: confirmedTask);

  factory TaskOperationOutcome.failed(String message) =>
      TaskOperationOutcome._(OperationOutcomeStatus.failed, message);

  factory TaskOperationOutcome.unconfirmed(String message) =>
      TaskOperationOutcome._(OperationOutcomeStatus.unconfirmed, message);
}
```

- [ ] **Step 2: executeOperation（发送 → 确认）**

在 `TaskService` 中新增（保留原有 `start/pause/resume/delete` 等薄封装）：

```dart
  /// 执行任务操作并给出三态结果。
  ///
  /// [onStatus] 用于向 UI 回传阶段提示（等待中 / 确认中）。
  Future<TaskOperationOutcome> executeOperation(
    int id,
    TaskOperation op, {
    void Function(String message)? onStatus,
  }) async {
    onStatus?.call('正在${_verb(op)}...');
    try {
      await _execute(op, id);
    } on ApiException catch (e) {
      // 确定性失败：服务器明确拒绝（400/401/403/500...）
      if (e.statusCode != null) {
        return TaskOperationOutcome.failed(e.friendlyMessage);
      }
      // 不确定性失败：超时/连接错误 → 查询确认
      onStatus?.call('请求超时，正在确认任务状态...');
      return _confirmOperation(id, op);
    } catch (_) {
      onStatus?.call('请求异常，正在确认任务状态...');
      return _confirmOperation(id, op);
    }

    // POST 返回 200：服务器总是返回 success，仍需查询确认实际状态
    onStatus?.call('正在确认任务状态...');
    return _confirmOperation(id, op);
  }

  Future<void> _execute(TaskOperation op, int id) => switch (op) {
        TaskOperation.start => _repository.startTask(id),
        TaskOperation.pause => _repository.pauseTask(id),
        TaskOperation.resume => _repository.resumeTask(id),
        TaskOperation.delete => _repository.deleteTask(id),
        TaskOperation.ready => _repository.readyTask(id),
        TaskOperation.reset => _repository.resetTask(id),
        _ => Future.value(),
      };

  String _verb(TaskOperation op) => switch (op) {
        TaskOperation.start => '启动',
        TaskOperation.pause => '暂停',
        TaskOperation.resume => '继续',
        TaskOperation.delete => '删除',
        TaskOperation.ready => '排队',
        TaskOperation.reset => '重置',
        _ => '操作',
      };

  bool _tookEffect(TaskOperation op, TaskStatus status) => switch (op) {
        TaskOperation.start => status == TaskStatus.running,
        TaskOperation.pause => status == TaskStatus.paused,
        TaskOperation.resume => status == TaskStatus.running,
        TaskOperation.ready =>
          status == TaskStatus.idleQueued || status == TaskStatus.pausedQueued,
        TaskOperation.reset => status == TaskStatus.idle,
        TaskOperation.delete => false, // delete 单独处理
        _ => true,
      };

  Future<TaskOperationOutcome> _confirmOperation(int id, TaskOperation op) async {
    // 删除：通过「任务是否还在列表中」确认
    if (op == TaskOperation.delete) {
      try {
        final ids = await _repository.listTaskIds();
        if (!ids.contains(id)) {
          return TaskOperationOutcome.success('删除已生效');
        }
        return TaskOperationOutcome.failed('删除未生效，任务仍存在');
      } catch (_) {
        return TaskOperationOutcome.unconfirmed('操作结果未知，请手动刷新确认');
      }
    }

    // 其他操作：重新拉取任务，比对状态
    try {
      final task = await _repository.getTask(id);
      if (_tookEffect(op, task.status)) {
        return TaskOperationOutcome.success(
          '操作已生效，当前状态：${task.status.apiValue}',
          confirmedTask: task,
        );
      }
      return TaskOperationOutcome.failed('操作未生效，当前状态：${task.status.apiValue}');
    } catch (_) {
      return TaskOperationOutcome.unconfirmed('操作结果未知，请手动刷新确认');
    }
  }
```

- [ ] **Step 3: UI 阶段提示与三态处理**

改写 `TaskListScreen._onOperation` 与 `_run`：

```dart
  Future<void> _onOperation(Task task, TaskOperation op) async {
    final service = ref.read(taskServiceProvider);
    final outcome = await service.executeOperation(
      task.id,
      op,
      onStatus: (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(outcome.message)));
    // 三态都刷新列表，让 UI 与服务器真实状态一致
    await _refresh();
  }
```

> 说明：`onStatus` 依次输出「正在启动...」（等待中）→ 超时或成功后「正在确认任务状态...」（确认中）→ 最终三态结果（成功/失败/未知）。`unconfirmed` 时文案「操作结果未知，请手动刷新确认」明确引导用户手动刷新。

- [ ] **Step 4: 登录兜底**

登录超时视为「未登录」：超时未拿到 `sessionId` 即不建立会话，直接提示重试（重复登录无害，旧 session 自动作废）。

在 `_LoginScreenState._submit` 中捕获超时：

```dart
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.statusCode == null
            ? '连接超时，无法确认是否登录成功，请重试'
            : e.friendlyMessage;
      });
    }
```

- [ ] **Step 5: 其他模块审查（以此类推）**

| 模块             | 风险                                         | 兜底方案                             | 状态                 |
| ---------------- | -------------------------------------------- | ------------------------------------ | -------------------- |
| 登录             | 超时拿不到 sessionId                         | 视为未登录，提示重试（重复登录无害） | 本版实现（Step 4）   |
| 任务列表加载     | 单任务详情超时                               | 部分失败容忍 + 友好文案              | 已补（追加 E）       |
| 任务操作         | 写操作超时结果不确定；200 也可能是静默 no-op | 查询确认（query-confirm）+ 三态结果  | 本版实现（Step 2/3） |
| 会话失效         | 401/403                                      | 清除会话跳登录                       | 已补（追加 E）       |
| 创建任务（预留） | 超时后不确定是否已创建                       | 查询任务列表确认是否新增             | 预留说明             |
| 实时推送（预留） | 断线/单通/假死                               | 心跳 + 断线重连                      | 预留说明             |

- [ ] **Step 6: 提交**

```bash
git add lib/application/task/task_service.dart lib/presentation/screens/task_list_screen.dart lib/presentation/screens/login_screen.dart
git commit -m "feat: add query-confirm fallback for uncertain task operations"
```

### 追加 G：任务进度定时轮询刷新

**背景**：任务运行进度（elapsed、size 等）需实时更新。首版采用定时轮询（默认 1 秒）；任务量很大时 N+1 开销会上升，后续可切换 WebSocket 推送（已在预留范围）。

**Files:**

- Modify: `lib/presentation/screens/task_list_screen.dart`

- [ ] **Step 1: 定时器 + 防重入 + 无闪屏刷新**

改写 `_TaskListScreenState`：

```dart
import 'dart:async';
// ...其余 import 不变

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  AsyncValue<List<Task>> _tasks = const AsyncValue.loading();
  int _failedCount = 0;
  Timer? _pollTimer;
  bool _refreshing = false;

  static const _pollInterval = Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    _refresh();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return; // 防重入：上一次未完成则跳过本次
    _refreshing = true;
    // 仅错误态重试时回退到 loading，正常轮询不闪屏
    if (_tasks.hasError) {
      setState(() => _tasks = const AsyncValue.loading());
    }
    try {
      final result = await ref.read(taskServiceProvider).loadTasks();
      if (!mounted) return;
      setState(() {
        _tasks = AsyncValue.data(result.tasks);
        _failedCount = result.failedCount;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        await _logout();
        return;
      }
      setState(() => _tasks = AsyncValue.error(e, StackTrace.current));
    } catch (e) {
      if (!mounted) return;
      setState(() => _tasks = AsyncValue.error(e, StackTrace.current));
    } finally {
      _refreshing = false;
    }
  }

  // _onOperation / _logout 保持不变，操作后仍调用 _refresh()
}
```

- [ ] **Step 2: 部分失败提示改为常驻条（避免每秒弹 SnackBar）**

在 `build` 的 body 中，用常驻提示条替代 SnackBar：

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务列表'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
          if (_failedCount > 0)
            Container(
              width: double.infinity,
              color: Colors.orange.shade100,
              padding: const EdgeInsets.all(8),
              child: Text('$_failedCount 个任务加载失败，已自动重试'),
            ),
          Expanded(
            child: _tasks.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (tasks) => tasks.isEmpty
                  ? const Center(child: Text('暂无任务'))
                  : ListView.builder(
                      itemCount: tasks.length,
                      itemBuilder: (_, i) {
                        final task = tasks[i];
                        return TaskTile(
                          task: task,
                          onOperation: (op) => _onOperation(task, op),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 3: 提交**

```bash
git add lib/presentation/screens/task_list_screen.dart
git commit -m "feat: add 1s periodic task progress refresh"
```

> 说明：`_pollInterval` 可调（默认 1s）。轮询只在任务列表页存活期间运行，离开页面即 `dispose` 取消。进度字段（elapsed 等）随每次刷新更新，后续可在 `Task` 实体中扩展 size/frame 等更丰富的进度数据。

### 追加 H：设备名旁显示网络延迟

**背景**：在任务列表页显示当前连接的设备名（服务器 host），并在其旁显示实时网络延迟，便于用户判断网络状况。延迟复用每轮轮询中 `listTaskIds()` 的往返耗时，无需额外请求。

**Files:**

- Modify: `lib/application/task/task_service.dart`（`TaskLoadResult` 增加 `latencyMs`）
- Modify: `lib/presentation/screens/task_list_screen.dart`（设备名 + 延迟显示）

- [ ] **Step 1: loadTasks 测量延迟**

在 `lib/application/task/task_service.dart` 中：

```dart
class TaskLoadResult {
  final List<Task> tasks;
  final int failedCount;
  final int latencyMs;

  const TaskLoadResult({
    required this.tasks,
    this.failedCount = 0,
    this.latencyMs = 0,
  });
}
```

```dart
  Future<TaskLoadResult> loadTasks() async {
    final sw = Stopwatch()..start();
    final ids = await _repository.listTaskIds();
    sw.stop();
    final latencyMs = sw.elapsedMilliseconds;

    final tasks = <Task>[];
    var failed = 0;
    for (final id in ids) {
      try {
        tasks.add(await _repository.getTask(id));
      } catch (e) {
        failed++;
        logDebug('loadTasks: task $id failed: $e');
      }
    }
    return TaskLoadResult(tasks: tasks, failedCount: failed, latencyMs: latencyMs);
  }
```

- [ ] **Step 2: 设备名 + 延迟显示**

在 `_TaskListScreenState` 中新增状态与辅助方法：

```dart
  int _latencyMs = 0;

  String _hostOf(String? baseUrl) {
    if (baseUrl == null || baseUrl.isEmpty) return '未连接';
    final uri = Uri.tryParse(baseUrl);
    return uri?.host ?? baseUrl;
  }

  Color _latencyColor(int ms) {
    if (ms <= 0) return Colors.grey;
    if (ms < 100) return Colors.green;
    if (ms < 500) return Colors.orange;
    return Colors.red;
  }
```

在 `_refresh` 成功分支中记录延迟：

```dart
      setState(() {
        _tasks = AsyncValue.data(result.tasks);
        _failedCount = result.failedCount;
        _latencyMs = result.latencyMs;
      });
```

在 `build` 中从会话取设备名并显示：

```dart
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final deviceName = _hostOf(session?.baseUrl);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('任务列表'),
            Text(
              '$deviceName · $_latencyMs ms',
              style: TextStyle(
                fontSize: 12,
                color: _latencyColor(_latencyMs),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: /* 追加 G 中的 body 不变 */,
    );
  }
```

- [ ] **Step 3: 提交**

```bash
git add lib/application/task/task_service.dart lib/presentation/screens/task_list_screen.dart
git commit -m "feat: show device name and network latency in task list"
```

> 说明：延迟随 1s 轮询自动更新；颜色分级（<100ms 绿 / <500ms 橙 / ≥500ms 红）帮助直观判断网络状况。若后续需要更精确的纯延迟，可改用独立的轻量探测端点。

---

## Self-Review

**Spec 覆盖检查：**

- 登录远端服务器：Task 4/5/7/8/9/11 覆盖（含 SHA256 密码、可配置地址、错误分支）。
- 显示任务列表：Task 2/3/9/12 覆盖（状态枚举、任务实体、列表页）。
- 操作任务（基本操作）：Task 2 状态机 + Task 12 卡片按钮覆盖（start/pause/resume/delete）。
- 预留创建任务接口：Task 4 `TaskRepository.createTask` + Task 9 `TaskService.create` 已预留。
- 解耦模块：domain/application 为纯 Dart，presentation 仅 Riverpod 粘合，状态机可复用于 Bloc。
- 预留全部操作接入：Task 2 `TaskOperation` 枚举 + Task 4 `TaskRepository` 接口声明全部操作。
- 服务器数据持久化：追加 B（`ServerProfile` + `ServerRepository`）覆盖，登录页回填最近地址/用户名。
- kDebugMode 调试打印：追加 A（`logDebug`）覆盖，仅 debug 构建输出。
- Windows 默认调试 + Android 人工测试：追加 C/D 覆盖。
- 网络延迟/丢包/单通/会话失效：追加 E 覆盖（超时配置、幂等 GET 重试、错误分类、部分失败容忍、401 跳转）。
- 写操作超时不确定性/兜底确认：追加 F 覆盖（查询确认 + 三态结果 + 阶段提示，应对「200 也不一定生效」与「超时结果未知」）。
- 任务进度定时刷新 + 设备名旁延迟显示：追加 G/H 覆盖（1s 轮询、防重入/无闪屏、延迟颜色分级）。

**已知边界（非本版范围，均已预留接口）：**

- 实时推送（WebSocket `ws://{host}/?sessionId=...`）未实现，当前用轮询 + 手动刷新；后续可新增 `RealtimeEventSource` 实现。
- 创建任务的完整表单 UI 未实现，仅预留 `createTask` 接口。
- 队列级 start/pause、ready/reset、参数设置、上传等操作接口已声明，UI 未暴露。
- Web 目标 CORS：FFBox 服务端当前 CORS 仅放行 `GET` + `Content-Type`，未放行 `Authorization` 头与 `POST`/`DELETE`；Web 端需服务端配合调整，默认以 Windows 桌面规避。

---

## Execution Handoff

方案已保存到 `docs/superpowers/plans/2026-08-14-ffbox-remote-management.md`。两种执行方式：

**1. Subagent-Driven（推荐）**：每个 Task 派发独立子代理实现，任务间进行两阶段评审，迭代快。

**2. Inline Execution**：在当前会话中按 Task 顺序批量执行，配合检查点评审。

请选择执行方式。
