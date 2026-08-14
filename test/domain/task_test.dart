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

    test('parses id from JSON', () {
      final task = Task.fromJson({'id': 42, 'taskName': 'x', 'status': 'idle'});
      expect(task.id, 42);
    });

    test('parses progress from before.duration and progressLog.time', () {
      final task = Task.fromJson({
        'taskName': 'x',
        'status': 'running',
        'before': [
          {'duration': 120.0},
        ],
        'runs': [
          {
            'elapsed': 30.0,
            'progressLog': {
              'time': [
                [0, 60.0],
              ],
            },
          },
        ],
      });
      expect(task.durationSeconds, 120.0);
      expect(task.processedSeconds, 60.0);
      expect(task.progress, closeTo(0.5, 0.01));
      expect(task.estimatedRemaining, closeTo(30.0, 0.1));
    });

    test('defaults missing optional fields', () {
      final task = Task.fromJson({'taskName': 'x', 'status': 'idle'});
      expect(task.elapsedSeconds, 0);
      expect(task.errorInfo, isEmpty);
      expect(task.progress, -1);
      expect(task.estimatedRemaining, -1);
    });
  });

  group('Task.formatDuration', () {
    test('formats seconds', () {
      expect(Task.formatDuration(0), '0:00');
      expect(Task.formatDuration(65), '1:05');
      expect(Task.formatDuration(3661), '1:01:01');
    });
  });
}
