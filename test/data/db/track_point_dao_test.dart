import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/ride_dao.dart';
import 'package:cycling_app/data/db/track_point_dao.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late TrackPointDao dao;
  late int rideId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    dao = TrackPointDao(db);
    rideId = await RideDao(db).insert(
      const Ride(startedAtMs: 1000, status: RideStatus.recording),
    );
  });

  tearDown(() => db.close());

  test('批量插入后按时间升序读出', () async {
    await dao.insertBatch(<TrackPoint>[
      TrackPoint(rideId: rideId, tMs: 3000, lat: 31.23, lon: 121.47, hr: 130),
      TrackPoint(rideId: rideId, tMs: 1000, lat: 31.23, lon: 121.46, hr: 120),
      TrackPoint(rideId: rideId, tMs: 2000, lat: 31.23, lon: 121.465, hr: 125),
    ]);

    final List<TrackPoint> points = await dao.listByRide(rideId);
    expect(points.map((TrackPoint p) => p.tMs).toList(), <int>[1000, 2000, 3000]);
    expect(points.first.hr, 120);
  });

  test('空列表不产生任何写入', () async {
    await dao.insertBatch(const <TrackPoint>[]);
    expect(await dao.countByRide(rideId), 0);
  });

  test('lastByRide 返回时间最大的点', () async {
    await dao.insertBatch(<TrackPoint>[
      TrackPoint(rideId: rideId, tMs: 1000, lat: 31.23, lon: 121.46),
      TrackPoint(rideId: rideId, tMs: 5000, lat: 31.23, lon: 121.48),
    ]);
    expect((await dao.lastByRide(rideId))!.tMs, 5000);
  });

  test('没有点时 lastByRide 返回 null', () async {
    expect(await dao.lastByRide(rideId), isNull);
  });

  test('countByRide 只统计指定骑行的点', () async {
    final int otherRideId = await RideDao(db).insert(
      const Ride(startedAtMs: 2000, status: RideStatus.recording),
    );
    await dao.insertBatch(<TrackPoint>[
      TrackPoint(rideId: rideId, tMs: 1000, lat: 31.23, lon: 121.46),
      TrackPoint(rideId: rideId, tMs: 2000, lat: 31.23, lon: 121.465),
      TrackPoint(rideId: otherRideId, tMs: 1000, lat: 31.24, lon: 121.48),
    ]);

    expect(await dao.countByRide(rideId), 2);
    expect(await dao.countByRide(otherRideId), 1);
  });

  test('deleteByRide 只删除指定骑行的点', () async {
    final int otherRideId = await RideDao(db).insert(
      const Ride(startedAtMs: 2000, status: RideStatus.recording),
    );
    await dao.insertBatch(<TrackPoint>[
      TrackPoint(rideId: rideId, tMs: 1000, lat: 31.23, lon: 121.46),
      TrackPoint(rideId: rideId, tMs: 2000, lat: 31.23, lon: 121.465),
      TrackPoint(rideId: otherRideId, tMs: 1000, lat: 31.24, lon: 121.48),
    ]);

    await dao.deleteByRide(rideId);

    expect(await dao.countByRide(rideId), 0);
    expect(await dao.countByRide(otherRideId), 1);
    expect((await dao.lastByRide(otherRideId))!.tMs, 1000);
  });

  test('listAll 按 ride_id 再按 t_ms 正序返回全部点', () async {
    final int rideA = await RideDao(db).insert(
      const Ride(startedAtMs: 0, status: RideStatus.finished),
    );
    final int rideB = await RideDao(db).insert(
      const Ride(startedAtMs: 0, status: RideStatus.finished),
    );

    await dao.insertBatch(<TrackPoint>[
      TrackPoint(rideId: rideB, tMs: 100, lat: 1.0, lon: 1.0),
      TrackPoint(rideId: rideA, tMs: 300, lat: 2.0, lon: 2.0),
      TrackPoint(rideId: rideA, tMs: 100, lat: 3.0, lon: 3.0),
    ]);

    final List<TrackPoint> all = await dao.listAll();
    expect(all.length, 3);
    expect(all.map((TrackPoint p) => p.rideId).toList(), <int>[rideA, rideA, rideB]);
    expect(all[0].tMs, 100);
    expect(all[1].tMs, 300);
  });

  test('deleteAll 清空 track_points 表', () async {
    final int rideId = await RideDao(db).insert(
      const Ride(startedAtMs: 0, status: RideStatus.finished),
    );
    await dao.insertBatch(<TrackPoint>[
      TrackPoint(rideId: rideId, tMs: 0, lat: 1.0, lon: 1.0),
    ]);

    await dao.deleteAll();
    expect(await dao.listAll(), isEmpty);
  });
}
