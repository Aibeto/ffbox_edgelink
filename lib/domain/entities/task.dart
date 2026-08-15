import 'dart:math' show min;

import 'package:ffbox_edgelink/domain/entities/task_status.dart';

// --- 输入媒体流信息 ---

/// 输入媒体流信息（before[].streams[i]）。
class TaskStreamInfo {
  /// Video / Audio。
  final String type;
  final String codec;
  final String pixelFormat;
  final String resolution;
  final int bitrate;
  final double fps;
  final int sampleRate;
  final String channel;
  final String infoText;

  const TaskStreamInfo({
    this.type = '',
    this.codec = '',
    this.pixelFormat = '',
    this.resolution = '',
    this.bitrate = 0,
    this.fps = 0,
    this.sampleRate = 0,
    this.channel = '',
    this.infoText = '',
  });

  bool get isVideo => type == 'Video';

  factory TaskStreamInfo.fromJson(dynamic json) {
    if (json is! Map) return const TaskStreamInfo();
    final codec = json['codec'] as String? ?? '';
    // resolution 可能为字符串（1920x1080）
    final resolution = json['resolution'];
    return TaskStreamInfo(
      type: json['type'] as String? ?? '',
      codec: codec,
      pixelFormat: json['pixelFormat'] as String? ?? '',
      resolution: resolution is String ? resolution : '',
      bitrate: (json['bitrate'] as num?)?.toInt() ?? 0,
      fps: (json['fps'] as num?)?.toDouble() ?? 0,
      sampleRate: (json['sampleRate'] as num?)?.toInt() ?? 0,
      channel: json['channel'] as String? ?? '',
      infoText: json['infoText'] as String? ?? '',
    );
  }
}

// --- 输入媒体信息 ---

/// 输入媒体信息（before[i]）。
class TaskInputInfo {
  final String filePath;
  final String demuxer;
  final double duration;
  final int bitrate;
  final int createTime;
  final int modifyTime;
  final List<TaskStreamInfo> streams;
  final Map<String, dynamic> metadata;

  const TaskInputInfo({
    this.filePath = '',
    this.demuxer = '',
    this.duration = 0,
    this.bitrate = 0,
    this.createTime = 0,
    this.modifyTime = 0,
    this.streams = const [],
    this.metadata = const {},
  });

  factory TaskInputInfo.fromJson(dynamic json) {
    if (json is! Map) return const TaskInputInfo();
    return TaskInputInfo(
      filePath: json['path'] as String? ?? '',
      demuxer: json['demuxer'] as String? ?? '',
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      bitrate: (json['bitrate'] as num?)?.toInt() ?? 0,
      createTime: (json['createTime'] as num?)?.toInt() ?? 0,
      modifyTime: (json['modifyTime'] as num?)?.toInt() ?? 0,
      streams: (json['streams'] as List<dynamic>? ?? const [])
          .map(TaskStreamInfo.fromJson)
          .toList(),
      metadata:
          (json['metadata'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v),
          ) ??
          const {},
    );
  }
}

// --- 转码运行信息 ---

/// 转码 run（runs[i]）。
///
/// runs[0] 通常是「媒体信息」run（idle、elapsed=0），
/// 真实转码数据在后续的活跃 run 上。
class TaskRunInfo {
  final String status;
  final double elapsed;
  final double lastStarted;
  final double lastPaused;
  final List<String> outputFiles;
  final List<String> errorInfo;

  /// progressLog 序列，元素为 [时间点, 数值]。
  /// time 的数值为媒体秒，frame 为帧数，size 为字节。
  final List<List<num>> progressTime;
  final List<List<num>> progressFrame;
  final List<List<num>> progressSize;

  /// 转码命令日志（可能很长）。
  final String cmdData;

  /// 转码命令行参数。
  final List<String> paraArray;

  // 输出配置摘要（after.outputs[0]）。
  final String vcodec;
  final String acodec;
  final String muxFormat;
  final String outputPath;
  final String hwaccel;
  final String inputFilePath;

  const TaskRunInfo({
    this.status = '',
    this.elapsed = 0,
    this.lastStarted = 0,
    this.lastPaused = 0,
    this.outputFiles = const [],
    this.errorInfo = const [],
    this.progressTime = const [],
    this.progressFrame = const [],
    this.progressSize = const [],
    this.cmdData = '',
    this.paraArray = const [],
    this.vcodec = '',
    this.acodec = '',
    this.muxFormat = '',
    this.outputPath = '',
    this.hwaccel = '',
    this.inputFilePath = '',
  });

