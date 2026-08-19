/**
 * 内置 FFBox 服务（Android）构建编排。
 *
 * 步骤：
 * 1. 确保 nodejs-mobile 运行时就位（缺失时从 GitHub Releases 下载，
 *    放置 libnode.so 到 jniLibs/arm64-v8a、头文件到 cpp/include）；
 * 2. 下载 FFmpeg Android arm64 静态二进制（ffmpeg + ffprobe），
 *    放置到 android assets/nodejs-project/；
 * 3. 用 esbuild 将后端打包为单文件 index.cjs（依赖全内联，
 *    utimes 替换为 no-op shim），输出到 android assets；
 * 4. 拷贝宿主 main.js、内置 webUI 静态资源（→ nodejs-project/renderer/）并写入 BUILD_VERSION（触发原生侧重新解包）。
 *
 * 用法：node tool/build-mobile.mjs
 * 可用环境变量：
 *   FFBOX_REPO       — 主仓库位置（默认 ../FFBox）
 *   FFMPEG_ZIP_URL   — FFmpeg Android arm64 下载地址（默认使用 nickysn/ffmpeg-android-builder）
 */
import { execFileSync } from 'child_process';
import { createWriteStream, existsSync, mkdirSync, copyFileSync, writeFileSync, statSync } from 'fs';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { pipeline } from 'stream/promises';
import { Extract } from 'unzip-stream';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');
const ffboxRoot = process.env.FFBOX_REPO || path.resolve(repoRoot, '..', 'FFBox');

const NM_VERSION = 'v18.20.4';
const NM_ZIP_URL = `https://github.com/nodejs-mobile/nodejs-mobile/releases/download/${NM_VERSION}/nodejs-mobile-${NM_VERSION}-android.zip`;
const cacheDir = path.join(repoRoot, 'build', 'nodejs-mobile');

const jniLib = path.join(repoRoot, 'android/app/src/main/jniLibs/arm64-v8a/libnode.so');
const cppInclude = path.join(repoRoot, 'android/app/src/main/cpp/include/node');
const assetsDir = path.join(repoRoot, 'android/app/src/main/assets/nodejs-project');

// FFmpeg Android arm64 静态二进制下载
// 旧源 nickysn/ffmpeg-android-builder 已失效（404），改用 rhythmcache/ffmpeg-android
// build-264 的 arm64-v8a 静态包（Magisk 模块 zip，内含 ffmpeg/ffprobe）。
const FFMPEG_DEFAULT_ZIP = 'https://github.com/rhythmcache/ffmpeg-android/releases/download/build-264/ffmpeg-8.0-ee2eb6c-Static-android-arm64-v8a.zip';
const FFMPEG_ZIP_URL = process.env.FFMPEG_ZIP_URL || FFMPEG_DEFAULT_ZIP;
const ffmpegCacheDir = path.join(repoRoot, 'build', 'ffmpeg');

function log(msg) {
	console.log(`\x1b[104;97m ${msg} \x1b[49;39m`);
}

// --- 步骤 1：nodejs-mobile 运行时 ---

