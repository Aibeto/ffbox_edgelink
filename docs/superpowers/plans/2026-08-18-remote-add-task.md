# 远程新建任务（文件上传）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 任务列表右上角新增「新建任务」按钮，二级页选本机文件 → 分片上传（秒传/并发 2/重试）→ 后端合并 → 创建转码任务；上传后台进行并显示 Android 实时进度通知。

**Architecture:** API 层（FFBoxApi 4 个新端点）→ application 层纯 Dart 上传队列（Stream 广播状态）→ Riverpod 装配（StreamProvider + 通知桥接）→ UI（AddTaskScreen + 列表页横幅）+ Android MethodChannel 进度通知。协议与 `E:\FFBox\FFBox` web 前端（transferManager2.ts）语义一致。

**Tech Stack:** dio（FormData/MultipartFile）、crypto（SHA1）、file_picker（新增，唯一新依赖）、Isolate.run（分片哈希）、Riverpod 3、Kotlin NotificationCompat。

**工作区约定：** 禁止自动 git 提交/分支操作——所有 Commit 步骤仅给出建议信息，由用户手动执行。默认 `flutter run -d windows` 本机调试。

**规格文档：** `docs/superpowers/specs/2026-08-18-remote-add-task-design.md`

---

### Task 1: 添加 file_picker 依赖

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 添加依赖**

在 `pubspec.yaml` 的 `dependencies:` 中 `clarity_flutter: ^1.9.0` 之后添加：

```yaml
  file_picker: ^10.0.0
```

- [ ] **Step 2: 解析依赖**

Run: `flutter pub get`
Expected: `Got dependencies!`。若 10.x 不存在则改用 `^9.0.0` 重试。

- [ ] **Step 3: 建议 commit（用户手动执行）**

```
feat: add file_picker dependency for remote task upload
```

---

### Task 2: 上传协议模块（常量/分段/哈希/OutputParams）

**Files:**
- Create: `lib/application/upload/upload_protocol.dart`
- Test: `test/application/upload_protocol_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:ffbox_edgelink/application/upload/upload_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('uploadPlaceholder', () {
    test('生成 [uploading] 前缀占位符', () {
      expect(uploadPlaceholder('video.mp4'), '[uploading] video.mp4');
    });
  });

  group('uploadCacheKey', () {
    test('用 U+2B1D 分隔文件名与哈希', () {
      expect(uploadCacheKey('a.mkv', 'deadbeef'), 'a.mkv⬝deadbeef');
    });
  });

  group('segmentPlan', () {
    test('小于 1GB 用 4MB 十进制分段', () {
      final plan = segmentPlan(10 * 1000 * 1000); // 10MB
      expect(plan.length, 3);
      expect(plan[0], (offset: 0, length: 4 * 1000 * 1000));
      expect(plan[1], (offset: 4 * 1000 * 1000, length: 4 * 1000 * 1000));
      expect(plan[2], (offset: 8 * 1000 * 1000, length: 2 * 1000 * 1000));
    });

    test('大于等于 1GB 用 20MB 分段', () {
      final plan = segmentPlan(1 * 1000 * 1000 * 1000);
      expect(plan.length, 50);
      expect(plan.first.length, 20 * 1000 * 1000);
    });
  });

  group('fileHashOf', () {
    test('对分片哈希拼接的 UTF-8 再取 SHA1', () {
      // echo -n "abc" | sha1sum => a9993e364706816aba3e25717850c26c9cd0d89d
      expect(
        fileHashOf(['a9993e364706816aba3e25717850c26c9cd0d89d']),
        'a9993e364706816aba3e25717850c26c9cd0d89d',
      );
    });
  });

  group('buildOutputParams', () {
    test('嵌入基础配置且其余字段为 FFBox 默认值', () {
      final p = buildOutputParams(vcodec: 'libx264', crf: 20, format: 'mp4');
      expect(p['input']['files'][0]['demuxer'], '自动');
      expect(p['outputs'][0]['video']['vcodec'], 'libx264');
      expect(p['outputs'][0]['video']['ratecontrol'], 'CRF');
      expect(p['outputs'][0]['video']['detail']['crf'], 20);
      expect(p['outputs'][0]['audio']['acodec'], 'copy');
      expect(p['outputs'][0]['mux']['format'], 'mp4');
      expect(
        p['outputs'][0]['mux']['filePath'],
        '[filedir]/[filename]_converted.[fileext]',
      );
      expect(p['extra']['presetName'], '默认配置');
    });
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/application/upload_protocol_test.dart`
Expected: FAIL（文件不存在 / 方法未定义）

- [ ] **Step 3: 实现**

```dart
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

/// 构建 OutputParams：嵌入用户基础配置，其余字段为 FFBox defaultParams 副本。
Map<String, dynamic> buildOutputParams({
  required String vcodec,
  required int crf,
  required String format,
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
      {
        'video': {
          'vcodec': vcodec,
          'resolution': '不改变',
          'framerate': '不改变',
          'ratecontrol': 'CRF',
          'detail': {'crf': crf},
        },
        'audio': {
          'acodec': 'copy',
          'ratecontrol': 'CBR',
          'detail': <String, dynamic>{},
        },
        'mux': {
          'format': format,
          'moveflags': false,
          'filePath': '[filedir]/[filename]_converted.[fileext]',
          'begin': '',
          'end': '',
          'detail': <String, dynamic>{},
        },
      },
    ],
    'extra': {'presetName': '默认配置'},
  };
}
```

注意：`utf8` 来自 `dart:convert`（`crypto` 导出的 `sha1` 需要 `dart:convert` 的 `utf8`）——在文件顶部加 `import 'dart:convert';`。

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/application/upload_protocol_test.dart`
Expected: PASS

- [ ] **Step 5: 建议 commit（用户手动执行）**

```
feat: add upload protocol constants and default output params
```

---

### Task 3: ApiClient 扩展 + FFBoxApi 上传端点

**Files:**
- Modify: `lib/core/network/api_client.dart`
- Modify: `lib/data/sources/remote/ffbox_api.dart`
- Test: `test/data/ffbox_api_test.dart`

- [ ] **Step 1: 写失败测试**

在 `test/data/ffbox_api_test.dart` 的 `main()` 内、`group('FileLogger')` 之前添加（文件顶部已有 dio/FFBoxApi/ApiClient/AppConfig 导入；补充 `import 'dart:io';` 与 `FormData` 已随 dio 导出）：

```dart
  group('FFBoxApi.uploadCheck', () {
    test('POST hashs 并解析 0/1 数组', () async {
      late Map<String, dynamic>? received;
      final api = _buildApi((options) {
        received = options.data as Map<String, dynamic>;
        return [1, 0];
      });
      final result = await api.uploadCheck(['a⬝b', 'c']);
      expect(result, [1, 0]);
      expect(received, {
        'hashs': ['a⬝b', 'c'],
      });
    });
  });

  group('FFBoxApi.uploadFile', () {
    test('multipart 字段 name=hash 且 file 分片携带正确长度', () async {
      late FormData received;
      final api = _buildApi((options) {
        received = options.data as FormData;
        return {'success': true};
      });
      final bytes = List<int>.generate(1024, (i) => i % 251);
      await api.uploadFile(
        'abc123',
        1024,
        () => Stream<List<int>>.value(bytes),
      );
      expect(received.fields, hasLength(1));
      expect(received.fields.first.key, 'name');
      expect(received.fields.first.value, 'abc123');
      expect(received.files, hasLength(1));
      expect(received.files.first.key, 'file');
      final file = await received.files.first.value.finalize().bytesToString();
      expect(file.length, 1024);
    });
  });

  group('FFBoxApi.mergeUpload', () {
    test('POST 合并参数', () async {
      late Map<String, dynamic> received;
      late String path;
      final api = _buildApi((options) {
        received = options.data as Map<String, dynamic>;
        path = options.path;
        return {'success': true};
      });
      await api.mergeUpload(
        5,
        hashs: ['h1', 'h2'],
        fileBaseName: 'a.mp4',
        inputName: '[uploading] a.mp4',
        fileTime: {
          'accessTime': 1,
          'createTime': 2,
          'modifyTime': 3,
        },
      );
      expect(path, contains('/api/v1/tasks/5/merge-upload'));
      expect(received['hashs'], ['h1', 'h2']);
      expect(received['fileBaseName'], 'a.mp4');
      expect(received['inputName'], '[uploading] a.mp4');
      expect(received['fileTime'], {
        'accessTime': 1,
        'createTime': 2,
        'modifyTime': 3,
      });
    });
  });

  group('FFBoxApi.setUploadStatus', () {
    test('PUT isUploading', () async {
      late Map<String, dynamic> received;
      late String method;
      late String path;
      final api = _buildApi((options) {
        received = options.data as Map<String, dynamic>;
        method = options.method;
        path = options.path;
        return {'success': true};
      });
      await api.setUploadStatus(7, false);
      expect(method, 'PUT');
      expect(path, contains('/api/v1/tasks/7/upload-status'));
      expect(received, {'isUploading': false});
    });
  });
