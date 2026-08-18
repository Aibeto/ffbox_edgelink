# 远程新建任务（文件上传）设计

日期：2026-08-18
状态：已确认

## 背景与目标

FFBox EdgeLink 当前只能查看/操作远端已有任务。本次新增：任务列表右上角「新建任务」按钮 → 二级页面选择本设备文件 → 分片上传到 FFBox 服务端 → 创建转码任务。上传在后台进行（可离开页面），Android 端显示实时进度通知。

实现依据：本地运行版 FFBox 源码 `E:\FFBox\FFBox`（`src/backend/uiBridge.ts`、`src/backend/FFBoxService.ts`、`src/renderer/src/logic/transferManager2.ts`、`src/renderer/src/stores/appStore.ts`）与 swagger（http://127.0.0.1:5500/docs/swagger.html）。

## 服务端协议（已从源码确认）

远程上传建任务的完整流程（与 FFBox web 前端语义一致）：

1. **创建任务**：`POST /api/v1/tasks`，body `{filePaths: ["[uploading] 文件名.ext", ...], outputParams: {...}}`，返回任务 ID 数组（每路径一个任务）。服务端按登录用户权限决定模式：无 `FileSystem` 权限 → 上传模式（`remoteTask=true`，任务置 initializing，输入走 `tmpdir/FFBoxUploadCache`）；有权限也兼容占位符流程（`mergeUploaded` 同样替换占位符）。任务名由服务端从路径计算并剥离 `[uploading] ` 前缀。
2. **分片**：文件 <1GB 用 4MB 分段，≥1GB 用 20MB。
3. **哈希**：每分片 SHA1；文件哈希 = SHA1(所有分片哈希字符串按序拼接的 UTF-8 字节)。分隔符 `⬝`（U+2B1D）。
4. **文件级秒传**：`POST /api/v1/upload/check`，body `{hashs: ["文件名⬝文件哈希"]}`，响应 `number[]`（1=已缓存）。命中则跳过上传直接合并。
5. **分片级检查**：`POST /api/v1/upload/check`，body `{hashs: [分片哈希...]}`，跳过已缓存分片。
6. **分片上传**：`POST /api/v1/upload/file`，multipart 字段 `name`=分片哈希、`file`=分片数据（服务端以 `name` 作为缓存文件名落盘）。并发 2，每片最多重试 3 次。
7. **合并**：`POST /api/v1/tasks/{id}/merge-upload`，body `{hashs: [分片哈希按序], fileBaseName, inputName: "[uploading] 文件名.ext", fileTime: {accessTime, createTime, modifyTime}}`。服务端按序合并分片、删除分片缓存、将任务输入占位符替换为 `文件名⬝文件哈希`。
8. **收尾**：`PUT /api/v1/tasks/{id}/upload-status`，body `{isUploading: false}` → 任务 initializing→idle，服务端自动扫描输入媒体信息。

默认 `OutputParams`（来自 `src/common/defaultParams.ts`）：`input.files=[{filePath 占位, demuxer:'自动'}]`、`filter={nodes:[],lines:[]}`、`outputs=[{video:{vcodec, resolution:'不改变', framerate:'不改变', ratecontrol:'CRF', detail:{crf}}, audio:{acodec:'copy', ratecontrol:'CBR', detail:{}}, mux:{format, moveflags:false, filePath:'[filedir]/[filename]_converted.[fileext]', begin:'', end:'', detail:{}}}]`、`extra:{presetName:'默认配置'}`。

## 方案（已确认：方案 A）

Dart 侧全局上传队列（Riverpod Provider，生命周期独立于页面）+ dio 分片上传 + Android 原生进度通知。新增依赖仅 `file_picker`（文件选择）；哈希用已有的 `crypto`，上传用已有的 `dio`。不做原生 HTTP 上传（避免双端重复实现），不用 workmanager（实时性差）。

## 架构与数据流

```
TaskListScreen(AppBar「+」) ──push──> AddTaskScreen
                                        │ file_picker 选文件 + 基础配置
                                        │ POST /api/v1/tasks（占位符路径数组）
                                        ▼
                          UploadQueue（Riverpod 全局）
                          文件串行 → 文件内分片并发 2
                          │ 秒传检查 → 分片上传 → merge-upload → upload-status
                          ▼
              Android 进度通知(ID 3002) + 列表页上传横幅
```

## 模块设计

### 1. API 层（`lib/data/sources/remote/ffbox_api.dart` 新增）

- `uploadCheck(List<String> hashs)` → `POST /api/v1/upload/check`，响应 `List<int>`（1=已缓存）。
- `uploadFile(String hash, int size, Stream<List<int>> data)` → `POST /api/v1/upload/file`，multipart：`name`=hash、`file`=分片流。无自动重试（由编排层控制）；支持 onSendProgress 回调。
- `mergeUpload(int taskId, {required List<String> hashs, required String fileBaseName, required String inputName, required Map<String,int> fileTime})` → `POST /api/v1/tasks/{id}/merge-upload`。
- `setUploadStatus(int taskId, bool isUploading)` → `PUT /api/v1/tasks/{id}/upload-status`。

