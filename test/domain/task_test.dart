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

  group('Task run selection', () {
    test('picks latest running run instead of stale error run', () {
      final task = Task.fromJson({
        'taskName': 'x',
        'status': 'running',
        'runs': [
          {'status': 'idle', 'elapsed': 0, 'errorInfo': [], 'outputFiles': []},
          {
            'status': 'error',
            'elapsed': 50,
            'errorInfo': ['旧错误'],
            'outputFiles': ['old.mp4'],
          },
          {
            'status': 'running',
            'elapsed': 5,
            'errorInfo': [],
            'outputFiles': ['new.mp4'],
          },
        ],
      });
      expect(task.elapsedSeconds, 5);
      expect(task.errorInfo, isEmpty);
      expect(task.outputFiles, ['new.mp4']);
    });

    test('idle after reset ignores old run error info', () {
      final task = Task.fromJson({
        'taskName': 'x',
        'status': 'idle',
        'runs': [
          {'status': 'idle', 'elapsed': 0, 'errorInfo': [], 'outputFiles': []},
          {
            'status': 'error',
            'elapsed': 50,
            'errorInfo': ['旧错误'],
            'outputFiles': ['old.mp4'],
          },
          {'status': 'idle', 'elapsed': 0, 'errorInfo': [], 'outputFiles': []},
        ],
      });
      expect(task.errorInfo, isEmpty);
      expect(task.elapsedSeconds, 0);
    });

    test('activeRun returns the latest running run', () {
      final task = Task.fromJson({
        'taskName': 'x',
        'status': 'running',
        'runs': [
          {'status': 'idle', 'elapsed': 0, 'errorInfo': [], 'outputFiles': []},
          {
            'status': 'error',
            'elapsed': 50,
            'errorInfo': ['旧错误'],
            'outputFiles': ['old.mp4'],
          },
          {
            'status': 'running',
            'elapsed': 0,
            'errorInfo': [],
            'outputFiles': ['new.mp4'],
          },
        ],
      });
      final run = task.activeRun;
      expect(run, isNotNull);
      expect(run!.status, 'running');
      expect(run.outputFiles, ['new.mp4']);
      expect(run.errorInfo, isEmpty);
    });

    test('error run keeps its error when task is in error state', () {
      final task = Task.fromJson({
        'taskName': 'x',
        'status': 'error',
        'runs': [
          {'status': 'idle', 'elapsed': 0, 'errorInfo': [], 'outputFiles': []},
          {
            'status': 'error',
            'elapsed': 50,
            'errorInfo': ['转码失败'],
            'outputFiles': [],
          },
        ],
      });
      expect(task.errorInfo, ['转码失败']);
      expect(task.activeRun?.status, 'error');
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