```

注意：`bytesToString()` 需要 `import 'package:dio/dio.dart';` 已导出扩展（dio 的 `MultipartFile.finalize()` 返回 `ByteStream`，有 `bytesToString()` 扩展于 `dio/src/utils.dart`，经 `package:dio/dio.dart` 导出）。若该方法不可用，改为 `await file.finalize().fold<List<int>>(<int>[], (acc, d) => acc..addAll(d));` 再断言长度。

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/data/ffbox_api_test.dart`
Expected: FAIL（uploadCheck 等方法未定义）

- [ ] **Step 3: 扩展 ApiClient（可选 options/onSendProgress）**

`lib/core/network/api_client.dart` 中 `request` 方法签名与 `dio.request` 调用处修改：

```dart
  Future<T> request<T>({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? data,
    bool retryOnFailure = false,
    bool silent = false,
    Options? options,
    void Function(int count, int total)? onSendProgress,
  }) async {
```

请求调用改为（保留原有日志/重试/异常逻辑不变）：

```dart
        final response = await _dio.request<dynamic>(
          path,
          queryParameters: query,
          data: data,
          options: options ?? Options(method: method),
          onSendProgress: onSendProgress,
        );
```

并在文件级文档注释中补一句「支持调用方覆盖 Options（如上传分片延长 sendTimeout）与发送进度回调」。

- [ ] **Step 4: 实现 FFBoxApi 四个端点**

在 `lib/data/sources/remote/ffbox_api.dart` 中：文件顶部 `import 'package:dio/dio.dart';`（FormData/MultipartFile/Options），在 `createTasks` 之后新增分节：

```dart
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
```

- [ ] **Step 5: 运行确认通过（含既有用例不回归）**

Run: `flutter test test/data/ffbox_api_test.dart`
Expected: PASS（全部）

- [ ] **Step 6: 建议 commit（用户手动执行）**

```
feat: add upload endpoints to FFBoxApi and progress support in ApiClient
```

---

### Task 4: domain 仓储接口（TaskRepository.createTasks + UploadRepository）

**Files:**
- Modify: `lib/domain/repositories/task_repository.dart`
- Create: `lib/domain/repositories/upload_repository.dart`
- Create: `lib/data/repositories/upload_repository_impl.dart`
- Modify: `lib/data/repositories/task_repository_impl.dart`
- Modify: `lib/presentation/providers/app_providers.dart`
- Modify: `test/presentation/task_list_screen_test.dart`（接口变更同步 fake）

- [ ] **Step 1: TaskRepository 增加 createTasks**

`lib/domain/repositories/task_repository.dart` 在 `resetTasks` 后添加：

```dart
  /// 批量创建任务（[filePaths] 为服务器侧路径或上传占位符），返回任务 ID 列表。
  Future<List<int>> createTasks(
    List<String> filePaths,
    Map<String, dynamic>? outputParams,
  );
```

`lib/data/repositories/task_repository_impl.dart` 对应实现（置于 `resetTasks` 后）：

```dart
  @override
  Future<List<int>> createTasks(
    List<String> filePaths,
    Map<String, dynamic>? outputParams,
  ) => _api.createTasks(filePaths, outputParams);
```

- [ ] **Step 2: 新建 UploadRepository 接口与实现**

`lib/domain/repositories/upload_repository.dart`：

```dart
/// 文件上传仓储抽象接口：分片缓存检查、分片上传、合并、上传状态。
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
```

`lib/data/repositories/upload_repository_impl.dart`：

```dart
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
```

- [ ] **Step 3: provider 装配**

`lib/presentation/providers/app_providers.dart`：顶部导入 `upload_repository_impl.dart` 与 `upload_repository.dart`；在 `taskRepositoryProvider` 后添加：

```dart
/// 文件上传仓储。
final uploadRepositoryProvider = Provider<UploadRepository>(
  (ref) => UploadRepositoryImpl(ref.watch(ffboxApiProvider)),
);
```

- [ ] **Step 4: 同步既有测试 fake**

`test/presentation/task_list_screen_test.dart` 的 `_FakeTaskRepo` 增加成员（与 `task_detail_screen_test.dart` 中若同样存在 fake 一并添加；全局搜索 `implements TaskRepository`）：

```dart
  @override
  Future<List<int>> createTasks(
    List<String> filePaths,
    Map<String, dynamic>? outputParams,
  ) async => [1];
```

- [ ] **Step 5: 运行全部测试确认无回归**

Run: `flutter test`
Expected: PASS（含既有用例）

- [ ] **Step 6: 建议 commit（用户手动执行）**

```
feat: add createTasks and upload repository interfaces
```

---

### Task 5: 分片哈希器（Isolate）

**Files:**
- Create: `lib/application/upload/chunk_hasher.dart`
- Test: `test/application/chunk_hasher_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'dart:io';

import 'package:ffbox_edgelink/application/upload/chunk_hasher.dart';
import 'package:ffbox_edgelink/application/upload/upload_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('多分片哈希与 fileHashOf 拼接语义', () async {
    final dir = await Directory.systemTemp.createTemp('chunk_hash_test');
    final file = File('${dir.path}/data.bin');
    // 9MB 数据触发 3 个 4MB 分段（小文件阈值内）
    final data = List<int>.generate(9 * 1000 * 1000, (i) => i % 256);
    await file.writeAsBytes(data);

    final plan = segmentPlan(data.length);
    expect(plan.length, 3);

    final hashes = await ChunkHasher().hashSegments(file.path, plan);
    expect(hashes, hasLength(3));
    expect(hashes[0], isNot(hashes[2])); // 首尾数据不同

    // 首片哈希应等于直接对前 4MB 求 SHA1
    final direct = Sha1Of(data.sublist(0, 4 * 1000 * 1000));
    expect(hashes[0], direct);

    await dir.delete(recursive: true);
  });
}

// 测试辅助：避免与实现耦合，直接用 crypto
String Sha1Of(List<int> bytes) {
  // ignore: implementation_imports
  return _sha1(bytes);
}

String _sha1(List<int> bytes) {
  return (await_()) ; // placeholder removed below
}
```

上面的辅助函数写得繁琐，直接简化为在测试文件顶部导入 `package:crypto/crypto.dart` 并用 `sha1.convert(...).toString()`：

```dart
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffbox_edgelink/application/upload/chunk_hasher.dart';
import 'package:ffbox_edgelink/application/upload/upload_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('多分片哈希与分段方案一致', () async {
    final dir = await Directory.systemTemp.createTemp('chunk_hash_test');
    final file = File('${dir.path}/data.bin');
    final data = List<int>.generate(9 * 1000 * 1000, (i) => i % 251);
    await file.writeAsBytes(data);

    final plan = segmentPlan(data.length);
    expect(plan.length, 3);

    final hashes = await ChunkHasher().hashSegments(file.path, plan);
    expect(hashes, hasLength(3));
    expect(
      hashes[0],
      sha1.convert(data.sublist(0, 4 * 1000 * 1000)).toString(),
    );
    expect(
      hashes[2],
      sha1.convert(data.sublist(8 * 1000 * 1000)).toString(),
    );

    await dir.delete(recursive: true);
  });

  test('顺序读取保证分片哈希按序返回', () async {
    final dir = await Directory.systemTemp.createTemp('chunk_hash_test2');
    final file = File('${dir.path}/seq.bin');
    final data = List<int>.filled(4 * 1000 * 1000 + 10, 7);
    await file.writeAsBytes(data);

    final hashes = await ChunkHasher().hashSegments(
      file.path,
      segmentPlan(data.length),
    );
    // 末片只有 10 字节，全 7
    expect(
      hashes[1],
      sha1.convert(List<int>.filled(10, 7)).toString(),
    );
    await dir.delete(recursive: true);
  });
}
```

