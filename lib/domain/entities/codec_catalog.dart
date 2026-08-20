/// 转码配置目录领域模型：编码器/复用器/码率控制/表单参数的统一描述。
///
/// 语义对齐 FFBox web 前端 `@common/params/*`（vcodecs/acodecs/formats/
/// parameter/parser），domain 层纯 Dart，供应用层目录服务与展示层表单共用。
library;

import 'dart:math' as math;

// --- 基础选项项 ---

/// 通用下拉选项：value 为提交值，label 为显示文案。
class OptionItem {
  final String value;
  final String label;
  final String? tooltip;

  const OptionItem(this.value, this.label, [this.tooltip]);
}

// --- 表单参数（对应 web Parameter） ---

/// 参数控件模式。
enum ParamMode { text, combo, slider, switchMode }

/// 编码器详细参数定义：preset / pix_fmt / 采样率 等具体可调项。
///
/// - combo：枚举下拉（items 为候选）。
/// - slider：数值滑杆（sliderString 为 true 时按 tags 顺序取字符串值，
///   如 x264 的 ultrafast..placebo）。
/// - text：自由文本；switchMode：布尔开关。
class ParamSpec {
  /// 实际写入 OutputParams.detail 的键名（即 ffmpeg 参数名）。
  final String parameter;

  /// 表单显示标题。
  final String display;

  final String? description;

  /// 由服务端扫描得到的参数允许关闭（不写入 detail）。
  final bool optional;

  final ParamMode mode;

  /// combo 候选项。
  final List<OptionItem> items;

  /// slider 范围。
  final double? min;
  final double? max;

  /// slider 档位标签（位置 → 文案），顺序即档位顺序。
  final List<OptionItem> tags;

  /// slider 值类型：true 时 detail 存 tags 中的字符串，false 存数值。
  final bool sliderString;

  /// 默认值（数值 / 字符串 / 布尔）。
  final dynamic defaultValue;

  const ParamSpec({
    required this.parameter,
    required this.display,
    required this.mode,
    this.description,
    this.optional = false,
    this.items = const [],
    this.min,
    this.max,
    this.tags = const [],
    this.sliderString = false,
    this.defaultValue,
  });

  /// 由服务端扫描的 ffmpeg 编码器选项构建（web parseSingleOption 语义）。
  factory ParamSpec.fromEncoderOption(Map<String, dynamic> option) {
    final name = (option['name'] as String?) ?? '';
    final desc = option['description'] as String?;
    final type = (option['type'] as String?) ?? 'string';
    final defaultVal = option['default'];
    if (name.isEmpty) {
      return ParamSpec(parameter: name, display: name, mode: ParamMode.text);
    }
    if (type == 'boolean') {
      return ParamSpec(
        parameter: name,
        display: name,
        description: desc,
        optional: true,
        mode: ParamMode.switchMode,
        defaultValue: defaultVal is bool ? defaultVal : null,
      );
    }
    if (type == 'flags') {
      final options = (option['options'] as List?) ?? const [];
      return ParamSpec(
        parameter: name,
        display: name,
        description: desc,
        optional: true,
        mode: ParamMode.combo,
        items: [
          for (final o in options)
            OptionItem(
              '${o['value']}',
              '${o['value']}',
              o['description'] as String?,
            ),
        ],
        defaultValue: defaultVal,
      );
    }
    if (type == 'int' || type == 'int64' || type == 'float' || type == 'double') {
      final options = (option['options'] as List?) ?? const [];
      final min = (option['min'] as num?)?.toDouble();
      final max = (option['max'] as num?)?.toDouble();
      if (options.isNotEmpty) {
        final values = options
            .map((o) => double.tryParse('${o['value']}'))
            .whereType<double>()
            .toList();
        if (values.length == options.length && values.length >= 2) {
          final sorted = [...values]..sort();
          var equalDiff = true;
          for (var i = 1; i < values.length; i++) {
            if ((values[i] - values[i - 1]).abs() > 1) {
              equalDiff = false;
              break;
            }
          }
          final diff = (sorted.last - sorted.first).abs();
          if (equalDiff && diff >= 4 && diff <= 10) {
            return ParamSpec(
              parameter: name,
              display: name,
              description: desc,
              optional: true,
              mode: ParamMode.slider,
              min: sorted.first,
              max: sorted.last,
              tags: [
                for (final o in options)
                  OptionItem('${o['value']}', '${o['name'] ?? o['value']}'),
              ],
              defaultValue: defaultVal is num
                  ? defaultVal.toDouble()
                  : double.tryParse('$defaultVal'),
            );
          }
        }
        return ParamSpec(
          parameter: name,
          display: name,
          description: desc,
          optional: true,
          mode: ParamMode.combo,
          items: [
            for (final o in options)
              OptionItem('${o['value']}', '${o['name'] ?? o['value']}', o['description'] as String?),
          ],
          defaultValue: defaultVal,
        );
      }
      if (min != null && max != null && (max - min).abs() < 1000) {
        return ParamSpec(
          parameter: name,
          display: name,
          description: desc,
          optional: true,
          mode: ParamMode.slider,
          min: min,
          max: max,
          defaultValue: defaultVal is num
              ? defaultVal.toDouble()
              : double.tryParse('$defaultVal'),
        );
      }
      return ParamSpec(
        parameter: name,
        display: name,
        description: desc,
        optional: true,
        mode: ParamMode.text,
        defaultValue: defaultVal == null ? null : '$defaultVal',
      );
    }
    // string / dictionary / color / duration / image_size / rational 等
    return ParamSpec(
      parameter: name,
      display: name,
      description: desc,
      optional: true,
      mode: ParamMode.text,
      defaultValue: defaultVal == null ? null : '$defaultVal',
    );
  }
}

