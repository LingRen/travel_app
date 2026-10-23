/// 运动会话状态。与 `workouts.status` 列的取值一一对应。
enum WorkoutStatus {
  recording('recording'),
  paused('paused'),
  finished('finished');

  const WorkoutStatus(this.dbValue);

  /// 写入 SQLite 的字符串值。
  final String dbValue;

  /// 从数据库字符串还原。未知值直接抛错，不静默兜底。
  static WorkoutStatus fromDb(String value) {
    for (final WorkoutStatus s in WorkoutStatus.values) {
      if (s.dbValue == value) return s;
    }
    throw ArgumentError('未知的运动状态: $value');
  }

  /// 是否属于「未结束」，用于启动时的崩溃恢复扫描。
  bool get isUnfinished => this != WorkoutStatus.finished;
}
