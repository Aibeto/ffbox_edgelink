# AGENTS.md

FFBox EdgeLink —— FFBox 视频转码服务的远程管理 App（Flutter，Web + Android/iOS + Windows 调试）。本地默认无服务端，需输入远端服务地址登录。此文件供 AI 代理每次会话参考。

## 硬性约定

- **禁止自动 Git 提交/分支操作**，全部由用户手动完成。
- 每轮结束检查本文是否需更新：只记录长期有效的架构决策、命名约定、技术选型、边界约束，不记一次性细节。
- 包名 `ffbox_edgelink`；Android/iOS ID `top.raincrat.aibeto.ffboxedgelink`；显示名 `FFBox EdgeLink`。
- 技术栈：flutter_riverpod（状态/DI）、dio（网络）、crypto（SHA256）、encrypt（AES-256-CBC 密码加密）、本地 JSON 文件存储（`server_store.json` + `session_store.json`，路径经 path_provider 的 `getApplicationSupportDirectory`，不用 SharedPreferences）、archive + file_saver（日志导出 zip）。
- 架构：domain / application / data / presentation 分层，domain 与 application 为纯 Dart，不依赖 Riverpod/Bloc。
- 后端 API 文档 `http://127.0.0.1:5500/docs/swagger.html`；参考实现 `../FFBox`。

## UI 规范（ak-ui）

- 字体：只用系统字体；所有文字样式必须经 `AkTheme.sans()`/`AkTheme.mono()`（`lib/presentation/theme/ak_theme.dart`）生成，禁止直接构造 `TextStyle` 硬编码 fontFamily；`CustomPainter` 同理；`ThemeData` 中 const 处用 `AkTheme._sansBase`。
- 色板/几何/动效：一律引用 `AkColors` 与 `AkTheme` token（信号色 info=#4AABEA/action=#F1C644/accent=#E88040；cutSm=8/cutMd=16/cutLg=24/hairline=0.5/strongLine=1/signalBorder=3；motionFast=120ms/motionBase=200ms/motionSlow=350ms），禁止硬编码色值与尺寸。

## 数据与接口约定

