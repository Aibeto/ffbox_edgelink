# AGENTS.md

FFBox EdgeLink 项目的代理协作约定。此文件供 AI 代理在每次会话中参考。

## 核心约定

- **每轮对话结束时，检查本文件是否需要更新**：若本轮产生了新的架构决策、命名约定、技术选型、待办事项或边界约束，应更新本文件后再结束本轮。
- 保持本文件简洁，只记录长期有效的约定与关键上下文，不记录一次性细节。

## 项目概览

- 项目：FFBox EdgeLink —— FFBox 视频转码服务的远程管理 App。
- 平台：Web + Android/iOS（Flutter）。
- 本地默认无服务端，必须让用户输入远端 FFBox 服务地址后登录。

## 关键约束

- Dart 包名（`pubspec.yaml` 的 `name`）：`ffbox_edgelink`（不允许含点号）。
- Android `applicationId` / iOS Bundle ID：`top.raincrat.aibeto.ffboxedgelink`。
- 应用显示名（Android label / iOS CFBundleDisplayName / Web title）：`FFBox EdgeLink`。
- 后端 API 文档：`http://127.0.0.1:5500/docs/swagger.html`；参考实现：`../FFBox`。

## 技术选型

- 状态管理与依赖注入：flutter_riverpod。
- 网络：dio；密码哈希：crypto（SHA256）；本地存储：shared_preferences。
- 架构：分层解耦（domain / application / data / presentation），domain 与 application 为纯 Dart，不依赖 Riverpod/Bloc，以便未来切换状态管理方案。

## 开发与调试约定

- 服务器数据需持久化保存（服务器地址、用户名、会话 sessionId），登录页需回填最近使用过的地址与用户名。
- 调试日志统一走 `KDEBUGMODE` 开关（`lib/core/utils/log.dart` 的 `logDebug`），仅 `KDEBUGMODE == true` 时 `print`。
- 默认以 Windows 调试模式 exe 启动进行本机调试（`flutter run -d windows`）；项目需包含 Windows 桌面平台。
- Android 测试由人工进行（真机/模拟器手动验证），不要求自动化设备测试。
- 网络请求需配置连接/发送/接收超时，并对幂等 GET 做有限重试；错误统一经 `ApiException` 分类（超时/无法连接/未授权等）给出友好文案，容忍「单通」与丢包。
- 写操作（任务 start/pause/resume/delete 等）遵循「查询确认」优先于「盲目重试」：超时后重新查询任务状态确认真实结果，返回三态（成功/失败/未知），而非直接判失败。
- 任务列表采用定时轮询（默认 1s）刷新进度，需防重入、避免闪屏；任务列表页在设备名旁显示网络延迟（复用 `listTaskIds` 往返耗时，颜色分级），便于判断网络状况。

## 实施方案

- 完整实施计划：`docs/superpowers/plans/2026-08-14-ffbox-remote-management.md`。
