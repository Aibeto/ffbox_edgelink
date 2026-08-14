# AGENTS.md

FFBox EdgeLink —— FFBox 视频转码服务的远程管理 App（Flutter，Web + Android/iOS + Windows 调试）。本地默认无服务端，需输入远端服务地址登录。此文件供 AI 代理每次会话参考。

## 硬性约定

- **禁止自动 Git 提交/分支操作**，全部由用户手动完成。
- 每轮结束检查本文是否需更新：只记录长期有效的架构决策、命名约定、技术选型、边界约束，不记一次性细节。
- 包名 `ffbox_edgelink`；Android/iOS ID `top.raincrat.aibeto.ffboxedgelink`；显示名 `FFBox EdgeLink`。
- 技术栈：flutter_riverpod（状态/DI）、dio（网络）、crypto（SHA256）、shared_preferences（存储）。
- 架构：domain / application / data / presentation 分层，domain 与 application 为纯 Dart，不依赖 Riverpod/Bloc。
- 后端 API 文档 `http://127.0.0.1:5500/docs/swagger.html`；参考实现 `../FFBox`。

## UI 规范（ak-ui）

- 字体：只用系统字体；所有文字样式必须经 `AkTheme.sans()`/`AkTheme.mono()`（`lib/presentation/theme/ak_theme.dart`）生成，禁止直接构造 `TextStyle` 硬编码 fontFamily；`CustomPainter` 同理；`ThemeData` 中 const 处用 `AkTheme._sansBase`。
- 色板/几何/动效：一律引用 `AkColors` 与 `AkTheme` token（信号色 info=#4AABEA/action=#F1C644/accent=#E88040；cutSm=4/cutMd=8/cutLg=12/hairline=0.5/strongLine=1/signalBorder=3；motionFast=120ms/motionBase=200ms/motionSlow=350ms），禁止硬编码色值与尺寸。

## 数据与接口约定

- 服务器地址/用户名/sessionId 持久化；登录页回填最近记录。
- `GET /api/v1/tasks` 为区段接口：`offset`（0-based）、`size`（默认100）、`idOnly`（默认false）；响应 `{taskIds|tasks, totalCount}`，客户端传 `idOnly=true` 取 `taskIds`。
- 任务操作均为批量接口（`/start`、`/pause`、`/resume`、`/delete`、`/ready`、`/reset`），请求体 `{ids: [...]}`。
- Task 结构：`{id, taskName, before: InputInfo[], status, runs: Run[]}`；`elapsed/errorInfo/outputFiles` 在 Run 上，不在 Task 顶层。
- 写操作「查询确认」优先于盲目重试：超时后重查状态确认结果，返回三态（成功/失败/未知）。
- 网络：连接/发送/接收超时 + 幂等 GET 有限重试；错误统一经 `ApiException` 分类给友好文案，容忍单通与丢包。

## 开发约定

- 调试日志走 `kDebugMode` 门控的 `logDebug`（`lib/core/utils/log.dart`），ISO8601 时间戳格式 `[FFBox EdgeLink] <时间> <消息>`。
- 文件日志 `FileLogger`（`lib/core/utils/file_logger.dart`）：Windows 写 exe 同目录 `logs/`，Android 写缓存目录 `logs/`，其余写文档目录 `logs/`；普通日志 `app_{ts}.log`（同时输出控制台），原始数据 `raw_data_{ts}.log`（仅写文件）；测试环境写内存缓冲；启动时清理，仅保留最新 5 套（同时间戳为一套）。
- 默认 `flutter run -d windows` 本机调试；Android 由人工真机/模拟器验证。
- 任务列表 1s 轮询（防重入、避免闪屏），设备名旁显示网络延迟（复用 listTaskIds 耗时，颜色分级）。
- 任务详情页 `TaskDetailScreen`：`GET /api/v1/tasks/{id}` 1s 轮询（防重入、保留旧数据），展示输入媒体、输出配置、遥测曲线（progressLog）、输出文件、转码日志。
- 长标题用 `MarqueeText`（`lib/presentation/widgets/marquee_text.dart`）循环滚动，不引入外部包。

## 实施方案

- `docs/superpowers/plans/2026-08-14-ffbox-remote-management.md`