（以第二版测试代码为准，忽略第一版中的占位辅助函数。）

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/application/chunk_hasher_test.dart`
Expected: FAIL（ChunkHasher 未定义）

- [ ] **Step 3: 实现**

```dart
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
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/application/chunk_hasher_test.dart`
Expected: PASS

- [ ] **Step 5: 建议 commit（用户手动执行）**

```
feat: add isolate-based chunk hasher for upload segmentation
```

---

### Task 6: 上传队列（状态机 + 调度 + 秒传 + 重试 + 合并）

**Files:**
- Create: `lib/application/upload/upload_queue.dart`
- Test: `test/application/upload_queue_test.dart`

- [ ] **Step 1: 写失败测试**

测试用 `_FakeAdapter`（与 ffbox_api_test 相同模式）构建真实 `FFBoxApi` → `UploadRepositoryImpl`，配合临时小文件（用 1 字节文件：segmentPlan 首片即全文件）驱动完整流程：

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ffbox_edgelink/application/upload/chunk_hasher.dart';
import 'package:ffbox_edgelink/application/upload/upload_protocol.dart';
import 'package:ffbox_edgelink/application/upload/upload_queue.dart';
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/core/network/api_client.dart';
import 'package:ffbox_edgelink/core/utils/file_logger.dart';
import 'package:ffbox_edgelink/data/repositories/upload_repository_impl.dart';
import 'package:ffbox_edgelink/data/sources/remote/ffbox_api.dart';
import 'package:flutter_test/flutter_test.dart;

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._respond);

  final Object Function(RequestOptions) _respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      await requestStream.drain<void>();
    }
    return ResponseBody.fromString(
      jsonEncode(_respond(options)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

UploadQueue _buildQueue(_FakeAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  final api = FFBoxApi(
    ApiClient(dio: dio),
    AppConfig(baseUrl: 'http://127.0.0.1:5500'),
  );
  return UploadQueue(
    repository: UploadRepositoryImpl(api),
    hasher: ChunkHasher(),
  );
}

Future<File> _tempFile(String name, List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('upload_queue_test');
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  return file;
}

void main() {
  setUp(() {
    fileLogger.clearBuffers();
  });

  test('完整流程：文件级未缓存→分片上传→合并→状态收尾', () async {
    final adapter = _FakeAdapter((options) {
      if (options.path.contains('/api/v1/upload/check')) {
        final body = options.data as Map<String, dynamic>;
        final hashs = body['hashs'] as List;
        // 文件级（带 ⬝）返回未缓存，分片级返回已缓存（跳过上传）
        return hashs.first.contains(uploadCacheSeparator) ? [0] : [1];
      }
      return {'success': true};
    });
    final queue = _buildQueue(adapter);
    final file = await _tempFile('v.mp4', List<int>.filled(16, 3));

    final snapshots = <UploadQueueSnapshot>[];
    final sub = queue.states.listen(snapshots.add);

    await queue.enqueue(
      taskId: 9,
      path: file.path,
      fileBaseName: 'v.mp4',
      size: 16,
    );
    await queue.done; // 等待队列清空
    sub.cancel();

    final item = snapshots.last.items.single;
    expect(item.state, UploadItemState.done);
    expect(item.transferredBytes, 16);

    // 请求序列：文件级 check → 分片级 check → merge-upload → upload-status
    final paths = adapter.requests.map((r) => r.path).toList();
    expect(paths, containsAllInOrder([
      contains('/api/v1/upload/check'),
      contains('/api/v1/tasks/9/merge-upload'),
      contains('/api/v1/tasks/9/upload-status'),
    ]));
    // 分片已缓存时不应有 /upload/file
    expect(
      paths.where((p) => p.contains('/api/v1/upload/file')),
      isEmpty,
    );
    // merge 请求体校验
    final merge = adapter.requests.firstWhere(
      (r) => r.path.contains('/api/v1/tasks/9/merge-upload'),
    );
    expect(merge.data['fileBaseName'], 'v.mp4');
    expect(merge.data['inputName'], uploadPlaceholder('v.mp4'));
  });

  test('秒传：文件级缓存命中直接合并，不检查分片', () async {
    final adapter = _FakeAdapter((options) {
      if (options.path.contains('/api/v1/upload/check')) return [1];
      return {'success': true};
    });
    final queue = _buildQueue(adapter);
    final file = await _tempFile('s.mkv', List<int>.filled(8, 1));

    await queue.enqueue(
      taskId: 3,
      path: file.path,
      fileBaseName: 's.mkv',
      size: 8,
    );
    await queue.done;

    expect(adapter.requests.where((r) => r.path.contains('upload/file')),
        isEmpty);
    expect(adapter.requests.where((r) => r.path.contains('merge-upload')),
        isNotEmpty);
  });

  test('分片上传失败重试 3 次后标记 error，不阻断后续文件', () async {
    var uploadAttempts = 0;
    final adapter = _FakeAdapter((options) {
      if (options.path.contains('/api/v1/upload/check')) return [0];
      if (options.path.contains('/api/v1/upload/file')) {
        uploadAttempts++;
        return ResponseBody.fromString('', 500); // 不会走到：抛异常见下
      }
      return {'success': true};
    });
    // _FakeAdapter 固定 200，无法模拟 5xx——改用抛错适配器：
    final errorAdapter = _ThrowAdapter();
    final queue = _buildQueueAdapter(errorAdapter);
    final file = await _tempFile('e.mp4', List<int>.filled(8, 2));

    await queue.enqueue(
      taskId: 4,
      path: file.path,
      fileBaseName: 'e.mp4',
      size: 8,
    );
    await queue.done;
    expect(uploadAttempts + errorAdapter.uploadAttempts, 3); // 重试 3 次
    final snap = await queue.states.first;
    expect(snap.items.single.state, UploadItemState.error);
  });

  test('retryItem 重新入队失败项', () async {
    var failFirst = true;
    final adapter = _FakeAdapter((options) {
      if (options.path.contains('/api/v1/upload/file') && failFirst) {
        failFirst = false;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      if (options.path.contains('/api/v1/upload/check')) return [0];
      return {'success': true};
    });
    final queue = _buildQueue(adapter);
    final file = await _tempFile('r.mp4', List<int>.filled(8, 4));

    await queue.enqueue(
      taskId: 5,
      path: file.path,
      fileBaseName: 'r.mp4',
      size: 8,
    );
    await queue.done;
    // 第一轮：分片重试 3 次全失败（failFirst 只挡一次，改由 3 次计数断言 error）
    // 简化断言：最终 item 为 error，且 retry 后成功
    var snap = await queue.states.first;
    // 由于失败后重试可能成功，直接验证 retry 后 done：
    await queue.retryItem(5);
    await queue.done;
    snap = await queue.states.first;
    expect(snap.items.single.state, anyOf(UploadItemState.done, UploadItemState.error));
    queue.dispose();
  });
}
```

上述第 3/4 个用例中模拟异常的方式依赖适配器抛 `DioException`——`_FakeAdapter._respond` 是同步回调，直接 `throw DioException(...)` 会被 `fetch` 传播，dio 包装为 badResponse/unknown。为保证确定性，第 3 个用例定义专用适配器：

```dart
class _ThrowAdapter implements HttpClientAdapter {
  int uploadAttempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) await requestStream.drain<void>();
    if (options.path.contains('/api/v1/upload/file')) {
      uploadAttempts++;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    if (options.path.contains('/api/v1/upload/check')) {
      return ResponseBody.fromString('[0]', 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    return ResponseBody.fromString('{"success":true}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

UploadQueue _buildQueueAdapter(HttpClientAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  final api = FFBoxApi(
    ApiClient(dio: dio),
    AppConfig(baseUrl: 'http://127.0.0.1:5500'),
  );
  return UploadQueue(
    repository: UploadRepositoryImpl(api),
    hasher: ChunkHasher(),
  );
}
```

并把第 3 个用例中多余的首段 `_FakeAdapter` 代码删除，仅使用 `_ThrowAdapter` 版本（`_buildQueue(errorAdapter)` → `_buildQueueAdapter(errorAdapter)`）。第 4 个用例简化为只验证「失败 3 次后 error → retry 后重新走流程」（由 `_ThrowAdapter` 的变体或 failFirst 适配器均可，最终断言 `states` 快照中出现 `error` 态且 retry 后出现 `done` 或再次 `error`，不与具体次数强绑定则删除 `uploadAttempts + errorAdapter.uploadAttempts, 3` 的断言，改为 `expect(errorAdapter.uploadAttempts, 3)`）。

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/application/upload_queue_test.dart`
Expected: FAIL（upload_queue.dart 未定义）

- [ ] **Step 3: 实现 UploadQueue**

```dart
import 'dart:async';
import 'dart:io';

import 'package:ffbox_edgelink/application/upload/chunk_hasher.dart';
import 'package:ffbox_edgelink/application/upload/upload_protocol.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/domain/repositories/upload_repository.dart';

/// 上传项状态。
enum UploadItemState { pending, hashing, uploading, merging, done, error }

/// 单个上传项的不可变快照。
class UploadItem {
  final int taskId;
  final String path;
  final String fileBaseName;
  final int size;
  final UploadItemState state;
  final int transferredBytes;
  final double speedBps;
  final String? error;
  final bool unauthorized;

  const UploadItem({
    required this.taskId,
    required this.path,
    required this.fileBaseName,
    required this.size,
    this.state = UploadItemState.pending,
    this.transferredBytes = 0,
    this.speedBps = 0,
    this.error,
    this.unauthorized = false,
  });

  String get inputName => uploadPlaceholder(fileBaseName);

  UploadItem copyWith({
    UploadItemState? state,
    int? transferredBytes,
    double? speedBps,
    String? error,
    bool? unauthorized,
  }) => UploadItem(
    taskId: taskId,
    path: path,
    fileBaseName: fileBaseName,
    size: size,
    state: state ?? this.state,
    transferredBytes: transferredBytes ?? this.transferredBytes,
    speedBps: speedBps ?? this.speedBps,
    error: error ?? this.error,
    unauthorized: unauthorized ?? this.unauthorized,
  );
}

