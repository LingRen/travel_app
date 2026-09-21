import 'package:cycling_app/app/app.dart';
import 'package:cycling_app/app/home_shell.dart';
import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/ride_dao.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
  });

  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        child: const CyclingApp(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('CyclingApp 以深色主题启动并进入四 tab 主界面', (WidgetTester tester) async {
    await pumpApp(tester);

    final MaterialApp app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, '骑行记录');
    expect(app.theme!.brightness, Brightness.dark);
    expect(app.debugShowCheckedModeBanner, isFalse);

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('检测到未结束的骑行'), findsNothing);
  });

  testWidgets('启动时先过 RecoveryGate：有未结束骑行就弹恢复提示', (WidgetTester tester) async {
    await RideDao(db)
        .insert(Ride(startedAtMs: 1000, status: RideStatus.recording));

    await pumpApp(tester);

    expect(find.text('检测到未结束的骑行'), findsOneWidget);
  });
}
