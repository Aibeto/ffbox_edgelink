/// FFBox web 前端内置转码配置定义的 Dart 副本。
///
/// 移植自 `FFBox/src/common/params/{vcodecs,acodecs,formats}.ts` 的
/// builtInVcodecs / builtInAcodecs / builtInMuxers 及分辨率、帧率、
/// 元数据保留等静态列表；码率控制预设与 web 端滑杆语义一致。
/// application 层纯 Dart，不依赖 Riverpod。
library;

import 'dart:math' as math;

import 'package:ffbox_edgelink/domain/entities/codec_catalog.dart';

// --- 数学辅助（码率滑杆换算） ---

double _log2(double x) => math.log(x) / math.ln2;
double _pow2(double v) => math.pow(2, v).toDouble();

// --- 通用选项 ---

const _auto = OptionItem('自动', '自动', '不指定，由 FFmpeg 自动选择');
const _default = OptionItem('默认', '默认', '默认');
const _psnr = OptionItem('psnr', 'psnr', '优化 PSNR');
const _ssim = OptionItem('ssim', 'ssim', '优化 SSIM');
const _fastdecode = OptionItem('fastdecode', 'fastdecode', '快速解码');
const _zerolatency = OptionItem('zerolatency', 'zerolatency', '低延迟编码');
const _film = OptionItem('film', 'film', '电影');
const _animation = OptionItem('animation', 'animation', '动画');
const _grain = OptionItem('grain', 'grain', '保留噪点');
const _stillimage = OptionItem('stillimage', 'stillimage', '静态图像');

const _pixYuv420p = [_auto, OptionItem('yuv420p', 'yuv420p')];

// --- 码率控制预设（视频） ---

final _rcAutoList = <RateControlSpec>[
  RateControlSpec(
    value: '自动',
    label: '自动',
    tooltip: '不指定码率控制，由编码器自行决定',
    min: 0,
    max: 1,
    paramNames: [],
    defaultDetail: {},
    detailToSlider: (d) => null,
    sliderToDetail: (v) => {},
  ),
];

RateControlSpec _crf({
  required double max,
  required int defaultCrf,
  List<(double, String)> tags = const [],
}) =>
    RateControlSpec(
      value: 'CRF',
      label: '恒定质量 CRF',
      tooltip: 'Constant Rate Factor - 恒定速率因子\n指定视觉画质，而码率因画面内容而异，性价比最高。\n如果您对输出文件大小没有明确的目标，使用此项可获得视觉上最稳定的画质。相较于 CQP，CRF 会考虑帧间的动态关系，在人眼更容易捕捉的静态画面分配更低的 QP，从而节省码率并且获得更好的视觉效果。',
      min: 0,
      max: max,
      paramNames: ['crf'],
      defaultDetail: {'crf': defaultCrf},
      detailToSlider: (d) {
        final crf = (d['crf'] as num?)?.toDouble();
        return crf == null ? null : max - crf;
      },
      display: RcDisplay.revertInteger,
      sliderToDetail: (v) => {'crf': (max - v).round()},
      tags: tags,
    );

RateControlSpec _cqp({
  required double max,
  required int defaultQp,
  List<(double, String)> tags = const [],
}) =>
    RateControlSpec(
      value: 'CQP',
      label: '恒定量化 CQP',
      tooltip: 'Constant Quantization Parameter - 恒定量化参数\n指定每帧的画质，而码率因画面内容而异，可作为 CRF 的备选方案。\n如果您对输出文件大小没有明确的目标，使用此项可获得最稳定的画质。相较于 CRF，CQP 的 QP 是恒定的，每帧的画质相同，因此相同码率下视觉画质较 CRF 低，一般仅在显卡编码时使用。',
      min: 0,
      max: max,
      paramNames: ['qp'],
      defaultDetail: {'qp': defaultQp},
      detailToSlider: (d) {
        final qp = (d['qp'] as num?)?.toDouble();
        return qp == null ? null : max - qp;
      },
      display: RcDisplay.revertInteger,
      sliderToDetail: (v) => {'qp': (max - v).round()},
      tags: tags,
    );

/// 指定质量 Q（滑杆反向：0=最低画质，max=最高画质）。
RateControlSpec _qSpec({
  required double max,
  required int defaultQ,
  List<(double, String)> tags = const [],
}) =>
    RateControlSpec(
      value: 'Q',
      label: '指定质量 Q',
      tooltip: 'Q - 质量\n指定画质，具体值对应的画质由具体编码器决定。',
      min: 0,
      max: max,
      paramNames: ['q'],
      defaultDetail: {'q': defaultQ},
      detailToSlider: (d) {
        final q = (d['q'] as num?)?.toDouble();
        return q == null ? null : max - q;
      },
      display: RcDisplay.revertInteger,
      sliderToDetail: (v) => {'q': (max - v).round()},
      tags: tags,
    );

double? _bitrateToSlider(Map<String, dynamic> d, String key, double base) {
  final b = (d[key] as num?)?.toDouble();
  if (b == null || b <= 0) return null;
  return _log2(b / base);
}

final _abrVideo = RateControlSpec(
  value: 'ABR',
  label: '平均码率 ABR',
  tooltip: 'Average Bit Rate - 平均码率\n将码率控制在指定值左右，一般应用于限定文件大小但又不希望像 CBR 那样死板的场景。',
  min: 0,
  max: 12,
  paramNames: ['b:v'],
  defaultDetail: {'b:v': 4000000},
  detailToSlider: (d) => _bitrateToSlider(d, 'b:v', 62500),
  display: RcDisplay.bitrate,
  displayBase: 62500,
  sliderToDetail: (v) => {'b:v': (62500 * _pow2(v)).round()},
  tags: [
    (0, '62.5 Kbps'),
    (3, '500 Kbps'),
    (6, '4 Mbps'),
    (9, '32 Mbps'),
    (12, '256 Mbps'),
  ],
);

/// x264/x265 的 CBR：同时写入 b:v / minrate / maxrate。
final _cbrX264x265 = RateControlSpec(
  value: 'CBR',
  label: '固定码率 CBR',
  tooltip: 'Constant Bit Rate - 恒定码率\n将码率恒定在指定值，仅允许极小或没有波动，性价比最低，一般仅应用于直播等需要数据速率固定的场景。',
  min: 0,
  max: 12,
  paramNames: ['b:v', 'minrate', 'maxrate'],
  defaultDetail: {'b:v': 4000000, 'minrate': 4000000, 'maxrate': 4000000},
  detailToSlider: (d) => _bitrateToSlider(d, 'b:v', 62500),
  display: RcDisplay.bitrate,
  displayBase: 62500,
  sliderToDetail: (v) {
    final b = (62500 * _pow2(v)).round();
    return {'b:v': b, 'minrate': b, 'maxrate': b};
  },
  tags: [
    (0, '62.5 Kbps'),
    (3, '500 Kbps'),
    (6, '4 Mbps'),
    (9, '32 Mbps'),
    (12, '256 Mbps'),
  ],
);

/// nvenc / amf 硬件编码器的 CBR：附带 cbr 标记。
final _cbrHw = RateControlSpec(
  value: 'CBR',
  label: '固定码率 CBR',
  tooltip: 'Constant Bit Rate - 恒定码率\n将码率恒定在指定值，仅允许极小或没有波动，性价比最低，一般仅应用于直播等需要数据速率固定的场景。',
  min: 0,
  max: 12,
  paramNames: ['cbr', 'b:v'],
  defaultDetail: {'cbr': 'true', 'b:v': 4000000},
  detailToSlider: (d) => _bitrateToSlider(d, 'b:v', 62500),
  display: RcDisplay.bitrate,
  displayBase: 62500,
  sliderToDetail: (v) => {'cbr': 'true', 'b:v': (62500 * _pow2(v)).round()},
  tags: [
    (0, '62.5 Kbps'),
    (3, '500 Kbps'),
    (6, '4 Mbps'),
    (9, '32 Mbps'),
    (12, '256 Mbps'),
  ],
);

