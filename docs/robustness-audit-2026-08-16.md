# 代码健壮性审查报告

> 审查范围：FFBox EdgeLink 全部 Dart 源码（data / domain / application / presentation / core）
> 审查日期：2026-08-16

---

## 一、严重问题（崩溃风险）

### 1.1 ApiClient 仅捕获 DioException，非 Dio 异常直接穿透

**文件**：[api_client.dart](lib/core/network/api_client.dart#L74-L89)
**修复优先级**：P0 — 真实崩溃风险

**问题**：`request` 方法只 `catch (DioException)`。[L73](lib/core/network/api_client.dart#L73) 的 `response.data as T` 泛型强转在后端返回结构变化时抛 `TypeError`，`fileLogger.logRawData` 写入异常也会直接穿透循环。调用方（presentation / service 层）普遍只捕获 `ApiException`，最终形成未处理异常。

**修复**：在 `catch (DioException e)` 之后增加通用捕获，统一包装为 `ApiException`：

```dart
} catch (e) {
  throw ApiException(
    e.toString(),
    kind: ApiErrorKind.unknown,
  );
}
```

---

## 二、中等问题（功能缺陷）

### 2.1 输出配置卡片运算符优先级可读性差

**文件**：[task_detail_screen.dart](lib/presentation/screens/task_detail_screen.dart#L545)
**修复优先级**：P2 — 行为正确，纯可读性

**问题**：

```dart
if (run == null || run.vcodec.isEmpty && run.muxFormat.isEmpty)
```

`&&` 优先级高于 `||`，实际语义为 `run == null || (vcodec.isEmpty && muxFormat.isEmpty)`——行为正确。但可读性极差，维护者极易误读。

**修复**：加括号明确意图。

```dart
if (run == null || (run.vcodec.isEmpty && run.muxFormat.isEmpty))
```

### 2.2 ready 操作确认的竞态边界：已调度为 running 时误判"未生效"

**文件**：[task_service.dart](lib/application/task/task_service.dart#L223-L232)
**修复优先级**：P2 — 窗口极小，属防御性修复

**问题**：`_tookEffect` 对 `ready` 已包含 `idleQueued` / `pausedQueued` 判定（[L227-L228](lib/application/task/task_service.dart#L227-L228)）。残留的边界场景：ready 后任务被调度器立即执行，确认时状态已变为 `running`，判定"未生效"。

**修复**：将 `running` 也视为 ready 已生效。

```dart
TaskOperation.ready =>
  status == TaskStatus.idleQueued ||
  status == TaskStatus.pausedQueued ||
  status == TaskStatus.running,  // 已被调度执行也可视为生效
```

### 2.3 操作状态消息在 refresh 失败时残留

**文件**：[task_list_screen.dart](lib/presentation/screens/task_list_screen.dart#L72)、[task_detail_screen.dart](lib/presentation/screens/task_detail_screen.dart#L78)
**修复优先级**：P2

**问题**：`_onOperation` 设置 `_statusMessage` 后 `await _refresh()`，成功路径会清空消息（列表页 [L72](lib/presentation/screens/task_list_screen.dart#L72)、详情页 [L78](lib/presentation/screens/task_detail_screen.dart#L78)）。仅当操作成功但 refresh 失败时，`_statusMessage` 保持过期提示，与 `_error` 横幅同时显示。

**修复**：在 `_onOperation` 成功分支直接清空状态消息，不依赖 refresh。

---

## 三、低风险 / 代码质量

### 3.1 `catch (_)` 静默吞异常，丢失诊断信息

**文件**：[task.dart](lib/domain/entities/task.dart#L306-L322)、[file_logger.dart](lib/core/utils/file_logger.dart#L305-L307)
**修复优先级**：P3

**问题**：`fromJson` 与 `cleanOldLogs` 中多处 `catch (_) {}` 完全忽略异常。后端返回格式变化时解析静默失败，UI 显示空数据但无任何日志。

**修复**：debug 模式下用 `logDebug` 记录被忽略的异常。

```dart
try {
  id = (json['id'] as num?)?.toInt() ?? 0;
  // ...
} catch (e) {
  logDebug('Task.fromJson: 解析基础字段失败: $e');
}
```

### 3.2 AppConfig.baseUrl 直接赋值绕过 Riverpod 响应式通知

**文件**：[auth_repository_impl.dart](lib/data/repositories/auth_repository_impl.dart#L23)
**修复优先级**：P4 — 当前无 UI 依赖其变化，风险低

**问题**：仅 `AuthRepositoryImpl.login` 直接赋值 `_config.baseUrl`，绕过 Riverpod 响应式通知。

**修复**：长期改为 Riverpod Notifier 管理配置变更；短期可不动。

### 3.3 FileLogger 并发写入缺少串行化

**文件**：[file_logger.dart](lib/core/utils/file_logger.dart#L228-L244)
**修复优先级**：P3 — 单 isolate + append 语义下损坏概率极低，属防御性优化

**问题**：`_writeToFile` 用 `FileMode.append`，高频日志场景（1s 轮询）仍建议串行化，顺带消除 `await` 竞态。

**修复**：引入写入队列串行化。

```dart
Future<void> _pendingWrites = Future.value();

Future<void> _writeToFile(File? file, String content) async {
  if (file == null) return;
  _pendingWrites = _pendingWrites.then((_) => _doWrite(file, content));
  return _pendingWrites;
}
```

### 3.4 `logRawData` headers 参数类型可收紧

**文件**：[api_client.dart](lib/core/network/api_client.dart#L70) vs [file_logger.dart](lib/core/utils/file_logger.dart#L140)
**修复优先级**：P4 — 仅类型一致性，无运行时风险

**问题**：`logRawData` 的 `headers` 声明为 `Map<String, dynamic>?`，调用处传入 `Map<String, List<String>>`。泛型协变合法，`[file_logger.dart L150-L152](lib/core/utils/file_logger.dart#L150-L152)` 仅做字符串插值，无运行时风险。仅为类型一致性不佳。

**修复**：将参数改为 `Map<String, List<String>>?`，或在调用处合并为 `Map<String, String>`。

### 3.5 LogExportService 同步读文件阻塞主 isolate

**文件**：[log_export_service.dart](lib/application/log_export/log_export_service.dart#L79)
**修复优先级**：P1 — 大文件导出时 UI 明显卡顿

**问题**：`compressToZip` 内 `file.readAsBytesSync()` 为同步 IO。`Future(() => ...)` 不创建新 isolate，回调仍在主 isolate 同步执行。大量文件 + `level: 9` 压缩会长时间占用主 isolate，UI 卡顿。

**修复**：改用 `Isolate.run`（或 compute）执行压缩，获得真正的后台 isolate 隔离。

### 3.6 `_formatTimestamp` 手动拼接可读性差

**文件**：[file_logger.dart](lib/core/utils/file_logger.dart#L39-L48)
**修复优先级**：P4

**问题**：手动拼接紧凑 ISO 8601 时间戳，未复用 `DateTime.toIso8601String()`。

**修复**：可简化为 `dt.toIso8601String()`（格式差异：含 `-`/`:` 分隔符），需确认日志解析不依赖当前无分隔符格式。

### 3.7 ExportLogsScreen 失败路径返回无二次确认

**文件**：[export_logs_screen.dart](lib/presentation/screens/export_logs_screen.dart#L159-L174)
**修复优先级**：P3

**问题**：成功时 1.5s 自动 pop；失败时用户可随时点 AppBar 返回，压缩进行中无拦截，大文件压缩耗时较长时可能误操作。

**修复**：压缩阶段用 `PopScope` 阻止返回，或提示"压缩尚未完成"。

### 3.8 FileLogger 内存缓冲区无上限

**文件**：[file_logger.dart](lib/core/utils/file_logger.dart#L23-L24)，写入点 [L109](lib/core/utils/file_logger.dart#L109) / [L124](lib/core/utils/file_logger.dart#L124) / [L161](lib/core/utils/file_logger.dart#L161) / [L194](lib/core/utils/file_logger.dart#L194) / [L220](lib/core/utils/file_logger.dart#L220)
**修复优先级**：P1 — 长期运行内存泄漏

**问题**：`_logBuffer` / `_rawDataBuffer` 在每次 `log` / `logError` / `logRawData` / `logTaskParsing` 时无条件累积，`clearBuffers` 仅标注测试辅助。生产环境 `logRawData` 写入完整响应体，1s 轮询下长期运行内存持续增长。

**修复**：缓冲区设上限（如各保留最近 N 条），生产环境到达上限后丢弃最旧条目。

---

## 四、总结

| 级别   | 编号 | 问题                             | 修复优先级 | 估算工时   |
| ------ | ---- | -------------------------------- | ---------- | ---------- |
| 严重   | 1.1  | ApiClient 非 DioException 未捕获 | **P0**     | 0.5h       |
| 中等   | 2.1  | 运算符优先级可读性差             | P2         | 0.1h       |
| 中等   | 2.2  | ready 竞态边界误判               | P2         | 0.2h       |
| 中等   | 2.3  | 状态消息 refresh 失败残留        | P2         | 0.3h       |
| 低风险 | 3.1  | catch 静默吞异常                 | P3         | 0.3h       |
| 低风险 | 3.2  | AppConfig 直接赋值               | P4         | 1h（长期） |
| 低风险 | 3.3  | FileLogger 并发写入              | P3         | 0.5h       |
| 低风险 | 3.4  | headers 参数类型可收紧           | P4         | 0.1h       |
| 低风险 | 3.5  | 同步读阻塞主 isolate             | **P1**     | 0.5h       |
| 低风险 | 3.6  | 时间戳手动拼接                   | P4         | 0.1h       |
| 低风险 | 3.7  | 导出返回无拦截                   | P3         | 0.3h       |
| 低风险 | 3.8  | 内存缓冲区无上限                 | **P1**     | 0.5h       |

**建议优先修复**：1.1（崩溃风险）、3.5（UI 卡顿）、3.8（内存泄漏）。

### 已知设计权衡（非缺陷）

- 任务列表延迟 `latencyMs` 仅统计 ID 列表接口耗时（[task_service.dart L93-L94](lib/application/task/task_service.dart#L93-L94)），不含逐条 `getTask` 详情耗时；AGENTS.md 明确此为有意设计。
