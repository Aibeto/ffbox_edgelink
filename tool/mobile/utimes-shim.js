/**
 * utimes no-op shim（Android 构建专用）。
 *
 * FFBox 后端依赖 utimes（native 模块）同步输出文件时间戳；Android 上
 * 无对应 prebuild 二进制且 nodejs-mobile 无法加载。失败场景在源码中
 * 已被 try/catch 容忍（归入 hasTimeError），此处替换为空实现。
 */
export async function utimes() {}
