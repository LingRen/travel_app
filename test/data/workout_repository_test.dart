import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/settings_dao.dart';
import 'package:cycling_app/data/db/track_point_dao.dart';
import 'package:cycling_app/data/db/workout_dao.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/data/workout_repository.dart';
import 'package:cycling_app/domain/models/activity_type.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/models/workout.dart';
import 'package:cycling_app/domain/models/workout_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late WorkoutRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = WorkoutRepository(
      workouts: WorkoutDao(db),
      points: TrackPointDao(db),
      settings: SettingsRepository(SettingsDao(db)),
    );
  });

  tearDown(() => db.close());

  test('startWorkout 建立一条 recording 状态的记录', () async {
    final Workout ride = await repo.startWorkout(startedAtMs: 1000, hrDeviceName: 'FIT 3');

    expect(ride.id, isNotNull);
    expect(ride.status, WorkoutStatus.recording);
    expect(ride.hrDeviceName, 'FIT 3');
  });

  test('startWorkout 落库携带运动类型', () async {
    final Workout w = await repo.startWorkout(
      startedAtMs: 1000,
      activityType: ActivityType.running,
    );
    final Workout? back = await repo.getWorkout(w.id!);
    expect(back?.activityType, ActivityType.running);
  });

  test('appendPoints 与 getPoints 往返一致', () async {
    final Workout ride = await repo.startWorkout(startedAtMs: 1000);
    await repo.appendPoints(ride.id!, <TrackPoint>[
      TrackPoint(rideId: ride.id!, tMs: 1000, lat: 31.23, lon: 121.47, hr: 120),
      TrackPoint(rideId: ride.id!, tMs: 2000, lat: 31.23, lon: 121.471, hr: 122),
    ]);

    final List<TrackPoint> points = await repo.getPoints(ride.id!);
    expect(points.length, 2);
    expect(points.last.hr, 122);
  });

  test('finishRide 写入汇总并把状态改为 finished', () async {
    final Workout ride = await repo.startWorkout(startedAtMs: 0);
    await repo.appendPoints(ride.id!, <TrackPoint>[
      TrackPoint(rideId: ride.id!, tMs: 0, lat: 31.23, lon: 121.4700, speedMps: 5, hr: 120),
      TrackPoint(rideId: ride.id!, tMs: 1000, lat: 31.23, lon: 121.4701, speedMps: 5, hr: 120),
      TrackPoint(rideId: ride.id!, tMs: 2000, lat: 31.23, lon: 121.4702, speedMps: 5, hr: 120),
    ]);

    await repo.finishRide(ride.id!, endedAtMs: 2000, durationS: 2);

    final Workout done = (await repo.getWorkout(ride.id!))!;
    expect(done.status, WorkoutStatus.finished);
    expect(done.endedAtMs, 2000);
    expect(done.summary!.pointCount, 3);
    expect(done.summary!.distanceM, greaterThan(0));
    expect(done.summary!.avgHr, closeTo(120, 1e-9));
  });

  test('findUnfinished 能找到未结束的骑行', () async {
    final Workout ride = await repo.startWorkout(startedAtMs: 1000);
    expect((await repo.findUnfinished()).single.id, ride.id);
  });

  test('settleRide 从已有轨迹点结算一条崩溃遗留的骑行', () async {
    final Workout ride = await repo.startWorkout(startedAtMs: 0);
    await repo.appendPoints(ride.id!, <TrackPoint>[
      TrackPoint(rideId: ride.id!, tMs: 0, lat: 31.23, lon: 121.4700, speedMps: 5),
      TrackPoint(rideId: ride.id!, tMs: 10000, lat: 31.23, lon: 121.4710, speedMps: 5),
    ]);

    await repo.settleRide(ride.id!);

    final Workout done = (await repo.getWorkout(ride.id!))!;
    expect(done.status, WorkoutStatus.finished);
    expect(done.endedAtMs, 10000);
    expect(done.summary!.durationS, 10);
    expect(done.summary!.pointCount, 2);
  });

  test('deleteRide 同时删除轨迹点', () async {
    final Workout ride = await repo.startWorkout(startedAtMs: 0);
    await repo.appendPoints(ride.id!, <TrackPoint>[
      TrackPoint(rideId: ride.id!, tMs: 0, lat: 31.23, lon: 121.47),
    ]);

    await repo.deleteRide(ride.id!);

    expect(await repo.getWorkout(ride.id!), isNull);
    expect(await repo.getPoints(ride.id!), isEmpty);
  });

  group('onWorkoutDataChanged 回调', () {
    late int changed;

    setUp(() {
      changed = 0;
      repo = WorkoutRepository(
        workouts: WorkoutDao(db),
        points: TrackPointDao(db),
        settings: SettingsRepository(SettingsDao(db)),
        onWorkoutDataChanged: () => changed++,
      );
    });

    test('结束、结算、改标题、删除各通知一次', () async {
      final Workout a = await repo.startWorkout(startedAtMs: 0);
      await repo.appendPoints(a.id!, <TrackPoint>[
        TrackPoint(rideId: a.id!, tMs: 0, lat: 31.23, lon: 121.4700),
        TrackPoint(rideId: a.id!, tMs: 1000, lat: 31.23, lon: 121.4701),
      ]);
      await repo.finishRide(a.id!, endedAtMs: 1000, durationS: 1);

      final Workout b = await repo.startWorkout(startedAtMs: 5000);
      await repo.appendPoints(b.id!, <TrackPoint>[
        TrackPoint(rideId: b.id!, tMs: 5000, lat: 31.23, lon: 121.4700),
        TrackPoint(rideId: b.id!, tMs: 6000, lat: 31.23, lon: 121.4701),
      ]);
      await repo.settleRide(b.id!);

      await repo.updateTitle(a.id!, '晨骑');
      await repo.deleteRide(b.id!);

      expect(changed, 4);
    });

    test('记录中的追加写不通知，避免每次落盘都重查历史页', () async {
      final Workout ride = await repo.startWorkout(startedAtMs: 0);
      await repo.appendPoints(ride.id!, <TrackPoint>[
        TrackPoint(rideId: ride.id!, tMs: 0, lat: 31.23, lon: 121.47),
      ]);
      await repo.setStatus(ride.id!, WorkoutStatus.paused);
      await repo.setStatus(ride.id!, WorkoutStatus.recording);

      expect(changed, 0);
    });
  });
}