async function ensureNodeRuntime() {
	if (existsSync(jniLib) && existsSync(path.join(cppInclude, 'node.h'))) {
		log('nodejs-mobile 运行时已就绪');
		return;
	}
	log(`下载 nodejs-mobile ${NM_VERSION}（Android arm64）…`);
	mkdirSync(cacheDir, { recursive: true });
	const zipPath = path.join(cacheDir, `nodejs-mobile-${NM_VERSION}-android.zip`);

	if (!existsSync(zipPath)) {
		const partPath = zipPath + '.part';
		// 优先 fetch（尊重 HTTPS_PROXY），失败时 Windows 回退 PowerShell（走系统代理）
		let ok = false;
		try {
			const res = await fetch(NM_ZIP_URL, { signal: AbortSignal.timeout(30000) });
			if (res.ok) {
				await pipeline(res.body, createWriteStream(partPath));
				ok = true;
			} else {
				console.log(`fetch HTTP ${res.status}`);
			}
		} catch (e) {
			console.log(`fetch 失败（${e.message ?? e}），回退 PowerShell 下载…`);
		}
		if (!ok && process.platform === 'win32') {
			execFileSync('powershell.exe', [
				'-NoProfile', '-Command',
				`[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; Invoke-WebRequest -Uri '${NM_ZIP_URL}' -OutFile '${partPath}' -UseBasicParsing`,
			], { stdio: 'inherit' });
			ok = true;
		}
		if (!ok) throw new Error('下载 nodejs-mobile 失败（可设置 HTTPS_PROXY 后重试）');
		fs.renameSync(partPath, zipPath);
		console.log(`已缓存 ${zipPath}`);
	}

	log('解压 libnode.so 与头文件…');
	const unpacked = path.join(cacheDir, 'unpacked');
	fs.rmSync(unpacked, { recursive: true, force: true });
	mkdirSync(unpacked, { recursive: true });
	await new Promise((resolve, reject) => {
		fs.createReadStream(zipPath)
			.pipe(Extract({ path: unpacked }))
			.on('close', resolve)
			.on('error', reject);
	});

	// 定位解压产物（目录结构随版本可能不同，按文件名搜索）
	function findFile(root, name) {
		const queue = [root];
		while (queue.length) {
			const dir = queue.shift();
			for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
				const p = path.join(dir, entry.name);
				if (entry.isDirectory()) queue.push(p);
				else if (entry.name === name) return p;
			}
		}
		return null;
	}

	const so = findFile(unpacked, 'libnode.so');
	const nodeHeader = findFile(unpacked, 'node.h');
	if (!so || !nodeHeader) throw new Error('解压产物中未找到 libnode.so / node.h');

	mkdirSync(path.dirname(jniLib), { recursive: true });
	copyFileSync(so, jniLib);
	mkdirSync(cppInclude, { recursive: true });
	// include 目录整体拷贝（node.h 及其依赖头）
	const headerDir = path.dirname(nodeHeader);
	fs.cpSync(headerDir, cppInclude, { recursive: true });
	log('libnode.so 与头文件已放置');
}

// --- 步骤 1.5：FFmpeg Android arm64 二进制 ---

// Android 10+（targetSdk≥29）SELinux W^X 限制：untrusted_app 域禁止 exec
// 应用数据目录（filesDir）内的文件。ffmpeg/ffprobe 必须以 lib*.so 形式打入
// jniLibs，安装后由系统解压到 nativeLibraryDir（该目录可执行）。
// 注意：需在 build.gradle.kts 中开启 jniLibs.useLegacyPackaging 才会解压到磁盘。
const jniLibsArm64 = path.join(repoRoot, 'android/app/src/main/jniLibs/arm64-v8a');
const _ffmpegBin = path.join(jniLibsArm64, 'libffmpeg.so');
const _ffprobeBin = path.join(jniLibsArm64, 'libffprobe.so');