RateControlSpec _vbrNvencSpec({
  required String value,
  required String label,
  required String tooltip,
}) =>
    RateControlSpec(
      value: value,
      label: label,
      tooltip: tooltip,
      min: 0,
      max: 51,
      paramNames: ['cq', 'rc', 'maxrate'],
      defaultDetail: {'rc': value == 'VBR' ? 'vbr' : 'vbr_hq', 'cq': 28, 'maxrate': 800000000},
      detailToSlider: (d) {
        final cq = (d['cq'] as num?)?.toDouble();
        return cq == null ? null : 51 - cq;
      },
      display: RcDisplay.revertInteger,
      sliderToDetail: (v) => {
        'rc': value == 'VBR' ? 'vbr' : 'vbr_hq',
        'cq': (51 - v).round(),
        'maxrate': 800000000,
      },
      tags: [
        (0, '51（最低画质）'),
        (11, '40（低画质）'),
        (17, '34（一般画质）'),
        (23, '28（良画质）'),
        (31, '20（高画质）'),
        (51, '0（自动）'),
      ],
    );

final _vbrNvenc = _vbrNvencSpec(
  value: 'VBR',
  label: '动态码率 VBR',
  tooltip: 'Variable Bit Rate - 可变码率\n指定画质参数，控制比特率范围，可作为 CRF 的备选方案。',
);

final _vbrNvencHQ = _vbrNvencSpec(
  value: 'VBR_HQ',
  label: '动态码率 VBR_HQ',
  tooltip: 'Variable Bit Rate - 可变码率\n指定画质参数，控制比特率范围，可作为 CRF 的备选方案。该项是 NVIDIA 特有选项，在编码时间几乎不变的情况下略微提高质量。',
);

/// amf 的 CQP：qp_i / qp_p 成对写入。
final _qpAmf = RateControlSpec(
  value: 'CQP',
  label: '恒定量化 CQP',
  tooltip: 'Constant Quantization Parameter - 恒定量化参数\n指定每帧的画质，而码率因画面内容而异，可作为 CRF 的备选方案。\n如果您对输出文件大小没有明确的目标，使用此项可获得最稳定的画质。相较于 CRF，CQP 的 QP 是恒定的，每帧的画质相同，因此相同码率下视觉画质较 CRF 低，一般仅在显卡编码时使用。',
  min: 0,
  max: 51,
  paramNames: ['qp_i', 'qp_p'],
  defaultDetail: {'qp_i': 28, 'qp_p': 28},
  detailToSlider: (d) {
    final qp = (d['qp_i'] ?? d['qp_p'] ?? d['qp']) as num?;
    return qp == null ? null : 51 - qp.toDouble();
  },
  display: RcDisplay.revertInteger,
  sliderToDetail: (v) => {'qp_i': (51 - v).round(), 'qp_p': (51 - v).round()},
);

final _q100Video = _qSpec(max: 100, defaultQ: 50, tags: [(0, '100'), (100, '0')]);

final _q255Video = _qSpec(
  max: 255,
  defaultQ: 88,
  tags: [
    (0, '255（最低画质）'),
    (79, '176（很低画质）'),
    (123, '132（低画质）'),
    (167, '88（中画质）'),
    (211, '44（高画质）'),
    (255, '0（最高画质）'),
  ],
);

final _qMpeg4 = _qSpec(
  max: 31,
  defaultQ: 10,
  tags: [
    (31, '0（最高画质）'),
    (30, '1（高画质）'),
    (28, '3（良画质）'),
    (25, '6（一般画质）'),
    (21, '10（低画质）'),
    (0, '（最低为 10000）'),
  ],
);

final _qMjpeg = _qSpec(
  max: 31,
  defaultQ: 10,
  tags: [
    (29, '2（最高画质）'),
    (26, '5（良画质）'),
    (23, '8（一般画质）'),
    (13, '18（低画质）'),
    (0, '31（最低画质）'),
  ],
);

// --- 码率控制预设（音频） ---

final _qAudio = RateControlSpec(
  value: 'Q',
  label: 'Q',
  tooltip: '指定音频质量',
  min: 0,
  max: 100,
  paramNames: ['q:a'],
  defaultDetail: {'q:a': 50},
  detailToSlider: (d) => (d['q:a'] as num?)?.toDouble(),
  display: RcDisplay.integer,
  sliderToDetail: (v) => {'q:a': v.round()},
);

final _cbrAudio = RateControlSpec(
  value: 'CBR',
  label: 'CBR',
  tooltip: '指定预期码率大小',
  min: 0,
  max: 6,
  paramNames: ['b:a'],
  defaultDetail: {'b:a': 128000},
  detailToSlider: (d) => _bitrateToSlider(d, 'b:a', 8000),
  display: RcDisplay.bitrate,
  displayBase: 8000,
  sliderToDetail: (v) => {'b:a': (8000 * _pow2(v)).round()},
  tags: [
    (0, '8 Kbps'),
    (1, '16 Kbps'),
    (2, '32 Kbps'),
    (3, '64 Kbps'),
    (4, '128 Kbps'),
    (5, '256 Kbps'),
    (6, '512 Kbps'),
  ],
);

// --- 视频编码器滑杆预设 ---

const _h264265Preset = ParamSpec(
  parameter: 'preset',
  display: '编码质量',
  mode: ParamMode.slider,
  min: 0,
  max: 9,
  sliderString: true,
  defaultValue: 'medium',
  tags: [
    OptionItem('0', 'ultrafast'),
    OptionItem('1', 'superfast'),
    OptionItem('2', 'veryfast'),
    OptionItem('3', 'faster'),
    OptionItem('4', 'fast'),
    OptionItem('5', 'medium'),
    OptionItem('6', 'slow'),
    OptionItem('7', 'slower'),
    OptionItem('8', 'veryslow'),
    OptionItem('9', 'placebo'),
  ],
);

const _qsvPreset = ParamSpec(
  parameter: 'preset',
  display: '编码质量',
  mode: ParamMode.slider,
  min: 0,
  max: 6,
  sliderString: true,
  defaultValue: 'medium',
  tags: [
    OptionItem('0', 'veryfast'),
    OptionItem('1', 'faster'),
    OptionItem('2', 'fast'),
    OptionItem('3', 'medium'),
    OptionItem('4', 'slow'),
    OptionItem('5', 'slower'),
    OptionItem('6', 'veryslow'),
  ],
);

const _amfPreset = ParamSpec(
  parameter: 'preset',
  display: '编码质量',
  mode: ParamMode.slider,
  min: 0,
  max: 2,
  sliderString: true,
  defaultValue: 'balanced',
  tags: [
    OptionItem('0', 'speed'),
    OptionItem('1', 'balanced'),
    OptionItem('2', 'quality'),
  ],
);

const _nvencPresetItems = [
  _auto,
  OptionItem('slow', 'slow', 'hq 2 passes'),
  OptionItem('medium', 'medium', 'hq 1 pass'),
  OptionItem('fast', 'fast', 'hp 1 pass'),
  OptionItem('hq', 'hq'),
  OptionItem('bd', 'bd'),
  OptionItem('ll', 'll', 'low latency'),
  OptionItem('llhq', 'llhq', 'low latency hq'),
  OptionItem('llhp', 'llhp', 'low latency hp'),
  OptionItem('lossless', 'lossless'),
  OptionItem('losslesshp', 'losslesshp'),
  OptionItem('p1', 'p1', 'fastest (lowest quality)'),
  OptionItem('p2', 'p2', 'faster (lower quality)'),
  OptionItem('p3', 'p3', 'fast (low quality)'),
  OptionItem('p4', 'p4', 'medium (default)'),
  OptionItem('p5', 'p5', 'slow (good quality)'),
  OptionItem('p6', 'p6', 'slower (better quality)'),
  OptionItem('p7', 'p7', 'slowest (best quality)'),
];

const _vpxQuality = ParamSpec(
  parameter: 'quality',
  display: '编码质量',
  mode: ParamMode.slider,
  min: 0,
  max: 2,
  sliderString: true,
  defaultValue: 'good',
  tags: [
    OptionItem('0', 'realtime'),
    OptionItem('1', 'good'),
    OptionItem('2', 'best'),
  ],
);

// --- 级别列表 ---

