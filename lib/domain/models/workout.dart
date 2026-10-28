import 'activity_type.dart';
import 'workout_conditions.dart';
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
    this.placeName,
    this.placeShort,
    this.weatherText,
    this.weatherTempC,
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

  /// 开始记录时捕获的完整地名，形如「成都市 · 龙泉驿区 · 山泉镇」。
  ///
  /// 旧记录没有这个字段，保持 null；详情页据此整行省略，不回填假地名。
  final String? placeName;

  /// 历史列表用的短地名，通常是区县。
  final String? placeShort;

  /// 天气描述，形如「晴」；旧记录或查询失败时为 null。
  final String? weatherText;

  /// 开始记录时的气温（摄氏度，整数）；旧记录或查询失败时为 null。
  final int? weatherTempC;

  /// 把四个地点 / 天气列组合成界面模型。
  WorkoutConditions get conditions => WorkoutConditions(
    placeName: placeName,
    placeShort: placeShort,
    weatherText: weatherText,
    weatherTempC: weatherTempC,
  );

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
    'place_name': placeName,
    'place_short': placeShort,
    'weather_text': weatherText,
    'weather_temp_c': weatherTempC,
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
    placeName: m['place_name'] as String?,
    placeShort: m['place_short'] as String?,
    weatherText: m['weather_text'] as String?,
    weatherTempC: (m['weather_temp_c'] as num?)?.toInt(),
  );
}