// --- 码率控制（对应 web RateControl） ---

/// 滑杆值显示转换方式。
enum RcDisplay { integer, revertInteger, bitrate }

/// 码率控制模式定义（CRF / CQP / ABR / CBR / Q / VBR …）。
///
/// 滑杆值与 detail 的互转以闭包表达，与 web 端
/// detailToSliderValue / sliderParamToDetail 一致。
class RateControlSpec {
  /// 模式标识（写入 OutputParams.video.ratecontrol）。
  final String value;

  final String label;
  final String? tooltip;

  final double min;
  final double max;

  /// 该模式涉及的 detail 参数名（切换模式时清理）。
  final List<String> paramNames;

  /// 模式默认 detail。
  final Map<String, dynamic> defaultDetail;

  /// detail → 滑杆值。
  final double? Function(Map<String, dynamic> detail)? detailToSlider;

  /// 滑杆值 → detail 增量。
  final Map<String, dynamic> Function(double sliderValue) sliderToDetail;

  /// 滑杆值显示转换。
  final RcDisplay display;

  /// bitrate 显示基数（bitrate 模式下 码率 = base * 2^值）。
  final double displayBase;

  /// 滑杆标签（位置 → 文案）。
  final List<(double, String)> tags;

  /// 构造非 const：滑杆互转闭包无法作为编译期常量。
  RateControlSpec({
    required this.value,
    required this.label,
    required this.min,
    required this.max,
    required this.paramNames,
    required this.defaultDetail,
    required this.sliderToDetail,
    this.tooltip,
    this.detailToSlider,
    this.display = RcDisplay.integer,
    this.displayBase = 0,
    this.tags = const [],
  });

  /// 滑杆值 → 显示文案。
  String formatSlider(double v) {
    switch (display) {
      case RcDisplay.revertInteger:
        return '${(max - v).round()}';
      case RcDisplay.bitrate:
        final bps = displayBase * math.pow(2, v);
        if (bps >= 1000000) {
          return '${(bps / 1000000).toStringAsFixed(bps >= 10000000 ? 0 : 1)} Mbps';
        }
        if (bps >= 1000) {
          return '${(bps / 1000).toStringAsFixed(bps >= 10000 ? 0 : 1)} Kbps';
        }
        return '${bps.round()} bps';
      case RcDisplay.integer:
        return v.round().toString();
    }
  }
}

