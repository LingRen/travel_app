import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/ride_dao.dart';
import 'package:cycling_app/data/db/settings_dao.dart';
import 'package:cycling_app/data/db/track_point_dao.dart';
import 'package:cycling_app/data/mock_ride_seeder.dart';
import 'package:cycling_app/data/ride_repository.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 固定「现在」：2026-09-24 12:00，与统计页测试用的是同一天。
int get nowMs => DateTime(2026, 9, 24, 12).millisecondsSinceEpoch;

void main() {
  group('排期', () {
    test('铺两个半月共 16 条，日期不重复', () {
      final List<MockRidePlan> plan = mockRidePlan(nowMs: nowMs);
      expect(plan.length, 16);

      final Set<String> stamps = <String>{
        for (final MockRidePlan p in plan)
          DateTime.fromMillisecondsSinceEpoch(p.startedAtMs)
              .toIso8601String()
              .substring(0, 10),
      };
      expect(stamps.length, plan.length, reason: '同一天铺了多条：$stamps');
    });

    test('不会铺出未来时间', () {
      final List<MockRidePlan> plan = mockRidePlan(nowMs: nowMs);
      for (final MockRidePlan p in plan) {
        expect(p.startedAtMs, lessThan(nowMs));
        expect(p.durationS, greaterThan(0));
      }
    });

    test('同一种子两次生成的排期完全一致', () {
      final List<MockRidePlan> a = mockRidePlan(nowMs: nowMs);
      final List<MockRidePlan> b = mockRidePlan(nowMs: nowMs);
      expect(
        <int>[for (final MockRidePlan p in a) p.startedAtMs],
        <int>[for (final MockRidePlan p in b) p.startedAtMs],
      );
    });

    test('跨度覆盖到本月的更早日期，年视图才有多个非零月', () {
      final List<MockRidePlan> plan = mockRidePlan(nowMs: nowMs);
      final Set<int> months = <int>{
        for (final MockRidePlan p in plan)
          DateTime.fromMillisecondsSinceEpoch(p.startedAtMs).month,
      };
      expect(months.length, greaterThanOrEqualTo(2));
    });
  });

  group('采样点', () {
    test('2 秒一个点，点数与时长对应', () {
      final List<TrackPoint> points = generateMockPoints(
        rideId: 1,
        startedAtMs: nowMs,
        durationS: 600,
        seed: 7, // 7 % 3 != 0，这条没有隧道
      );
      expect(points.length, 600 ~/ 2 + 1);
      expect(points.first.tMs, nowMs);
      expect(points.last.tMs, nowMs + 600 * 1000);
    });

    test('时间是单调递增的，且跳过的隧道段留下超过断点阈值的空档', () {
      // seed 9 满足 9 % 3 == 0，这条会在中段整段丢掉定位。
      final List<TrackPoint> points = generateMockPoints(
        rideId: 1,
        startedAtMs: nowMs,
        durationS: 900,
        seed: 9,
      );

      int? prev;
      int gaps = 0;
      for (final TrackPoint p in points) {
        if (prev != null) {
          final int dt = p.tMs - prev;
          expect(dt, greaterThan(0), reason: '时间没有前进');
          if (dt > kGpsGapMs) gaps++;
        }
        prev = p.tMs;
      }
      // 恰好一处空档，多一处少一处都说明隧道逻辑跑偏了。
      expect(gaps, 1);

      // 对照组：同一条不带隧道的种子应当一个空档都没有，否则上面的 1 说明不了问题。
      final List<TrackPoint> smooth = generateMockPoints(
        rideId: 1,
        startedAtMs: nowMs,
        durationS: 900,
        seed: 8,
      );
      int smoothGaps = 0;
      int? last;
      for (final TrackPoint p in smooth) {
        if (last != null && p.tMs - last > kGpsGapMs) smoothGaps++;
        last = p.tMs;
      }
      expect(smoothGaps, 0);
    });

    test('轨迹真的在移动，不是原地踏步', () {
      final List<TrackPoint> points = generateMockPoints(
        rideId: 1,
        startedAtMs: nowMs,
        durationS: 600,
        seed: 7,
      );
      final Set<String> cells = <String>{
        for (final TrackPoint p in points)
          '${p.lat!.toStringAsFixed(3)},${p.lon!.toStringAsFixed(3)}',
      };
      expect(cells.length, greaterThan(10));
    });

    test('速度 / 心率 / 踏频 / 海拔都落在可信范围里', () {
      final List<TrackPoint> points = generateMockPoints(
        rideId: 1,
        startedAtMs: nowMs,
        durationS: 1200,
        seed: 11,
      );
      for (final TrackPoint p in points) {
        expect(p.speedMps, greaterThan(0));
        expect(p.speedMps, lessThan(20));
        expect(p.hr, inInclusiveRange(92, 184));
        expect(p.cadence, inInclusiveRange(42, 116));
        expect(p.altitudeM, greaterThan(0));
        expect(p.hasPosition, isTrue);
      }
    });

    test('同一种子两次生成的点完全一致', () {
      List<Object?> snapshot() => <Object?>[
            for (final TrackPoint p in generateMockPoints(
              rideId: 1,
              startedAtMs: nowMs,
              durationS: 300,
              seed: 5,
            ))
              <Object?>[p.tMs, p.lat, p.lon, p.speedMps, p.hr],
          ];
      expect(snapshot(), snapshot());
    });
  });

  group('落库', () {
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

    test('生成 16 条已完成记录，每条都有轨迹点与汇总', () async {
      final int count = await seedMockRides(repo, nowMs: nowMs);
      expect(count, 16);

      final List<Ride> rides = await repo.listFinished();
      expect(rides.length, 16);
      for (final Ride ride in rides) {
        expect(ride.status, RideStatus.finished);
        expect(ride.summary, isNotNull);
        expect(ride.summary!.distanceM, greaterThan(0));
        final List<TrackPoint> points = await repo.getPoints(ride.id!);
        expect(points.length, greaterThan(1));
      }
    });

    test('覆盖式生成：连点两次仍是同一批，不堆重复', () async {
      await seedMockRides(repo, nowMs: nowMs);
      await seedMockRides(repo, nowMs: nowMs);

      final List<Ride> rides = await repo.listFinished();
      expect(rides.length, 16);
      // 时间戳也不重复，说明是覆盖而不是在旧数据上又叠了一层。
      expect(<int>{for (final Ride r in rides) r.startedAtMs}.length, 16);
    });

    test('覆盖时不动时间戳不撞排期的记录', () async {
      // 一条「真实」记录：起点落在排期之外（差 12 秒）。
      final Ride real = await repo.startRide(startedAtMs: nowMs - 12345);
      await repo.finishRide(real.id!, endedAtMs: nowMs, durationS: 60);

      await seedMockRides(repo, nowMs: nowMs);
      await seedMockRides(repo, nowMs: nowMs);

      final List<Ride> rides = await repo.listFinished();
      expect(rides.length, 17);
      expect(rides.any((Ride r) => r.id == real.id), isTrue,
          reason: '真实记录被模拟数据的覆盖逻辑误删了');
    });

    test('清空会删掉全部记录（含真实记录），返回删除条数', () async {
      await seedMockRides(repo, nowMs: nowMs);
      // 再塞一条进行中的记录，确认未完成的也一起清掉。
      await repo.startRide(startedAtMs: nowMs);

      final int removed = await deleteAllRides(repo);
      expect(removed, 17);
      expect(await repo.listFinished(), isEmpty);
      expect(await repo.findUnfinished(), isEmpty);
    });
  });
}