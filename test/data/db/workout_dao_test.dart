import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/workout_dao.dart';
import 'package:cycling_app/domain/models/activity_type.dart';
import 'package:cycling_app/domain/models/workout.dart';
import 'package:cycling_app/domain/models/workout_status.dart';
import 'package:cycling_app/domain/models/workout_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late WorkoutDao dao;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    dao = WorkoutDao(db);
  });

  tearDown(() => db.close());

  test('插入进行中的骑行后可按 id 读回', () async {
    final int id = await dao.insert(
      const Workout(startedAtMs: 1000, status: WorkoutStatus.recording, hrDeviceName: 'FIT 3'),
    );

    final Workout ride = (await dao.findById(id))!;
    expect(ride.status, WorkoutStatus.recording);
    expect(ride.summary, isNull);
    expect(ride.hrDeviceName, 'FIT 3');
  });

  test('findUnfinished 只返回未结束的骑行', () async {
    await dao.insert(const Workout(startedAtMs: 1000, status: WorkoutStatus.recording));
    await dao.insert(const Workout(startedAtMs: 2000, status: WorkoutStatus.paused));
    await dao.insert(const Workout(startedAtMs: 3000, status: WorkoutStatus.finished));

    final List<Workout> unfinished = await dao.findUnfinished();
    expect(unfinished.length, 2);
    expect(unfinished.first.startedAtMs, 2000); // 按开始时间倒序
  });

  test('listFinished 按开始时间倒序且不含未结束的骑行', () async {
    await dao.insert(const Workout(startedAtMs: 1000, status: WorkoutStatus.finished));
    await dao.insert(const Workout(startedAtMs: 3000, status: WorkoutStatus.finished));
    await dao.insert(const Workout(startedAtMs: 5000, status: WorkoutStatus.recording));

    final List<Workout> rides = await dao.listFinished();
    expect(rides.map((Workout r) => r.startedAtMs).toList(), <int>[3000, 1000]);
  });

  test('listFinished 按类型筛选只返回该类型记录', () async {
    // 插两条 cycling + 一条 running，均为 finished。
    await dao.insert(const Workout(startedAtMs: 1000, status: WorkoutStatus.finished));
    await dao.insert(const Workout(startedAtMs: 2000, status: WorkoutStatus.finished));
    await dao.insert(const Workout(
      startedAtMs: 3000,
      status: WorkoutStatus.finished,
      activityType: ActivityType.running,
    ));

    final List<Workout> running = await dao.listFinished(activityType: ActivityType.running);
    expect(running.length, 1);
    expect(running.single.activityType, ActivityType.running);

    // null 返回全部。
    final List<Workout> all = await dao.listFinished();
    expect(all.length, 3);
  });

  test('markFinished 写入结束时间与全部汇总列', () async {
    final int id = await dao.insert(const Workout(startedAtMs: 1000, status: WorkoutStatus.recording));

    await dao.markFinished(
      id: id,
      endedAtMs: 3601000,
      summary: const WorkoutSummary(
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

    final Workout ride = (await dao.findById(id))!;
    expect(ride.status, WorkoutStatus.finished);
    expect(ride.endedAtMs, 3601000);
    expect(ride.summary!.distanceM, 25000);
    expect(ride.summary!.pointCount, 3600);
  });

  test('updateStatus 只改状态列', () async {
    final int id = await dao.insert(const Workout(startedAtMs: 1000, status: WorkoutStatus.recording));

    await dao.updateStatus(id, WorkoutStatus.paused);

    final Workout ride = (await dao.findById(id))!;
    expect(ride.status, WorkoutStatus.paused);
    expect(ride.startedAtMs, 1000);
    expect(ride.endedAtMs, isNull);
  });

  test('updateTitle 修改标题', () async {
    final int id = await dao.insert(const Workout(startedAtMs: 1000, status: WorkoutStatus.finished));
    await dao.updateTitle(id, '晨骑');
    expect((await dao.findById(id))!.title, '晨骑');
  });

  test('delete 后查不到', () async {
    final int id = await dao.insert(const Workout(startedAtMs: 1000, status: WorkoutStatus.finished));
    await dao.delete(id);
    expect(await dao.findById(id), isNull);
  });

  test('listFinishedBetween 只取区间内已完成的骑行，按开始时间正序', () async {
    await dao.insert(const Workout(startedAtMs: 1000, status: WorkoutStatus.finished));
    await dao.insert(const Workout(startedAtMs: 2000, status: WorkoutStatus.finished));
    await dao.insert(const Workout(startedAtMs: 3000, status: WorkoutStatus.finished));
    await dao.insert(const Workout(startedAtMs: 2500, status: WorkoutStatus.recording));

    final List<Workout> rides = await dao.listFinishedBetween(fromMs: 2000, toMs: 3000);
    expect(rides.map((Workout r) => r.startedAtMs).toList(), <int>[2000]);
  });

  test('listFinishedBetween 是左闭右开区间', () async {
    await dao.insert(const Workout(startedAtMs: 2000, status: WorkoutStatus.finished));
    await dao.insert(const Workout(startedAtMs: 3000, status: WorkoutStatus.finished));

    final List<Workout> rides = await dao.listFinishedBetween(fromMs: 2000, toMs: 3000);
    expect(rides.length, 1);
    expect(rides.first.startedAtMs, 2000);
  });

  test('countFinished 只数已完成的骑行', () async {
    await dao.insert(const Workout(startedAtMs: 1000, status: WorkoutStatus.finished));
    await dao.insert(const Workout(startedAtMs: 2000, status: WorkoutStatus.finished));
    await dao.insert(const Workout(startedAtMs: 3000, status: WorkoutStatus.recording));

    expect(await dao.countFinished(), 2);
  });

  test('insertWithId 保留给定的 id，供备份恢复使用', () async {
    await dao.insertWithId(const Workout(
      id: 7,
      startedAtMs: 1000,
      status: WorkoutStatus.finished,
      title: '通勤',
    ));

    final Workout ride = (await dao.findById(7))!;
    expect(ride.title, '通勤');
    expect(ride.startedAtMs, 1000);
  });

  test('insertWithId 能原样保留汇总列', () async {
    await dao.insertWithId(Workout(
      id: 3,
      startedAtMs: 1000,
      endedAtMs: 3601000,
      status: WorkoutStatus.finished,
      summary: const WorkoutSummary(
        distanceM: 25000,
        durationS: 3600,
        movingS: 3400,
        avgSpeedMps: 6.94,
        movingAvgSpeedMps: 7.35,
        maxSpeedMps: 12.5,
        elevationGainM: 180,
        avgHr: 142,
        maxHr: 176,
        avgCadence: 78,
        calories: 900,
        pointCount: 3400,
      ),
    ));

    final WorkoutSummary s = (await dao.findById(3))!.summary!;
    expect(s.distanceM, 25000);
    expect(s.maxHr, 176);
    expect(s.calories, 900);
    expect(s.pointCount, 3400);
  });

  test('deleteAll 清空 workouts 表', () async {
    await dao.insert(const Workout(startedAtMs: 1000, status: WorkoutStatus.finished));
    await dao.deleteAll();
    expect(await dao.countFinished(), 0);
    expect(await dao.listFinished(), isEmpty);
  });

  test('listFinishedBetween 区间内多条时按开始时间正序', () async {
    await dao.insert(const Workout(startedAtMs: 2500, status: WorkoutStatus.finished));
    await dao.insert(const Workout(startedAtMs: 2000, status: WorkoutStatus.finished));
    await dao.insert(const Workout(startedAtMs: 2800, status: WorkoutStatus.finished));

    final List<Workout> rides = await dao.listFinishedBetween(fromMs: 2000, toMs: 3000);
    expect(rides.map((Workout r) => r.startedAtMs).toList(), <int>[2000, 2500, 2800]);
  });
}
