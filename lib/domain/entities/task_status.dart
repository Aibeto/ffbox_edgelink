/// FFBox 任务状态。对应后端 TaskStatus 枚举。
enum TaskStatus {
  deleted,
  initializing,
  idle,
  idleQueued,
  running,
  paused,
  pausedQueued,
  stopping,
  finishing,
  finished,
  error;

  /// 从后端字符串解析状态。未知状态抛出 [FormatException]。
  static TaskStatus parse(String raw) {
    const map = <String, TaskStatus>{
      'deleted': TaskStatus.deleted,
      'initializing': TaskStatus.initializing,
      'idle': TaskStatus.idle,
      'idle_queued': TaskStatus.idleQueued,
      'running': TaskStatus.running,
      'paused': TaskStatus.paused,
      'paused_queued': TaskStatus.pausedQueued,
      'stopping': TaskStatus.stopping,
      'finishing': TaskStatus.finishing,
      'finished': TaskStatus.finished,
      'error': TaskStatus.error,
    };
    final value = map[raw];
    if (value == null) {
      throw FormatException('Unknown TaskStatus: $raw');
    }
    return value;
  }

  /// 还原为后端使用的字符串。
  String get apiValue => switch (this) {
        TaskStatus.deleted => 'deleted',
        TaskStatus.initializing => 'initializing',
        TaskStatus.idle => 'idle',
        TaskStatus.idleQueued => 'idle_queued',
        TaskStatus.running => 'running',
        TaskStatus.paused => 'paused',
        TaskStatus.pausedQueued => 'paused_queued',
        TaskStatus.stopping => 'stopping',
        TaskStatus.finishing => 'finishing',
        TaskStatus.finished => 'finished',
        TaskStatus.error => 'error',
      };
}
