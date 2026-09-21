import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/ride_dao.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late RideDao dao;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    dao = RideDao(db);
  });

  tearDown(() => db.close());

  test('插入进行中的骑行后可按 id 读回', () async {
    final int id = await dao.insert(
      const Ride(startedAtMs: 1000, status: RideStatus.recording, hrDeviceName: 'FIT 3'),
    );

    final Ride ride = (await dao.findById(id))!;
    expect(ride.status, RideStatus.recording);
    expect(ride.summary, isNull);
    expect(ride.hrDeviceName, 'FIT 3');
  });

  test('findUnfinished 只返回未结束的骑行', () async {
    await dao.insert(const Ride(startedAtMs: 1000, status: RideStatus.recording));
    await dao.insert(const Ride(startedAtMs: 2000, status: RideStatus.paused));
    await dao.insert(const Ride(startedAtMs: 3000, status: RideStatus.finished));

    final List<Ride> unfinished = await dao.findUnfinished();
    expect(unfinished.length, 2);
    expect(unfinished.first.startedAtMs, 2000); // 按开始时间倒序
  });

  test('listFinished 按开始时间倒序且不含未结束的骑行', () async {
    await dao.insert(const Ride(startedAtMs: 1000, status: RideStatus.finished));
    await dao.insert(const Ride(startedAtMs: 3000, status: RideStatus.finished));
    await dao.insert(const Ride(startedAtMs: 5000, status: RideStatus.recording));

    final List<Ride> rides = await dao.listFinished();
    expect(rides.map((Ride r) => r.startedAtMs).toList(), <int>[3000, 1000]);
  });

  test('markFinished 写入结束时间与全部汇总列', () async {
    final int id = await dao.insert(const Ride(startedAtMs: 1000, status: RideStatus.recording));

    await dao.markFinished(
      id: id,
      endedAtMs: 3601000,
      summary: const RideSummary(
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
    );

    final Ride ride = (await dao.findById(id))!;
    expect(ride.status, RideStatus.finished);
    expect(ride.endedAtMs, 3601000);
    expect(ride.summary!.distanceM, 25000);
    expect(ride.summary!.pointCount, 3600);
  });

  test('updateStatus 只改状态列', () async {
    final int id = await dao.insert(const Ride(startedAtMs: 1000, status: RideStatus.recording));

    await dao.updateStatus(id, RideStatus.paused);

    final Ride ride = (await dao.findById(id))!;
    expect(ride.status, RideStatus.paused);
    expect(ride.startedAtMs, 1000);
    expect(ride.endedAtMs, isNull);
  });

  test('updateTitle 修改标题', () async {
    final int id = await dao.insert(const Ride(startedAtMs: 1000, status: RideStatus.finished));
    await dao.updateTitle(id, '晨骑');
    expect((await dao.findById(id))!.title, '晨骑');
  });

  test('delete 后查不到', () async {
    final int id = await dao.insert(const Ride(startedAtMs: 1000, status: RideStatus.finished));
    await dao.delete(id);
    expect(await dao.findById(id), isNull);
  });
}
