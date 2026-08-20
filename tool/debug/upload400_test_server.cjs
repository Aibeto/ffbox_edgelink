/**
 * 上传 400 问题复现服务器：复刻 FFBox uiBridge.ts 的 koa-body 中间件配置与上传相关路由。
 * 用法：node tool/debug/upload400_test_server.cjs [port]（默认 33269）
 */
'use strict';
const path = require('path');
const fs = require('fs');
const os = require('os');
const Koa = require(path.resolve('e:/FFBox/FFBox/node_modules/koa'));
const Router = require(path.resolve('e:/FFBox/FFBox/node_modules/koa-router'));
const koaBodyModule = require(path.resolve('e:/FFBox/FFBox/node_modules/koa-body'));
const koaBody = koaBodyModule.default || koaBodyModule;

const port = +(process.argv[2] || 33269);
const uploadDir = os.tmpdir() + '/FFBoxUploadCache';
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });

const koa = new Koa();
const router = new Router();

koa.use(async (ctx, next) => {
	ctx.response.set('Access-Control-Allow-Origin', '*');
	ctx.response.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
	ctx.response.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
	if (ctx.request.method === 'OPTIONS') { ctx.response.status = 204; return; }
	try { await next(); } catch (err) { console.log(err); ctx.status = 500; ctx.body = { error: 'Internal Server Error' }; }
});

// 与 uiBridge.ts 完全一致的请求体解析中间件
koa.use(async (ctx, next) => {
	try {
		await koaBody({
			multipart: true,
			formidable: {
				maxFileSize: 1024 ** 4,
				uploadDir,
			},
		})(ctx, next);
	} catch (err) {
		console.log('[400 复现] 请求体解析失败:', err.message, err.code || '', ctx.request.url);
		console.log('[400 复现] content-type:', ctx.request.headers['content-type'], 'content-length:', ctx.request.headers['content-length']);
		ctx.status = 400;
		ctx.body = { error: 'Request body is invalid data' };
	}
});

router.post('/api/v1/tasks', async (ctx) => {
	if (!ctx.request.body) { ctx.status = 400; ctx.body = { error: 'Missing request body' }; return; }
	const { outputParams, filePaths } = ctx.request.body;
	if (!Array.isArray(filePaths) || !filePaths.every((p) => typeof p === 'string')) { ctx.status = 400; ctx.body = { error: 'filePaths must be an array of strings' }; return; }
	if (!outputParams || typeof outputParams !== 'object') { ctx.status = 400; ctx.body = { error: 'outputParams is required' }; return; }
	ctx.body = [1, 2];
});

router.post('/api/v1/upload/check', async (ctx) => {
	if (!ctx.request.body || !(ctx.request.body.hashs instanceof Array)) { ctx.status = 400; ctx.body = { error: 'Invalid request' }; return; }
	const hashs = ctx.request.body.hashs;
	const ret = hashs.map((hash) => (fs.existsSync(uploadDir + '/' + hash) ? 1 : 0));
	ctx.body = ret;
});

router.post('/api/v1/upload/file', async (ctx) => {
	if (!ctx.request.files || !ctx.request.files.file) { ctx.status = 400; ctx.body = { error: 'Missing file' }; return; }
	const file = ctx.request.files.file;
	const body = ctx.request.body;
	console.log('[upload/file] 收到文件 originalFilename=', file.originalFilename, 'name=', body.name);
	const destPath = uploadDir + '/' + body.name;
	try {
		fs.renameSync(file.filepath, destPath);
		ctx.body = { success: true };
	} catch (error) {
		console.log('[upload/file] 重命名失败', error);
		ctx.status = 500;
		ctx.body = { error: 'Failed to save file' };
	}
});

router.post('/api/v1/tasks/:id/merge-upload', async (ctx) => {
	if (!ctx.request.body) { ctx.status = 400; ctx.body = { error: 'Missing request body' }; return; }
	const { hashs, fileBaseName, inputName, fileTime } = ctx.request.body;
	console.log('[merge-upload] hashs.length=', hashs && hashs.length, 'fileBaseName=', fileBaseName, 'inputName=', inputName, 'fileTime=', JSON.stringify(fileTime));
	ctx.body = { success: true };
});

router.put('/api/v1/tasks/:id/upload-status', async (ctx) => {
	if (!ctx.request.body) { ctx.status = 400; ctx.body = { error: 'Missing request body' }; return; }
	console.log('[upload-status] body=', JSON.stringify(ctx.request.body));
	ctx.body = { success: true };
});

koa.use(router.routes());
koa.listen(port, () => console.log(`测试服务器监听 http://127.0.0.1:${port}`));