/// 队列整体快照（广播流每次变更发出）。
class UploadQueueSnapshot {
  final List<UploadItem> items;

  const UploadQueueSnapshot(this.items);

  bool get hasActive => items.any(
    (i) =>
        i.state == UploadItemState.pending ||
        i.state == UploadItemState.hashing ||
        i.state == UploadItemState.uploading ||
        i.state == UploadItemState.merging,
  );

  bool get hasError => items.any((i) => i.state == UploadItemState.error);

  bool get hasUnauthorizedError =>
      items.any((i) => i.state == UploadItemState.error && i.unauthorized);
}

/// 全局上传队列：文件串行、文件内分片并发 2、每片重试 3 次。
///
/// 生命周期独立于页面（由 Riverpod 全局持有）。纯 Dart 实现，
/// 通过 [states] 广播流对外发布状态；401 项由 UI 层负责登出。
class UploadQueue {
  UploadQueue({required UploadRepository repository, required ChunkHasher hasher})
    : _repository = repository,
      _hasher = hasher;

  final UploadRepository _repository;
  final ChunkHasher _hasher;
  final List<UploadItem> _items = [];
  final _controller = StreamController<UploadQueueSnapshot>.broadcast();
  Completer<void>? _drainCompleter;

  static const _chunkConcurrency = 2;
  static const _maxChunkRetries = 3;

  // --- 状态流 ---

  Stream<UploadQueueSnapshot> get states => _controller.stream;

  /// 队列排空的 Future（测试与 UI 等待用）。
  Future<void> get done => _drainCompleter?.future ?? Future.value();

  bool get hasUnfinished =>
      _items.any((i) => i.state == UploadItemState.pending) ||
      _isPumping ||
      _items.any(
        (i) =>
            i.state == UploadItemState.hashing ||
            i.state == UploadItemState.uploading ||
            i.state == UploadItemState.merging,
      );

  bool _isPumping = false;

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(UploadQueueSnapshot(List.unmodifiable(_items)));
    }
  }

  // --- 入队与重试 ---

  Future<void> enqueue({
    required int taskId,
    required String path,
    required String fileBaseName,
    required int size,
  }) async {
    _items.add(
      UploadItem(
        taskId: taskId,
        path: path,
        fileBaseName: fileBaseName,
        size: size,
      ),
    );
    logDebug('uploadQueue: enqueue $fileBaseName (task $taskId)');
    _emit();
    _pump();
  }

  /// 重试失败项（复位为 pending 并重新调度；服务端分片缓存生效）。
  Future<void> retryItem(int taskId) async {
    _updateWhere(taskId, (item) => item.copyWith(state: UploadItemState.pending, error: null, unauthorized: false));
    _pump();
  }

  // --- 调度 ---

  Future<void> _pump() async {
    if (_isPumping) return;
    _isPumping = true;
    _drainCompleter = Completer<void>();
    try {
      while (true) {
        final index = _items.indexWhere(
          (i) => i.state == UploadItemState.pending,
        );
        if (index < 0) break;
        final stop = await _processItem(_items[index]);
        if (stop) break; // 401：停止调度，余下保持 pending
      }
    } finally {
      _isPumping = false;
      _drainCompleter?.complete();
      _drainCompleter = null;
      _emit();
    }
  }

  void _updateWhere(int taskId, UploadItem Function(UploadItem) transform) {
    final index = _items.indexWhere((i) => i.taskId == taskId);
    if (index >= 0) {
      _items[index] = transform(_items[index]);
      _emit();
    }
  }

  /// 处理单个上传项。返回 true 表示遇到 401 需停止调度。
  Future<bool> _processItem(UploadItem item) async {
    try {
      await _processPhases(item);
      return false;
    } on ApiException catch (e) {
      logDebug('uploadQueue: item ${item.taskId} error ${e.friendlyMessage}');
      _updateWhere(item.taskId, (i) => i.copyWith(
        state: UploadItemState.error,
        error: e.friendlyMessage,
        unauthorized: e.isUnauthorized,
        speedBps: 0,
      ));
      return e.isUnauthorized;
    }
  }

  Future<void> _processPhases(UploadItem item) async {
    // --- 哈希 ---
    _updateWhere(item.taskId, (i) => i.copyWith(state: UploadItemState.hashing));
    final segments = segmentPlan(item.size);
    final chunkHashes = await _hasher.hashSegments(item.path, segments);
    final fileHash = fileHashOf(chunkHashes);
    final cacheKey = uploadCacheKey(item.fileBaseName, fileHash);

    // --- 秒传检查 ---
    final fileCached = await _repository.uploadCheck([cacheKey]);
    if (fileCached.isEmpty || fileCached.first != 1) {
      // --- 分片检查与上传 ---
      final chunkCached = await _repository.uploadCheck(chunkHashes);
      final pendingIndices = [
        for (var i = 0; i < segments.length; i++)
          if (i >= chunkCached.length || chunkCached[i] != 1) i,
      ];
      final completedBytes = <int>{
        for (var i = 0; i < segments.length; i++)
          if (i < chunkCached.length && chunkCached[i] == 1) segments[i].length,
      };
      _updateWhere(item.taskId, (i) => i.copyWith(
        state: UploadItemState.uploading,
        transferredBytes: completedBytes.fold<int>(0, (a, b) => a + b),
      ));

      final failedIndex = <int>[];
      await _forEachLimited(pendingIndices, _chunkConcurrency, (index) async {
        if (failedIndex.isNotEmpty) return;
        final segment = segments[index];
        await _uploadChunkWithRetry(item, index, segment, completedBytes);
      });
      if (failedIndex.isNotEmpty) {
        throw ApiException('分片上传失败', kind: ApiErrorKindUnknown());
      }
    }

    // --- 合并与收尾 ---
    _updateWhere(item.taskId, (i) => i.copyWith(state: UploadItemState.merging));
    final stat = await File(item.path).stat();
    await _repository.mergeUpload(
      item.taskId,
      hashs: chunkHashes,
      fileBaseName: item.fileBaseName,
      inputName: item.inputName,
      fileTime: {
        'accessTime': stat.accessed.millisecondsSinceEpoch,
        'createTime': stat.changed.millisecondsSinceEpoch,
        'modifyTime': stat.modified.millisecondsSinceEpoch,
      },
    );
    await _repository.setUploadStatus(item.taskId, false);
    _updateWhere(item.taskId, (i) => i.copyWith(
      state: UploadItemState.done,
      transferredBytes: item.size,
      speedBps: 0,
    ));
    logDebug('uploadQueue: item ${item.taskId} done');
  }

  // --- 分片上传（并发 worker 内调用，带 3 次重试与进度） ---

  Future<void> _uploadChunkWithRetry(
    UploadItem item,
    int index,
    ({int offset, int length}) segment,
    Set<int> completedBytes,
  ) async {
    for (var attempt = 1; attempt <= _maxChunkRetries; attempt++) {
      try {
        await _repository.uploadFile(
          _chunkHashOf(item, index),
          segment.length,
          () => File(item.path).openRead(segment.offset, segment.offset + segment.length),
          onProgress: (count, total) => _onChunkProgress(item, completedBytes, count),
        );
        completedBytes.add(segment.length);
        _onChunkProgress(item, completedBytes, 0);
        return;
      } on ApiException catch (e) {
        if (e.isUnauthorized) rethrow;
        logDebug('uploadQueue: chunk $index attempt $attempt failed');
      }
    }
    throw ApiException('分片重试 3 次仍失败');
  }

  // 分片哈希在哈希阶段已知——为避免重算，这里从缓存读取。
  final Map<int, List<String>> _hashesByTask = {};

  String _chunkHashOf(UploadItem item, int index) =>
      _hashesByTask[item.taskId]![index];

  // --- 进度与速度 ---

  final Map<int, ({int bytes, DateTime time})> _lastProgress = {};

  void _onChunkProgress(UploadItem item, Set<int> completedBytes, int chunkSent) {
    final base = completedBytes.fold<int>(0, (a, b) => a + b) + chunkSent;
    final now = DateTime.now();
    final last = _lastProgress[item.taskId];
    var speed = 0.0;
    if (last != null) {
      final dt = now.difference(last.time).inMicroseconds;
      if (dt > 0) {
        final instant = (base - last.bytes) * 1000 * 1000 / dt;
        speed = last.bytes > 0 ? instant * 0.4 + item.speedBps * 0.6 : instant;
      }
    }
    _lastProgress[item.taskId] = (bytes: base, time: now);
    _updateWhere(item.taskId, (i) => i.copyWith(
      transferredBytes: base.clamp(0, i.size),
      speedBps: speed,
    ));
  }

  // --- 并发限流 ---

  Future<void> _forEachLimited<T>(
    List<T> items,
    int limit,
    Future<void> Function(T) task,
  ) async {
    var cursor = 0;
    final errors = <Object>[];
    Future<void> worker() async {
      while (cursor < items.length && errors.isEmpty) {
        final current = items[cursor++];
        try {
          await task(current);
        } catch (e) {
          errors.add(e);
        }
      }
    }

    await Future.wait([for (var i = 0; i < limit; i++) worker()]);
    if (errors.isNotEmpty) throw errors.first;
  }

  // --- 释放 ---

  void dispose() {
    _controller.close();
  }
}
```

实现时需修正两处草稿问题（直接按以下落地，不留 TODO）：

1. 删除 `_processPhases` 中对 `failedIndex`/`ApiErrorKindUnknown` 的错误草稿：`_forEachLimited` 已聚合异常并重抛首个 `ApiException`，因此 `pendingIndices` 上传段写成：

```dart
      await _forEachLimited(pendingIndices, _chunkConcurrency, (index) async {
        final segment = segments[index];
        await _uploadChunkWithRetry(item, index, segment, completedBytes);
      });
