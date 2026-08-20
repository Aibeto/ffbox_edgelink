/// 输出参数表单：视频/音频/输出三段转码配置的动态渲染。
///
/// presentation 层组件：watch codecCatalogProvider 获取「内置 + 服务端
/// 扫描」合并目录；编码器/复用器经分组底部弹层选取；码率控制与详细参数
/// 的交互语义对齐 FFBox web 前端 ParaBox（VcodecView/AcodecView/MuxView
/// 与 appStore.checkAndApplyCodecDefaults：切换编码器重置默认值、切换码率
/// 控制清理旧参数写入新默认）。参数帮助对齐 web 悬停 tooltip 语义，因触屏
/// 无悬停，统一以行尾「?」按钮（_HelpButton）点击弹出底部说明层承载。
/// 提交值经 videoSection/audioSection/muxSection 暴露给宿主页面（新建任务页）。
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/application/config/builtin_codec_catalog.dart';
import 'package:ffbox_edgelink/application/config/codec_catalog_service.dart';
import 'package:ffbox_edgelink/application/local_node/local_output_service.dart';
import 'package:ffbox_edgelink/domain/entities/codec_catalog.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';

// --- 特殊编码器提交值 ---

/// 视频与音频编码选择中共有的特殊值（非具体编码器）。
const Set<String> _specialCodecs = {'禁用', 'copy', '自动'};

/// 常规（远程服务器）模式的默认输出文件名模板。
const String _defaultFilePathTemplate =
    '[filedir]/[filename]_converted.[fileext]';

/// 文件时间保留特性说明（对齐 web MuxView 标题 tooltip）。
const String _keepFileTimeHelp = 'FFBox 特色功能，对产出文件进行文件时间修改。对远程服务器任务暂不生效';

// --- 表单组件 ---

/// 输出参数表单：单一卡片内分「视频 / 音频 / 输出」三节。
class OutputParamsForm extends ConsumerStatefulWidget {
  const OutputParamsForm({super.key});

  @override
  ConsumerState<OutputParamsForm> createState() => OutputParamsFormState();
}

