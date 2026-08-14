import 'package:flutter/material.dart';
import 'package:ffbox_edgelink/application/task/task_state_machine.dart';
import 'package:ffbox_edgelink/domain/entities/task.dart';
import 'package:ffbox_edgelink/domain/entities/task_operation.dart';
import 'package:ffbox_edgelink/domain/entities/task_status.dart';

/// 首版暴露的基本操作。
const _basicOperations = {
  TaskOperation.start,
  TaskOperation.pause,
  TaskOperation.resume,
  TaskOperation.delete,
};

class TaskTile extends StatelessWidget {
  final Task task;
  final Future<void> Function(TaskOperation operation) onOperation;

  const TaskTile({super.key, required this.task, required this.onOperation});

  static const _labels = {
    TaskOperation.start: '启动',
    TaskOperation.pause: '暂停',
    TaskOperation.resume: '继续',
    TaskOperation.delete: '删除',
  };

  @override
  Widget build(BuildContext context) {
    final allowed = TaskStateMachine.allowedOperations(task.status);
    final actions = _basicOperations.where(allowed.contains).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.taskName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('状态：${task.status.apiValue}'),
                  if (task.status == TaskStatus.running)
                    Text('已运行 ${task.elapsedSeconds.toStringAsFixed(1)}s'),
                ],
              ),
            ),
            for (final op in actions)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: TextButton(
                  onPressed: () => onOperation(op),
                  child: Text(_labels[op]!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
