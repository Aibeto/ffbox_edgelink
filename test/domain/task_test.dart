import 'package:flutter_test/flutter_test.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';

void main() {
  group('Task.fromJson', () {
    test('parses minimal valid JSON', () {
      final task = Task.fromJson({
        'taskName': 'demo.mp4',
        'status': 'running',
        'runs': [
          {'elapsed': 12.5, 'errorInfo': [], 'outputFiles': []},
        ],
      });

      expect(task.taskName, 'demo.mp4');
      expect(task.status, TaskStatus.running);
      expect(task.elapsedSeconds, 12.5);
    });

    test('defaults missing optional fields', () {
      final task = Task.fromJson({'taskName': 'x', 'status': 'idle'});
      expect(task.elapsedSeconds, 0);
      expect(task.errorInfo, isEmpty);
    });
  });
}