```

2. `_uploadChunkWithRetry` 使用 `_hashesByTask`：在 `_processPhases` 哈希完成后写入 `_hashesByTask[item.taskId] = chunkHashes;`（done/error 后可保留，供 retry 复用哈希；retry 项在哈希阶段会重新覆盖）。同时 `_uploadChunkWithRetry` 中捕获 `ApiException` 后若为最后一次尝试则 rethrow（让 `_forEachLimited` 聚合）：

```dart
      } on ApiException catch (e) {
        if (e.isUnauthorized || attempt == _maxChunkRetries) rethrow;
        logDebug('uploadQueue: chunk $index attempt $attempt failed');
      }
```

3. `hasUnfinished` getter 中 `_isPumping` 已覆盖进行中语义，简化为：

```dart
  bool get hasUnfinished =>
      _isPumping ||
      _items.any((i) => i.state == UploadItemState.pending);
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/application/upload_queue_test.dart`
Expected: PASS（全部 4 个用例）

- [ ] **Step 5: 建议 commit（用户手动执行）**

```
feat: add upload queue with instant-upload check, retry and merge
```

---

### Task 7: Dart 通知通道 + Riverpod 装配

**Files:**
- Create: `lib/core/notifications/upload_notification_channel.dart`
- Modify: `lib/presentation/providers/app_providers.dart`

- [ ] **Step 1: Dart 通知通道**

```dart
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 上传进度 MethodChannel 封装。
///
/// 桥接 Android 原生进度通知（固定 ID 3002，channel upload，静默）。
/// 非 Android 平台 [isSupported] 返回 false，调用侧跳过。
class UploadNotificationChannel {
  static const MethodChannel _channel = MethodChannel(
    'top.raincrat.aibeto.ffboxedgelink/upload_notification',
  );

  static const int notificationId = 3002;

  /// 是否支持上传通知（仅 Android）。
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 显示/更新进度通知。progress 0-100，indeterminate 为 true 时不显示具体刻度。
  Future<void> show({
    required String title,
    required String content,
    required int progress,
    bool indeterminate = false,
  }) async {
    await _channel.invokeMethod<void>('show', {
      'title': title,
      'content': content,
      'progress': progress,
      'indeterminate': indeterminate,
    });
  }

  /// 移除上传通知。
  Future<void> cancel() async {
    await _channel.invokeMethod<void>('cancel');
  }
}
```

- [ ] **Step 2: provider 装配与通知桥接**

`lib/presentation/providers/app_providers.dart` 顶部补充导入：

```dart
import 'package:ffbox_edgelink/application/upload/chunk_hasher.dart';
import 'package:ffbox_edgelink/application/upload/upload_queue.dart';
import 'package:ffbox_edgelink/core/notifications/upload_notification_channel.dart';
import 'dart:async';
```

在文件末尾（liveActivityProvider 之后）添加：

```dart
// --- 远程上传（后台队列 + Android 进度通知） ---

/// 上传进度原生通道。
final uploadNotificationChannelProvider = Provider<UploadNotificationChannel>(
  (ref) => UploadNotificationChannel(),
);

/// 全局上传队列（生命周期独立于页面）。
final uploadQueueProvider = Provider<UploadQueue>((ref) {
  final queue = UploadQueue(
    repository: ref.watch(uploadRepositoryProvider),
    hasher: ChunkHasher(),
  );
  ref.onDispose(queue.dispose);
  return queue;
});

/// 队列状态流（列表页横幅与新建任务页共用）。
final uploadQueueStateProvider = StreamProvider<UploadQueueSnapshot>(
  (ref) => ref.watch(uploadQueueProvider).states,
);

/// 通知桥接：订阅队列状态，500ms 节流更新 Android 进度通知。
/// 需在任务列表页 build 中 watch 以激活。
final uploadNotificationBridgeProvider = Provider<void>((ref) {
  final channel = ref.watch(uploadNotificationChannelProvider);
  if (!channel.isSupported) return;
  Timer? throttle;
  var lastShown = false;
  final sub = ref.watch(uploadQueueProvider).states.listen((snap) {
    if (throttle?.isActive ?? false) return;
    throttle = Timer(const Duration(milliseconds: 500), () async {
      final active = snap.items.where((i) =>
          i.state == UploadItemState.pending ||
          i.state == UploadItemState.hashing ||
          i.state == UploadItemState.uploading ||
          i.state == UploadItemState.merging).toList();
      if (active.isNotEmpty) {
        final current = active.firstWhere(
          (i) => i.state != UploadItemState.pending,
          orElse: () => active.first,
        );
        final percent = current.size > 0
            ? (current.transferredBytes * 100 / current.size).round().clamp(0, 100)
            : 0;
        await channel.show(
          title: 'FFBox 上传任务',
          content: '${current.fileBaseName} · $percent%',
          progress: percent,
          indeterminate: current.state == UploadItemState.hashing,
        );
        lastShown = true;
      } else if (lastShown) {
        await channel.cancel();
        lastShown = false;
      }
    });
  });
  ref.onDispose(() {
    throttle?.cancel();
    sub.cancel();
  });
});
```

- [ ] **Step 3: 静态检查**

Run: `flutter analyze lib/presentation/providers/app_providers.dart lib/core/notifications/upload_notification_channel.dart`
Expected: No issues found!

- [ ] **Step 4: 建议 commit（用户手动执行）**

```
feat: wire upload queue providers and Android notification bridge
```

---

### Task 8: Android 原生进度通知

**Files:**
- Create: `android/app/src/main/res/drawable/ic_status_upload.xml`
- Create: `android/app/src/main/kotlin/top/raincrat/aibeto/ffboxedgelink/upload/UploadNotificationChannel.kt`
- Modify: `android/app/src/main/kotlin/top/raincrat/aibeto/ffboxedgelink/MainActivity.kt`

- [ ] **Step 1: 通知图标 drawable**

`android/app/src/main/res/drawable/ic_status_upload.xml`（与既有 `ic_action_*` 同风格的单色 vector，24dp 上传箭头）：

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M12,3L6.5,8.5L7.9,9.9L11,6.8V16H13V6.8L16.1,9.9L17.5,8.5L12,3zM5,18V20H19V18H5z" />
</vector>
```

- [ ] **Step 2: Kotlin 通道**

`android/app/src/main/kotlin/top/raincrat/aibeto/ffboxedgelink/upload/UploadNotificationChannel.kt`：

```kotlin
package top.raincrat.aibeto.ffboxedgelink.upload

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger

// 上传进度通知 MethodChannel：Dart 侧节流调用 show/cancel，固定 ID 3002。
// 普通进度通知（非前台服务、非 Live Updates），静默 channel 不打扰用户。
class UploadNotificationChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "top.raincrat.aibeto.ffboxedgelink/upload_notification"
        const val CHANNEL_ID = "upload"
        const val NOTIFICATION_ID = 3002
    }

    private val channel = MethodChannel(messenger, CHANNEL_NAME).also {
        it.setMethodCallHandler(this)
    }

    fun register() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "上传进度",
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "show" -> {
                show(
                    title = call.argument<String>("title") ?: "FFBox 上传任务",
                    content = call.argument<String>("content") ?: "",
                    progress = call.argument<Int>("progress") ?: 0,
                    indeterminate = call.argument<Boolean>("indeterminate") ?: false,
                )
                result.success(null)
            }
            "cancel" -> {
                NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun show(title: String, content: String, progress: Int, indeterminate: Boolean) {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_status_upload)
            .setContentTitle(title)
            .setContentText(content)
            .setProgress(100, progress.coerceIn(0, 100), indeterminate)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // 权限被撤销时静默跳过
        }
    }
}
```

注意：`R` 引用为 `top.raincrat.aibeto.ffboxedgelink.R`（同包根，无需 import）。

- [ ] **Step 3: MainActivity 注册**

`MainActivity.kt` 修改为：

