import 'dart:io' show Platform;

import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 内置 FFBox 服务（本地 Node 引擎）MethodChannel + EventChannel 封装。
///
/// 桥接 Android 原生 LocalNodeService：启动/停止 nodejs-mobile 引擎、
/// 查询运行状态、订阅实时日志流。非 Android 平台或非 arm64-v8a ABI
/// 时 [isSupported] 为 false，调用侧应隐藏入口、不发起调用。
class LocalNodeChannel {
  static const MethodChannel _method = MethodChannel(
    'top.raincrat.aibeto.ffboxedgelink/local_node',
  );

  static const EventChannel _logs = EventChannel(
    'top.raincrat.aibeto.ffboxedgelink/local_node_logs',
  );

  /// 内置服务唯一支持的 ABI（nodejs-mobile 运行时仅打包 arm64）。
  static const String _supportedAbi = 'arm64-v8a';

  bool _abiChecked = false;
  bool _abiSupported = false;

  /// 是否支持内置服务（仅 Android 且主 ABI 为 arm64-v8a）。
  ///
  /// 需先经 [querySupported] 完成 ABI 校准，未校准前始终为 false。
  bool get isSupported {
    if (kIsWeb || !Platform.isAndroid) return false;
    return _abiChecked && _abiSupported;
  }

  /// 校准并查询当前设备是否支持内置服务（幂等）。
  ///
  /// 从原生侧读取主 ABI（Build.SUPPORTED_ABIS.first），结果缓存；
  /// 非 arm64-v8a 或查询失败返回 false。
  Future<bool> querySupported() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    if (_abiChecked) return _abiSupported;
    _abiChecked = true;
    try {
      final abi = await _method.invokeMethod<String>('abi');
      _abiSupported = abi == _supportedAbi;
      if (!_abiSupported) {
        logDebug('LocalNode: 当前 ABI=$abi，不支持内置服务（仅 $_supportedAbi）');
      }
    } catch (e) {
      logDebug('LocalNode: ABI 查询失败 $e');
      _abiSupported = false;
    }
    return _abiSupported;
  }

  /// 启动本地服务（幂等：已在运行时直接返回 true）。
  Future<bool> start() async {
    final ok = await _method.invokeMethod<bool>('startNode');
    return ok ?? false;
  }

  /// 停止本地服务：先停止全部转码任务与 ffmpeg，再终止 Node 线程。
  Future<bool> stop() async {
    final ok = await _method.invokeMethod<bool>('stopNode');
    return ok ?? false;
  }

  /// 查询本地服务是否在运行。
  Future<bool> isRunning() async {
    final running = await _method.invokeMethod<bool>('isNodeRunning');
    return running ?? false;
  }

  /// 是否已获得读取用户文件的存储权限（所有文件访问权）。
  Future<bool> hasStoragePermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    final ok = await _method.invokeMethod<bool>('hasStoragePermission');
    return ok ?? false;
  }

  /// 引导用户授予存储权限：打开系统“所有文件访问”设置页（返回即视为已发起跳转）。
  Future<bool> requestStoragePermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    final ok = await _method.invokeMethod<bool>('requestStoragePermission');
    return ok ?? false;
  }

  /// 订阅实时日志流（每行一条字符串；连接断开自动重发）。
  Stream<String> logLines() {
    return _logs.receiveBroadcastStream().map((line) => line as String);
  }
}
