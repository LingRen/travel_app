import 'activity_type.dart';
import 'workout_status.dart';
import 'workout_summary.dart';

/// 一次运动，对应 `workouts` 表的一行。
class Workout {
  const Workout({
    this.id,
    required this.startedAtMs,
    this.endedAtMs,
    required this.status,
    this.title,
    this.activityType = ActivityType.cycling,
    this.summary,
    this.hrDeviceName,
    this.cadenceDeviceName,
    this.powerDeviceName,
  });

  final int? id;
  final int startedAtMs;
  final int? endedAtMs;
  final WorkoutStatus status;
  final String? title;

  /// 本次运动的类型。开始记录时冻结落库，历史/统计按它聚合。
  final ActivityType activityType;

  /// 进行中的运动为 null。
  final WorkoutSummary? summary;
  final String? hrDeviceName;
  final String? cadenceDeviceName;
  final String? powerDeviceName;

  Map<String, Object?> toDbMap() => <String, Object?>{
    if (id != null) 'id': id,
    'started_at': startedAtMs,
    'ended_at': endedAtMs,
    'status': status.dbValue,
    'title': title,
    'activity_type': activityType.dbValue,
    'hr_device_name': hrDeviceName,
    'cadence_device_name': cadenceDeviceName,
    'power_device_name': powerDeviceName,
    if (summary != null) ...summary!.toDbColumns(),
  };

  static Workout fromDbMap(Map<String, Object?> m) => Workout(
    id: (m['id'] as num?)?.toInt(),
    startedAtMs: (m['started_at'] as num).toInt(),
    endedAtMs: (m['ended_at'] as num?)?.toInt(),
    status: WorkoutStatus.fromDb(m['status'] as String),
    title: m['title'] as String?,
    activityType: ActivityType.fromDb(m['activity_type'] as String?),
    summary: m['distance_m'] == null ? null : WorkoutSummary.fromDbColumns(m),
    hrDeviceName: m['hr_device_name'] as String?,
    cadenceDeviceName: m['cadence_device_name'] as String?,
    powerDeviceName: m['power_device_name'] as String?,
  );
}
