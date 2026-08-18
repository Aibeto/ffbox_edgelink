/**
 * nodejs-project 宿主入口（Android / nodejs-mobile 常驻线程）。
 *
 * 职责：
 * 1. 准备运行环境（XDG_CONFIG_HOME / TMPDIR 指向应用私有目录）；
 * 2. 监听控制 Unix socket（nodectl.sock），接收原生侧启停指令，
 *    向其推送实时日志（JSON Lines）与运行状态；
 * 3. 以 worker_threads 拉起 / 终止 FFBox 后端（index.cjs），
 *    stdout/stderr 管道回收为日志流。
 *
 * 引擎本身常驻（保持事件循环不退出），App 进程被 kill 才随之销毁。
 */
'use strict';

const path = require('path');
const fs = require('fs');
const net = require('net');
const { Worker } = require('worker_threads');

const projectDir = __dirname; // filesDir/nodejs-project
const filesDir = path.dirname(projectDir);
const ctlPath = path.join(projectDir, 'nodectl.sock');
const indexCjs = path.join(projectDir, 'index.cjs');
const FFBOX_PORT = 33269;

// --- 环境准备 ---

process.env.XDG_CONFIG_HOME = path.join(filesDir, 'config'); // conf 包写入位置
process.env.TMPDIR = path.join(filesDir, 'cache'); // os.tmpdir() → 下载缓存等
try {
	fs.mkdirSync(process.env.XDG_CONFIG_HOME, { recursive: true });
	fs.mkdirSync(process.env.TMPDIR, { recursive: true });
} catch (_) { }

// --- 控制通道 ---

const clients = new Set();

function emit(obj) {
	const line = JSON.stringify(obj) + '\n';
	for (const c of clients) {
		try {
			c.write(line);
		} catch (_) { }
	}
}

function pushLog(line) {
	emit({ type: 'log', line });
}

function pushState(running) {
	emit({ type: 'state', running });
}

const server = net.createServer((socket) => {
	clients.add(socket);
	socket.setEncoding('utf8');
	let buffer = '';
	socket.on('data', (chunk) => {
		buffer += chunk;
		let idx;
		while ((idx = buffer.indexOf('\n')) >= 0) {
			const line = buffer.slice(0, idx).trim();
			buffer = buffer.slice(idx + 1);
			if (line) handleCommand(line, socket);
		}
	});
	socket.on('close', () => clients.delete(socket));
	socket.on('error', () => clients.delete(socket));
	// 连接建立即上报当前状态
	pushState(!!worker);
});

// 内置 ffmpeg/ffprobe 位于 nativeLibraryDir（jniLibs 解压产物
// libffmpeg.so / libffprobe.so）。filesDir 因 Android 10+ 的 W^X 限制
// 不可 exec，故不再从 assets 携带、也无需 chmod。
let ffmpegDir = projectDir; // 兜底：原生侧未传时退回项目目录

function handleCommand(line, socket) {
	let cmd;
	try {
		cmd = JSON.parse(line);
	} catch {
		return;
	}
	if (cmd.type === 'start') {
		if (cmd.nativeLibraryDir) ffmpegDir = cmd.nativeLibraryDir;
		startWorker();
	} else if (cmd.type === 'stop') {
		stopWorker();
	}
}

// --- worker 管理 ---

let worker = null;
let stopping = false;

function startWorker() {
	if (worker) {
		pushState(true);
		return;
	}
	stopping = false;
	pushLog('[host] 正在启动 FFBox 服务…');
	worker = new Worker(indexCjs, {
		argv: ['--port', String(FFBOX_PORT)],
		stdout: true,
		stderr: true,
		env: {
			...process.env,
			// nativeLibraryDir（含 libffmpeg.so/libffprobe.so），见 handleCommand
			FFMPEG_DIR: ffmpegDir,
		},
	});

	let outBuf = '';
	worker.stdout.on('data', (chunk) => {
		outBuf += chunk.toString('utf8');
		let idx;
		while ((idx = outBuf.indexOf('\n')) >= 0) {
			const line = outBuf.slice(0, idx).replace(/\r$/, '');
			outBuf = outBuf.slice(idx + 1);
			if (line) pushLog(line);
		}
	});
	let errBuf = '';
	worker.stderr.on('data', (chunk) => {
		errBuf += chunk.toString('utf8');
		let idx;
		while ((idx = errBuf.indexOf('\n')) >= 0) {
			const line = errBuf.slice(0, idx).replace(/\r$/, '');
			errBuf = errBuf.slice(idx + 1);
			if (line) pushLog('[error] ' + line);
		}
	});

	worker.on('exit', (code) => {
		worker = null;
		pushLog(`[host] FFBox 服务已退出（code=${code}）`);
		pushState(false);
	});

	pushState(true);
}

function stopWorker() {
	if (!worker) {
		pushState(false);
		return;
	}
	if (stopping) return;
	stopping = true;
	pushLog('[host] 正在停止 FFBox 服务…');
	try {
		worker.postMessage({ type: 'stop' });
	} catch (_) { }
	// 兜底：10s 后强制终止
	const w = worker;
	setTimeout(() => {
		if (w === worker && worker) {
			pushLog('[host] 优雅停止超时，强制终止');
			try {
				worker.terminate();
			} catch (_) { }
		}
	}, 10000).unref();
}

// --- 启动 ---

try {
	fs.unlinkSync(ctlPath);
} catch (_) { }

server.listen(ctlPath, () => {
	// 引擎就绪日志（原生侧连上即收到）
});

console.log('[host] nodejs-mobile 引擎已就绪');

// 常驻保活：维持事件循环，引擎不退出（App 进程被 kill 才销毁）
setInterval(() => { }, 60000);