class OutputParamsFormState extends ConsumerState<OutputParamsForm> {
  late final Map<String, dynamic> _video;
  late final Map<String, dynamic> _audio;
  late final Map<String, dynamic> _mux;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _video = {
      'vcodec': 'libx265',
      'resolution': '不改变',
      'framerate': '不改变',
      'detail': <String, dynamic>{},
    };
    _audio = {'acodec': 'copy', 'detail': <String, dynamic>{}};
    _mux = {
      'format': 'mp4',
      'moveflags': false,
      'filePath': _defaultFilePathTemplate,
      'begin': '',
      'end': '',
      'detail': <String, dynamic>{},
    };
    // 内置目录立即可用：先落默认值，服务端扫描到达后仅扩充可选项
    final encoder = ref
        .read(codecCatalogServiceProvider)
        .builtinCatalog
        .findVideoEncoder('libx265');
    if (encoder != null) {
      CodecCatalogService.applyCodecDefaults(_video, encoder);
    }
    // Android 本机回环（内置服务）：输出默认写入应用缓存目录
    // FFBoxOutput（可在任务详情页导出），异步解析后替换模板
    if (Platform.isAndroid &&
        LocalOutputService.isLoopbackUrl(
          ref.read(appConfigProvider).normalizedBaseUrl,
        )) {
      _applyLocalOutputTemplate();
    }
  }

  /// 将默认输出模板替换为本地缓存目录绝对路径（用户已手动改动时不覆盖）。
  Future<void> _applyLocalOutputTemplate() async {
    try {
      final template = await ref
          .read(localOutputServiceProvider)
          .localOutputTemplate();
      if (!mounted || _mux['filePath'] != _defaultFilePathTemplate) return;
      setState(() {
        _mux['filePath'] = template;
        _controllers['mux.filePath']?.text = template;
      });
    } catch (_) {
      // 路径解析失败保持常规模板
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // --- 提交值 ---

  /// 输出参数 video 段（引用，宿主在提交时读取）。
  Map<String, dynamic> get videoSection => _video;

  /// 输出参数 audio 段。
  Map<String, dynamic> get audioSection => _audio;

  /// 输出参数 mux 段。
  Map<String, dynamic> get muxSection => _mux;

  Map<String, dynamic> _detailOf(Map<String, dynamic> section) =>
      section['detail'] as Map<String, dynamic>;

  TextEditingController _controllerFor(String key, String initial) =>
      _controllers.putIfAbsent(key, () => TextEditingController(text: initial));

  // --- 构建 ---

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(codecCatalogProvider);
    final catalog =
        catalogAsync.value ??
        ref.read(codecCatalogServiceProvider).builtinCatalog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 目录状态头：标题 + 服务端扫描中指示 + 手动刷新
        Row(
          children: [
            const Icon(Icons.tune_outlined, size: 16, color: AkColors.info),
            const SizedBox(width: 8),
            Text(
              '输出配置',
              style: AkTheme.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AkColors.textPrimary,
              ),
            ),
            if (catalogAsync.isLoading) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            ],
            const Spacer(),
            IconButton(
              icon: const Icon(
                Icons.refresh,
                size: 16,
                color: AkColors.textSecondary,
              ),
              tooltip: '从服务器刷新配置',
              onPressed: () => ref.invalidate(codecCatalogProvider),
            ),
          ],
        ),
        _videoSection(catalog),
        const SizedBox(height: AkTheme.cutMd),
        _audioSection(catalog),
        const SizedBox(height: AkTheme.cutMd),
        _muxSection(catalog),
      ],
    );
  }

  // --- 分节卡片 ---

  /// 分节卡片：小节头（信号色图标 + 标题）+ 内容列。
  Widget _sectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AkColors.panel,
        border: Border.all(color: AkColors.border, width: AkTheme.hairline),
      ),
      padding: const EdgeInsets.all(AkTheme.cutMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AkColors.info),
              const SizedBox(width: 6),
              Text(
                title,
                style: AkTheme.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AkColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }

  // --- 视频节 ---

  Widget _videoSection(CodecCatalog catalog) {
    final vcodec = _video['vcodec'] as String;
    final encoder = _specialCodecs.contains(vcodec)
        ? null
        : catalog.findVideoEncoder(vcodec);
    return _sectionCard(
      icon: Icons.videocam_outlined,
      title: '视频',
      children: [
        _PickerRow(
          label: '编码器',
          value: _codecDisplayLabel(catalog, vcodec, isVideo: true),
          onTap: () => _pickCodec(catalog, isVideo: true),
          help: _codecHelp(catalog, vcodec, isVideo: true),
        ),
        if (encoder != null) ...[
          _dropdownRow(
            '分辨率',
            resolutionList,
            _video['resolution'] as String?,
            (v) => setState(() => _video['resolution'] = v),
            help: _selectedTooltip(
              resolutionList,
              _video['resolution'] as String?,
            ),
          ),
          _dropdownRow(
            '帧率',
            framerateList,
            _video['framerate'] as String?,
            (v) => setState(() => _video['framerate'] = v),
            help: _selectedTooltip(
              framerateList,
              _video['framerate'] as String?,
            ),
          ),
          ..._rateControlRows(_video, encoder),
          ..._paramRows('video', _video, encoder.parameters, optional: false),
          _advancedTile([
            ..._paramRows('video', _video, encoder.parameters, optional: true),
            _customRow('video', _video),
          ]),
        ],
      ],
    );
  }

  // --- 音频节 ---

  Widget _audioSection(CodecCatalog catalog) {
    final acodec = _audio['acodec'] as String;
    final encoder = _specialCodecs.contains(acodec)
        ? null
        : catalog.findAudioEncoder(acodec);
    return _sectionCard(
      icon: Icons.graphic_eq_outlined,
      title: '音频',
      children: [
        _PickerRow(
          label: '编码器',
          value: _codecDisplayLabel(catalog, acodec, isVideo: false),
          onTap: () => _pickCodec(catalog, isVideo: false),
          help: _codecHelp(catalog, acodec, isVideo: false),
        ),
        if (encoder != null) ...[
          ..._rateControlRows(_audio, encoder),
          ..._paramRows('audio', _audio, encoder.parameters, optional: false),
          _advancedTile([
            ..._paramRows('audio', _audio, encoder.parameters, optional: true),
            _customRow('audio', _audio),
          ]),
        ],
      ],
    );
  }

  // --- 输出（容器）节 ---

  Widget _muxSection(CodecCatalog catalog) {
    final format = _mux['format'] as String? ?? '';
    final muxer = format.isEmpty ? null : catalog.findMuxer(format);
    final filePathCtrl = _controllerFor(
      'mux.filePath',
      _mux['filePath'] as String? ?? '',
    );
    final beginCtrl = _controllerFor(
      'mux.begin',
      _mux['begin'] as String? ?? '',
    );
    final endCtrl = _controllerFor('mux.end', _mux['end'] as String? ?? '');
    return _sectionCard(
      icon: Icons.output_outlined,
      title: '输出',
      children: [
        _PickerRow(
          label: '容器格式',
          value: muxer?.label ?? format,
          onTap: () => _pickMuxer(catalog),
          help: muxer?.tooltip,
        ),
        _dropdownRow(
          '元数据保留',
          keepMetadataList,
          _mux['keepMetadata'] as String? ?? '',
          (v) => setState(() {
            if (v.isEmpty) {
              _mux.remove('keepMetadata');
            } else {
              _mux['keepMetadata'] = v;
            }
          }),
          help: _selectedTooltip(
            keepMetadataList,
            _mux['keepMetadata'] as String?,
          ),
        ),
        _dropdownRow(
          '文件时间保留',
          keepFileTimeList,
          _mux['keepFileTime'] as String? ?? '',
          (v) => setState(() {
            if (v.isEmpty) {
              _mux.remove('keepFileTime');
            } else {
              _mux['keepFileTime'] = v;
            }
          }),
          help: _keepFileTimeHelp,
        ),
        // 复用器扫描参数：非 optional 项直接展示，optional 项并入下方
        // 唯一的「高级选项」折叠区（避免出现两个折叠区）
        if (muxer != null && muxer.parameters.isNotEmpty)
          ..._paramRows('mux', _mux, muxer.parameters, optional: false),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: filePathCtrl,
                  style: AkTheme.mono(
                    fontSize: 12,
                    color: AkColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    labelText: '输出文件名模板',
                    isDense: true,
                  ),
                  onChanged: (v) => _mux['filePath'] = v,
                ),
              ),
              const SizedBox(width: 4),
              const _HelpButton(title: '输出文件名模板', help: filePathTemplateHint),
            ],
          ),
        ),
        _advancedTile([
          // 复用器扫描参数（movflags/faststart 等按容器实际支持项出现，
          // 对齐 web MuxView「详细参数」折叠区；硬编码 faststart 开关已移除）
          if (muxer != null)
            ..._paramRows('mux', _mux, muxer.parameters, optional: true),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextField(
              controller: beginCtrl,
              style: AkTheme.mono(fontSize: 12, color: AkColors.textPrimary),
              decoration: const InputDecoration(
                labelText: '剪辑起点（如 00:01:20）',
                isDense: true,
              ),
              onChanged: (v) => _mux['begin'] = v,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextField(
              controller: endCtrl,
              style: AkTheme.mono(fontSize: 12, color: AkColors.textPrimary),
              decoration: const InputDecoration(
                labelText: '剪辑终点（留空为至结尾）',
                isDense: true,
              ),
              onChanged: (v) => _mux['end'] = v,
            ),
          ),
          _customRow('mux', _mux),
        ]),
      ],
    );
  }

  // --- 编码器/复用器选择 ---

  /// 当前编码器（含特殊值）的帮助文案，对齐 web 菜单项 tooltip；
  /// 「自动」动态拼接当前复用器的默认编码器说明。
  String? _codecHelp(
    CodecCatalog catalog,
    String value, {
    required bool isVideo,
  }) {
    switch (value) {
      case '禁用':
        return '''不输出${isVideo ? '视频' : '音频'}
（如果输入中本来就没有${isVideo ? '视频' : '音频'}，
或者输出容器中不支持${isVideo ? '视频' : '音频'}，
ffmpeg 会自动忽略相关选项，无需手动选择此处）''';
      case 'copy':
        return '复制源码流，不重新编码。';
      case '自动':
        final format = _mux['format'] as String? ?? '';
        final muxer = catalog.findMuxer(format);
        final def = isVideo
            ? muxer?.defaultVideoCodec
            : muxer?.defaultAudioCodec;
        if (def != null && def.isNotEmpty) {
          return '不指定，让 ffmpeg 根据复用器默认设定选择编码\n'
              '根据你选择的复用器【$format】，默认使用【$def】编码器';
        }
        return '不指定，由 FFmpeg 根据复用器默认设定选择编码器';
      default:
        return isVideo
            ? catalog.findVideoEncoder(value)?.tooltip
            : catalog.findAudioEncoder(value)?.tooltip;
    }
  }

  /// 下拉当前选中项的帮助文案（对齐 web 菜单项悬停 tooltip）。
  String? _selectedTooltip(List<OptionItem> items, String? value) {
    if (value == null) return null;
    return items.where((i) => i.value == value).firstOrNull?.tooltip;
  }

  /// 当前编码器显示文案（特殊值映射 + 自动标注复用器默认编码器）。
  String _codecDisplayLabel(
    CodecCatalog catalog,
    String value, {
    required bool isVideo,
  }) {
    switch (value) {
      case '禁用':
        return '禁用';
      case 'copy':
        return '不重新编码';
      case '自动':
        final muxer = catalog.findMuxer(_mux['format'] as String? ?? '');
        final def = isVideo
            ? muxer?.defaultVideoCodec
            : muxer?.defaultAudioCodec;
        return def != null && def.isNotEmpty ? '自动【$def】' : '自动';
      default:
        final encoder = isVideo
            ? catalog.findVideoEncoder(value)
            : catalog.findAudioEncoder(value);
        return encoder?.label ?? value;
    }
  }

  Future<void> _pickCodec(CodecCatalog catalog, {required bool isVideo}) async {
    final muxer = catalog.findMuxer(_mux['format'] as String? ?? '');
    final defaultCodec = isVideo
        ? muxer?.defaultVideoCodec
        : muxer?.defaultAudioCodec;
    final groups = <_PickerGroup>[
      _PickerGroup('特殊', [
        OptionItem('禁用', '禁用', _codecHelp(catalog, '禁用', isVideo: isVideo)),
        OptionItem(
          'copy',
          '不重新编码',
          _codecHelp(catalog, 'copy', isVideo: isVideo),
        ),
        OptionItem(
          '自动',
          defaultCodec != null && defaultCodec.isNotEmpty
              ? '自动【$defaultCodec】'
              : '自动',
          _codecHelp(catalog, '自动', isVideo: isVideo),
        ),
      ]),
      for (final f
          in isVideo
              ? catalog.builtinVideoFamilies
              : catalog.builtinAudioFamilies)
        _PickerGroup(f.label, [
          for (final e in f.encoders)
            OptionItem(e.name, e.label ?? e.name, e.tooltip),
        ]),
      ..._serverEncoderGroups(catalog, isVideo: isVideo),
    ];
    final current =
        (isVideo ? _video['vcodec'] : _audio['acodec']) as String? ?? '';
    final value = await _showGroupedPicker(
      title: '选择${isVideo ? '视频' : '音频'}编码器',
      groups: groups,
      currentValue: current,
    );
    if (value == null || value == current) return;
    setState(() {
      final section = isVideo ? _video : _audio;
      final key = isVideo ? 'vcodec' : 'acodec';
      if (_specialCodecs.contains(value)) {
        // 特殊值：无码率控制（web checkAndApplyCodecDefaults 语义）
        section[key] = value;
        section.remove('ratecontrol');
        return;
      }
      final encoder = isVideo
          ? catalog.findVideoEncoder(value)
          : catalog.findAudioEncoder(value);
      if (encoder == null) return;
      section[key] = value;
      CodecCatalogService.applyCodecDefaults(section, encoder);
    });
  }

  /// 服务端扫描编码族 → 去重（内置已有同名编码器）后的「全部可用编码」分组。
  List<_PickerGroup> _serverEncoderGroups(
    CodecCatalog catalog, {
    required bool isVideo,
  }) {
    final builtinNames = <String>{
      for (final f
          in isVideo
              ? catalog.builtinVideoFamilies
              : catalog.builtinAudioFamilies)
        for (final e in f.encoders) e.name,
    };
    final groups = <_PickerGroup>[];
    for (final f
        in isVideo
            ? catalog.serverVideoFamilies
            : catalog.serverAudioFamilies) {
      final items = [
        for (final e in f.encoders)
          if (!builtinNames.contains(e.name))
            OptionItem(e.name, e.label ?? e.name, e.tooltip),
      ];
      if (items.isNotEmpty) groups.add(_PickerGroup(f.label, items));
    }
    return groups;
  }

  Future<void> _pickMuxer(CodecCatalog catalog) async {
    final builtinValues = <String>{
      for (final g in catalog.builtinMuxerGroups)
        for (final m in g.muxers) m.value,
    };
    final serverItems = [
      for (final m in catalog.serverMuxers)
        if (!builtinValues.contains(m.value))
          OptionItem(m.value, m.label, m.tooltip),
    ];
    final groups = <_PickerGroup>[
      for (final g in catalog.builtinMuxerGroups)
        _PickerGroup(g.label, [
          for (final m in g.muxers) OptionItem(m.value, m.label, m.tooltip),
        ]),
      if (serverItems.isNotEmpty) _PickerGroup('全部可用复用器', serverItems),
    ];
    final current = _mux['format'] as String? ?? '';
    final value = await _showGroupedPicker(
      title: '选择容器格式',
      groups: groups,
      currentValue: current,
    );
    if (value == null || value == current) return;
    setState(() => _mux['format'] = value);
  }

  Future<String?> _showGroupedPicker({
    required String title,
    required List<_PickerGroup> groups,
    required String currentValue,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AkColors.raised,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: AkTheme.cutSm),
          children: [
            Padding(
              padding: const EdgeInsets.all(AkTheme.cutMd),
              child: Text(
                title,
                style: AkTheme.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AkColors.textPrimary,
                ),
              ),
            ),
            for (final g in groups) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AkTheme.cutMd,
                  vertical: 4,
                ),
                child: Text(
                  g.label,
                  style: AkTheme.sans(
                    fontSize: 11,
                    color: AkColors.textSecondary,
                  ),
                ),
              ),
              for (final item in g.items)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AkTheme.cutMd,
                  ),
                  title: Text(
                    item.label,
                    style: AkTheme.mono(
                      fontSize: 13,
                      color: item.value == currentValue
                          ? AkColors.info
                          : AkColors.textPrimary,
                    ),
                  ),
                  subtitle: item.tooltip == null
                      ? null
                      : Text(
                          item.tooltip!,
                          style: AkTheme.sans(
                            fontSize: 10,
                            color: AkColors.textSecondary,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: item.value == currentValue
                      ? const Icon(Icons.check, size: 16, color: AkColors.info)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(item.value),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // --- 码率控制 ---

  List<Widget> _rateControlRows(
    Map<String, dynamic> section,
    EncoderSpec encoder,
  ) {
    final rcs = encoder.rateControls;
    if (rcs.isEmpty) return const [];
    final current = section['ratecontrol'] as String?;
    var rc = rcs.where((r) => r.value == current).firstOrNull;
    // 当前模式不在列表中（如切换编码器后）：回落到第一项（web 语义）
    rc ??= rcs.first;
    return [
      Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              '码率控制',
              style: AkTheme.sans(fontSize: 13, color: AkColors.textPrimary),
            ),
          ),
          Expanded(
            child: DropdownButton<String>(
              value: rc.value,
              isExpanded: true,
              dropdownColor: AkColors.raised,
              borderRadius: BorderRadius.zero,
              style: AkTheme.sans(fontSize: 13, color: AkColors.textPrimary),
              underline: const SizedBox.shrink(),
              items: [
                for (final r in rcs)
                  DropdownMenuItem(value: r.value, child: Text(r.label)),
              ],
              onChanged: (v) {
                if (v != null) _changeRateControl(section, rcs, v);
              },
            ),
          ),
          if (rc.tooltip != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _HelpButton(title: '码率控制', help: rc.tooltip!),
            ),
        ],
      ),
      if (rc.value != '自动') _rcSliderRow(section, rc),
    ];
  }

  /// 切换码率控制：清理全部码率控制参数后写入新模式默认值（web 语义）。
  void _changeRateControl(
    Map<String, dynamic> section,
    List<RateControlSpec> rcs,
    String value,
  ) {
    setState(() {
      final detail = _detailOf(section);
      for (final r in rcs) {
        for (final name in r.paramNames) {
          detail.remove(name);
        }
      }
      final rc = rcs.firstWhere(
        (r) => r.value == value,
        orElse: () => rcs.first,
      );
      section['ratecontrol'] = rc.value;
      detail.addAll(rc.defaultDetail);
    });
  }

  Widget _rcSliderRow(Map<String, dynamic> section, RateControlSpec rc) {
    final detail = _detailOf(section);
    var v = rc.detailToSlider?.call(detail);
    v ??= rc.detailToSlider?.call(rc.defaultDetail);
    v ??= (rc.min + rc.max) / 2;
    final clamped = v.clamp(rc.min, rc.max);
    return _SliderRow(
      title: _rcTitle(rc),
      value: clamped,
      min: rc.min,
      max: rc.max,
      display: rc.formatSlider,
      tags: rc.tags,
      onChanged: (nv) => setState(() => detail.addAll(rc.sliderToDetail(nv))),
    );
  }

  /// 滑杆标题（web rateControlSlider 映射）。
  String _rcTitle(RateControlSpec rc) {
    switch (rc.value) {
      case 'CRF':
        return 'CRF';
      case 'CQP':
        return 'QP 参数';
      case 'CBR':
      case 'ABR':
        return '码率';
      case 'Q':
      case 'VBR':
      case 'VBR_HQ':
        return '质量参数';
      default:
        return rc.label;
    }
  }

  // --- 详细参数 ---

  List<Widget> _paramRows(
    String sectionKey,
    Map<String, dynamic> section,
    List<ParamSpec> params, {
    required bool optional,
  }) {
    return [
      for (final p in params.where((p) => p.optional == optional))
        _paramRow(sectionKey, section, p),
    ];
  }

  Widget _paramRow(
    String sectionKey,
    Map<String, dynamic> section,
    ParamSpec p,
  ) {
    final detail = _detailOf(section);
    switch (p.mode) {
      case ParamMode.combo:
        return _dropdownRow(
          p.display,
          p.items,
          detail[p.parameter] as String?,
          (v) => setState(() => detail[p.parameter] = v),
          unsetLabel: '（未设置）',
          // 参数级 description 优先，缺失时回退选中项 tooltip（web 菜单悬停）
          help:
              _nonEmpty(p.description) ??
              _selectedTooltip(p.items, detail[p.parameter] as String?),
        );
      case ParamMode.slider:
        return _paramSliderRow(section, p);
      case ParamMode.switchMode:
        return _switchRow(
          p.display,
          detail[p.parameter] == true,
          (v) => setState(() {
            if (v) {
              detail[p.parameter] = true;
            } else {
              detail.remove(p.parameter);
            }
          }),
          help: _nonEmpty(p.description),
        );
      case ParamMode.text:
        final controller = _controllerFor(
          '$sectionKey.${p.parameter}',
          '${detail[p.parameter] ?? ''}',
        );
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: AkTheme.mono(
                    fontSize: 12,
                    color: AkColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: p.display,
                    isDense: true,
                  ),
                  onChanged: (v) {
                    if (v.isEmpty) {
                      detail.remove(p.parameter);
                    } else {
                      detail[p.parameter] = v;
                    }
                  },
                ),
              ),
              if (_nonEmpty(p.description) != null) ...[
                const SizedBox(width: 4),
                _HelpButton(title: p.display, help: p.description!),
              ],
            ],
          ),
        );
    }
  }

  Widget _paramSliderRow(Map<String, dynamic> section, ParamSpec p) {
    final detail = _detailOf(section);
    if (p.sliderString) {
      // 字符串档位滑杆（如 x264 preset）：detail 存档位文案，滑杆位置为索引
      final tags = p.tags;
      var pos = tags.indexWhere((t) => t.label == detail[p.parameter]);
      if (pos == -1 && p.defaultValue is String) {
        pos = tags.indexWhere((t) => t.label == p.defaultValue);
      }
      if (pos == -1) pos = 0;
      return _SliderRow(
        title: p.display,
        value: pos.toDouble(),
        min: 0,
        max: (tags.length - 1).toDouble(),
        display: (v) {
          final i = v.round().clamp(0, tags.length - 1);
          return tags[i].label;
        },
        tags: [
          for (var i = 0; i < tags.length; i++) (i.toDouble(), tags[i].label),
        ],
        onChanged: (v) => setState(() {
          final i = v.round().clamp(0, tags.length - 1);
          detail[p.parameter] = tags[i].label;
        }),
        help: _nonEmpty(p.description),
      );
    }
    final min = p.min ?? 0;
    final max = p.max ?? 1;
    var v = (detail[p.parameter] as num?)?.toDouble();
    v ??= p.defaultValue is num
        ? (p.defaultValue as num).toDouble()
        : double.tryParse('${p.defaultValue}');
    v ??= (min + max) / 2;
    final clamped = v.clamp(min, max);
    return _SliderRow(
      title: p.display,
      value: clamped,
      min: min,
      max: max,
      display: (nv) => _formatNum(nv),
      tags: [
        for (final t in p.tags)
          if (double.tryParse(t.value) != null)
            (double.parse(t.value), t.label),
      ],
      onChanged: (nv) => setState(() {
        detail[p.parameter] = _numValue(nv);
      }),
      help: _nonEmpty(p.description),
    );
  }

  /// 自定义参数输入（追加到 ffmpeg 命令行）。
  Widget _customRow(String sectionKey, Map<String, dynamic> section) {
    final controller = _controllerFor(
      '$sectionKey.custom',
      '${section['custom'] ?? ''}',
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TextField(
        controller: controller,
        style: AkTheme.mono(fontSize: 12, color: AkColors.textPrimary),
        decoration: const InputDecoration(
          labelText: '自定义参数',
          hintText: '追加到 ffmpeg 命令行',
          isDense: true,
        ),
        onChanged: (v) {
          if (v.isEmpty) {
            section.remove('custom');
          } else {
            section['custom'] = v;
          }
        },
      ),
    );
  }

  // --- 通用行组件 ---

  /// 空串归一为 null（目录中大量 tooltip 为空字符串，等价于无帮助）。
  static String? _nonEmpty(String? s) => (s != null && s.isNotEmpty) ? s : null;

  /// 高级选项折叠区。ExpansionTile 内部为 ListTile，须以透明 Material
  /// 包裹：否则 ListTile 的水墨效果绘制在分节卡片的 DecoratedBox 之下，
  /// 触发「ink splashes may be invisible」断言。
  Widget _advancedTile(List<Widget> children) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: Material(
      color: Colors.transparent,
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        dense: true,
        initiallyExpanded: false,
        title: Text(
          '高级选项',
          style: AkTheme.sans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AkColors.textSecondary,
          ),
        ),
        iconColor: AkColors.textSecondary,
        collapsedIconColor: AkColors.textSecondary,
        children: children,
      ),
    ),
  );

  /// 下拉行：标签 + OptionItem 下拉；当前值不在候选项时以 hint 展示。
  /// [help] 非空时行尾显示「?」帮助按钮。
  Widget _dropdownRow(
    String label,
    List<OptionItem> items,
    String? currentValue,
    ValueChanged<String> onChanged, {
    String? unsetLabel,
    String? help,
  }) {
    final selected = currentValue == null
        ? null
        : items.where((i) => i.value == currentValue).firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: AkTheme.sans(fontSize: 13, color: AkColors.textPrimary),
            ),
          ),
          Expanded(
            child: DropdownButton<String>(
              value: selected?.value,
              isExpanded: true,
              dropdownColor: AkColors.raised,
              borderRadius: BorderRadius.zero,
              style: AkTheme.sans(fontSize: 13, color: AkColors.textPrimary),
              underline: const SizedBox.shrink(),
              hint:
                  selected == null &&
                      currentValue != null &&
                      currentValue.isNotEmpty
                  ? Text(
                      currentValue,
                      style: AkTheme.mono(
                        fontSize: 12,
                        color: AkColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    )
                  : (selected == null && unsetLabel != null
                        ? Text(
                            unsetLabel,
                            style: AkTheme.sans(
                              fontSize: 12,
                              color: AkColors.textSecondary,
                            ),
                          )
                        : null),
              items: [
                for (final i in items)
                  DropdownMenuItem(
                    value: i.value,
                    child: Text(
                      i.label,
                      overflow: TextOverflow.ellipsis,
                      style: AkTheme.sans(
                        fontSize: 13,
                        color: AkColors.textPrimary,
                      ),
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
          if (help != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _HelpButton(title: label, help: help),
            ),
        ],
      ),
    );
  }

  /// 开关行：标签 + Switch；[help] 非空时行尾显示「?」帮助按钮。
  Widget _switchRow(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String? help,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AkTheme.sans(fontSize: 13, color: AkColors.textPrimary),
            ),
          ),
          if (help != null) _HelpButton(title: label, help: help),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// --- 数值格式化辅助 ---

String _formatNum(double v) =>
    v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

dynamic _numValue(double v) => v == v.roundToDouble() ? v.round() : v;

// --- 私有行组件 ---

/// 参数帮助按钮：以「?」入口替代 web 悬停 tooltip，点击弹出底部说明层。
class _HelpButton extends StatelessWidget {
  final String title;
  final String help;

  const _HelpButton({required this.title, required this.help});

  Future<void> _show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AkColors.raised,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(AkTheme.cutMd),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AkTheme.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AkColors.textPrimary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(sheetContext).pop(),
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: AkColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              help,
              style: AkTheme.sans(
                fontSize: 12,
                color: AkColors.textSecondary,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: InkWell(
        onTap: () => _show(context),
        child: const Icon(
          Icons.help_outline,
          size: 15,
          color: AkColors.textSecondary,
        ),
      ),
    );
  }
}

