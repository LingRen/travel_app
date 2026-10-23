import 'package:cycling_app/domain/models/activity_type.dart';
import 'package:cycling_app/domain/models/workout.dart';
import 'package:cycling_app/domain/models/workout_status.dart';
import 'package:cycling_app/domain/models/workout_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('进行中的运动没有汇总指标', () {
    const Workout workout = Workout(startedAtMs: 1000, status: WorkoutStatus.recording);
    final Map<String, Object?> row = workout.toDbMap();

    expect(row['distance_m'], isNull);
    expect(Workout.fromDbMap(<String, Object?>{...row, 'id': 1}).summary, isNull);
  });

  test('已完成的运动汇总指标往返一致', () {
    const Workout workout = Workout(
      id: 5,
      startedAtMs: 1000,
      endedAtMs: 3601000,
      status: WorkoutStatus.finished,
      title: '晨骑',
      summary: WorkoutSummary(
        distanceM: 25000,
        durationS: 3600,
        movingS: 3400,
        avgSpeedMps: 6.94,
        movingAvgSpeedMps: 7.35,
        maxSpeedMps: 12.5,
        elevationGainM: 180,
        avgHr: 142,
        maxHr: 176,
        avgCadence: 84,
        calories: 720,
        pointCount: 3600,
      ),
      hrDeviceName: 'HUAWEI WATCH FIT 3',
    );

    final Workout back = Workout.fromDbMap(workout.toDbMap());

    expect(back.id, 5);
    expect(back.status, WorkoutStatus.finished);
    expect(back.title, '晨骑');
    expect(back.summary!.distanceM, 25000);
    expect(back.summary!.maxHr, 176);
    expect(back.summary!.calories, 720);
    expect(back.hrDeviceName, 'HUAWEI WATCH FIT 3');
  });

  test('未知状态字符串直接抛错', () {
    expect(() => WorkoutStatus.fromDb('running'), throwsArgumentError);
  });

  test('ActivityType.fromDb 未知值回退骑行', () {
    expect(ActivityType.fromDb(null), ActivityType.cycling);
    expect(ActivityType.fromDb('unknown'), ActivityType.cycling);
    expect(ActivityType.fromDb('running'), ActivityType.running);
  });

  test('ActivityType 能力集', () {
    expect(ActivityType.cycling.supportsCadence, isTrue);
    expect(ActivityType.cycling.supportsPower, isTrue);
    expect(ActivityType.cycling.supportsSpeedTierCue, isTrue);
    expect(ActivityType.cycling.usesPace, isFalse);
    expect(ActivityType.running.supportsCadence, isFalse);
    expect(ActivityType.running.supportsPower, isFalse);
    expect(ActivityType.running.supportsSpeedTierCue, isFalse);
    expect(ActivityType.running.usesPace, isTrue);
    expect(ActivityType.walking.usesPace, isTrue);
    expect(ActivityType.hiking.usesPace, isTrue);
  });

  test('toDbMap/fromDbMap 往返携带 activity_type', () {
    final Workout w = Workout(
      startedAtMs: 1000,
      status: WorkoutStatus.recording,
      activityType: ActivityType.running,
    );
    final Workout back = Workout.fromDbMap(w.toDbMap());
    expect(back.activityType, ActivityType.running);
    // 默认类型是骑行，与迁移后旧记录一致。
    expect(
      Workout.fromDbMap(const <String, Object?>{'started_at': 1, 'status': 'recording'}).activityType,
      ActivityType.cycling,
    );
  });
}