const _h264Level = [
  _auto,
  OptionItem('1', '1'),
  OptionItem('1b', '1b'),
  OptionItem('1.1', '1.1'),
  OptionItem('1.2', '1.2'),
  OptionItem('1.3', '1.3'),
  OptionItem('2', '2'),
  OptionItem('2.1', '2.1'),
  OptionItem('2.2', '2.2'),
  OptionItem('3', '3'),
  OptionItem('3.1', '3.1'),
  OptionItem('3.2', '3.2'),
  OptionItem('4', '4'),
  OptionItem('4.1', '4.1'),
  OptionItem('4.2', '4.2'),
  OptionItem('5', '5'),
  OptionItem('5.1', '5.1'),
  OptionItem('5.2', '5.2'),
  OptionItem('6', '6'),
  OptionItem('6.1', '6.1'),
  OptionItem('6.2', '6.2'),
];

const _hevcLevel = [
  _auto,
  OptionItem('1', '1'),
  OptionItem('2', '2'),
  OptionItem('2.1', '2.1'),
  OptionItem('3', '3'),
  OptionItem('3.1', '3.1'),
  OptionItem('4', '4'),
  OptionItem('4.1', '4.1'),
  OptionItem('5', '5'),
  OptionItem('5.1', '5.1'),
  OptionItem('5.2', '5.2'),
  OptionItem('6', '6'),
  OptionItem('6.1', '6.1'),
  OptionItem('6.2', '6.2'),
];

const _baseline = OptionItem('baseline', 'baseline');
const _main = OptionItem('main', 'main');
const _main10 = OptionItem('main10', 'main10');
const _high = OptionItem('high', 'high');

// --- 采样率 / 声道布局 ---

OptionItem _sr(int n) => OptionItem('$n', '$n Hz');

const _srAac = [
  _auto,
  OptionItem('96000', '96000 Hz'),
  OptionItem('88200', '88200 Hz'),
  OptionItem('64000', '64000 Hz'),
  OptionItem('48000', '48000 Hz'),
  OptionItem('44100', '44100 Hz'),
  OptionItem('32000', '32000 Hz'),
  OptionItem('24000', '24000 Hz'),
  OptionItem('22050', '22050 Hz'),
  OptionItem('16000', '16000 Hz'),
  OptionItem('12000', '12000 Hz'),
  OptionItem('11025', '11025 Hz'),
  OptionItem('8000', '8000 Hz'),
  OptionItem('7350', '7350 Hz'),
];

final _sr48000 = [_auto, _sr(48000)];
final _srCommon = [
  _auto,
  _sr(48000),
  _sr(44100),
  _sr(32000),
  _sr(24000),
  _sr(22050),
  _sr(16000),
  _sr(12000),
  _sr(11025),
  _sr(8000),
];

const _loMono = OptionItem('mono', 'mono', '单声道 FC');
const _loStereo = OptionItem('stereo', 'stereo', '立体声 FL+FR');
const _loMonoStereo = [_auto, _loMono, _loStereo];

// --- 内置视频编码族 ---