- 服务器配置持久化到 `server_store.json`（回填+历史），会话信息（sessionId）持久化到 `session_store.json`（免重新登录）；Windows 下位于 `%APPDATA%\top.raincrat.aibeto\FFBox EdgeLink\`；登录页回填最近记录，RECENT 列表显示 7 天内历史。旧版共用 `server_store.json` 的会话数据在首次启动时自动迁移到 `session_store.json`。
- 历史记录中的密码加密存储：Android 首次保存密码时在应用私有目录（`/data/data/<package>/files`）生成随机密钥文件 `secret.key`（32 字节 base64），用 AES-256-CBC 加密（密文带 `enc:` 前缀）；其余平台回退明文保存。加解密统一经 `SecretCipher`（`lib/core/utils/secret_cipher.dart`）。
- `GET /api/v1/tasks` 为区段接口：`offset`（0-based）、`size`（默认100）、`idOnly`（默认false）；响应 `{taskIds|tasks, totalCount}`，客户端传 `idOnly=true` 取 `taskIds`。
- 任务操作均为批量接口（`/start`、`/pause`、`/resume`、`/delete`、`/ready`、`/reset`），请求体 `{ids: [...]}`。
- Task 结构：`{id, taskName, before: InputInfo[], status, runs: Run[]}`；`elapsed/errorInfo/outputFiles` 在 Run 上，不在 Task 顶层。
- 客户端取「当前 run」必须与后端 `getCurrentRun` 语义一致：runs 数组只追加（reset 追加新 run），从**后往前**取第一条活跃态（running/paused/paused_queued/stopping/finishing/**error**）run，无则回退最新一条；禁止从前向后取第一个非 idle 的 run，否则会命中历史出错/完成的旧 run 导致状态停滞。活跃态**包含 error**：修正 error 任务后 reset 追加新 idle run，若回退到 idle run 会丢失错误信息，须保留旧 error run 直到新 run 真正运行（running 等）才被覆盖。错误信息展示：详情页 `errorInfo` 非空即显示错误卡片（标题按 `task.status == error` 区分「错误信息」/「任务历史报错」）；列表页仍按 `task.status == error` 门控。
- 写操作「查询确认」优先于盲目重试：超时后重查状态确认结果，返回三态（成功/失败/未知）。
- 网络：连接/发送/接收超时 + 幂等 GET 有限重试；错误统一经 `ApiException` 分类给友好文案，容忍单通与丢包。

## 内置 FFBox 服务（仅 Android）

- 参考设计 `../FFBox/docs/android-app-design.md`。登录页右上角入口按钮以 `Platform.isAndroid` 门控，其余平台（Windows/iOS/Web）整块隐藏；`LocalNodeChannel.isSupported` 为唯一能力开关。
- 技术方案：**nodejs-mobile v18.20.4**（libnode.so 进程内 Node 线程，arm64-v8a only）。**pkg 的 Linux ELF 二进制在 Android 上不可用**（glibc/Bionic 不兼容 + W^X 限制），后端以 esbuild 单文件 `index.cjs`（依赖全内联）经 assets 分发。
- 构建链在本仓库 `tool/build-mobile.mjs`（FFBox 主仓库零改动，esbuild 为 tool 本地 devDependency）：esbuild 打包 `tool/mobile/mobile-entry.ts`（入口复刻 index.ts，额外支持优雅停止）→ `android/app/src/main/assets/nodejs-project/`；自动下载放置 libnode.so 与 node.h（gitignore）。**CJS 兼容三件套**（vite/rolldown 均无法正确处理，勿回退）：① `utimes` native 模块 alias 为 no-op shim；② `force-cjs-entries` 插件将全部裸包名按 require 条件解析（`require.resolve`），绕过双系统包（ws/koa-body 等）exports 的 ESM 分支——其 default 导出不含 `.Server` 等挂载属性，会报 `xx is not a constructor`；③ koa-body@6 CJS 缺 `koaBody` 命名导出，onLoad 注入 `exports.koaBody = exports.default`。产物用 `node --check` + 本机 smoke test（监听 33269 返回 200）验证。
- FFmpeg 内置：`tool/build-mobile.mjs` 下载 Android arm64 静态二进制（`FFMPEG_ZIP_URL` 默认 `rhythmcache/ffmpeg-android` build-264 的 arm64-v8a 静态 Magisk 模块 zip；旧源 `nickysn/ffmpeg-android-builder` 已 404）。**该 zip 内含嵌套 `ffmpeg.tar.xz`**：脚本解外层 zip 后递归解压嵌套 tar/tar.xz/tar.gz 归档（node 不内置 xz，用系统 `tar`，Windows 自带 bsdtar 自动识别压缩格式），每次解压后删除原归档防死循环，直到找到 `ffmpeg`/`ffprobe`。**二进制必须以 `libffmpeg.so`/`libffprobe.so` 之名放入 `jniLibs/arm64-v8a/`**（勿放 assets：Android 10+ targetSdk≥29 的 SELinux W^X 限制使 untrusted_app 域**禁止 exec filesDir 等应用数据目录文件**——spawn 报 EACCES，经 spawnInvoker 映射为「启动异常」；注意 `adb shell run-as` 测试走 `runas_app` 调试域可 exec，**不能**代表 App 域行为）。安装后系统解压到 `nativeLibraryDir`（App 域内唯一可 exec 自带二进制的位置），前提是 `build.gradle.kts` 开启 `packagingOptions.jniLibs.useLegacyPackaging = true`（否则 so 压缩在 APK 内、无磁盘文件可 exec）。链路：Kotlin `buildStartCommand` 附带 `nativeLibraryDir` → `main.js` 存为 `FFMPEG_DIR` 传 worker → `mobile-entry.ts` 在创建 `FFBoxService` 前**合并**写入 `localConfig.set('service', { ..., customFFmpegPath: <nativeLibraryDir>/libffmpeg.so })`（勿覆盖已有 maxThreads/preserveUnfinishedTasks 等）；因 FFBox 按「同目录/ffprobe」推断 ffprobe 而实际文件名为 `libffprobe.so`，`mobile-entry.ts` 监听 `ffmpegInfo` 事件持续把 `service.ffprobePath` 修正为实际文件（设置重载后重扫亦会触发）。下载失败时打印警告并继续，可手动放置二进制。
- 运行时环境目录（Android）：nodejs-mobile 的 libuv 硬编码 `os.tmpdir()==/data/local/tmp`（不读 TMPDIR），普通 App 不可写。宿主 `main.js` 设 `TMPDIR=filesDir/cache`、`XDG_CONFIG_HOME=filesDir/config`；`mobile-entry.ts` 必须在加载 FFBox 模块前 `os.tmpdir=()=>TMPDIR` 补丁（FFBox「uiBridge」在模块加载即读 tmpdir，故须 require() 后加载）。因此 FFBox 代码里的 `os.tmpdir()/FFBoxUploadCache`、`os.tmpdir()/FFBoxDownloadCache` 实际创建于 `filesDir/cache/FFBoxUploadCache`、`filesDir/cache/FFBoxDownloadCache`。
- 存储权限（内置服务读用户媒体转码）：manifest 声明 `MANAGE_EXTERNAL_STORAGE`（API 30+，`tools:ignore="ScopedStorage"`）+ `READ_EXTERNAL_STORAGE`（API 23-29，`maxSdkVersion=32`）。`LocalNodeChannel.kt` 提供 `hasStoragePermission`（API 30+ 用 `Environment.isExternalStorageManager`）/`requestStoragePermission`（打开所有文件访问设置页，`ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` 缺失时回退总列表）；Dart `LocalNodeChannel` 暴露同名方法；`LocalServiceScreen` 启动服务前先检查权限，未授权弹窗引导去授权。
- 运行时分层：`main.js`（宿主，常驻：设 XDG_CONFIG_HOME/TMPDIR → 监听控制 Unix socket `filesDir/nodejs-project/nodectl.sock` → worker_threads 拉起/终止 `index.cjs`）。**引擎只启动一次且常驻**（nodejs-mobile 限制：Node 线程不可重启、process.exit 会杀整个 app 进程）；FFBox 后端跑在 worker 中，停止 = parentPort 发 stop → `taskPauseBatch` 全部活跃任务（终止 ffmpeg 防孤儿）→ `process.exit(0)`（worker 内仅结束线程，端口自动释放）→ 可再次拉起。
- 协议（JSON Lines over Unix socket）：`{type:'start'|'stop'}` 下行指令；`{type:'log',line}` / `{type:'state',running}` 上行事件。
- 内置 webUI：启动服务时随后端**同步启动** webuiServer（`webuiServer.start(33270)`，端口区分于后端默认 33269）。webuiServer 只在固定候选路径探测 `webUI/index.html`。**worker 线程内 `process.chdir()` 不受支持**（`ERR_WORKER_UNSUPPORTED_OPERATION`，勿用 chdir 方案），故利用其候选 `path.dirname(__dirname)/renderer`：worker 内 `__dirname`=解包目录 `files/nodejs-project`，`dirname`=filesDir，该项固定解析为 `filesDir/renderer`。`mobile-entry.ts` 在 start 前把 assets 分发的 `nodejs-project/webUI/` 经 `fs` **复制**到 `filesDir/renderer/`（命中该候选）再 start；`build-mobile.mjs copyAssets` 把 `service/webUI/` 整目录拷到 `assets/nodejs-project/webUI/`（运行期源）。`process.cwd()` 在 FFBox 后端仅用于 ffmpeg fallback 与 webUI 沙箱判断，与 webUI 定位无关。
- 原生侧 `LocalNodeService`（前台服务 dataSync + 通知 ID 3002）：首次启动按 `BUILD_VERSION` 解包 assets 到 filesDir；`LocalNodeChannel` 提供 MethodChannel `local_node`（startNode/stopNode/isNodeRunning）与 EventChannel `local_node_logs`（回调经 mainLooper 切主线程）。JNI 桥 `cpp/nodejni.cpp` 调 libnode 的 **`node::Start`**（C++ 符号 `_ZN4node5StartEiPPc`，CMake include 指向 `cpp/include/node`；注意 libnode.so **无** C 函数 `node_start`，写错符号名运行时直接 UnsatisfiedLinkError）。
- 原生侧启停为**阻塞式**：`LocalNodeService.requestStart/requestStop(context, timeoutSec): Boolean` 内部 sleep 轮询等待状态（默认 40s/20s，`awaitRunning`/`awaitStopped`）。**禁止在主线程直接调用**（会 ANR），一律经 `LocalNodeChannel` 的后台线程执行后经 mainHandler 回发 MethodChannel 结果。
- Dart 侧：`LocalNodeService`（application，状态机 + 500 行日志环形缓冲）、`LocalServiceScreen`（presentation）。服务默认端口 33269，登录页地址栏输入 `http://127.0.0.1:33269` 连接本机服务。
- 生命周期语义：页面切换/返回登录页不影响运行（前台服务保活）；「停止服务」按钮手动停止；App 进程被 kill 时服务随之终止。
- 已知风险：nodejs-mobile 官方 libnode.so 非 16KB page 对齐，Android 15+ 强制 16KB 的设备上可能加载失败（需自行重编译 libnode）。

