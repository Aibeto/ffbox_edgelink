import 'package:ffbox_edgelink/application/upload/upload_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

/// 上传协议模块单元测试：占位符、缓存键、分段方案、文件哈希与默认输出参数。
///
/// 位于 test 层，验证 application 层 `upload_protocol.dart` 的纯函数语义
/// 与 FFBox web 前端（transferManager2.ts / defaultParams.ts）保持一致。

void main() {
  group('uploadPlaceholder', () {
    test('生成 [uploading] 前缀占位符', () {
      expect(uploadPlaceholder('video.mp4'), '[uploading] video.mp4');
    });
  });

  group('uploadCacheKey', () {
    test('用 U+2B1D 分隔文件名与哈希', () {
      expect(uploadCacheKey('a.mkv', 'deadbeef'), 'a.mkv⬝deadbeef');
    });
  });

  group('segmentPlan', () {
    test('小于 1GB 用 4MB 十进制分段', () {
      final plan = segmentPlan(10 * 1000 * 1000); // 10MB
      expect(plan.length, 3);
      expect(plan[0], (offset: 0, length: 4 * 1000 * 1000));
      expect(plan[1], (offset: 4 * 1000 * 1000, length: 4 * 1000 * 1000));
      expect(plan[2], (offset: 8 * 1000 * 1000, length: 2 * 1000 * 1000));
    });

    test('大于等于 1GB 用 20MB 分段', () {
      final plan = segmentPlan(1 * 1000 * 1000 * 1000);
      expect(plan.length, 50);
      expect(plan.first.length, 20 * 1000 * 1000);
    });
  });

  group('fileHashOf', () {
    test('对分片哈希拼接的 UTF-8 再取 SHA1', () {
      // 单分片哈希取 "abc" 的 SHA1（echo -n "abc" | sha1sum），
      // 文件哈希 = SHA1("a9993e...d89d")（期望值经 PowerShell SHA1 独立计算核对）
      expect(
        fileHashOf(['a9993e364706816aba3e25717850c26c9cd0d89d']),
        '9ef2bdeea2b1bae79b9ddb930427d0b2c880bdac',
      );
    });
  });

  group('buildOutputParams', () {
    test('嵌入三段输出配置且其余字段为 FFBox 默认值', () {
      final video = {
        'vcodec': 'libx264',
        'resolution': '不改变',
        'framerate': '不改变',
        'ratecontrol': 'CRF',
        'detail': {'crf': 20},
      };
      final audio = {'acodec': 'copy', 'detail': <String, dynamic>{}};
      final mux = {'format': 'mp4', 'moveflags': false, 'detail': <String, dynamic>{}};
      final p = buildOutputParams(video: video, audio: audio, mux: mux);
      expect(p['input']['files'][0]['demuxer'], '自动');
      expect(p['outputs'][0]['video']['vcodec'], 'libx264');
      expect(p['outputs'][0]['video']['ratecontrol'], 'CRF');
      expect(p['outputs'][0]['video']['detail']['crf'], 20);
      expect(p['outputs'][0]['audio']['acodec'], 'copy');
      expect(p['outputs'][0]['mux']['format'], 'mp4');
      expect(p['extra']['presetName'], '默认配置');
    });
  });
}
