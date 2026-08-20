/// 服务端 ffmpeg 扫描结果解析器：原始 JSON → 编码目录领域模型。
///
/// 移植自 FFBox web 前端 `@common/params/parser.ts` 的
/// parseFFmpegCodecsToCodecsList / parseFFmpegMuDeMuxersToList：
/// 内置编码器参数在前，服务端扫描选项按参数名去重后追加；
/// 内置码率控制与 strict2 语义保留。application 层纯 Dart。
library;

import 'package:ffbox_edgelink/application/config/builtin_codec_catalog.dart';
import 'package:ffbox_edgelink/domain/entities/codec_catalog.dart';

// --- 解析结果 ---

/// 一次服务端扫描解析的产物与统计（用于提示文案）。
class ServerCodecData {
  /// 服务端视频编码族（含与内置合并后的参数）。
  final List<CodecFamilySpec> videoFamilies;

  /// 服务端音频编码族。
  final List<CodecFamilySpec> audioFamilies;

  /// 服务端复用器（多扩展名的复用器已按「扩展 (复用器)」展平）。
  final List<MuxerSpec> muxers;

  /// 解复用器数量（仅统计）。
  final int demuxerCount;

  /// 滤镜数量（仅统计，滤镜功能暂未启用）。
  final int filterCount;

  const ServerCodecData({
    required this.videoFamilies,
    required this.audioFamilies,
    required this.muxers,
    required this.demuxerCount,
    required this.filterCount,
  });
}

// --- 入口 ---

/// 解析 `GET /api/v1/system/codecs` 响应。
///
/// 容错处理：结构缺失/类型异常时按空列表处理，不抛异常。
ServerCodecData parseServerCodecData(Map<String, dynamic>? json) {
  final codecs = _asMap(json?['codecs']);
  final formats = _asMap(json?['formats']);
  final video = _parseFamilies(
    _asList(codecs['video']),
    builtinVideoFamilies,
  );
  final audio = _parseFamilies(
    _asList(codecs['audio']),
    builtinAudioFamilies,
  );
  final muxers = _parseMuxers(_asList(formats['muxer']));
  return ServerCodecData(
    videoFamilies: video,
    audioFamilies: audio,
    muxers: muxers,
    demuxerCount: _asList(formats['demuxer']).length,
    filterCount: _asList(json?['filters']).length,
  );
}

// --- 编码族解析 ---

List<CodecFamilySpec> _parseFamilies(
  List<dynamic> rawFamilies,
  List<CodecFamilySpec> builtinFamilies,
) {
  final result = <CodecFamilySpec>[];
  for (final raw in rawFamilies) {
    final family = _asMap(raw);
    final name = family['name'] as String? ?? '';
    if (name.isEmpty) continue;
    final encoders = <EncoderSpec>[];
    for (final rawEncoder in _asList(family['encoders'])) {
      final e = _asMap(rawEncoder);
      final encName = e['name'] as String? ?? '';
      if (encName.isEmpty) continue;
      final builtin = _findBuiltinEncoder(builtinFamilies, encName);
      encoders.add(
        EncoderSpec(
          name: encName,
          label: builtin?.label ?? encName,
          tooltip: builtin?.tooltip,
          rateControls: builtin?.rateControls ?? const [],
          parameters: _mergeParameters(builtin?.parameters, _asList(e['options'])),
          strict2: builtin?.strict2 ?? false,
        ),
      );
    }
    if (encoders.isEmpty) continue;
    result.add(
      CodecFamilySpec(label: name, tooltip: family['description'] as String?, encoders: encoders),
    );
  }
  return result;
}

EncoderSpec? _findBuiltinEncoder(List<CodecFamilySpec> families, String name) {
  for (final f in families) {
    for (final e in f.encoders) {
      if (e.name == name) return e;
    }
  }
  return null;
}

/// 内置参数在前，扫描选项去重追加（web parser 语义）。
List<ParamSpec> _mergeParameters(List<ParamSpec>? builtin, List<dynamic> options) {
  final params = List<ParamSpec>.from(builtin ?? const []);
  final exist = params.map((p) => p.parameter).toSet();
  for (final opt in options) {
    final optMap = _asMap(opt);
    final optName = optMap['name'] as String? ?? '';
    if (optName.isEmpty || exist.contains(optName)) continue;
    params.add(ParamSpec.fromEncoderOption(optMap));
  }
  return params;
}

// --- 复用器解析 ---

List<MuxerSpec> _parseMuxers(List<dynamic> rawMuxers) {
  final result = <MuxerSpec>[];
  for (final raw in rawMuxers) {
    final m = _asMap(raw);
    final name = m['name'] as String? ?? '';
    if (name.isEmpty) continue;
    final desc = m['description'] as String? ?? '';
    final defaultVideoCodec = (m['defaultVideoCodec'] as String?)?.trim();
    final defaultAudioCodec = (m['defaultAudioCodec'] as String?)?.trim();
    final extensions = _asList(m['extensions'])
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .toList();
    final builtin = _findBuiltinMuxer(name);

    // 内置复用器无预置参数，此处仍走统一合并路径以备将来扩展
    final params = _mergeParameters(builtin?.parameters, _asList(m['options']));
    final tooltip = desc
        + (defaultVideoCodec != null && defaultVideoCodec.isNotEmpty ? '\n默认视频编码器：$defaultVideoCodec' : '')
        + (defaultAudioCodec != null && defaultAudioCodec.isNotEmpty ? '\n默认音频编码器：$defaultAudioCodec' : '');

    if (extensions.isEmpty || (extensions.length == 1 && extensions.first == name)) {
      result.add(MuxerSpec(
        value: name,
        label: name,
        tooltip: tooltip,
        defaultVideoCodec: defaultVideoCodec,
        defaultAudioCodec: defaultAudioCodec,
        parameters: params,
      ));
    } else {
      // 多扩展名复用器：每个扩展名一项，提交值「扩展 (复用器)」
      for (final ext in extensions) {
        result.add(MuxerSpec(
          value: '$ext ($name)',
          label: ext,
          tooltip: tooltip,
          defaultVideoCodec: defaultVideoCodec,
          defaultAudioCodec: defaultAudioCodec,
          parameters: params,
        ));
      }
    }
  }
  return result;
}

/// 内置复用器匹配：值全等或值形如 `X (name)` 且括号内一致（web parser 语义）。
MuxerSpec? _findBuiltinMuxer(String name) {
  final pattern = RegExp(r'^.+ \((.+)\)$');
  for (final g in builtinMuxerGroups) {
    for (final m in g.muxers) {
      if (m.value == name) return m;
      final match = pattern.firstMatch(m.value);
      if (match != null && match.group(1) == name) return m;
    }
  }
  return null;
}

// --- JSON 容错辅助 ---

Map<String, dynamic> _asMap(dynamic v) =>
    v is Map<String, dynamic> ? v : const {};

List<dynamic> _asList(dynamic v) => v is List ? v : const [];