## Android 实时活动通知（Live Updates）

- 详情页开关将当前任务推送为实时通知；**全局只允许一条**：单例前台服务 `LiveTaskService` + 固定通知 ID `3001`，切换任务直接替换轮询与通知。
- Android 16 (API 36) 及以上用原生 `Notification.ProgressStyle`（Live Updates，系统自动升级为状态栏/锁屏/主屏芯片）；API < 36 回退 `NotificationCompat` 普通进度通知。`LiveNotificationBuilder` 为唯一渲染入口。
- 通知布局：title=状态文案（运行/暂停 恒显示 "状态 · 百分比"，其他状态仅 0<x<100 的中间进度显示百分比，0%/100% 不显示）、contentText=任务名、subText=服务器 IP · 剩余时间；**状态文案/信号色与 App 内 `StatusBadge.labelFor`/`colorFor` 完全一致**（notify 侧 `statusText`/`statusColor`/`dotForStatus` 为唯一映射，改动须同步两侧）。右上角 smallIcon 用**形状标识**区分状态（`statusIconFor`：播放/双竖条/时钟/对勾/感叹号/圆点，颜色会被系统单色化，尤其 ColorOS）；trackerIcon（进度条）用状态色圆点（能变色）；BigTextStyle 展开显示"已用/总长/进度百分比/剩余"；按钮按状态语义显示（运行→暂停、暂停/暂停排队→继续、等待 idle→启动，其余状态不显示按钮），用户点击直接调后端 API。
- 暂停状态（paused/paused_queued）保留通知（ongoing=true）不停止前台服务；终态仅限 finished/error/deleted（不含 idle），命中后 `stopForeground(DETACH)` 保留最终通知。
- Service 收到 ACTION_PAUSE/ACTION_RESUME/ACTION_START_TASK 时直接 POST `/api/v1/tasks/{pause|resume|start}`（`{ids:[taskId]}`），不依赖 Flutter 侧参与；按钮 PendingIntent 用 `getForegroundService`（API 26+）。**禁止乐观假切换**：先真实调用后端，稍等生效后 `refreshNow()` 拉取真实状态刷新通知（通知始终反映服务器真实状态）；`config` 缺失时从 SharedPreferences 恢复并重启轮询。
- Live Updates 提升三要素（缺失则降级为普通通知）：manifest 声明 `POST_PROMOTED_NOTIFICATIONS`（非运行时权限）；经 extras `"android.requestPromotedOngoing"=true` 请求提升（compileSdk 36 无 `setRequestPromotedOngoing` API）；channel 重要性 ≥ IMPORTANCE_DEFAULT。状态栏芯片文本用 `setShortCriticalText`。
- **明文流量前提**：后端为 HTTP 明文（非 HTTPS），主 manifest 必须 `android:usesCleartextTraffic="true"`。原生 `HttpURLConnection`（轮询/按钮调用）受 Android 9+ cleartext 策略拦截，而 Dart 端走 Flutter engine 不受限——缺失该配置会导致「登录/列表正常，但通知轮询与按钮始终失败」的割裂现象。
- 原生后台轮询 `GET /api/v1/tasks/{id}`（Bearer token，2s 间隔，5s 超时），解析语义与 Dart `Task.fromJson`/`activeRun` 完全一致。
- MethodChannel 契约 `top.raincrat.aibeto.ffboxedgelink/live_activity`：`start/stop/isRunning/getActiveConfig`；启用前走 POST_NOTIFICATIONS 权限申请。
- 激活配置存 SharedPreferences（`live_activity_prefs`/`KEY_CONFIG`，Service 自持），App 重启经 `getActiveConfig` 恢复开关态；Dart 侧 `liveActivityProvider` 负责状态同步与校准（列表轮询发现任务消失时 `refresh()` 纠正）。