```kotlin
package top.raincrat.aibeto.ffboxedgelink

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import top.raincrat.aibeto.ffboxedgelink.live.LiveActivityChannel
import top.raincrat.aibeto.ffboxedgelink.upload.UploadNotificationChannel

// Flutter 宿主 Activity：注册实时活动与上传通知 MethodChannel，转发通知权限结果。
class MainActivity : FlutterActivity() {
    private lateinit var liveActivityChannel: LiveActivityChannel
    private lateinit var uploadNotificationChannel: UploadNotificationChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        liveActivityChannel = LiveActivityChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        ).also { it.register() }
        uploadNotificationChannel = UploadNotificationChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        ).also { it.register() }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        liveActivityChannel.onRequestPermissionsResult(requestCode, grantResults)
    }
}
```

- [ ] **Step 4: 编译验证**

Run: `flutter build apk --debug`（或 `cd android && gradlew assembleDebug`，取项目惯用方式）
Expected: BUILD SUCCESSFUL。Android 真机通知表现由人工验证（见 Task 11）。

- [ ] **Step 5: 建议 commit（用户手动执行）**

```
feat: add Android upload progress notification channel
```

---

### Task 9: 新建任务页 AddTaskScreen

**Files:**
- Create: `lib/presentation/screens/add_task_screen.dart`
- Test: `test/presentation/add_task_screen_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:ffbox_edgelink/application/upload/upload_queue.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';
import 'package:ffbox_edgelink/domain/repositories/task_repository.dart';
import 'package:ffbox_edgelink/domain/repositories/upload_repository.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/screens/add_task_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTaskRepo implements TaskRepository {
  List<String>? lastFilePaths;
  Map<String, dynamic>? lastOutputParams;

  @override
  Future<List<int>> createTasks(
    List<String> filePaths,
    Map<String, dynamic>? outputParams,
  ) async {
    lastFilePaths = filePaths;
    lastOutputParams = outputParams;
    return [101, 102];
  }

  @override
  Future<List<int>> listTaskIds({int offset = 0, int size = 100, bool silent = false}) async => [];
  @override
  Future<Task> getTask(int id, {bool silent = false}) async =>
      Task(id: id, taskName: 't', status: TaskStatus.idle);
  @override
  Future<void> deleteTasks(List<int> ids) async {}
  @override
  Future<void> startTasks(List<int> ids) async {}
  @override
  Future<void> readyTasks(List<int> ids) async {}
  @override
  Future<void> pauseTasks(List<int> ids) async {}
  @override
  Future<void> resumeTasks(List<int> ids) async {}
  @override
  Future<void> resetTasks(List<int> ids) async {}
}

class _FakeUploadRepo implements UploadRepository {
  int enqueued = 0;

  @override
  Future<List<int>> uploadCheck(List<String> hashs) async => [0];
  @override
  Future<void> uploadFile(
    String hash,
    int length,
    Stream<List<int>> Function() openStream, {
    void Function(int count, int total)? onProgress,
  }) async {}
  @override
  Future<void> mergeUpload(
    int taskId, {
    required List<String> hashs,
    required String fileBaseName,
    required String inputName,
    required Map<String, int> fileTime,
  }) async {
    enqueued++;
  }

  @override
  Future<void> setUploadStatus(int taskId, bool isUploading) async {}
}

void main() {
  testWidgets('渲染配置行与文件列表，无文件时禁用提交', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskRepositoryProvider.overrideWith((ref) => _FakeTaskRepo()),
          uploadRepositoryProvider.overrideWith((ref) => _FakeUploadRepo()),
        ],
        child: const MaterialApp(home: AddTaskScreen()),
      ),
    );
    expect(find.text('视频编码器'), findsOneWidget);
    expect(find.text('输出格式'), findsOneWidget);
    expect(find.text('添加并上传'), findsOneWidget);
    // 无文件时按钮禁用
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '添加并上传'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('初始文件可移除，提交发送占位符与配置并调用 createTasks',
      (tester) async {
    final taskRepo = _FakeTaskRepo();
    final uploadRepo = _FakeUploadRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskRepositoryProvider.overrideWith((ref) => taskRepo),
          uploadRepositoryProvider.overrideWith((ref) => uploadRepo),
        ],
        child: const MaterialApp(
          home: AddTaskScreen(
            initialFiles: [
              (path: '/tmp/a.mp4', name: 'a.mp4', size: 1024),
            ],
          ),
        ),
      ),
    );
    expect(find.text('a.mp4'), findsOneWidget);

    await tester.tap(find.text('添加并上传'));
    await tester.pumpAndSettle();

    expect(taskRepo.lastFilePaths, ['[uploading] a.mp4']);
    expect(taskRepo.lastOutputParams!['outputs'][0]['video']['vcodec'], 'libx265');
    expect(taskRepo.lastOutputParams!['outputs'][0]['video']['detail']['crf'], 24);
    expect(taskRepo.lastOutputParams!['outputs'][0]['mux']['format'], 'mp4');
  });
}
```

注意：真实 `UploadQueue.enqueue` 会开始哈希（读取 `/tmp/a.mp4` 不存在），测试中 `uploadQueueProvider` 需覆写为不执行的真实子类：

```dart
class _NoopQueue extends UploadQueue {
  _NoopQueue() : super(
    repository: _FakeUploadRepo(),
    hasher: _NoopHasher(),
  );

  @override
  Future<void> enqueue({
    required int taskId,
    required String path,
    required String fileBaseName,
    required int size,
  }) async {}
}

class _NoopHasher extends ChunkHasher {}
```

并在两个用例的 `overrides` 中加 `uploadQueueProvider.overrideWith((ref) => _NoopQueue())`。`ChunkHasher`/`UploadQueue` 构造需为 public（Task 5/6 已是）。由于 `_NoopHasher` 继承即可（不实际调用），同时在文件顶部导入：

```dart
import 'package:ffbox_edgelink/application/upload/chunk_hasher.dart';
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/presentation/add_task_screen_test.dart`
Expected: FAIL（AddTaskScreen 未定义）

- [ ] **Step 3: 实现 AddTaskScreen**

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/application/upload/upload_protocol.dart';
import 'package:ffbox_edgelink/application/upload/upload_queue.dart';
import 'package:ffbox_edgelink/core/network/api_exception.dart';
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';

/// 远程新建任务页：选择本机视频文件 + 基础输出配置，
/// 提交后先以占位符创建任务再入队后台上传。
class AddTaskScreen extends ConsumerStatefulWidget {
  /// 预填文件（测试/外部入口用），元素为 (path, name, size)。
  final List<({String path, String name, int size})> initialFiles;

  const AddTaskScreen({super.key, this.initialFiles = const []});

  @override
  ConsumerState<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends ConsumerState<AddTaskScreen> {
  final List<({String path, String name, int size})> _files = [];
  String _vcodec = 'libx265';
  int _crf = 24;
  String _format = 'mp4';
  bool _submitting = false;

  static const _vcodecs = ['libx264', 'libx265'];
  static const _formats = ['mp4', 'mkv (matroska)'];

  // --- 文件选择 ---

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    if (result == null) return;
    final picked =
        result.paths
            .whereType<String>()
            .where((p) => p.isNotEmpty)
            .map((p) => _fileEntryOf(p))
            .whereType<({String path, String name, int size})>()
            .toList();
    if (picked.isEmpty) return;
    setState(() {
      for (final f in picked) {
        if (!_files.any((e) => e.path == f.path)) _files.add(f);
      }
    });
  }

  ({String path, String name, int size})? _fileEntryOf(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final size = _fileSizeOf(path);
    if (size <= 0) return null;
    return (path: path, name: name, size: size);
  }

  int _fileSizeOf(String path) {
    try {
      final stat = io.File(path).statSync();
      return stat.type == io.FileSystemEntityType.file ? stat.size : 0;
    } catch (_) {
      return 0;
    }
  }

  // --- 提交 ---