/// 编码器/容器选择行：标签 + 当前值 + 展开箭头，点击弹分组选择器；
/// [help] 非空时行尾显示「?」帮助按钮。
class _PickerRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final String? help;

  const _PickerRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.help,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 84,
              child: Text(
                label,
                style: AkTheme.sans(fontSize: 13, color: AkColors.textPrimary),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: AkTheme.mono(fontSize: 13, color: AkColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (help != null) _HelpButton(title: label, help: help!),
            const Icon(
              Icons.expand_more,
              size: 16,
              color: AkColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 滑杆行：标题 + Slider + 当前值；tags 为滑杆下方按位置排布的档位提示；
/// [help] 非空时行尾显示「?」帮助按钮。
class _SliderRow extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final String Function(double) display;
  final List<(double, String)> tags;
  final ValueChanged<double> onChanged;
  final String? help;

  const _SliderRow({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.tags = const [],
    this.help,
  });

  @override
  Widget build(BuildContext context) {
    final span = max - min;
    final divisions = span > 0 && span == span.roundToDouble()
        ? span.round()
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 84,
              child: Text(
                title,
                style: AkTheme.sans(fontSize: 13, color: AkColors.textPrimary),
              ),
            ),
            Expanded(
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                activeColor: AkColors.info,
                inactiveColor: AkColors.muted,
                label: display(value),
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 76,
              child: Text(
                display(value),
                style: AkTheme.mono(fontSize: 12, color: AkColors.textPrimary),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (help != null) _HelpButton(title: title, help: help!),
          ],
        ),
        if (tags.isNotEmpty) _tagLabels(),
      ],
    );
  }

  /// 档位提示行：按位置比例排布（滑杆区对齐，避开右侧数值区）。
  Widget _tagLabels() {
    return Padding(
      padding: EdgeInsets.only(
        left: 84,
        right: help != null ? 110 : 84,
        top: 2,
      ),
      child: SizedBox(
        height: 14,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final (pos, text) in tags)
              () {
                final f = max > min ? (pos - min) / (max - min) : 0.0;
                final Alignment alignment;
                if (f <= 0.08) {
                  alignment = Alignment.centerLeft;
                } else if (f >= 0.92) {
                  alignment = Alignment.centerRight;
                } else {
                  alignment = Alignment(f * 2 - 1, 0);
                }
                return Align(
                  alignment: alignment,
                  child: Text(
                    text,
                    style: AkTheme.mono(
                      fontSize: 9,
                      color: AkColors.textSecondary,
                    ),
                  ),
                );
              }(),
          ],
        ),
      ),
    );
  }
}

/// 分组选择器的分组（标题 + 选项）。
class _PickerGroup {
  final String label;
  final List<OptionItem> items;

  const _PickerGroup(this.label, this.items);
}
