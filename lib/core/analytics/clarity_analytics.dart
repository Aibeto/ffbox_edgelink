/// Clarity 埋点门面：按编译目标条件导出实现。
///
/// clarity_flutter SDK 依赖 dart:io 且仅提供 Android/iOS 原生插件，
/// 直接 import 会破坏 Web 构建，故用条件导出隔离：
/// - 原生平台（dart.library.io 可用）→ [clarity_analytics_io.dart] 真实现；
/// - Web → [clarity_analytics_stub.dart] 全量 no-op 桩。
///
/// 业务代码统一 `import .../clarity_analytics.dart`，无需感知平台差异。
library;
export 'clarity_analytics_stub.dart'
    if (dart.library.io) 'clarity_analytics_io.dart';