async function ensureFFmpeg() {
	// 清理旧方案遗留（曾放置于 assets，App 数据目录不可 exec，已废弃）
	for (const stale of [
		path.join(assetsDir, 'ffmpeg'),
		path.join(assetsDir, 'ffprobe'),
	]) {
		if (existsSync(stale)) {
			fs.rmSync(stale, { force: true });
			log(`已清理旧位置文件 ${path.basename(stale)}（assets，已废弃）`);
		}
	}
	if (existsSync(_ffmpegBin) && existsSync(_ffprobeBin)) {
		log('FFmpeg 二进制已就绪（jniLibs/libffmpeg.so、libffprobe.so）');
		return;
	}
	log('下载 FFmpeg Android arm64 静态二进制…');
	mkdirSync(ffmpegCacheDir, { recursive: true });
	const zipName = path.basename(FFMPEG_ZIP_URL);
	const zipPath = path.join(ffmpegCacheDir, zipName);

	if (!existsSync(zipPath)) {
		// 清理残留的 .part（上次中断可能遗留并被占用）
		const partPath = zipPath + '.part';
		if (existsSync(partPath)) {
			try { fs.rmSync(partPath, { force: true }); } catch (_) { }
		}
		let ok = false;
		try {
			const res = await fetch(FFMPEG_ZIP_URL, { signal: AbortSignal.timeout(60000) });
			if (res.ok) {
				await pipeline(res.body, createWriteStream(partPath));
				ok = true;
			} else {
				console.log(`fetch HTTP ${res.status}`);
			}
		} catch (e) {
			console.log(`fetch 失败（${e.message ?? e}），回退 PowerShell 下载…`);
		}
		if (!ok && process.platform === 'win32') {
			execFileSync('powershell.exe', [
				'-NoProfile', '-Command',
				`[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; Invoke-WebRequest -Uri '${FFMPEG_ZIP_URL}' -OutFile '${partPath}' -UseBasicParsing`,
			], { stdio: 'inherit' });
			ok = true;
		}
		if (!ok) {
			console.warn('⚠ FFmpeg 下载失败，可设置 FFMPEG_ZIP_URL 指定其他源，或手动放置 libffmpeg.so/libffprobe.so 到 jniLibs/arm64-v8a/');
			return;
		}
		fs.renameSync(partPath, zipPath);
		console.log(`已缓存 ${zipPath}`);
	}

	log('解压 ffmpeg / ffprobe…');
	const unpacked = path.join(ffmpegCacheDir, 'unpacked');
	fs.rmSync(unpacked, { recursive: true, force: true });
	mkdirSync(unpacked, { recursive: true });
	await new Promise((resolve, reject) => {
		fs.createReadStream(zipPath)
			.pipe(Extract({ path: unpacked }))
			.on('close', resolve)
			.on('error', reject);
	});

	// 递归搜索 ffmpeg 与 ffprobe
	function findFile(root, name) {
		const queue = [root];
		while (queue.length) {
			const dir = queue.shift();
			for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
				const p = path.join(dir, entry.name);
				if (entry.isDirectory()) queue.push(p);
				else if (entry.name === name) return p;
			}
		}
		return null;
	}
	// 递归枚举全部文件（任意层级）
	function walkFiles(root, onFile) {
		const queue = [root];
		while (queue.length) {
			const dir = queue.shift();
			for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
				const p = path.join(dir, entry.name);
				if (entry.isDirectory()) queue.push(p);
				else onFile(p);
			}
		}
	}
	// 是否为需解压的 tar 类归档（Magisk 模块 zip 内含 ffmpeg.tar.xz）
	function isTarArchive(name) {
		return /\.(tar\.xz|tar\.gz|txz|tgz|tar|xz|gz)$/.test(name);
	}
	// 解压单个 tar/xz/gz：系统 tar（Windows 自带 bsdtar）可自动识别压缩格式
	function unTar(filePath) {
		const dest = path.join(path.dirname(filePath), path.basename(filePath) + '-x');
		mkdirSync(dest, { recursive: true });
		execFileSync('tar', ['-xf', filePath, '-C', dest]);
		return dest;
	}

	// 递归解压嵌套归档，直到再无可解压归档或已找到目标二进制。
	// 每次解压后删除原归档，避免死循环；解压失败（如非 tar 压缩）仅警告。
	while (!findFile(unpacked, 'ffmpeg') || !findFile(unpacked, 'ffprobe')) {
		const archives = [];
		walkFiles(unpacked, (p) => {
			if (isTarArchive(path.basename(p))) archives.push(p);
		});
		if (archives.length === 0) break;
		for (const a of archives) {
			try {
				log(`解压嵌套归档 ${path.basename(a)}…`);
				unTar(a);
				fs.rmSync(a, { force: true });
			} catch (e) {
				console.warn(`解压失败 ${a}（${e.message ?? e}），跳过`);
			}
		}
	}
	const ffmpegSrc = findFile(unpacked, 'ffmpeg');
	const ffprobeSrc = findFile(unpacked, 'ffprobe');
	if (!ffmpegSrc || !ffprobeSrc) {
		console.warn('⚠ 解压产物中未找到 ffmpeg/ffprobe，可手动放置到 jniLibs/arm64-v8a/（libffmpeg.so、libffprobe.so）');
		return;
	}
	mkdirSync(jniLibsArm64, { recursive: true });
	copyFileSync(ffmpegSrc, _ffmpegBin);
	copyFileSync(ffprobeSrc, _ffprobeBin);
	log('ffmpeg / ffprobe 已放置到 jniLibs/arm64-v8a/（libffmpeg.so、libffprobe.so）');
}

// --- 步骤 2：后端单文件构建（esbuild） ---

