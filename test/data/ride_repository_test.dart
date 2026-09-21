import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/ride_dao.dart';
import 'package:cycling_app/data/db/settings_dao.dart';
import 'package:cycling_app/data/db/track_point_dao.dart';
import 'package:cycling_app/data/ride_repository.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late RideRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = RideRepository(
      rides: RideDao(db),
      points: TrackPointDao(db),
      settings: SettingsRepository(SettingsDao(db)),
    );
  });

  tearDown(() => db.close());

  test('startRide 建立一条 recording 状态的记录', () async {
    final Ride ride = await repo.startRide(startedAtMs: 1000, hrDeviceName: 'FIT 3');

    expect(ride.id, isNotNull);
    expect(ride.status, RideStatus.recording);
    expect(ride.hrDeviceName, 'FIT 3');
  });

  test('appendPoints 与 getPoints 往返一致', () async {
    final Ride ride = await repo.startRide(startedAtMs: 1000);
    await repo.appendPoints(ride.id!, <TrackPoint>[
      TrackPoint(rideId: ride.id!, tMs: 1000, lat: 31.23, lon: 121.47, hr: 120),
      TrackPoint(rideId: ride.id!, tMs: 2000, lat: 31.23, lon: 121.471, hr: 122),
    ]);

    final List<TrackPoint> points = await repo.getPoints(ride.id!);
    expect(points.length, 2);
    expect(points.last.hr, 122);
  });

  test('finishRide 写入汇总并把状态改为 finished', () async {
    final Ride ride = await repo.startRide(startedAtMs: 0);
    await repo.appendPoints(ride.id!, <TrackPoint>[
      TrackPoint(rideId: ride.id!, tMs: 0, lat: 31.23, lon: 121.4700, speedMps: 5, hr: 120),
      TrackPoint(rideId: ride.id!, tMs: 1000, lat: 31.23, lon: 121.4701, speedMps: 5, hr: 120),
      TrackPoint(rideId: ride.id!, tMs: 2000, lat: 31.23, lon: 121.4702, speedMps: 5, hr: 120),
    ]);

    await repo.finishRide(ride.id!, endedAtMs: 2000, durationS: 2);

    final Ride done = (await repo.getRide(ride.id!))!;
    expect(done.status, RideStatus.finished);
    expect(done.endedAtMs, 2000);
    expect(done.summary!.pointCount, 3);
    expect(done.summary!.distanceM, greaterThan(0));
    expect(done.summary!.avgHr, closeTo(120, 1e-9));
  });

  test('findUnfinished 能找到未结束的骑行', () async {
    final Ride ride = await repo.startRide(startedAtMs: 1000);
    expect((await repo.findUnfinished()).single.id, ride.id);
  });

  test('settleRide 从已有轨迹点结算一条崩溃遗留的骑行', () async {
    final Ride ride = await repo.startRide(startedAtMs: 0);
    await repo.appendPoints(ride.id!, <TrackPoint>[
      TrackPoint(rideId: ride.id!, tMs: 0, lat: 31.23, lon: 121.4700, speedMps: 5),
      TrackPoint(rideId: ride.id!, tMs: 10000, lat: 31.23, lon: 121.4710, speedMps: 5),
    ]);

    await repo.settleRide(ride.id!);

    final Ride done = (await repo.getRide(ride.id!))!;
    expect(done.status, RideStatus.finished);
    expect(done.endedAtMs, 10000);
    expect(done.summary!.durationS, 10);
    expect(done.summary!.pointCount, 2);
  });

  test('deleteRide 同时删除轨迹点', () async {
    final Ride ride = await repo.startRide(startedAtMs: 0);
    await repo.appendPoints(ride.id!, <TrackPoint>[
      TrackPoint(rideId: ride.id!, tMs: 0, lat: 31.23, lon: 121.47),
    ]);

    await repo.deleteRide(ride.id!);

    expect(await repo.getRide(ride.id!), isNull);
    expect(await repo.getPoints(ride.id!), isEmpty);
  });
}
