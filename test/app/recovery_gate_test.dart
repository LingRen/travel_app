import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/app/recovery_gate.dart';
import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/ride_dao.dart';
import 'package:cycling_app/data/db/track_point_dao.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late ProviderContainer container;

  setUpAll(() {
    sqfliteFfiInit();
    // widget 测试跑在 FakeAsync 里，必须用同 isolate 的工厂，否则跨 isolate
    // 的端口消息在假时钟下永远送不到。
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    container = ProviderContainer(
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pumpGate(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RecoveryGate(child: Text('主界面'))),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Future<int> seedUnfinishedRide(int startedAtMs) => RideDao(db)
      .insert(Ride(startedAtMs: startedAtMs, status: RideStatus.recording));

  testWidgets('没有未结束的骑行时不弹窗，直接进入主界面', (WidgetTester tester) async {
    await pumpGate(tester);

    expect(find.text('检测到未结束的骑行'), findsNothing);
    expect(find.text('主界面'), findsOneWidget);
  });

  testWidgets('有未结束骑行时弹窗，选「继续」把 id 写入 resumeRideIdProvider', (WidgetTester tester) async {
    final int startedAtMs = DateTime(2026, 1, 2, 3, 4).millisecondsSinceEpoch;
    final int id = await seedUnfinishedRide(startedAtMs);

    await pumpGate(tester);

    expect(find.text('检测到未结束的骑行'), findsOneWidget);
    expect(find.text('开始于 2026-01-02 03:04，是否继续？'), findsOneWidget);

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(container.read(resumeRideIdProvider), id);
    // 「继续」不结算，骑行仍是进行中。
    expect((await RideDao(db).findById(id))!.status, RideStatus.recording);
  });

  testWidgets('有未结束骑行时选「结算保存」把它置为 finished', (WidgetTester tester) async {
    final int id = await seedUnfinishedRide(1000);
    await TrackPointDao(db).insertBatch(<TrackPoint>[
      TrackPoint(rideId: id, tMs: 1000, lat: 31.2300, lon: 121.4700),
      TrackPoint(rideId: id, tMs: 61000, lat: 31.2400, lon: 121.4800),
    ]);

    await pumpGate(tester);

    await tester.tap(find.text('结算保存'));
    await tester.pumpAndSettle();

    final Ride ride = (await RideDao(db).findById(id))!;
    expect(ride.status, RideStatus.finished);
    expect(ride.endedAtMs, 61000);
    expect(ride.summary, isNotNull);
    expect(container.read(resumeRideIdProvider), isNull);
  });

  testWidgets('多条未结束骑行时提示最近开始的那条', (WidgetTester tester) async {
    await seedUnfinishedRide(DateTime(2025, 12, 31, 23, 59).millisecondsSinceEpoch);
    await seedUnfinishedRide(DateTime(2026, 1, 2, 3, 4).millisecondsSinceEpoch);

    await pumpGate(tester);

    expect(find.text('开始于 2026-01-02 03:04，是否继续？'), findsOneWidget);
  });
}