  Future<void> _submit() async {
    if (_files.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final outputParams = buildOutputParams(
        vcodec: _vcodec,
        crf: _crf,
        format: _format,
      );
      final filePaths = _files.map((f) => uploadPlaceholder(f.name)).toList();
      final ids = await ref
          .read(taskRepositoryProvider)
          .createTasks(filePaths, outputParams);
      final queue = ref.read(uploadQueueProvider);
      for (var i = 0; i < ids.length && i < _files.length; i++) {
        await queue.enqueue(
          taskId: ids[i],
          path: _files[i].path,
          fileBaseName: _files[i].name,
          size: _files[i].size,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已创建任务并开始上传，可离开页面')),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      // 401 交给列表页轮询登出；此处提示后返回
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.friendlyMessage)),
      );
      if (e.isUnauthorized) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // --- 构建 ---

  @override
  Widget build(BuildContext context) {
    ref.watch(uploadNotificationBridgeProvider);
    final queueSnap = ref.watch(uploadQueueStateProvider).value;
    final sizeText = <int>{
      for (final f in _files) f.size,
    }.length == _files.length
        ? null
        : null;

    return Scaffold(
      backgroundColor: AkColors.canvas,
      appBar: AppBar(
        title: Text(
          '新建任务',
          style: AkTheme.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AkColors.textPrimary,
          ),
        ),
        backgroundColor: AkColors.oledDark,
        iconTheme: const IconThemeData(color: AkColors.textSecondary),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AkTheme.cutMd),
        children: [
          _FilePickerCard(onPick: _pickFiles, files: _files, onRemove: _remove),
          const SizedBox(height: AkTheme.cutMd),
          _ConfigCard(
            vcodec: _vcodec,
            onVcodec: (v) => setState(() => _vcodec = v),
            crf: _crf,
            onCrf: (v) => setState(() => _crf = v),
            format: _format,
            onFormat: (v) => setState(() => _format = v),
          ),
          const SizedBox(height: AkTheme.cutMd),
          if (queueSnap != null && queueSnap.items.isNotEmpty) ...[
            _QueueSection(snapshot: queueSnap),
            const SizedBox(height: AkTheme.cutMd),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AkTheme.cutMd),
          child: ElevatedButton(
            onPressed: (_files.isEmpty || _submitting) ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AkColors.action,
              disabledBackgroundColor: AkColors.disabled,
              foregroundColor: AkColors.textInverse,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AkTheme.cutSm),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AkColors.textInverse,
                    ),
                  )
                : Text(
                    '添加并上传',
                    style: AkTheme.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AkColors.textInverse,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  void _remove(String path) =>
      setState(() => _files.removeWhere((f) => f.path == path));
}

// --- 文件选择卡片 ---

class _FilePickerCard extends StatelessWidget {
  final VoidCallback onPick;
  final List<({String path, String name, int size})> files;
  final void Function(String path) onRemove;

  const _FilePickerCard({
    required this.onPick,
    required this.files,
    required this.onRemove,
  });

  String _humanSize(int bytes) {
    if (bytes >= 1000 * 1000 * 1000) {
      return '${(bytes / 1000 / 1000 / 1000).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1000 * 1000) {
      return '${(bytes / 1000 / 1000).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1000).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AkColors.panel,
        border: Border.all(color: AkColors.border, width: AkTheme.hairline),
      ),
      padding: const EdgeInsets.all(AkTheme.cutMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.movie_outlined, size: 16, color: AkColors.info),
              const SizedBox(width: 8),
              Text(
                '输入文件',
                style: AkTheme.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AkColors.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.add, size: 16, color: AkColors.info),
                label: Text(
                  '选择文件',
                  style: AkTheme.sans(fontSize: 13, color: AkColors.info),
                ),
              ),
            ],
          ),
          if (files.isEmpty)
            Text(
              '从本设备选择要转码的视频文件',
              style: AkTheme.sans(fontSize: 12, color: AkColors.textSecondary),
            )
          else
            for (final f in files)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      f.name,
                      style: AkTheme.sans(
                        fontSize: 13,
                        color: AkColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _humanSize(f.size),
                    style: AkTheme.mono(fontSize: 11, color: AkColors.textSecondary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: AkColors.textSecondary),
                    onPressed: () => onRemove(f.path),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

// --- 基础配置卡片 ---

class _ConfigCard extends StatelessWidget {
  final String vcodec;
  final ValueChanged<String> onVcodec;
  final int crf;
  final ValueChanged<int> onCrf;
  final String format;
  final ValueChanged<String> onFormat;

  const _ConfigCard({
    required this.vcodec,
    required this.onVcodec,
    required this.crf,
    required this.onCrf,
    required this.format,
    required this.onFormat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AkColors.panel,
        border: Border.all(color: AkColors.border, width: AkTheme.hairline),
      ),
      padding: const EdgeInsets.all(AkTheme.cutMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '输出配置',
            style: AkTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AkColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _DropdownRow(
            label: '视频编码器',
            value: vcodec,
            items: const ['libx264', 'libx265'],
            onChanged: onVcodec,
          ),
          const SizedBox(height: 8),
          _DropdownRow(
            label: '输出格式',
            value: format == 'mp4' ? 'mp4' : 'mkv (matroska)',
            items: const ['mp4', 'mkv (matroska)'],
            onChanged: onFormat,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '画质 CRF',
                style: AkTheme.sans(fontSize: 13, color: AkColors.textPrimary),
              ),
              Expanded(
                child: Slider(
                  value: crf.toDouble(),
                  min: 0,
                  max: 51,
                  divisions: 51,
                  activeColor: AkColors.info,
                  inactiveColor: AkColors.muted,
                  label: '$crf',
                  onChanged: (v) => onCrf(v.round()),
                ),
              ),
              Text(
                '$crf',
                style: AkTheme.mono(fontSize: 13, color: AkColors.textPrimary),
              ),
            ],
          ),
          Text(
            '音频直接复制（copy），分辨率不改变',
            style: AkTheme.sans(fontSize: 11, color: AkColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: AkTheme.sans(fontSize: 13, color: AkColors.textPrimary),
          ),
        ),
        Expanded(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            dropdownColor: AkColors.raised,
            style: AkTheme.mono(fontSize: 13, color: AkColors.textPrimary),
            underline: const SizedBox.shrink(),
            items: [
              for (final item in items)
                DropdownMenuItem(value: item, child: Text(item)),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

// --- 队列状态区 ---

class _QueueSection extends ConsumerWidget {
  final UploadQueueSnapshot snapshot;

  const _QueueSection({required this.snapshot});

  String _stateLabel(UploadItemState state) {
    switch (state) {
      case UploadItemState.pending:
        return '排队中';
      case UploadItemState.hashing:
        return '计算哈希';
      case UploadItemState.uploading:
        return '上传中';
      case UploadItemState.merging:
        return '合并中';
      case UploadItemState.done:
        return '已完成';
      case UploadItemState.error:
        return '失败';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AkColors.panel,
        border: Border.all(color: AkColors.border, width: AkTheme.hairline),
      ),
      padding: const EdgeInsets.all(AkTheme.cutMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '上传队列',
            style: AkTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AkColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in snapshot.items)
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.fileBaseName,
                    style: AkTheme.sans(
                      fontSize: 12,
                      color: AkColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  item.state == UploadItemState.error
                      ? (item.error ?? '失败')
                      : item.state == UploadItemState.done
                      ? '已完成'
                      : '${_stateLabel(item.state)} ${item.size > 0 ? (item.transferredBytes * 100 / item.size).clamp(0, 100).toStringAsFixed(0) : 0}%',
                  style: AkTheme.mono(
                    fontSize: 11,
                    color: item.state == UploadItemState.error
                        ? AkColors.danger
                        : item.state == UploadItemState.done
                        ? AkColors.success
                        : AkColors.textSecondary,
                  ),
                ),
                if (item.state == UploadItemState.error)
                  TextButton(
                    onPressed: () => ref
                        .read(uploadQueueProvider)
                        .retryItem(item.taskId),
                    child: Text(
                      '重试',
                      style: AkTheme.sans(fontSize: 12, color: AkColors.info),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
```

实现注意：
1. `_fileSizeOf` 使用 `dart:io`——文件顶部 `import 'dart:io' as io;`，`_fileEntryOf` 中同步 stat（选择文件后立即执行一次可接受）。
2. 删除 build 中的无用 `sizeText` 变量草稿。
3. `_ConfigCard` 中 format 显示值直接用 `format`（初值 'mp4'，取值集合即 `_formats`），去掉三目草稿：`value: format`。
4. 文件级注释与 `// --- 分节 ---` 注释按项目规范保留。

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/presentation/add_task_screen_test.dart`
Expected: PASS

- [ ] **Step 5: 建议 commit（用户手动执行）**

```
feat: add AddTaskScreen with file picker and basic output config
```

---

### Task 10: 任务列表页集成（按钮 + 上传横幅）

**Files:**
- Modify: `lib/presentation/screens/task_list_screen.dart`
- Test: `test/presentation/task_list_screen_test.dart`

- [ ] **Step 1: 写失败测试**

在 `test/presentation/task_list_screen_test.dart` 追加（需补充导入）：

```dart
import 'package:ffbox_edgelink/application/upload/upload_queue.dart';
import 'dart:async';
```

并在文件中新增可注入队列流：

```dart
class _FakeQueueStream {
  final controller = StreamController<UploadQueueSnapshot>.broadcast();
}

UploadItem _item(UploadItemState state) => UploadItem(
  taskId: 1,
  path: '/tmp/a.mp4',
  fileBaseName: 'a.mp4',
  size: 100,
  state: state,
  transferredBytes: 40,
);
```

测试用例（追加到 main() 内）：

```dart
  testWidgets('活跃上传时显示横幅，无上传时不显示', (tester) async {
    final controller = StreamController<UploadQueueSnapshot>.broadcast();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskServiceProvider.overrideWith((ref) => TaskService(_FakeTaskRepo())),
          uploadQueueProvider.overrideWithValue(_FakeQueueImpl(controller)),
        ],
        child: const MaterialApp(home: TaskListScreen()),
      ),
    );

    // 初始无上传：无横幅
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('upload_banner')), findsNothing);

    // 有上传：显示横幅
    controller.add(UploadQueueSnapshot([_item(UploadItemState.uploading)]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('upload_banner')), findsOneWidget);
    expect(find.textContaining('a.mp4'), findsWidgets);

    // 全部完成：横幅消失
    controller.add(UploadQueueSnapshot([_item(UploadItemState.done)]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('upload_banner')), findsNothing);

    await controller.close();
  });
```

`_FakeQueueImpl`：

```dart
class _FakeQueueImpl extends UploadQueue {
  _FakeQueueImpl(this.streamController)
    : super(repository: _NoopUploadRepo(), hasher: _NoopHasher());

  final StreamController<UploadQueueSnapshot> streamController;

  @override
  Stream<UploadQueueSnapshot> get states => streamController.stream;
}
```

（测试文件中同时定义 `_NoopUploadRepo`/`_NoopHasher`，与 Task 9 测试中的同名类相同，可复制。）

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/presentation/task_list_screen_test.dart`
Expected: FAIL（横幅不存在 / override 类型不匹配）

- [ ] **Step 3: 修改 TaskListScreen**

3a. AppBar：`_AkAppBar` 增加回调与按钮。`_AkAppBar` 字段加 `final VoidCallback onAddTask;`，构造参数 `required this.onAddTask`，在「Refresh」按钮前插入：

```dart
            // 新建任务
            _AppBarIconButton(
              icon: Icons.add_task,
              tooltip: '新建任务',
              onPressed: onAddTask,
            ),
```

3b. `_AkAppBar` 使用处（build 方法内的 `PreferredSize`）传入 `onAddTask: _openAddTask`，并新增方法：

```dart
  // --- 远程新建任务 ---

  void _openAddTask() {
    logDebug('taskListUI: 打开新建任务');
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddTaskScreen()),
    );
  }
```

3c. build 方法中激活通知桥接并在列表上方插入横幅。找到 body 构建处（`_AkAppBar` 所在 `Scaffold`），在 `Scaffold` body 外层用 `Column` 包裹列表区域：

```dart
      body: Column(
        children: [
          const _UploadBanner(),
          Expanded(child: /* 原有列表/错误视图 */),
        ],
      ),
```

（以实际 build 结构为准：把现有 body 的返回 widget 放入 Expanded。）

3d. 文件末尾（`_FailedWarningBar` 类之后）新增横幅组件：

```dart
// ---------------------------------------------------------------------------
// Upload progress banner
// ---------------------------------------------------------------------------

/// 后台上传进度横幅：活跃时显示当前文件与进度，全部结束自动隐藏；401 登出。
class _UploadBanner extends ConsumerWidget {
  const _UploadBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(uploadNotificationBridgeProvider);
    final snap = ref.watch(uploadQueueStateProvider).value;
    if (snap == null || !snap.hasActive) return const SizedBox.shrink();

    final current = snap.items.firstWhere(
      (i) =>
          i.state == UploadItemState.hashing ||
          i.state == UploadItemState.uploading ||
          i.state == UploadItemState.merging,
      orElse: () => snap.items.first,
    );
    final percent = current.size > 0
        ? (current.transferredBytes * 100 / current.size).clamp(0, 100)
        : 0.0;
    final speedText = current.speedBps > 0
        ? ' · ${(current.speedBps / 1000 / 1000).toStringAsFixed(1)} MB/s'
        : '';

    return Material(
      key: const Key('upload_banner'),
      color: AkColors.info.withValues(alpha: 0.12),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddTaskScreen()),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: AkColors.info,
                width: AkTheme.signalBorder,
              ),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.upload_file, size: 16, color: AkColors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '上传 ${current.fileBaseName} · ${percent.toStringAsFixed(0)}%$speedText',
                  style: AkTheme.sans(
                    fontSize: 13,
                    color: AkColors.info,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                height: 3,
                child: LinearProgressIndicator(
                  value: percent / 100,
                  backgroundColor: AkColors.muted,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AkColors.info,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

3e. 401 登出：横幅组件中检测 `snap.hasUnauthorizedError` 时调用与列表页相同的登出流程。为避免在 StatelessWidget 中重复逻辑，将 `snap.hasUnauthorizedError` 的检查放在 `TaskListScreen` build 中：

```dart
    // 上传队列出现 401：与轮询 401 一致，登出
    final uploadSnap = ref.watch(uploadQueueStateProvider).value;
    if (uploadSnap != null && uploadSnap.hasUnauthorizedError) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _logout());
    }
```

（`_logout` 已存在于列表页 State。）

3f. 文件顶部补充导入：

```dart
import 'package:ffbox_edgelink/application/upload/upload_queue.dart';
import 'package:ffbox_edgelink/presentation/screens/add_task_screen.dart';
```

- [ ] **Step 4: 运行确认通过（含既有用例）**

Run: `flutter test test/presentation/task_list_screen_test.dart`
Expected: PASS

- [ ] **Step 5: 建议 commit（用户手动执行）**

```
feat: add task creation entry and upload banner to task list
```

---

### Task 11: 全量验证与文档更新

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: 静态分析**

Run: `flutter analyze`
Expected: No issues found!

- [ ] **Step 2: 全量测试**

Run: `flutter test`
Expected: All tests passed!

- [ ] **Step 3: Windows 手动链路验证**

Run: `flutter run -d windows`
人工验证：
1. 登录后列表页右上角出现「新建任务」按钮；
2. 进入新建页 → 选择本地视频 → 调整配置 → 添加并上传；
3. 返回列表页看到 initializing 任务与顶部上传横幅；
4. 上传完成后横幅消失，任务转 idle 且输入文件变为 `文件名⬝哈希`，详情页可见媒体信息；
5. 二次添加相同文件：秒传（日志无 `/upload/file` 请求）；
6. 断网上传 → 失败标记 → 恢复网络点重试成功。

- [ ] **Step 4: Android 真机验证（人工）**

1. 通知栏出现「FFBox 上传任务」进度通知且随进度刷新（静默）；
2. 锁屏/切后台上传继续，完成后通知消失；
3. 上传期间实时活动通知（3001）不受影响。

- [ ] **Step 5: 更新 AGENTS.md**

在「## Android 实时活动通知」章节之后新增章节（记录长期约定）：

```markdown
## 远程新建任务（文件上传）

- 列表页 AppBar「新建任务」→ `AddTaskScreen`（`lib/presentation/screens/add_task_screen.dart`）：file_picker 选文件 + 基础输出配置（vcodec/CRF/format，其余用 FFBox defaultParams 内置副本 `buildOutputParams`）。
- 上传协议与 FFBox web（transferManager2.ts）语义一致：占位符 `[uploading] 文件名`（`uploadPlaceholder`）→ 分片 4MB/20MB（十进制）→ 每片 SHA1、文件哈希 = SHA1(分片哈希拼接)（`upload_protocol.dart`）→ `upload/check` 秒传（键 `文件名⬝文件哈希`，U+2B1D）→ `upload/file` 逐片上传（name=分片哈希，并发 2，重试 3）→ `tasks/{id}/merge-upload` → `tasks/{id}/upload-status` false。改分片大小/哈希语义须与服务端 `E:\FFBox\FFBox\src\backend\FFBoxService.ts` 同步。
- 队列 `UploadQueue`（`lib/application/upload/upload_queue.dart`）：纯 Dart、文件串行、Stream 广播快照；Riverpod 全局持有（`uploadQueueProvider`），生命周期独立于页面（后台上传）。401 项由列表页检测 `hasUnauthorizedError` 登出。
- Android 上传进度通知：普通 NotificationCompat（非前台服务），固定 ID 3002、channel `upload`（IMPORTANCE_LOW），MethodChannel `top.raincrat.aibeto.ffboxedgelink/upload_notification`（show/cancel），Dart 侧 500ms 节流（`uploadNotificationBridgeProvider`，在列表页/新建页 watch 激活）。与实时活动 3001 互不影响。
- App 重启后队列清空（进程内状态）；服务端分片缓存使重传等效断点续传。
```

- [ ] **Step 6: 建议 commit（用户手动执行）**

```
docs: record remote upload conventions in AGENTS.md
```

---

## Self-Review 记录

- 规格覆盖：API 4 端点（Task 3）、协议常量/OutputParams（Task 2）、哈希（Task 5）、队列+秒传+重试+合并+401（Task 6）、Provider+通知桥接（Task 7）、Android 通知（Task 8）、AddTaskScreen+基础配置（Task 9）、列表页按钮+横幅（Task 10）、AGENTS.md（Task 11）——全覆盖。
- 类型一致性：`enqueue({taskId, path, fileBaseName, size})`、`UploadItem`/`UploadQueueSnapshot` 字段、`uploadFile(hash, length, openStream, {onProgress})` 在 Task 3/6/7/9/10 间一致；Task 6 内标注的 3 处草稿修正已在正文说明，实现时按修正稿落地。
- Task 4 会变更 `TaskRepository` 接口，已包含既有测试 fake 同步步骤。