async function buildBackend() {
	log('编译 FFBox 后端（单文件 index.cjs，esbuild）…');
	// esbuild 优先取 tool 本地 devDependency（构建自包含、CI 可重现），
	// 回退主仓库；rolldown/vite 打包 CJS 依赖（iconv-lite 的 require(x)(arg)
	// 模式）存在双调用 bug，故用 esbuild
	const requireLocal = (await import('module')).createRequire(path.join(__dirname, 'package.json'));
	const requireFromFfbox = (await import('module')).createRequire(path.join(ffboxRoot, 'package.json'));
	let esbuild;
	try {
		esbuild = requireLocal('esbuild');
	} catch {
		try {
			esbuild = requireFromFfbox('esbuild');
		} catch {
			// 两处均缺失但产物已存在时跳过（如仅更新宿主脚本）
			if (existsSync(path.join(assetsDir, 'index.cjs'))) {
				log('esbuild 缺失，跳过后端构建（沿用现有 index.cjs）');
				return;
			}
			throw new Error('未找到 esbuild，请在 tool 目录执行 npm install');
		}
	}
	// 双系统包（ws/koa-body 等）的 exports import 分支（ESM）default 导出
	// 不含 CJS 挂载属性（.Server/.koaBody），interop 后运行时报 not a function。
	// 产物为 CJS，统一按 require 条件解析裸包名（require.resolve），
	// 内建模块交还 esbuild 默认处理。
	const { isBuiltin } = await import('module');
	const forceCjsEntries = {
		name: 'force-cjs-entries',
		setup(build) {
			build.onResolve({ filter: /^[^./]/ }, (args) => {
				if (args.path === 'electron' || isBuiltin(args.path)) return null;
				try {
					return { path: requireFromFfbox.resolve(args.path) };
				} catch {
					return null;
				}
			});
			// koa-body@6 的 CJS 仅导出 default，缺 koaBody 命名导出，
			// 注入别名使 `import { koaBody }` 可静态绑定
			build.onLoad({ filter: /[\\/]koa-body[\\/]lib[\\/]index\.js$/ }, (args) => {
				const contents = fs.readFileSync(args.path, 'utf8');
				return {
					contents: contents + '\nexports.koaBody = exports.default;\n',
					loader: 'js',
				};
			});
		},
	};
	await esbuild.build({
		entryPoints: [path.join(__dirname, 'mobile', 'mobile-entry.ts')],
		bundle: true,
		platform: 'node',
		format: 'cjs',
		target: 'node18',
		conditions: ['node', 'require', 'default'],
		outfile: path.join(assetsDir, 'index.cjs'),
		external: ['electron'],
		plugins: [forceCjsEntries],
		alias: {
			'@common': path.join(ffboxRoot, 'src/common'),
			'utimes': path.join(__dirname, 'mobile', 'utimes-shim.js'),
		},
		minify: true,
		sourcemap: false,
		define: {
			// constants.ts 以对象形式引用（buildInfo.isDev 等），替换为对象字面量
			buildInfo: JSON.stringify({ gitCommit: 'mobile', isDev: false }),
		},
	});
	const out = path.join(assetsDir, 'index.cjs');
	if (!existsSync(out)) throw new Error('构建产物缺失: index.cjs');
	console.log(`index.cjs ${(statSync(out).size / 1024 / 1024).toFixed(1)} MB`);
}

// --- 步骤 3：宿主与版本标记 ---

function copyAssets() {
	mkdirSync(assetsDir, { recursive: true });
	copyFileSync(path.join(__dirname, 'mobile', 'main.js'), path.join(assetsDir, 'main.js'));

	// 内置 webUI 静态资源 → nodejs-project/webUI/：webuiServer 会依次探测若干
	// 候选路径找 webUI/index.html，其中 process.cwd()/webUI 一项即 README 所述
	// 「webUI 与 FFBoxService 并排放置」语义。
	const webUiSrc = path.join(repoRoot, 'service', 'webUI');
	const webUiDst = path.join(assetsDir, 'webUI');
	if (existsSync(path.join(webUiSrc, 'index.html'))) {
		fs.rmSync(webUiDst, { recursive: true, force: true });
		fs.cpSync(webUiSrc, webUiDst, { recursive: true });
		log('webUI 静态资源已复制到 assets/nodejs-project/webUI/');
	} else {
		console.warn('⚠ 未找到 service/webUI/index.html，跳过 webUI（可后续放入 webUI/）');
	}

	writeFileSync(path.join(assetsDir, 'BUILD_VERSION'), new Date().toISOString());
	log('main.js 与 BUILD_VERSION 已写入 assets');
}

// --- 主流程 ---

await ensureNodeRuntime();
await ensureFFmpeg();
await buildBackend();
copyAssets();
log('内置服务构建完成');