## 远程新建任务（文件上传）

- 列表页 AppBar「新建任务」→ `AddTaskScreen`（`lib/presentation/screens/add_task_screen.dart`）：file_picker 选文件 + 基础输出配置（vcodec/CRF/format，其余用 FFBox defaultParams 内置副本 `buildOutputParams`）。
- 上传协议与 FFBox web（transferManager2.ts）语义一致：占位符 `[uploading] 文件名`（`uploadPlaceholder`）→ 分片 4MB/20MB（十进制）→ 每片 SHA1、文件哈希 = SHA1(分片哈希拼接)（`upload_protocol.dart`）→ `upload/check` 秒传（键 `文件名⬝文件哈希`，U+2B1D）→ `upload/file` 逐片上传（name=分片哈希，并发 2，重试 3）→ `tasks/{id}/merge-upload` → `tasks/{id}/upload-status` false。改分片大小/哈希语义须与服务端 `E:\FFBox\FFBox\src\backend\FFBoxService.ts` 同步。
- 队列 `UploadQueue`（`lib/application/upload/upload_queue.dart`）：纯 Dart、文件串行、Stream 广播快照；Riverpod 全局持有（`uploadQueueProvider`），生命周期独立于页面（后台上传）。401 项由列表页检测 `hasUnauthorizedError` 登出。
- Android 上传进度通知：普通 NotificationCompat（非前台服务），固定 ID 3002、channel `upload`（IMPORTANCE_LOW），MethodChannel `top.raincrat.aibeto.ffboxedgelink/upload_notification`（show/cancel），Dart 侧 500ms 节流（`uploadNotificationBridgeProvider`，在列表页/新建页 watch 激活）。与实时活动 3001 互不影响。
- App 重启后队列清空（进程内状态）；服务端分片缓存使重传等效断点续传。

