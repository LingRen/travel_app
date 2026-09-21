import 'package:cycling_app/app/home_shell.dart';
import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/ble/sensor_monitor.dart';
import 'package:cycling_app/data/sensor_pairing.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/features/history/history_page.dart';
import 'package:cycling_app/features/history/history_providers.dart';
import 'package:cycling_app/features/history/ride_card.dart';
import 'package:cycling_app/features/record/record_page.dart';
import 'package:cycling_app/features/settings/settings_page.dart';
import 'package:cycling_app/features/stats/stats_page.dart';
import 'package:cycling_app/features/stats/stats_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override 在 riverpod 3 里只从 misc 入口导出。
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

const AppSettings _testSettings = AppSettings(
  maxHeartRate: kDefaultMaxHeartRate,
  weightKg: kDefaultWeightKg,
  distanceUnit: DistanceUnit.kilometer,
  mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
);

/// 一条已结束的骑行：历史页会为它渲染一张卡片，统计页会把它算进累计。
const Ride _ride = Ride(
  id: 1,
  startedAtMs: 1000,
  endedAtMs: 2000,
  status: RideStatus.finished,
  title: '晨骑',
  summary: RideSummary(
    distanceM: 25300,
    durationS: 3600,
    movingS: 3400,
    avgSpeedMps: 7.03,
    movingAvgSpeedMps: 7.44,
    maxSpeedMps: 12.5,
    elevationGainM: 180,
    pointCount: 2,
  ),
);

/// 内存版配对仓储。设置页的传感器区块在 `initState` 的 post-frame 回调里读它，
/// 不 override 就会走到真实 `SettingsDao`，而未 override 的 `databaseProvider`
/// 一读就抛 `UnimplementedError`。
class _FakeSensorPairing implements SensorPairingRepository {
  @override
  Future<PairedSensor?> load(SensorKind kind) async => null;

  @override
  Future<void> save(SensorKind kind, PairedSensor sensor) async {}

  @override
  Future<void> clear(SensorKind kind) async {}
}

void main() {
  /// 四个 tab 现在都是真实页面，`IndexedStack` 会把它们全部建出来（只是不绘制
  /// 非当前 tab），所以每个页面依赖的 provider 都要 override，否则会碰到
  /// 「未 override 的 databaseProvider」。
  ///
  /// 只 override 各页面在 `build` / `initState` 阶段真正读到的 provider：设置页的
  /// 保存、备份导出与恢复都只在点按钮时才读仓储，本文件不点，因此不需要它们。
  Future<void> pumpShell(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appSettingsProvider.overrideWithValue(
              const AsyncValue<AppSettings>.data(_testSettings),
            ),
            historyRidesProvider.overrideWith((Ref ref) => const <Ride>[_ride]),
            finishedRidesProvider.overrideWith((Ref ref) => const <Ride>[_ride]),
            // 历史页每张卡片各自 watch 自己那次的轨迹点。
            ridePointsProvider(_ride.id!).overrideWith(
              (Ref ref) => const <TrackPoint>[],
            ),
            sensorPairingProvider.overrideWithValue(_FakeSensorPairing()),
          ],
          child: const MaterialApp(home: HomeShell()),
        ),
      );

  int stackIndex(WidgetTester tester) =>
      tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;

  int selectedIndex(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  List<String> tabLabels(WidgetTester tester) {
    final NavigationBar bar =
        tester.widget<NavigationBar>(find.byType(NavigationBar));
    return bar.destinations
        .map((Widget d) => (d as NavigationDestination).label)
        .toList();
  }

  /// 底部导航里的 tab 按钮。「历史」等文本在页面 AppBar 里也会出现，必须限定在
  /// `NavigationBar` 内才不会撞上。
  Finder tab(String label) => find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );

  testWidgets('底部四个 tab 顺序为 记录/历史/统计/设置（设计文档 10）', (WidgetTester tester) async {
    await pumpShell(tester);

    expect(tabLabels(tester), <String>['记录', '历史', '统计', '设置']);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
  });

  testWidgets('默认停在「记录」tab', (WidgetTester tester) async {
    await pumpShell(tester);

    expect(stackIndex(tester), 0);
    expect(selectedIndex(tester), 0);
  });

  testWidgets('点击底部 tab 切换页面', (WidgetTester tester) async {
    await pumpShell(tester);

    await tester.tap(tab('统计'));
    await tester.pumpAndSettle();
    expect(stackIndex(tester), 2);
    expect(selectedIndex(tester), 2);
    expect(find.byType(StatsPage), findsOneWidget);

    await tester.tap(tab('设置'));
    await tester.pumpAndSettle();
    expect(stackIndex(tester), 3);
    expect(selectedIndex(tester), 3);

    await tester.tap(tab('历史'));
    await tester.pumpAndSettle();
    expect(stackIndex(tester), 1);
    expect(selectedIndex(tester), 1);
  });

  testWidgets('同一时刻只渲染当前 tab 的内容', (WidgetTester tester) async {
    await pumpShell(tester);

    // 记录 tab 是当前 tab，另外三个真实页面虽然被建出来（`IndexedStack` 保留
    // 状态）但不绘制，对默认的 finder 来说等同于不存在。
    expect(find.byType(RecordPage), findsOneWidget);
    expect(find.text('开始骑行'), findsOneWidget);
    expect(find.byType(HistoryPage), findsNothing);
    expect(find.byType(StatsPage), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('晨骑'), findsNothing);

    await tester.tap(tab('历史'));
    await tester.pumpAndSettle();

    expect(find.byType(HistoryPage), findsOneWidget);
    expect(find.byType(RideCard), findsOneWidget);
    expect(find.text('晨骑'), findsOneWidget);
    expect(find.byType(RecordPage), findsNothing);
    expect(find.text('开始骑行'), findsNothing);
    expect(find.byType(StatsPage), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);
  });

  testWidgets('切到历史 / 统计 / 设置三个 tab 各自渲染真实页面且不抛异常', (WidgetTester tester) async {
    await pumpShell(tester);

    // 只断言 tab 标签的话，四个 tab 全指向同一个占位页也照样通过；必须逐个断言
    // 切过去之后真的是那个页面。
    await tester.tap(tab('历史'));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryPage), findsOneWidget);
    expect(find.text('晨骑'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(tab('统计'));
    await tester.pumpAndSettle();
    expect(find.byType(StatsPage), findsOneWidget);
    expect(find.text('周'), findsOneWidget); // 周/月/年范围选择器
    expect(tester.takeException(), isNull);

    await tester.tap(tab('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('个人参数'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
