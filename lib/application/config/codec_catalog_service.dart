/// 编码目录服务：内置定义 + 服务端扫描结果的合并与刷新。
///
/// 持有当前 [CodecCatalog]（内置编码族/复用器 + 服务端扫描条目），
/// 并提供切换编码器后的默认值重置（web appStore.checkAndApplyCodecDefaults
/// 语义）。application 层纯 Dart，不依赖 Riverpod。
library;

import 'package:ffbox_edgelink/application/config/builtin_codec_catalog.dart';
import 'package:ffbox_edgelink/application/config/codec_catalog_parser.dart';
import 'package:ffbox_edgelink/domain/entities/codec_catalog.dart';
import 'package:ffbox_edgelink/domain/repositories/codec_catalog_repository.dart';

// --- 服务 ---

/// 编码目录应用服务。
class CodecCatalogService {
  final CodecCatalogRepository _repository;

  CodecCatalogService(this._repository);

  CodecCatalog _catalog = _builtinCatalog();

  /// 当前编码目录（未拉取过服务端时仅含内置定义）。
  CodecCatalog get catalog => _catalog;

  /// 仅内置定义的目录（拉取失败回退用）。
  CodecCatalog get builtinCatalog => _builtinCatalog();

  /// 从服务器拉取扫描结果并合并进目录，返回新目录。
  Future<CodecCatalog> refresh() async {
    final json = await _repository.getCodecs();
    final server = parseServerCodecData(json);
    _catalog = CodecCatalog(
      builtinVideoFamilies: builtinVideoFamilies,
      serverVideoFamilies: server.videoFamilies,
      builtinAudioFamilies: builtinAudioFamilies,
      serverAudioFamilies: server.audioFamilies,
      builtinMuxerGroups: builtinMuxerGroups,
      serverMuxers: server.muxers,
    );
    return _catalog;
  }

  static CodecCatalog _builtinCatalog() => CodecCatalog(
        builtinVideoFamilies: builtinVideoFamilies,
        builtinAudioFamilies: builtinAudioFamilies,
        builtinMuxerGroups: builtinMuxerGroups,
      );

  // --- 编码器切换默认值 ---

  /// 切换编码器后重置码率控制与参数默认值。
  ///
  /// [section] 为输出参数的 video/audio 段
  /// （`{vcodec/acodec, resolution, ratecontrol, detail, ...}`），
  /// 就地修改：清空全部码率控制参数 → 写入非 optional 参数默认值 →
  /// 码率控制取首个非「自动」模式并应用其默认 detail；无可用模式时
  /// 移除 ratecontrol 键（web 语义：undefined 序列化时丢弃）。
  static void applyCodecDefaults(Map<String, dynamic> section, EncoderSpec encoder) {
    final detail = section['detail'] as Map<String, dynamic>? ?? {};
    section['detail'] = detail;

    // 1. 清理所有码率控制参数
    for (final rc in encoder.rateControls) {
      for (final name in rc.paramNames) {
        detail.remove(name);
      }
    }

    // 2. 非 optional 参数默认值（combo：default ?? 首项；slider：default ?? 中值）
    for (final p in encoder.parameters) {
      if (p.optional) continue;
      switch (p.mode) {
        case ParamMode.combo:
          final v = p.defaultValue ?? (p.items.isNotEmpty ? p.items.first.value : null);
          if (v != null) detail[p.parameter] = v;
          break;
        case ParamMode.slider:
          detail[p.parameter] = p.defaultValue ?? ((p.max ?? 1) + (p.min ?? 0)) / 2;
          break;
        case ParamMode.text:
        case ParamMode.switchMode:
          break;
      }
    }

    // 3. 码率控制默认值
    RateControlSpec? firstRc;
    for (final rc in encoder.rateControls) {
      if (rc.value != '自动') {
        firstRc = rc;
        break;
      }
    }
    if (firstRc != null) {
      section['ratecontrol'] = firstRc.value;
      detail.addAll(firstRc.defaultDetail);
    } else {
      section.remove('ratecontrol');
    }
  }
}