  /// 是否为有实际转码数据的活跃 run。
  bool get isActive =>
      status.isNotEmpty &&
      status != 'idle' &&
      (elapsed > 0 || progressTime.isNotEmpty || outputFiles.isNotEmpty);

  factory TaskRunInfo.fromJson(dynamic json) {
    if (json is! Map) return const TaskRunInfo();

    // 转码命令参数
    final paraArray = (json['paraArray'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList();

    // --- 输出配置解析 ---
    var vcodec = '';
    var acodec = '';
    var muxFormat = '';
    var outputPath = '';
    var hwaccel = '';
    var inputFilePath = '';
    try {
      final after = json['after'] as Map<String, dynamic>?;
      final outputs = after?['outputs'] as List<dynamic>?;
      final output = outputs != null && outputs.isNotEmpty
          ? outputs.first as Map<String, dynamic>?
          : null;
      final video = output?['video'] as Map<String, dynamic>?;
      final audio = output?['audio'] as Map<String, dynamic>?;
      final mux = output?['mux'] as Map<String, dynamic>?;
      vcodec = video?['vcodec'] as String? ?? '';
      acodec = audio?['acodec'] as String? ?? '';
      muxFormat = mux?['format'] as String? ?? '';
      outputPath = mux?['filePath'] as String? ?? '';
      final input = after?['input'] as Map<String, dynamic>?;
      final files = input?['files'] as List<dynamic>?;
      final file = files != null && files.isNotEmpty
          ? files.first as Map
          : null;
      hwaccel = file?['hwaccel'] as String? ?? '';
      inputFilePath = file?['filePath'] as String? ?? '';
    } catch (_) {}

    return TaskRunInfo(
      status: json['status'] as String? ?? '',
      elapsed: (json['elapsed'] as num?)?.toDouble() ?? 0,
      lastStarted: (json['lastStarted'] as num?)?.toDouble() ?? 0,
      lastPaused: (json['lastPaused'] as num?)?.toDouble() ?? 0,
      outputFiles: _toStringList(json['outputFiles']),
      errorInfo: _toStringList(json['errorInfo']),
      progressTime: _toNumPairs(json['progressLog'], 'time'),
      progressFrame: _toNumPairs(json['progressLog'], 'frame'),
      progressSize: _toNumPairs(json['progressLog'], 'size'),
      cmdData: json['cmdData'] as String? ?? '',
      paraArray: paraArray,
      vcodec: vcodec,
      acodec: acodec,
      muxFormat: muxFormat,
      outputPath: outputPath,
      hwaccel: hwaccel,
      inputFilePath: inputFilePath,
    );
  }

  static List<List<num>> _toNumPairs(dynamic progressLog, String key) {
    try {
      final log = progressLog as Map<String, dynamic>?;
      final list = log?[key] as List<dynamic>?;
      if (list == null) return const [];
      return list
          .whereType<List>()
          .map((pair) => pair.whereType<num>().take(2).toList(growable: false))
          .where((pair) => pair.length == 2)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }
}

// --- 任务实体 ---

class Task {
  final int id;
  final String taskName;
  final TaskStatus status;
  final double elapsedSeconds;
  final double durationSeconds;
  final double processedSeconds;
  final List<String> errorInfo;
  final List<String> outputFiles;

  /// 输入媒体信息（before）。
  final List<TaskInputInfo> inputs;

  /// 全部转码 run。
  final List<TaskRunInfo> runs;

  const Task({
    this.id = 0,
    required this.taskName,
    required this.status,
    this.elapsedSeconds = 0,
    this.durationSeconds = 0,
    this.processedSeconds = 0,
    this.errorInfo = const [],
    this.outputFiles = const [],
    this.inputs = const [],
    this.runs = const [],
  });

  /// 进度百分比 [0.0, 1.0]，无法计算时返回 -1。
  double get progress {
    if (durationSeconds <= 0 || processedSeconds < 0) return -1;
    return min(processedSeconds / durationSeconds, 1.0);
  }

  /// 预估剩余秒数，无法计算时返回 -1。
  double get estimatedRemaining {
    if (progress <= 0 || progress >= 1 || elapsedSeconds <= 0) return -1;
    return elapsedSeconds * (1 - progress) / progress;
  }

  /// 活跃 run（有实际转码数据），无则返回 null。
  TaskRunInfo? get activeRun {
    for (final run in runs) {
      if (run.isActive) return run;
    }
    return runs.isEmpty ? null : runs.first;
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    var id = 0;
    var taskName = '';
    var status = TaskStatus.idle;
    var elapsed = 0.0;
    var duration = 0.0;
    var processed = 0.0;
    var errorInfo = const <String>[];
    var outputFiles = const <String>[];
    var inputs = const <TaskInputInfo>[];
    var runs = const <TaskRunInfo>[];

    // 基础字段
    try {
      id = (json['id'] as num?)?.toInt() ?? 0;
      taskName = json['taskName'] as String? ?? '';
      status = _parseStatus(json['status']);
    } catch (_) {}

    // before / runs 完整解析
    try {
      inputs = (json['before'] as List<dynamic>? ?? const [])
          .map(TaskInputInfo.fromJson)
          .toList();
    } catch (_) {}
    try {
      runs = (json['runs'] as List<dynamic>? ?? const [])
          .map(TaskRunInfo.fromJson)
          .toList();
    } catch (_) {}

    // 顶层摘要：优先取活跃 run 的数据（runs[0] 通常是媒体信息 run）。
    final activeRun = _pickActiveRun(
      (json['runs'] as List<dynamic>?)?.whereType<Map<String, dynamic>>(),
    );
    try {
      elapsed = _parseElapsed(activeRun);
      errorInfo = _toStringList(activeRun?['errorInfo']);
      outputFiles = _toStringList(activeRun?['outputFiles']);

      final progressLog = activeRun?['progressLog'] as Map<String, dynamic>?;
      final timeLog = progressLog?['time'] as List<dynamic>?;
      if (timeLog != null && timeLog.isNotEmpty) {
        final lastEntry = timeLog.last as List<dynamic>;
        if (lastEntry.length >= 2) {
          processed = (lastEntry[1] as num?)?.toDouble() ?? 0;
        }
      }
    } catch (_) {}

    // Input 字段（before[0].duration）
    try {
      if (inputs.isNotEmpty) duration = inputs.first.duration;
    } catch (_) {}

    return Task(
      id: id,
      taskName: taskName,
      status: status,
      elapsedSeconds: elapsed,
      durationSeconds: duration,
      processedSeconds: processed,
      errorInfo: errorInfo,
      outputFiles: outputFiles,
      inputs: inputs,
      runs: runs,
    );
  }

  static double _parseElapsed(Map<String, dynamic>? run) {
    if (run == null) return 0;
    final elapsed = run['elapsed'];
    if (elapsed is num) return elapsed.toDouble();
    return 0;
  }

  /// 从 runs 中挑选「活跃」run：优先非 idle 状态的 run，
  /// 其次是有进度/耗时数据的 run，最后回退到第一条。
  static Map<String, dynamic>? _pickActiveRun(
    Iterable<Map<String, dynamic>>? runs,
  ) {
    if (runs == null) return null;
    final parsed = runs.toList();
    if (parsed.isEmpty) return null;

    for (final run in parsed) {
      if (run['status'] is String && run['status'] != 'idle') return run;
    }
    for (final run in parsed) {
      final elapsed = run['elapsed'];
      final progressLog = run['progressLog'] as Map<String, dynamic>?;
      final timeLog = progressLog?['time'] as List<dynamic>?;
      final hasData =
          (elapsed is num && elapsed.toDouble() > 0) ||
          (timeLog != null && timeLog.isNotEmpty) ||
          run['errorInfo'] is List && (run['errorInfo'] as List).isNotEmpty ||
          run['outputFiles'] is List && (run['outputFiles'] as List).isNotEmpty;
      if (hasData) return run;
    }
    return parsed.first;
  }

  static TaskStatus _parseStatus(dynamic value) {
    if (value is String) {
      try {
        return TaskStatus.parse(value);
      } catch (_) {
        return TaskStatus.idle;
      }
    }
    if (value is num) {
      const values = TaskStatus.values;
      final index = value.toInt();
      if (index >= 0 && index < values.length) return values[index];
    }
    return TaskStatus.idle;
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }

  Task copyWith({int? id, TaskStatus? status}) => Task(
    id: id ?? this.id,
    taskName: taskName,
    status: status ?? this.status,
    elapsedSeconds: elapsedSeconds,
    durationSeconds: durationSeconds,
    processedSeconds: processedSeconds,
    errorInfo: errorInfo,
    outputFiles: outputFiles,
    inputs: inputs,
    runs: runs,
  );

  /// 格式化秒数为 mm:ss 或 hh:mm:ss。
  static String formatDuration(double seconds) {
    if (seconds <= 0) return '0:00';
    final s = seconds.toInt();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
    return '$m:${sec.toString().padLeft(2, '0')}';
  }
}
