import { parentPort } from 'worker_threads';

/**
 * FFBox 内置服务 worker 入口（Android / nodejs-mobile）。
 *
 * 复刻 src/backend/index.ts 的启动逻辑（零改动主仓库），区别：
 * - 运行在 worker_threads 中，宿主 main.js 负责生命周期与 stdout 管道；
 * - 收到 stop 消息后先暂停全部任务（终止 ffmpeg），再退出 worker，
 *   端口随 worker 线程结束自动释放，宿主可再次拉起新 worker。
 *
 * 注意：本文件经 esbuild 打包为 CJS（index.cjs），顶级 await 与对 ESM
 * 具名导入的赋值均不允许，故用 require() 获取可变模块对象、并把初始化
 * 包进 async 自执行函数。
 */

// --- 运行环境目录（Android） ---
// 见 AGENTS.md「运行时环境目录」：nodejs-mobile 的 libuv 在 Android 上
// os.tmpdir() 恒返回 /data/local/tmp（uv__android_tmpdir 硬编码，不读 TMPDIR
// 环境变量），普通 App 不可写。宿主 main.js 已将 TMPDIR 指向应用私有目录
// filesDir/cache；此处必须在加载 FFBox 模块之前补丁 os.tmpdir()，使 FFBox 的
//   /tmp/FFBoxUploadCache   → filesDir/cache/FFBoxUploadCache
//   /tmp/FFBoxDownloadCache → filesDir/cache/FFBoxDownloadCache
// 落到可写目录。FFBox 模块（尤其 uiBridge）在模块加载时即读取 os.tmpdir()，
// 因此必须用 require() 在补丁之后加载，不能用顶部静态 import。
// 用 require 取 os.module.exports 对象（可变），补丁后 CJS 打包的 FFBox 代码
// （同样 require('os')）会命中同一对象，看到补丁后的 tmpdir。
const os = require('os');
const fs = require('fs');
const path = require('path');
const runtimeTmpdir = process.env.TMPDIR || os.tmpdir();
try {
	fs.mkdirSync(runtimeTmpdir, { recursive: true });
} catch (_) {}
os.tmpdir = () => runtimeTmpdir;

const { FFBoxService } = require('../../../FFBox/src/backend/FFBoxService');
const UIBridge = require('../../../FFBox/src/backend/uiBridge').default;
const { version } = require('../../../FFBox/src/common/constants');
const { NotificationLevel } = require('../../../FFBox/src/common/types');
const localConfig = require('../../../FFBox/src/common/localConfig').default;

let service: FFBoxService;

void (async () => {
	console.log(`FFBoxService 版本 ${version} - FFBox 内置服务（worker）`);

	// 内置 FFmpeg：宿主 main.js 通过 FFMPEG_DIR（nativeLibraryDir）传入。
	// Android 10+（targetSdk≥29）SELinux W^X 限制下，filesDir 不可 exec，
	// 二进制只能以 lib*.so 形式从 jniLibs 解压到 nativeLibraryDir。
	// customFFmpegPath 指向 ffmpeg 二进制文件本体（libffmpeg.so）；
	// FFBox 会按 dirname/ffprobe 推断 ffprobe 路径，与实际文件名
	// （libffprobe.so）不符，故在 ffmpegInfo 事件中持续修正（见下）。
	const ffmpegDir = process.env.FFMPEG_DIR;
	const builtinFFmpeg = ffmpegDir ? path.join(ffmpegDir, 'libffmpeg.so') : null;
	if (ffmpegDir && builtinFFmpeg && fs.existsSync(builtinFFmpeg)) {
		try {
			// 合并写入而非覆盖：保留用户已配置的 maxThreads/preserveUnfinishedTasks 等，
			// 否则每次启动都会把 service 配置重置为仅 customFFmpegPath
			const current = (await localConfig.get('service')) as Record<string, unknown> | undefined;
			await localConfig.set('service', { ...(current || {}), customFFmpegPath: builtinFFmpeg });
			console.log(`已设置 FFmpeg 路径: ${builtinFFmpeg}`);
		} catch (e) {
			console.error('设置 FFmpeg 路径失败', e);
		}
	} else if (ffmpegDir) {
		console.warn(`未找到内置 FFmpeg（${builtinFFmpeg}），FFBox 将使用环境 PATH 检测`);
	}

	process.on('uncaughtException', (err) => {
		console.error('发生未捕获异常，以下为错误信息');
		console.error(err);
		if (service) {
			service.setNotification(
				-1,
				'服务器发生未捕获异常。如果您发现了该异常的复现规律，欢迎向 FFBox 作者报告 issue🙇',
				NotificationLevel.error,
			);
		}
	});

	service = new FFBoxService();

	// --- ffprobe 路径修正 ---
	// FFBox 的 resolveFFmpegPaths 按「同目录 + ffprobe」推断，而 jniLibs 产物
	// 文件名为 libffprobe.so，推断结果不存在（快速帧扫描会失败）。此处监听
	// ffmpegInfo 事件（initFFmpeg 每次完成都会触发，含设置重载后的重扫）
	// 持续把 ffprobePath 修正为实际文件。
	const builtinFFprobe = ffmpegDir ? path.join(ffmpegDir, 'libffprobe.so') : null;
	if (builtinFFprobe && fs.existsSync(builtinFFprobe)) {
		const fixFFprobe = () => {
			if (service.ffprobePath !== builtinFFprobe) service.ffprobePath = builtinFFprobe;
		};
		fixFFprobe();
		service.on('ffmpegInfo', fixFFprobe);
	}

	service.on('serverError', () => {
		// 内置模式：退出 worker（端口释放），由用户重新启动
		process.exit(1);
	});
	service.on('serverClose', () => {
		process.exit(0);
	});

	UIBridge.init(service);
	UIBridge.listen();
})();

// --- 优雅停止 ---

parentPort?.on('message', async (msg: unknown) => {
	if ((msg as { type?: string })?.type !== 'stop') return;
	try {
		// 暂停全部活跃任务：FFBox 的暂停语义即终止 ffmpeg 进程并记录断点，
		// 避免 worker 退出后 ffmpeg 成为孤儿进程
		const tasks = (await service.getTaskList(0, 999999)) as Array<{
			id: number;
			status: string;
		}>;
		const activeIds = tasks
			.filter((t) => !['idle', 'finished'].includes(t.status))
			.map((t) => t.id);
		if (activeIds.length > 0) {
			await service.taskPauseBatch(activeIds);
		}
	} catch (e) {
		console.error('停止任务时出错', e);
	} finally {
		process.exit(0);
	}
});