// --- 编码器与编码族 ---

/// 单个编码器（libx264 等）：码率控制模式 + 详细参数。
class EncoderSpec {
  /// 编码器名（提交值）。
  final String name;

  /// 显示文案（缺省同 name）。
  final String? label;
  final String? tooltip;

  final List<RateControlSpec> rateControls;
  final List<ParamSpec> parameters;

  /// 需要 -strict -2 的实验性编码器。
  final bool strict2;

  const EncoderSpec({
    required this.name,
    required this.rateControls,
    required this.parameters,
    this.label,
    this.tooltip,
    this.strict2 = false,
  });
}

/// 编码族（AV1 / H.264 等分组）。
class CodecFamilySpec {
  final String label;
  final String? tooltip;
  final List<EncoderSpec> encoders;

  const CodecFamilySpec({required this.label, required this.encoders, this.tooltip});
}

// --- 复用器 ---

/// 输出容器/格式。
class MuxerSpec {
  /// 提交值（如 `mp4`、`mkv (matroska)`）。
  final String value;

  final String label;
  final String? tooltip;

  final String? defaultVideoCodec;
  final String? defaultAudioCodec;

  /// 容器自身详细参数（服务端扫描）。
  final List<ParamSpec> parameters;

  const MuxerSpec({
    required this.value,
    required this.label,
    this.tooltip,
    this.defaultVideoCodec,
    this.defaultAudioCodec,
    this.parameters = const [],
  });
}

/// 复用器分组（视频 / 音频 / 图像 等）。
class MuxerGroupSpec {
  final String label;
  final String? tooltip;
  final List<MuxerSpec> muxers;

  const MuxerGroupSpec({required this.label, required this.muxers, this.tooltip});
}

// --- 编解码目录 ---

/// 转码配置目录：内置定义 + 服务端扫描结果合并后的统一视图。
class CodecCatalog {
  /// 内置视频编码族。
  final List<CodecFamilySpec> builtinVideoFamilies;

  /// 服务端扫描视频编码族（「全部可用编码」）。
  final List<CodecFamilySpec> serverVideoFamilies;

  /// 内置音频编码族。
  final List<CodecFamilySpec> builtinAudioFamilies;

  /// 服务端扫描音频编码族。
  final List<CodecFamilySpec> serverAudioFamilies;

  /// 内置复用器分组。
  final List<MuxerGroupSpec> builtinMuxerGroups;

  /// 服务端扫描复用器（「全部可用复用器」）。
  final List<MuxerSpec> serverMuxers;

  const CodecCatalog({
    this.builtinVideoFamilies = const [],
    this.serverVideoFamilies = const [],
    this.builtinAudioFamilies = const [],
    this.serverAudioFamilies = const [],
    this.builtinMuxerGroups = const [],
    this.serverMuxers = const [],
  });

  /// 按编码器名查找（先内置后服务端），找不到返回 null。
  EncoderSpec? findVideoEncoder(String name) =>
      _findEncoder(builtinVideoFamilies, name) ??
      _findEncoder(serverVideoFamilies, name);

  /// 按编码器名查找音频编码器。
  EncoderSpec? findAudioEncoder(String name) =>
      _findEncoder(builtinAudioFamilies, name) ??
      _findEncoder(serverAudioFamilies, name);

  static EncoderSpec? _findEncoder(List<CodecFamilySpec> families, String name) {
    for (final f in families) {
      for (final e in f.encoders) {
        if (e.name == name) return e;
      }
    }
    return null;
  }

  /// 按提交值查找复用器（先内置后服务端）。
  MuxerSpec? findMuxer(String value) {
    for (final g in builtinMuxerGroups) {
      for (final m in g.muxers) {
        if (m.value == value) return m;
      }
    }
    for (final m in serverMuxers) {
      if (m.value == value) return m;
    }
    return null;
  }
}