/// 与 web builtInVcodecs 一致（含闭包，不能为 const）。
final List<CodecFamilySpec> builtinVideoFamilies = [
  CodecFamilySpec(
    label: 'AV1',
    tooltip: 'AV1 - AV1 即 AOMedia Video 1 是一个开放、免专利的影片编码格式，专为通过网络进行流传输而设计。',
    encoders: [
      EncoderSpec(
        name: 'libaom-av1',
        label: '【默认】libaom-av1',
        rateControls: [
          ..._rcAutoList,
          _crf(
            max: 63,
            defaultCrf: 29,
            tags: [
              (0, '63（最低画质）'),
              (5, '58（低画质）'),
              (15, '48（一般画质）'),
              (29, '34（良画质）'),
              (43, '20（高画质）'),
              (63, '0（最高画质）'),
            ],
          ),
          _abrVideo,
        ],
        parameters: [
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [
              _auto,
              OptionItem('yuv420p', 'yuv420p'),
              OptionItem('yuv422p', 'yuv422p'),
              OptionItem('yuv444p', 'yuv444p'),
              OptionItem('gbrp', 'gbrp'),
              OptionItem('yuv420p10le', 'yuv420p10le'),
              OptionItem('yuv422p10le', 'yuv422p10le'),
              OptionItem('yuv444p10le', 'yuv444p10le'),
              OptionItem('yuv420p12le', 'yuv420p12le'),
              OptionItem('yuv422p12le', 'yuv422p12le'),
              OptionItem('yuv444p12le', 'yuv444p12le'),
              OptionItem('gbrp10le', 'gbrp10le'),
              OptionItem('gbrp12le', 'gbrp12le'),
              OptionItem('gray', 'gray'),
              OptionItem('gray10le', 'gray10le'),
            ],
          ),
          ParamSpec(
            parameter: 'cpu-used',
            display: '编码质量',
            mode: ParamMode.slider,
            min: 0,
            max: 8,
            defaultValue: 0,
            tags: [
              OptionItem('0', '8（低质量，快）'),
              OptionItem('8', '0（高质量，慢）'),
            ],
          ),
        ],
      ),
      EncoderSpec(
        name: 'libsvtav1',
        label: 'libsvtav1',
        rateControls: [
          ..._rcAutoList,
          _crf(
            max: 63,
            defaultCrf: 27,
            tags: [
              (0, '63（最低画质）'),
              (3, '60（低画质）'),
              (13, '50（一般画质）'),
              (27, '36（良画质）'),
              (41, '22（高画质）'),
              (62, '1（最高画质）'),
              (63, '0（自动）'),
            ],
          ),
          _cqp(max: 63, defaultQp: 30),
          _abrVideo,
        ],
        parameters: [
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [_auto, OptionItem('yuv420p', 'yuv420p'), OptionItem('yuv420p10le', 'yuv420p10le')],
          ),
          ParamSpec(
            parameter: 'preset',
            display: '编码质量',
            mode: ParamMode.slider,
            min: 0,
            max: 13,
            defaultValue: 6,
            tags: [
              OptionItem('0', '13（低质量，快）'),
              OptionItem('13', '0（高质量，慢）'),
            ],
          ),
        ],
      ),
      EncoderSpec(
        name: 'av1_qsv',
        label: 'av1_qsv',
        tooltip: 'Intel 硬件加速编码器',
        rateControls: [..._rcAutoList, _q255Video, _abrVideo],
        parameters: [
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [_auto, OptionItem('nv12', 'nv12'), OptionItem('p010le', 'p010le'), OptionItem('qsv', 'qsv')],
          ),
          _qsvPreset,
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'HEVC (H.265)',
    tooltip: 'HEVC - HEVC 即高效率视频编码（High Efficiency Video Coding），又称为 H.265，是一种视频压缩标准，被视为是 H.264 的继任者。',
    encoders: [
      EncoderSpec(
        name: 'libx265',
        label: '【默认】libx265',
        rateControls: [
          ..._rcAutoList,
          _crf(
            max: 51,
            defaultCrf: 24,
            tags: [
              (0, '51（最低画质）'),
              (15, '36（低画质）'),
              (21, '30（一般画质）'),
              (27, '24（良画质）'),
              (33, '18（高画质）'),
              (39, '12（肉眼无损）'),
              (51, '0（最高画质）'),
            ],
          ),
          _cqp(max: 70, defaultQp: 34),
          _abrVideo,
          _cbrX264x265,
        ],
        parameters: [
          _h264265Preset,
          ParamSpec(
            parameter: 'tune',
            display: '编码倾重',
            mode: ParamMode.combo,
            items: [_default, _psnr, _ssim, _fastdecode, _zerolatency],
          ),
          ParamSpec(parameter: 'level', display: '级别', mode: ParamMode.combo, items: _hevcLevel),
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [
              _auto,
              OptionItem('yuv420p', 'yuv420p'),
              OptionItem('yuv422p', 'yuv422p'),
              OptionItem('yuv444p', 'yuv444p'),
              OptionItem('gbrp', 'gbrp'),
              OptionItem('yuv420p10le', 'yuv420p10le'),
              OptionItem('yuv422p10le', 'yuv422p10le'),
              OptionItem('yuv444p10le', 'yuv444p10le'),
              OptionItem('gbrp10le', 'gbrp10le'),
              OptionItem('gray', 'gray'),
              OptionItem('gray10le', 'gray10le'),
            ],
          ),
        ],
      ),
      EncoderSpec(
        name: 'hevc_qsv',
        label: 'hevc_qsv',
        tooltip: 'Intel 硬件加速编码器',
        rateControls: [..._rcAutoList, _q255Video, _abrVideo],
        parameters: [
          _qsvPreset,
          ParamSpec(
            parameter: 'profile:v',
            display: '规格',
            mode: ParamMode.combo,
            items: [_auto, _main, _main10, OptionItem('mainsp', 'mainsp')],
          ),
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [_auto, OptionItem('nv12', 'nv12'), OptionItem('p010le', 'p010le'), OptionItem('qsv', 'qsv')],
          ),
        ],
      ),
      EncoderSpec(
        name: 'hevc_nvenc',
        label: 'hevc_nvenc',
        tooltip: 'NVIDIA 硬件加速编码器',
        rateControls: [
          ..._rcAutoList,
          _vbrNvencHQ,
          _vbrNvenc,
          _cqp(max: 51, defaultQp: 28),
          _cbrHw,
          _abrVideo,
        ],
        parameters: [
          ParamSpec(parameter: 'preset', display: '编码质量', mode: ParamMode.combo, items: _nvencPresetItems),
          ParamSpec(
            parameter: 'tune',
            display: '编码倾重',
            mode: ParamMode.combo,
            items: [_default, _psnr, _ssim, _fastdecode, _zerolatency],
          ),
          ParamSpec(
            parameter: 'profile:v',
            display: '规格',
            mode: ParamMode.combo,
            items: [_auto, _main, _main10, OptionItem('rext', 'rext')],
          ),
          ParamSpec(parameter: 'level', display: '级别', mode: ParamMode.combo, items: _hevcLevel),
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [
              _auto,
              OptionItem('yuv420p', 'yuv420p'),
              OptionItem('nv12', 'nv12'),
              OptionItem('p016le', 'p016le'),
              OptionItem('yuv444p', 'yuv444p'),
              OptionItem('p010le', 'p010le'),
              OptionItem('yuv444p16le', 'yuv444p16le'),
              OptionItem('bgr0', 'bgr0'),
              OptionItem('rgb0', 'rgb0'),
              OptionItem('cuda', 'cuda'),
              OptionItem('d3d11', 'd3d11'),
            ],
          ),
        ],
      ),
      EncoderSpec(
        name: 'hevc_amf',
        label: 'hevc_amf',
        tooltip: 'AMD 硬件加速编码器',
        rateControls: [
          ..._rcAutoList,
          _qpAmf,
          _cbrHw,
          _abrVideo,
        ],
        parameters: [
          _amfPreset,
          ParamSpec(
            parameter: 'tune',
            display: '编码倾重',
            mode: ParamMode.combo,
            items: [
              _auto,
              OptionItem('transcoding', 'transcoding（默认）', '转码'),
              OptionItem('ultralowlatency', 'ultralowlatency', '超低延迟'),
              OptionItem('webcam', 'webcam', '网络摄像头'),
            ],
          ),
          ParamSpec(parameter: 'profile:v', display: '规格', mode: ParamMode.combo, items: [_auto, _main, _high]),
          ParamSpec(parameter: 'level', display: '级别', mode: ParamMode.combo, items: _hevcLevel),
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [_auto, OptionItem('yuv420p', 'yuv420p'), OptionItem('nv12', 'nv12'), OptionItem('d3d11', 'd3d11'), OptionItem('dxva2_vld', 'dxva2_vld')],
          ),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'H.264 (AVC)',
    tooltip: 'H.264 - H.264 又称为 MPEG-4 第 10 部分，高级视频编码（AVC），是一种面向块，基于运动补偿的视频编码标准。',
    encoders: [
      EncoderSpec(
        name: 'libx264',
        label: '【默认】libx264',
        rateControls: [
          ..._rcAutoList,
          _crf(
            max: 51,
            defaultCrf: 24,
            tags: [
              (0, '51（最低画质）'),
              (15, '36（低画质）'),
              (21, '30（一般画质）'),
              (27, '24（良画质）'),
              (33, '18（高画质）'),
              (39, '12（肉眼无损）'),
              (51, '0（最高画质）'),
            ],
          ),
          _cqp(max: 70, defaultQp: 34),
          _abrVideo,
          _cbrX264x265,
        ],
        parameters: [
          _h264265Preset,
          ParamSpec(
            parameter: 'tune',
            display: '编码倾重',
            mode: ParamMode.combo,
            items: [_default, _film, _animation, _grain, _stillimage, _psnr, _ssim, _fastdecode, _zerolatency],
          ),
          ParamSpec(
            parameter: 'profile:v',
            display: '规格',
            mode: ParamMode.combo,
            items: [_auto, _baseline, _main, _high, OptionItem('high422', 'high422'), OptionItem('high444', 'high444')],
          ),
          ParamSpec(parameter: 'level', display: '级别', mode: ParamMode.combo, items: _h264Level),
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [
              _auto,
              OptionItem('yuv420p', 'yuv420p'),
              OptionItem('yuvj420p', 'yuvj420p'),
              OptionItem('yuv422p', 'yuv422p'),
              OptionItem('yuvj422p', 'yuvj422p'),
              OptionItem('yuv444p', 'yuv444p'),
              OptionItem('yuvj444p', 'yuvj444p'),
              OptionItem('nv12', 'nv12'),
              OptionItem('nv16', 'nv16'),
              OptionItem('nv21', 'nv21'),
              OptionItem('yuv420p10le', 'yuv420p10le'),
              OptionItem('yuv422p10le', 'yuv422p10le'),
              OptionItem('yuv444p10le', 'yuv444p10le'),
              OptionItem('nv20le', 'nv20le'),
              OptionItem('gray', 'gray'),
              OptionItem('gray10le', 'gray10le'),
            ],
          ),
        ],
      ),
      EncoderSpec(
        name: 'libx264rgb',
        label: 'libx264rgb',
        rateControls: [
          ..._rcAutoList,
          _crf(max: 51, defaultCrf: 24),
          _cqp(max: 70, defaultQp: 34),
          _cbrX264x265,
          _abrVideo,
        ],
        parameters: [
          _h264265Preset,
          ParamSpec(
            parameter: 'tune',
            display: '编码倾重',
            mode: ParamMode.combo,
            items: [_default, _film, _animation, _grain, _stillimage, _psnr, _ssim, _fastdecode, _zerolatency],
          ),
          ParamSpec(parameter: 'level', display: '级别', mode: ParamMode.combo, items: _h264Level),
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [_auto, OptionItem('bgr0', 'bgr0'), OptionItem('bgr24', 'bgr24'), OptionItem('rgb24', 'rgb24')],
          ),
        ],
      ),
      EncoderSpec(
        name: 'h264_qsv',
        label: 'h264_qsv',
        tooltip: 'Intel 硬件加速编码器',
        rateControls: [..._rcAutoList, _q100Video, _abrVideo],
        parameters: [
          _qsvPreset,
          ParamSpec(parameter: 'profile:v', display: '规格', mode: ParamMode.combo, items: [_auto, _baseline, _main, _high]),
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [_auto, OptionItem('nv12', 'nv12'), OptionItem('qsv', 'qsv')],
          ),
        ],
      ),
      EncoderSpec(
        name: 'h264_nvenc',
        label: 'h264_nvenc',
        tooltip: 'NVIDIA 硬件加速编码器',
        rateControls: [
          ..._rcAutoList,
          _vbrNvencHQ,
          _vbrNvenc,
          _cqp(max: 51, defaultQp: 28),
          _cbrHw,
          _abrVideo,
        ],
        parameters: [
          ParamSpec(parameter: 'preset', display: '编码质量', mode: ParamMode.combo, items: _nvencPresetItems),
          ParamSpec(
            parameter: 'tune',
            display: '编码倾重',
            mode: ParamMode.combo,
            items: [_default, _psnr, _ssim, _fastdecode, _zerolatency],
          ),
          ParamSpec(
            parameter: 'profile:v',
            display: '规格',
            mode: ParamMode.combo,
            items: [_auto, _baseline, _main, _high, OptionItem('high444p', 'high444p')],
          ),
          ParamSpec(parameter: 'level', display: '级别', mode: ParamMode.combo, items: _h264Level),
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [
              _auto,
              OptionItem('yuv420p', 'yuv420p'),
              OptionItem('nv12', 'nv12'),
              OptionItem('p016le', 'p016le'),
              OptionItem('yuv444p', 'yuv444p'),
              OptionItem('p010le', 'p010le'),
              OptionItem('yuv444p16le', 'yuv444p16le'),
              OptionItem('bgr0', 'bgr0'),
              OptionItem('rgb0', 'rgb0'),
              OptionItem('cuda', 'cuda'),
              OptionItem('d3d11', 'd3d11'),
            ],
          ),
        ],
      ),
      EncoderSpec(
        name: 'h264_amf',
        label: 'h264_amf',
        tooltip: 'AMD 硬件加速编码器',
        rateControls: [..._rcAutoList, _qpAmf, _cbrHw, _abrVideo],
        parameters: [
          _amfPreset,
          ParamSpec(
            parameter: 'tune',
            display: '编码倾重',
            mode: ParamMode.combo,
            items: [
              _auto,
              OptionItem('transcoding', 'transcoding（默认）', '转码'),
              OptionItem('ultralowlatency', 'ultralowlatency', '超低延迟'),
              OptionItem('webcam', 'webcam', '网络摄像头'),
            ],
          ),
          ParamSpec(parameter: 'profile:v', display: '规格', mode: ParamMode.combo, items: [_auto, _baseline, _main, _high]),
          ParamSpec(parameter: 'level', display: '级别', mode: ParamMode.combo, items: _h264Level),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'VP9',
    tooltip: 'VP9 - VP9 是谷歌公司为了替换老旧的 VP8 影像编码格式并与 HEVC 竞争所开发的免费、开源的影像编码格式。',
    encoders: [
      EncoderSpec(
        name: 'libvpx-vp9',
        label: '【默认】libvpx-vp9',
        rateControls: [
          ..._rcAutoList,
          _crf(
            max: 63,
            defaultCrf: 29,
            tags: [
              (0, '63（最低画质）'),
              (9, '54（低画质）'),
              (19, '44（一般画质）'),
              (29, '34（良画质）'),
              (41, '22（高画质）'),
              (63, '0（有损最高画质）'),
            ],
          ),
          _abrVideo,
        ],
        parameters: [
          _vpxQuality,
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [
              _auto,
              OptionItem('yuv420p', 'yuv420p'),
              OptionItem('yuv422p', 'yuv422p'),
              OptionItem('yuv440p', 'yuv440p'),
              OptionItem('yuv444p', 'yuv444p'),
              OptionItem('yuv420p10le', 'yuv420p10le'),
              OptionItem('yuv422p10le', 'yuv422p10le'),
              OptionItem('yuv440p10le', 'yuv440p10le'),
              OptionItem('yuv444p10le', 'yuv444p10le'),
              OptionItem('yuv420p12le', 'yuv420p12le'),
              OptionItem('yuv422p12le', 'yuv422p12le'),
              OptionItem('yuv440p12le', 'yuv440p12le'),
              OptionItem('yuv444p12le', 'yuv444p12le'),
              OptionItem('gbrp', 'gbrp'),
              OptionItem('gbrp10le', 'gbrp10le'),
              OptionItem('gbrp12le', 'gbrp12le'),
            ],
          ),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'VP8',
    tooltip: 'VP8 - VP8 是一个由 On2 Technologies 开发并由 Google 发布的开放的影像压缩格式。',
    encoders: [
      EncoderSpec(
        name: 'libvpx',
        label: '【默认】libvpx',
        rateControls: [
          ..._rcAutoList,
          _crf(max: 63, defaultCrf: 30),
          _abrVideo,
        ],
        parameters: [
          _vpxQuality,
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [_auto, OptionItem('yuv420p', 'yuv420p'), OptionItem('yuva420p', 'yuva420p')],
          ),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'MPEG-4 (Part 2)',
    tooltip: 'MPEG-4 Part 2 - MPEG-4 是一套用于音频、视频信息的压缩编码标准。该标准的第二部分为视频编解码器。',
    encoders: [
      EncoderSpec(
        name: 'mpeg4',
        label: '【默认】mpeg4',
        rateControls: [
          ..._rcAutoList,
          _qMpeg4,
          _abrVideo,
        ],
        parameters: [
          ParamSpec(parameter: 'pix_fmt', display: '像素格式', mode: ParamMode.combo, items: _pixYuv420p),
        ],
      ),
      EncoderSpec(
        name: 'libxvid',
        label: 'libxvid',
        rateControls: [..._rcAutoList, _q100Video, _abrVideo],
        parameters: [
          ParamSpec(parameter: 'pix_fmt', display: '像素格式', mode: ParamMode.combo, items: _pixYuv420p),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'MPEG-2 (Part 2)',
    tooltip: 'MPEG-2 - MPEG-2 是 MPEG 工作组于 1994 年发布的视频和音频压缩国际标准，通常用来为广播信号提供视频和音频编码。',
    encoders: [
      EncoderSpec(
        name: 'mpeg2video',
        label: '【默认】mpeg2video',
        rateControls: [..._rcAutoList, _q100Video, _abrVideo],
        parameters: [
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [_auto, OptionItem('yuv420p', 'yuv420p'), OptionItem('yuv422p', 'yuv422p')],
          ),
        ],
      ),
      EncoderSpec(
        name: 'mpeg2_qsv',
        label: 'mpeg2_qsv',
        rateControls: [..._rcAutoList, _q100Video, _abrVideo],
        parameters: [
          _qsvPreset,
          ParamSpec(parameter: 'profile:v', display: '规格', mode: ParamMode.combo, items: [_auto, _main, _main10, OptionItem('mainsp', 'mainsp')]),
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [_auto, OptionItem('nv12', 'nv12'), OptionItem('qsv', 'qsv')],
          ),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'MPEG-1',
    tooltip: 'MPEG-1 - MPEG-1 是 MPEG 组织制定的第一个视频和音频有损压缩标准。',
    encoders: [
      EncoderSpec(
        name: 'mpeg1video',
        label: '【默认】mpeg1video',
        rateControls: [..._rcAutoList, _q100Video, _abrVideo],
        parameters: [
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [_auto, OptionItem('yuv420p', 'yuv420p'), OptionItem('yuv422p', 'yuv422p')],
          ),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'MJPEG',
    tooltip: 'MJPEG - MJPEG 即 Motion JPEG，是一种影像压缩格式，其中每一帧图像都分别使用 JPEG 编码。',
    encoders: [
      EncoderSpec(
        name: 'mjpeg',
        label: '【默认】mjpeg',
        rateControls: [..._rcAutoList, _qMjpeg, _abrVideo],
        parameters: [
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [_auto, OptionItem('yuvj420p', 'yuvj420p'), OptionItem('yuvj422p', 'yuvj422p'), OptionItem('yuvj444p', 'yuvj444p')],
          ),
        ],
      ),
      EncoderSpec(
        name: 'mjpeg_qsv',
        label: 'mjpeg_qsv',
        rateControls: [..._rcAutoList, _abrVideo],
        parameters: [
          ParamSpec(
            parameter: 'pix_fmt',
            display: '像素格式',
            mode: ParamMode.combo,
            items: [_auto, OptionItem('nv12', 'nv12'), OptionItem('qsv', 'qsv')],
          ),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'WMV2 (WMV v8)',
    tooltip: 'WMV2 - WMV 是微软公司开发的一组数字影片编解码格式的通称。WMV2 即 Windows Media Video v8',
    encoders: [
      EncoderSpec(
        name: 'wmv2',
        label: '【默认】wmv2',
        rateControls: [..._rcAutoList, _q100Video, _abrVideo],
        parameters: [
          ParamSpec(parameter: 'pix_fmt', display: '像素格式', mode: ParamMode.combo, items: [_auto, OptionItem('yuvj420p', 'yuvj420p')]),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'WMV1 (WMV v7)',
    tooltip: 'WMV1 - WMV 是微软公司开发的一组数字影片编解码格式的通称。WMV1 即 Windows Media Video v7',
    encoders: [
      EncoderSpec(
        name: 'wmv1',
        label: '【默认】wmv1',
        rateControls: [..._rcAutoList, _q100Video, _abrVideo],
        parameters: [
          ParamSpec(parameter: 'pix_fmt', display: '像素格式', mode: ParamMode.combo, items: [_auto, OptionItem('yuvj420p', 'yuvj420p')]),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'RV20',
    tooltip: 'RV20 - RealVideo 是由 RealNetworks 于 1997 年所开发的一种专用视频压缩格式。RV20 使用 H.263 编码器。',
    encoders: [
      EncoderSpec(
        name: 'rv20',
        label: '【默认】rv20',
        rateControls: [..._rcAutoList, _q100Video, _abrVideo],
        parameters: [
          ParamSpec(parameter: 'pix_fmt', display: '像素格式', mode: ParamMode.combo, items: [_auto, OptionItem('yuvj420p', 'yuvj420p')]),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'RV10',
    tooltip: 'RV10 - RealVideo 是由 RealNetworks 于 1997 年所开发的一种专用视频压缩格式。RV10 使用 H.263 编码器。',
    encoders: [
      EncoderSpec(
        name: 'rv10',
        label: '【默认】rv10',
        rateControls: [..._rcAutoList, _q100Video, _abrVideo],
        parameters: [
          ParamSpec(parameter: 'pix_fmt', display: '像素格式', mode: ParamMode.combo, items: [_auto, OptionItem('yuvj420p', 'yuvj420p')]),
        ],
      ),
    ],
  ),
];

// --- 内置音频编码族 ---

/// 与 web builtInAcodecs 一致（含闭包，不能为 const）。
final List<CodecFamilySpec> builtinAudioFamilies = [
  CodecFamilySpec(
    label: 'OPUS',
    tooltip: 'OPUS - Opus 是一个有损声音编码的格式，由 Xiph.Org 基金会开发，目标是希望用单一格式包含声音和语音。',
    encoders: [
      EncoderSpec(
        name: 'opus',
        label: '【默认】opus',
        rateControls: [..._rcAutoList, _cbrAudio],
        parameters: [
          ParamSpec(parameter: 'ar', display: '采样频率', mode: ParamMode.combo, items: _sr48000),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.combo, items: _loMonoStereo),
        ],
        strict2: true,
      ),
      EncoderSpec(
        name: 'libopus',
        label: 'libopus',
        rateControls: [..._rcAutoList, _qAudio, _cbrAudio],
        parameters: [
          ParamSpec(
            parameter: 'ar',
            display: '采样频率',
            mode: ParamMode.combo,
            items: [
              _auto,
              _sr(48000),
              _sr(24000),
              _sr(16000),
              _sr(12000),
              _sr(8000),
            ],
          ),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.text),
        ],
        strict2: true,
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'AAC',
    tooltip: 'AAC - AAC 即 Advanced Audio Coding，高级音频编码，为一种基于 MPEG-2 的有损数字音频压缩的专利音频编码标准。',
    encoders: [
      EncoderSpec(
        name: 'aac',
        label: '【默认】aac',
        rateControls: [..._rcAutoList, _qAudio, _cbrAudio],
        parameters: [
          ParamSpec(parameter: 'ar', display: '采样频率', mode: ParamMode.combo, items: _srAac),
          ParamSpec(
            parameter: 'aac_coder',
            display: '编码算法',
            mode: ParamMode.combo,
            items: [
              _auto,
              OptionItem('anmr', 'anmr', 'ANMR method'),
              OptionItem('twoloop', 'twoloop', 'Two loop searching method'),
              OptionItem('fast', 'fast（默认）', 'Default fast search'),
            ],
          ),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'Vorbis (OGG)',
    tooltip: 'Vorbis - Vorbis 是一种有损音频压缩格式，由 Xiph.Org 基金会所领导并开放源代码的一个免费的开源软件项目。',
    encoders: [
      EncoderSpec(
        name: 'vorbis',
        label: '【默认】vorbis',
        rateControls: [..._rcAutoList, _qAudio, _cbrAudio],
        parameters: [
          ParamSpec(parameter: 'ar', display: '采样频率', mode: ParamMode.text),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.text),
        ],
        strict2: true,
      ),
      EncoderSpec(
        name: 'libvorbis',
        label: 'libvorbis',
        rateControls: [..._rcAutoList, _qAudio, _cbrAudio],
        parameters: [
          ParamSpec(parameter: 'ar', display: '采样频率', mode: ParamMode.text),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.text),
        ],
        strict2: true,
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'MP3',
    tooltip: 'MP3 - MP3 即 MPEG-1 Audio Layer Ⅲ，是当今流行的一种数字音频编码和有损压缩格式。',
    encoders: [
      EncoderSpec(
        name: 'libmp3lame',
        label: '【默认】libmp3lame',
        rateControls: [..._rcAutoList, _qAudio, _cbrAudio],
        parameters: [
          ParamSpec(parameter: 'ar', display: '采样频率', mode: ParamMode.combo, items: _srCommon),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.combo, items: _loMonoStereo),
        ],
      ),
      EncoderSpec(
        name: 'libshine',
        label: 'libshine',
        rateControls: [..._rcAutoList, _cbrAudio],
        parameters: [
          ParamSpec(
            parameter: 'ar',
            display: '采样频率',
            mode: ParamMode.combo,
            items: [_auto, _sr(48000), _sr(44100), _sr(32000)],
          ),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.combo, items: _loMonoStereo),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'MP2',
    tooltip: 'MP2 - MP2 即 MPEG-1 Audio Layer Ⅱ。个人电脑和互联网音乐流行 MP3，MP2 则多用于广播。',
    encoders: [
      EncoderSpec(
        name: 'mp2',
        label: '【默认】mp2',
        rateControls: [..._rcAutoList, _cbrAudio],
        parameters: [
          ParamSpec(
            parameter: 'ar',
            display: '采样频率',
            mode: ParamMode.combo,
            items: [_auto, _sr(48000), _sr(44100), _sr(32000), _sr(24000), _sr(22050), _sr(16000)],
          ),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.combo, items: _loMonoStereo),
        ],
      ),
      EncoderSpec(
        name: 'mp2fixed',
        label: 'mp2fixed',
        rateControls: [..._rcAutoList, _cbrAudio],
        parameters: [
          ParamSpec(
            parameter: 'ar',
            display: '采样频率',
            mode: ParamMode.combo,
            items: [_auto, _sr(48000), _sr(44100), _sr(32000), _sr(24000), _sr(22050), _sr(16000)],
          ),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.combo, items: _loMonoStereo),
        ],
      ),
      EncoderSpec(
        name: 'libtwolame',
        label: 'libtwolame',
        rateControls: [..._rcAutoList, _qAudio, _cbrAudio],
        parameters: [
          ParamSpec(
            parameter: 'ar',
            display: '采样频率',
            mode: ParamMode.combo,
            items: [_auto, _sr(48000), _sr(44100), _sr(32000), _sr(24000), _sr(22050), _sr(16000)],
          ),
          ParamSpec(
            parameter: 'mode',
            display: '声道模式',
            mode: ParamMode.combo,
            items: [
              _auto,
              OptionItem('stereo', 'stereo', '立体声'),
              OptionItem('joint_stereo', 'joint_stereo', '联合立体声'),
              OptionItem('dual_channel', 'dual_channel', '双声道'),
              OptionItem('mono', 'mono', '单声道'),
            ],
          ),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'AC3',
    tooltip: 'AC3 - AC3 即杜比数字音频编码。杜比数字是美国杜比实验室开发的一系列有损和无损的多媒体单元格式。',
    encoders: [
      EncoderSpec(
        name: 'ac3',
        label: '【默认】ac3',
        rateControls: [..._rcAutoList, _cbrAudio],
        parameters: [
          ParamSpec(
            parameter: 'ar',
            display: '采样频率',
            mode: ParamMode.combo,
            items: [_auto, _sr(48000), _sr(44100), _sr(32000)],
          ),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.combo, items: _loMonoStereo),
        ],
      ),
      EncoderSpec(
        name: 'ac3_fixed',
        label: 'ac3_fixed',
        rateControls: [..._rcAutoList, _cbrAudio],
        parameters: [
          ParamSpec(
            parameter: 'ar',
            display: '采样频率',
            mode: ParamMode.combo,
            items: [_auto, _sr(48000), _sr(44100), _sr(32000)],
          ),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.combo, items: _loMonoStereo),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'FLAC',
    tooltip: 'FLAC - FLAC 即 Free Lossless Audio Codec，是一款的自由音频压缩编码，其特点是可以对音频文件无损压缩。',
    encoders: [
      EncoderSpec(
        name: 'flac',
        label: '【默认】flac',
        rateControls: [],
        parameters: [
          ParamSpec(parameter: 'ar', display: '采样频率', mode: ParamMode.text),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.text),
        ],
        strict2: true,
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'ALAC',
    tooltip: 'ALAC - ALAC 即 Apple Lossless Audio Codec，为苹果的无损音频压缩编码格式。',
    encoders: [
      EncoderSpec(
        name: 'alac',
        label: '【默认】alac',
        rateControls: [],
        parameters: [
          ParamSpec(parameter: 'ar', display: '采样频率', mode: ParamMode.text),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.combo, items: _loMonoStereo),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'WMA V2',
    tooltip: 'WMA 2 - WMA 是微软公司开发的一系列音频编解码器。',
    encoders: [
      EncoderSpec(
        name: 'wmav2',
        label: '【默认】wmav2',
        rateControls: [..._rcAutoList, _cbrAudio],
        parameters: [
          ParamSpec(parameter: 'ar', display: '采样频率', mode: ParamMode.text),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.text),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'WMA V1',
    tooltip: 'WMA 1 - WMA 是微软公司开发的一系列音频编解码器。',
    encoders: [
      EncoderSpec(
        name: 'wmav1',
        label: '【默认】wmav1',
        rateControls: [..._rcAutoList, _cbrAudio],
        parameters: [
          ParamSpec(parameter: 'ar', display: '采样频率', mode: ParamMode.text),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.combo, items: _loMonoStereo),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'DTS',
    tooltip: 'DTS - DTS 即 Digital Theater Systems，数字影院系统，为多声道音频格式中的一种。',
    encoders: [
      EncoderSpec(
        name: 'dca',
        label: '【默认】dca',
        rateControls: [..._rcAutoList, _cbrAudio],
        parameters: [
          ParamSpec(parameter: 'ar', display: '采样频率', mode: ParamMode.combo, items: _srCommon),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.combo, items: _loMonoStereo),
        ],
        strict2: true,
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'AMR WB',
    tooltip: 'AMR - AMR 即 Adaptive multi-Rate compression，自适应多速率音频压缩。',
    encoders: [
      EncoderSpec(
        name: 'libvo_amrwbenc',
        label: '【默认】libvo_amrwbenc',
        rateControls: [..._rcAutoList, _cbrAudio],
        parameters: [
          ParamSpec(parameter: 'ar', display: '采样频率', mode: ParamMode.text),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.text),
        ],
      ),
    ],
  ),
  CodecFamilySpec(
    label: 'AMR NB',
    tooltip: 'AMR - AMR 即 Adaptive multi-Rate compression，自适应多速率音频压缩。',
    encoders: [
      EncoderSpec(
        name: 'libopencore_amrnb',
        label: '【默认】libopencore_amrnb',
        rateControls: [..._rcAutoList, _cbrAudio],
        parameters: [
          ParamSpec(parameter: 'ar', display: '采样频率', mode: ParamMode.text),
          ParamSpec(parameter: 'channel_layout', display: '声道布局', mode: ParamMode.text),
        ],
      ),
    ],
  ),
];

// --- 内置复用器分组 ---

/// 与 web builtInMuxers 一致（提交值带扩展名 + 括号复用器名）。
const List<MuxerGroupSpec> builtinMuxerGroups = [
  MuxerGroupSpec(label: '常用', muxers: [
    MuxerSpec(value: '无', label: '无', tooltip: '不输出文件，转码完成即丢弃'),
  ]),
  MuxerGroupSpec(label: '视频', muxers: [
    MuxerSpec(
      value: 'mp4',
      label: 'MP4',
      tooltip: 'MP4 即 MPEG-4 Part 14 是一种标准的数字多媒体容器格式。\n默认视频编码器：h264\n默认音频编码器：aac',
      defaultVideoCodec: 'h264',
      defaultAudioCodec: 'aac',
    ),
    MuxerSpec(
      value: 'mkv (matroska)',
      label: 'MKV',
      tooltip: 'MKV 即 Matroska Video File 是一种开放源代码的多媒体封装格式。\n默认视频编码器：h264\n默认音频编码器：vorbis',
      defaultVideoCodec: 'h264',
      defaultAudioCodec: 'vorbis',
    ),
    MuxerSpec(
      value: 'mov (mp4)',
      label: 'MOV',
      tooltip: 'MOV 为 QuickTime Movie 的文件扩展名。QuickTime 是 MP4 的前身，由苹果公司开发。\n默认视频编码器：h264\n默认音频编码器：aac',
      defaultVideoCodec: 'h264',
      defaultAudioCodec: 'aac',
    ),
    MuxerSpec(
      value: 'flv',
      label: 'FLV',
      tooltip: 'FLV 即 Flash Video，是一种应用在 SWF 中的网络视频格式。\n默认视频编码器：flv1\n默认音频编码器：mp3',
      defaultVideoCodec: 'flv1',
      defaultAudioCodec: 'mp3',
    ),
    MuxerSpec(
      value: 'ts (mpegts)',
      label: 'TS',
      tooltip: 'TS 即 MPEG2-TS 传输流，用于数字电视广播系统。\n默认视频编码器：mpeg2video\n默认音频编码器：mp2',
      defaultVideoCodec: 'mpeg2video',
      defaultAudioCodec: 'mp2',
    ),
    MuxerSpec(
      value: '3gp',
      label: '3GP',
      tooltip: '3GP 是 MP4 的一种简化版本。\n默认视频编码器：h263\n默认音频编码器：amr_nb',
      defaultVideoCodec: 'h263',
      defaultAudioCodec: 'amr_nb',
    ),
    MuxerSpec(
      value: 'wmv (asf)',
      label: 'WMV',
      tooltip: 'WMV 即 Windows Media Video 是微软公司开发的一组数字影片编解码格式的通称。\n默认视频编码器：msmpeg4v3\n默认音频编码器：wmav2',
      defaultVideoCodec: 'msmpeg4v3',
      defaultAudioCodec: 'wmav2',
    ),
    MuxerSpec(
      value: 'avi',
      label: 'AVI',
      tooltip: 'AVI 即 Audio Video Interleave 是由微软在 1992 年推出的一种多媒体文件格式。\n默认视频编码器：mpeg4\n默认音频编码器：mp3',
      defaultVideoCodec: 'mpeg4',
      defaultAudioCodec: 'mp3',
    ),
    MuxerSpec(
      value: 'dvd',
      label: 'DVD',
      tooltip: '（另有 .vob 扩展名）\n默认视频编码器：mpeg2video\n默认音频编码器：mp2',
      defaultVideoCodec: 'mpeg2video',
      defaultAudioCodec: 'mp2',
    ),
  ]),
  MuxerGroupSpec(label: '音频', muxers: [
    MuxerSpec(
      value: 'aac (adts)',
      label: 'AAC',
      tooltip: 'AAC（Advanced Audio Coding）是一种有损音频压缩格式。\n默认音频编码器：aac',
      defaultAudioCodec: 'aac',
    ),
    MuxerSpec(
      value: 'opus',
      label: 'OPUS',
      tooltip: 'Opus 是一种开放、免专利费的音频编码格式。\n默认音频编码器：libopus',
      defaultAudioCodec: 'libopus',
    ),
    MuxerSpec(
      value: 'ogg',
      label: 'OGG',
      tooltip: 'OGG 是一个开放容器格式。\n默认音频编码器：libvorbis',
      defaultAudioCodec: 'libvorbis',
    ),
    MuxerSpec(
      value: 'mp3',
      label: 'MP3',
      tooltip: 'MP3（MPEG-1 Audio Layer III）是一种古老且被广泛使用的有损音频压缩格式。\n默认音频编码器：libmp3lame',
      defaultAudioCodec: 'libmp3lame',
    ),
    MuxerSpec(
      value: 'mp2',
      label: 'MP2',
      tooltip: 'MP2（MPEG-1 Audio Layer II）广泛用于广播和数字电视音频传输。\n默认音频编码器：mp2',
      defaultAudioCodec: 'mp2',
    ),
    MuxerSpec(
      value: 'ac3',
      label: 'AC3',
      tooltip: 'AC-3（Dolby Digital）是杜比实验室开发的音频压缩技术。\n默认音频编码器：ac3',
      defaultAudioCodec: 'ac3',
    ),
    MuxerSpec(
      value: 'flac',
      label: 'FLAC',
      tooltip: 'FLAC（Free Lossless Audio Codec）是一种无损音频压缩格式。\n默认音频编码器：flac',
      defaultAudioCodec: 'flac',
    ),
    MuxerSpec(
      value: 'dts',
      label: 'DTS',
      tooltip: 'DTS（Digital Theater Systems）是一种用于影院及家庭影院的音频压缩技术。\n默认音频编码器：dca',
      defaultAudioCodec: 'dca',
    ),
    MuxerSpec(
      value: 'amr',
      label: 'AMR',
      tooltip: 'AMR（Adaptive Multi-Rate）是一种音频压缩格式，优化用于语音编码。\n默认音频编码器：libopencore_amrnb',
      defaultAudioCodec: 'libopencore_amrnb',
    ),
  ]),
  MuxerGroupSpec(label: '图像（静态）', muxers: [
    MuxerSpec(value: 'bmp (image2)', label: 'BMP', tooltip: 'BMP（Bitmap）是一种由微软开发的通常为不压缩的图像格式。'),
    MuxerSpec(value: 'jpg (image2)', label: 'JPG/JPEG', tooltip: 'JPEG 是一种针对照片影像而广泛使用的有损压缩标准方法。'),
    MuxerSpec(value: 'png (image2)', label: 'PNG', tooltip: 'PNG（Portable Network Graphics）是一种无损压缩的图像格式，支持透明通道。'),
    MuxerSpec(value: 'tif (image2)', label: 'TIF/TIFF', tooltip: 'TIFF 是一种灵活的图像格式，支持无损和有损压缩。'),
    MuxerSpec(value: 'avif (image2)', label: 'AVIF', tooltip: 'AVIF 是一种基于 AV1 编码的视频图像格式。'),
    MuxerSpec(value: 'apng (image2)', label: 'APNG', tooltip: 'APNG 是对 PNG 的扩展，支持帧动画。'),
    MuxerSpec(value: 'webp (image2)', label: 'WEBP', tooltip: 'WebP 是由 Google 开发的衍生自 VP8 的现代图像格式。'),
    MuxerSpec(value: 'gif (image2)', label: 'GIF', tooltip: 'GIF 是一种古老的支持帧动画的图像格式。'),
  ]),
  MuxerGroupSpec(label: '图像（动态）', muxers: [
    MuxerSpec(value: 'apng', label: 'APNG', tooltip: 'APNG 是对 PNG 的扩展，支持帧动画。'),
    MuxerSpec(value: 'avif', label: 'AVIF', tooltip: 'AVIF 是一种基于 AV1 编码的视频图像格式。'),
    MuxerSpec(value: 'gif', label: 'GIF', tooltip: 'GIF 是一种古老的支持帧动画的图像格式。'),
    MuxerSpec(value: 'webp', label: 'WEBP', tooltip: 'WebP 是由 Google 开发的现代图像格式。'),
    MuxerSpec(value: 'h264', label: 'h264', tooltip: 'h.264 裸流'),
    MuxerSpec(value: 'hevc', label: 'hevc', tooltip: 'hevc 裸流'),
    MuxerSpec(value: 'mjpeg', label: 'mjpeg', tooltip: 'mjpeg 裸流'),
  ]),
];

// --- 分辨率 ---

/// 常用分辨率（label 为显示值，value 为提交值）。
const List<OptionItem> resolutionList = [
  OptionItem('不改变', '不改变', '不改变分辨率'),
  OptionItem('3840x2160', '3840×2160', 'UHD 4K, 8.3M 像素'),
  OptionItem('2560x1440', '2560×1440', 'QHD 2K, 3.7M 像素'),
  OptionItem('1920x1080', '1920×1080', 'FHD, 2.0M 像素'),
  OptionItem('1280x720', '1280×720', 'HD, 921.6K 像素'),
  OptionItem('960x540', '960×540', 'qHD, 518.4K 像素'),
  OptionItem('640x360', '640×360', '230.4K 像素'),
  OptionItem('2160x3840', '2160×3840', '纵向 UHD 4K'),
  OptionItem('1080x1920', '1080×1920', '纵向 FHD'),
  OptionItem('720x1280', '720×1280', '纵向 HD'),
  OptionItem('854x480', '854×480', 'FWVGA, 409.9K 像素'),
  OptionItem('640x480', '640×480', 'VGA, 307.2K 像素'),
  OptionItem('480x360', '480×360', '172.8K 像素'),
  OptionItem('320x240', '320×240', 'qVGA, 76.8K 像素'),
];

// --- 帧率 ---

/// 常用帧率。
const List<OptionItem> framerateList = [
  OptionItem('不改变', '不改变', '按源平均帧率输出'),
  OptionItem('60', '60', '60p（常见屏幕刷新率）'),
  OptionItem('50', '50', '50p'),
  OptionItem('30', '30', '30p'),
  OptionItem('25', '25', '25p（PAL 帧频）'),
  OptionItem('24', '24', '24p（常见电影制作标准）'),
  OptionItem('15', '15', '15p'),
  OptionItem('12', '12', '12p'),
  OptionItem('10', '10', '10p'),
  OptionItem('5', '5', '5p'),
  OptionItem('1', '1', '1p'),
];

// --- 元数据 / 文件时间保留 ---

/// 元数据保留策略（keepMetadata）。
const List<OptionItem> keepMetadataList = [
  OptionItem('', '无'),
  OptionItem('map', 'map metadata', '该方式主要用于保留大多数标签、描述信息，如创建时间、作者信息等元数据'),
  OptionItem('movflags', 'move flags', '该方式主要用于某些特定元数据，如对于 MP4/MOV 容器，FFmpeg 将内部 metadata 映射为 QuickTime 的 udta 元数据'),
  OptionItem('both', '两者'),
];

/// 文件时间保留策略（keepFileTime）。
const List<OptionItem> keepFileTimeList = [
  OptionItem('', '无'),
  OptionItem('original', '原样复制文件时间', '输出文件的创建时间、修改时间、访问时间将从输入文件的时间原样复制'),
  OptionItem('autoShift', '复制修正后的文件时间（依创建时间）', '输出文件的创建时间、修改时间将以创建时间为基准，按照剪裁位置自动调整后进行修改'),
  OptionItem('fixCTbyMTandShift', '复制修正后的文件时间（依修改时间）', '以修改时间为基准，按照剪裁位置自动调整后进行修改'),
  OptionItem('fixByFilenameAndShift', '根据文件名修正新文件时间', '将通过识别文件名中的时间作为创建时间（按当前系统时区），根据剪裁位置自动调整后进行修改'),
];

// --- 输出路径模板说明 ---

/// 输出路径占位符说明（mux.filePath）。
const String filePathTemplateHint = '[filedir]：首个输入文件所在目录\n[filename]：首个输入文件基础名\n[fileext]：文件扩展名\n[taskId]：任务 ID\n[taskIndex]：任务序号\n[runIndex]：运行次序\n[outputIndex]：输出序号\n\n默认值：[filedir]/[filename].[fileext]';