全部经现有 `ApiClient`（Bearer 自动注入、`ApiException` 分类、原始数据日志）。

### 2. 上传编排（`lib/application/upload/upload_queue.dart`，纯 Dart + 回调通知）

- `UploadItem`：`{taskId, 本地路径, fileBaseName, inputName, size, 状态, 已传字节, 速度, 错误信息, 分片哈希缓存}`。
- 状态机：`pending → hashing → uploading → merging → done`；`error`（保留可重试）；`canceled`。
- 单文件流程：
  1. 分段（4MB/20MB）；`Isolate.run` 逐段读文件 + SHA1，内存峰值 = 1 个分片；
  2. 文件级秒传检查，命中跳到 6；
  3. 分片级检查，标记已缓存分片；
  4. 未缓存分片并发 2 上传（上传时流式重读文件段，内存峰值 = 2 个分片），每片重试 3 次；
  5. 全部完成后 `mergeUpload`（fileTime 取本地文件 stat）；
  6. `setUploadStatus(false)` → done。
- 队列调度：文件串行；单文件失败标记 error 不阻断后续；401 抛出由 UI 层登出。
- Riverpod 侧 `uploadQueueProvider`（`presentation/providers/app_providers.dart`）持有队列并桥接：状态变化通知列表页横幅与 Android 通知（500ms 节流）。

### 3. UI

- **列表页**（`lib/presentation/screens/task_list_screen.dart`）：`_AkAppBar` 刷新按钮左侧新增 `_AppBarIconButton(icon: Icons.add_task, tooltip: '新建任务')`，push `AddTaskScreen`；存在活跃/失败上传项时列表顶部显示横幅（当前文件名 · 百分比 · 速度/错误态，点击重新打开 AddTaskScreen 查看队列详情），复用 `AkColors` 信号色与 `_FailedWarningBar` 样式语言。
- **新建任务页**（`lib/presentation/screens/add_task_screen.dart`）：
  - 文件选择卡片：`file_picker` 多选（Android 用 `video/*`，桌面不过滤）；已选列表（名称/大小/移除）；
  - 基础配置三行：视频编码器（libx264/libx265，音频固定 copy）、CRF 滑条 0–51（默认 24）、输出格式（mp4 / mkv (matroska)）；其余字段用内置默认参数副本；
  - 「添加并上传」：先 `POST /api/v1/tasks`（占位符数组 → taskId 列表）→ 逐个入队 → SnackBar 提示「已开始上传，可离开页面」→ pop；
  - 页面下方展示队列实时状态（引用队列 Provider），失败项可「重试」（重新入队，服务端分片缓存生效）。
- 样式全部经 `AkTheme.sans()/mono()`、`AkColors`/`AkTheme` token，不硬编码。

### 4. Android 进度通知

- MethodChannel `top.raincrat.aibeto.ffboxedgelink/upload_notification`：`show{title, content, progress(0-100), indeterminate}` / `cancel`；Dart 侧节流 500ms，入队即显示、队列清空（全部 done/error）后 cancel。
- Kotlin 侧 `NotificationCompat` 进度通知：固定 ID 3002（与 LiveTaskService 的 3001 不冲突）、channel `upload`（IMPORTANCE_LOW 静默）、图标新增 `ic_status_upload` drawable；非 Android 平台 no-op。
- 契约封装于 `lib/core/notifications/upload_notification_channel.dart`（对齐 `live_activity_channel.dart` 模式）。

### 5. 错误处理

- 网络/超时沿用 `ApiException.friendlyMessage`；分片上传失败重试 3 次后文件标记 error；
- `mergeUpload` 前任务被删（400/任务不存在）→ 该文件标记 error（文案「任务已被删除」），不重试 merge；
- 401：与现有约定一致，由 UI 层登出；
- App 进程重启：队列清空（进程内状态）；服务端分片缓存仍在，重新上传时秒传/分片检查自动生效（等效断点续传）。

## 测试

- 单测（`test/`）：分片分段与哈希拼接语义（构造小文件对比已知 SHA1）、`OutputParams` 构造、`uploadCheck`/`uploadFile`/`mergeUpload` 请求形态（MockDio 或 fake ApiClient）、队列状态流转与失败重试。
- Widget 测试：AddTaskScreen 配置交互与提交回调、列表页横幅显隐。
- 真机（Android）：完整链路（选文件→建任务→上传→合并→idle）、通知刷新、后台锁屏上传、失败重试；Windows 调试链路（无通知）。

## 边界与非目标

- 不做完整参数编辑器（滤镜/多输出/多输入等维持 FFBox web 端能力）；
- 不做跨 App 重启的持久化断点续传（依赖服务端分片缓存即可）；
- 不做 iOS/Windows 原生通知；
- 不修改 LiveTaskService 及其实时活动逻辑。
