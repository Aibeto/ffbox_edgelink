import 'package:flutter_test/flutter_test.dart';
import 'package:ffbox_edgelink/application/task/task_state_machine.dart';
import 'package:ffbox_edgelink/domain/entities/task_operation.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';

void main() {
  group('TaskStateMachine.allowedOperations', () {
    test('idle allows start, ready, delete', () {
      final ops = TaskStateMachine.allowedOperations(TaskStatus.idle);
      expect(ops, containsAll({TaskOperation.start, TaskOperation.ready, TaskOperation.delete}));
      expect(ops, isNot(contains(TaskOperation.pause)));
    });

    test('running allows only pause', () {
      expect(TaskStateMachine.allowedOperations(TaskStatus.running),
          {TaskOperation.pause});
    });

    test('paused allows resume, ready, reset', () {
      final ops = TaskStateMachine.allowedOperations(TaskStatus.paused);
      expect(ops, containsAll({TaskOperation.resume, TaskOperation.ready, TaskOperation.reset}));
      expect(ops, isNot(contains(TaskOperation.delete)));
    });

    test('finished allows reset and delete', () {
      expect(TaskStateMachine.allowedOperations(TaskStatus.finished),
          containsAll({TaskOperation.reset, TaskOperation.delete}));
    });

    test('deleted allows nothing', () {
      expect(TaskStateMachine.allowedOperations(TaskStatus.deleted), isEmpty);
    });
  });

  group('TaskStateMachine.canExecute', () {
    test('returns true for allowed operation', () {
      expect(TaskStateMachine.canExecute(TaskStatus.idle, TaskOperation.start), isTrue);
    });

    test('returns false for disallowed operation', () {
      expect(TaskStateMachine.canExecute(TaskStatus.running, TaskOperation.delete), isFalse);
    });
  });
}