## 代码注释规范

- 每个 `.dart` 文件在 import 语句之后、第一个类/函数之前必须有文件级 `///` 文档注释，概述文件职责和在架构中的位置。
- 长文件（>100 行或包含多个类/功能块）使用 `// --- xxx ---` 分节注释划分功能区块，便于快速定位。分节注释前后各空一行。
- 分节注释统一使用中文，如 `// --- 会话恢复 ---`、`// --- 批量操作 ---`、`// --- 错误分类 ---`。
- 已有 `///` 文档注释的类/方法无需重复，只补充缺失的文件级注释和分节注释。
- 简单委托类（如 `*_impl.dart`）仅需文件级注释说明委托关系，无需分节。

## 开发约定

- 调试日志走 `kDebugMode` 门控的 `logDebug`（`lib/core/utils/log.dart`），ISO8601 时间戳格式 `[FFBox EdgeLink] <时间> <消息>`。
- 文件日志 `FileLogger`（`lib/core/utils/file_logger.dart`）：Windows 写 exe 同目录 `logs/`，Android 写缓存目录 `logs/`，其余写文档目录 `logs/`；普通日志 `app_{ts}.log`（同时输出控制台），原始数据 `raw_data_{ts}.log`（仅写文件）；测试环境写内存缓冲（上限 500 条，超出丢弃最旧）；文件写入经队列串行化；启动时清理，仅保留最新 3 套（同时间戳为一套）。
- 默认 `flutter run -d windows` 本机调试；Android 由人工真机/模拟器验证。
- 任务列表 1s 轮询（防重入、避免闪屏），设备名旁显示网络延迟（复用 listTaskIds 耗时，颜色分级）。
- 任务详情页 `TaskDetailScreen`：`GET /api/v1/tasks/{id}` 1s 轮询（防重入、保留旧数据），展示输入媒体、输出配置、遥测曲线（progressLog）、输出文件、转码日志。
- 轮询失败处理：任一非 401 刷新失败即视为连接丢失，停止轮询并显示错误 + 手动「重试」按钮（列表页错误视图 / 详情页错误横幅），点击重试后恢复 1s 轮询并立即刷新；禁止自动继续重试，避免错误/加载中每秒交替闪烁与无效请求。
- 长标题用 `MarqueeText`（`lib/presentation/widgets/marquee_text.dart`）循环滚动，不引入外部包。
- 内置本地服务（nodejs-mobile）仅 Android arm64-v8a 支持：登录页「本地服务」入口经 `localNodeSupportedProvider` 校准原生 ABI（MethodChannel `abi` → `Build.SUPPORTED_ABIS.first`）后显示；非 arm64 设备隐藏入口，`LocalNodeChannel.isSupported` 为 false，启动/停止/初始化均短路。新增支持 ABI 时须同步原生 `abi` 返回与 Dart `_supportedAbi`。
- 构建要点：`build.gradle.kts` 中 `defaultConfig.ndk` 必须 `abiFilters.clear()` 后仅限 `arm64-v8a`；`defaultConfig.externalNativeBuild.cmake.arguments` 必须包含 `-DANDROID_STL=c++_shared`（`libnode.so` 依赖 NDK C++ 运行时），否则 `System.loadLibrary("nodeext")` 因 `libc++_shared.so` 缺失抛出 `UnsatisfiedLinkError` 闪退。Kotlin 侧 `catch (Throwable)` 而非 `catch (Exception)` 以防御此类 Error 子类。

## 实施方案

- `docs/superpowers/plans/2026-08-14-ffbox-remote-management.md`
