import 'package:cycling_app/app/app.dart';
import 'package:cycling_app/app/home_shell.dart';
import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/app/ui/paper_nav_bar.dart';
import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/workout_dao.dart';
import 'package:cycling_app/domain/models/workout.dart';
import 'package:cycling_app/domain/models/workout_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    // 先过封面：1.2 秒停留 + 300 毫秒淡出，再等恢复检查与首帧。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
  }

  testWidgets('冷启动先显示封面，封面退场后才构建主界面', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        child: const CyclingApp(),
      ),
    );
    await tester.pump();

    expect(find.text('行迹'), findsOneWidget);
    expect(find.text('X I N G J I'), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(PaperNavBar), findsOneWidget);
  });

  testWidgets('CyclingApp 以亮色纸本启动并进入四 tab 主界面', (WidgetTester tester) async {
    await pumpApp(tester);

    final MaterialApp app = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );
    expect(app.title, '行迹');
    expect(app.theme!.brightness, Brightness.light);
    expect(app.theme!.scaffoldBackgroundColor, const Color(0xFFF5F0E5));
    expect(app.debugShowCheckedModeBanner, isFalse);

    final AnnotatedRegion<SystemUiOverlayStyle> region = tester.widget(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(region.value.statusBarColor, Colors.transparent);
    expect(region.value.statusBarIconBrightness, Brightness.dark);
    expect(region.value.statusBarBrightness, Brightness.light);

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(PaperNavBar), findsOneWidget);
    expect(find.text('检测到未结束的骑行'), findsNothing);
  });

  testWidgets('启动时先过 RecoveryGate：有未结束骑行就弹恢复提示', (WidgetTester tester) async {
    await WorkoutDao(db)
        .insert(Workout(startedAtMs: 1000, status: WorkoutStatus.recording));

    await pumpApp(tester);

    expect(find.text('检测到未结束的骑行'), findsOneWidget);
  });
}
