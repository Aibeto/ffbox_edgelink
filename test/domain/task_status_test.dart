import 'package:flutter_test/flutter_test.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';

void main() {
  group('TaskStatus.parse', () {
    test('parses all known statuses', () {
      expect(TaskStatus.parse('idle'), TaskStatus.idle);
      expect(TaskStatus.parse('running'), TaskStatus.running);
      expect(TaskStatus.parse('paused'), TaskStatus.paused);
      expect(TaskStatus.parse('finished'), TaskStatus.finished);
      expect(TaskStatus.parse('error'), TaskStatus.error);
      expect(TaskStatus.parse('deleted'), TaskStatus.deleted);
    });

    test('throws on unknown status', () {
      expect(() => TaskStatus.parse('nope'), throwsA(isA<FormatException>()));
    });
  });
}
