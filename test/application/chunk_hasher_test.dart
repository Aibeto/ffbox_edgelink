import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffbox_edgelink/application/upload/chunk_hasher.dart';
import 'package:ffbox_edgelink/application/upload/upload_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('多分片哈希与分段方案一致', () async {
    final dir = await Directory.systemTemp.createTemp('chunk_hash_test');
    final file = File('${dir.path}/data.bin');
    final data = List<int>.generate(9 * 1000 * 1000, (i) => i % 251);
    await file.writeAsBytes(data);

    final plan = segmentPlan(data.length);
    expect(plan.length, 3);

    final hashes = await ChunkHasher().hashSegments(file.path, plan);
    expect(hashes, hasLength(3));
    expect(
      hashes[0],
      sha1.convert(data.sublist(0, 4 * 1000 * 1000)).toString(),
    );
    expect(
      hashes[2],
      sha1.convert(data.sublist(8 * 1000 * 1000)).toString(),
    );

    await dir.delete(recursive: true);
  });

  test('顺序读取保证分片哈希按序返回', () async {
    final dir = await Directory.systemTemp.createTemp('chunk_hash_test2');
    final file = File('${dir.path}/seq.bin');
    final data = List<int>.filled(4 * 1000 * 1000 + 10, 7);
    await file.writeAsBytes(data);

    final hashes = await ChunkHasher().hashSegments(
      file.path,
      segmentPlan(data.length),
    );
    // 末片只有 10 字节，全 7
    expect(
      hashes[1],
      sha1.convert(List<int>.filled(10, 7)).toString(),
    );
    await dir.delete(recursive: true);
  });
}
