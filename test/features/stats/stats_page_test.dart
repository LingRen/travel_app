import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/features/stats/personal_bests_card.dart';
import 'package:cycling_app/features/stats/stats_page.dart';
import 'package:cycling_app/features/stats/stats_providers.dart';
import 'package:cycling_app/features/stats/trend_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

const AppSettings _settings = AppSettings(
  maxHeartRate: 190,
  weightKg: 70,
  distanceUnit: DistanceUnit.kilometer,
  mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
);

/// 固定「现在」：2026-09-24（周四），因此本周是 09-21（周一）到 09-27。
int get nowMs => DateTime(2026, 9, 24, 12).millisecondsSinceEpoch;

Ride ride(int id, int y, int m, int d, {double distanceM = 10000}) => Ride(
      id: id,
      startedAtMs: DateTime(y, m, d, 8).millisecondsSinceEpoch,
      endedAtMs: DateTime(y, m, d, 9).millisecondsSinceEpoch,
      status: RideStatus.finished,
      summary: RideSummary(
        distanceM: distanceM,
        durationS: 1800,
        movingS: 1700,
        avgSpeedMps: 5.56,
        movingAvgSpeedMps: 5.88,
        maxSpeedMps: 11.1,
        elevationGainM: 100,
        pointCount: 1800,
      ),
    );

Widget wrap({
  required List<Ride> rides,
  AppSettings settings = _settings,
}) =>
    ProviderScope(
      overrides: <Override>[
        finishedRidesProvider.overrideWith((Ref ref) => rides),
        nowProvider.overrideWithValue(() => nowMs),
        appSettingsProvider.overrideWithValue(AsyncValue<AppSettings>.data(settings)),
      ],
      child: const MaterialApp(home: StatsPage()),
    );

/// 统计页是 `ListView`，默认 800x600 的测试视口只构建前几屏，趋势折线与个人最佳
/// 卡片都在下半部分，不调高视口就根本不会被 build，`find.byType` 会假失败。
Future<void> pumpStats(
  WidgetTester tester, {
  required List<Ride> rides,
  AppSettings settings = _settings,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(rides: rides, settings: settings));
  await tester.pumpAndSettle();
}

/// 读取 `_Totals` 某一格的数值文本。
///
/// 每格都有稳定的 Key（`totals-distance` / `totals-duration` / `totals-gain` /
/// `totals-count`）：距离与爬升都为 0 时两格都渲染 `0 m`，只靠 `find.text('0 m')`
/// 无法区分是哪一格（`findsOneWidget` 必然失败），键才能钉住「距离那一格」。
String totalsValue(WidgetTester tester, String tile) {
  final Finder texts = find.descendant(
    of: find.byKey(Key('totals-$tile')),
    matching: find.byType(Text),
  );
  // 每格是「标签 + 值」两行，第二行才是值。
  return tester.widget<Text>(texts.at(1)).data!;
}

void main() {
  testWidgets('默认显示本周累计距离、时长与爬升', (WidgetTester tester) async {
    await pumpStats(tester, rides: <Ride>[
      ride(1, 2026, 9, 22),
      ride(2, 2026, 9, 24),
    ]);

    expect(totalsValue(tester, 'distance'), '20.00 km');
    expect(totalsValue(tester, 'duration'), '1:00:00');
    expect(totalsValue(tester, 'gain'), '200 m');
    expect(totalsValue(tester, 'count'), '2');
  });

  testWidgets('范围外的骑行不计入累计', (WidgetTester tester) async {
    await pumpStats(tester, rides: <Ride>[
      ride(1, 2026, 9, 20), // 上周日，不在 09-21..09-27 内
    ]);

    expect(totalsValue(tester, 'distance'), '0 m');
    expect(totalsValue(tester, 'gain'), '0 m');
    expect(totalsValue(tester, 'duration'), '00:00');
    expect(totalsValue(tester, 'count'), '0');
  });

  testWidgets('切到「年」后累计包含全年的骑行', (WidgetTester tester) async {
    await pumpStats(tester, rides: <Ride>[
      ride(1, 2026, 3, 15),
      ride(2, 2026, 9, 24),
    ]);
    expect(totalsValue(tester, 'distance'), '10.00 km');

    await tester.tap(find.text('年'));
    await tester.pumpAndSettle();

    expect(totalsValue(tester, 'distance'), '20.00 km');
  });

  testWidgets('切到「月」后累计包含整月的骑行', (WidgetTester tester) async {
    await pumpStats(tester, rides: <Ride>[
      ride(1, 2026, 9, 2),
      ride(2, 2026, 9, 24),
    ]);
    expect(totalsValue(tester, 'distance'), '10.00 km');

    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();

    expect(totalsValue(tester, 'distance'), '20.00 km');
  });

  testWidgets('渲染趋势折线', (WidgetTester tester) async {
    await pumpStats(tester, rides: <Ride>[ride(1, 2026, 9, 22)]);

    expect(find.byType(TrendChart), findsOneWidget);
    final TrendChart chart = tester.widget<TrendChart>(find.byType(TrendChart));
    expect(chart.trend.buckets.length, 7);

    // 上面两条只断言入参，把 `TrendChart.build` 掏空也照样通过。下面直接读
    // `fl_chart` 收到的数据，证明折线真的被喂了这 7 个桶。
    expect(find.byType(LineChart), findsOneWidget);
    final LineChartData data =
        tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.lineBarsData.single.spots.length, chart.trend.buckets.length);
    expect(data.minX, 0);
    expect(data.maxX, 6); // 7 个桶 → 0..6
    // 09-22 是本周第 2 个桶（下标 1），距离 10000 m → 10 km。
    expect(data.lineBarsData.single.spots[1].y, 10.0);
  });

  testWidgets('渲染个人最佳卡片，四项都显示', (WidgetTester tester) async {
    await pumpStats(tester, rides: <Ride>[
      ride(1, 2026, 9, 22, distanceM: 30000),
      ride(2, 2026, 9, 24, distanceM: 10000),
    ]);

    expect(find.byType(PersonalBestsCard), findsOneWidget);
    final PersonalBestsCard card =
        tester.widget<PersonalBestsCard>(find.byType(PersonalBestsCard));
    expect(card.bests.longestDistanceM!.rideId, 1);
    expect(card.bests.longestDistanceM!.value, 30000);

    expect(find.text('最远距离'), findsOneWidget);
    expect(find.text('30.00 km'), findsOneWidget);
    expect(find.text('最长时长'), findsOneWidget);
    expect(find.text('30:00'), findsOneWidget);
    expect(find.text('最快移动均速'), findsOneWidget);
    expect(find.text('21.2 km/h'), findsOneWidget);
    expect(find.text('最大爬升'), findsOneWidget);
    expect(find.text('100 m'), findsOneWidget);
  });

  testWidgets('个人最佳跨范围统计，不受周月年切换影响', (WidgetTester tester) async {
    await pumpStats(tester, rides: <Ride>[
      ride(1, 2026, 3, 15, distanceM: 40000),
      ride(2, 2026, 9, 24, distanceM: 10000),
    ]);

    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();

    final PersonalBestsCard card =
        tester.widget<PersonalBestsCard>(find.byType(PersonalBestsCard));
    expect(card.bests.longestDistanceM!.value, 40000);
  });

  testWidgets('没有任何记录时不崩溃', (WidgetTester tester) async {
    await pumpStats(tester, rides: const <Ride>[]);

    expect(totalsValue(tester, 'distance'), '0 m');
    expect(totalsValue(tester, 'gain'), '0 m');
    expect(totalsValue(tester, 'count'), '0');
    expect(find.text('还没有可统计的记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('Y 轴刻度', () {
    // 真机验证时看到的是 `0 / 1 / 1 / 2 / 2`：fl_chart 自己算出的步长是
    // 0.5，而标签按整数四舍五入就出现了重复。这条钉住重复不再出现。
    testWidgets('刻度标签不重复', (WidgetTester tester) async {
      // 单次 2 km → 轴上最大 2*1.2 = 2.4，正是真机上出现 `0/1/1/2/2` 的量级
      // （旧实现没给 interval，fl_chart 自己算出 0.5 的步长）。
      await pumpStats(tester, rides: <Ride>[ride(1, 2026, 9, 22, distanceM: 2000)]);

      final LineChartData data =
          tester.widget<LineChart>(find.byType(LineChart)).data;
      // 轴顶取步长的整数倍，2.4 向上补到 3。
      expect(data.maxY, 3);

      final SideTitles titles = data.titlesData.leftTitles.sideTitles;
      final double interval = titles.interval!;

      final List<String> labels = <String>[
        for (double v = data.minY; v <= data.maxY + 1e-9; v += interval)
          axisLabel(v, interval),
      ];

      expect(labels.toSet().length, labels.length, reason: '刻度标签重复了：$labels');
      // 具体值也钉一下，避免「只印一个 0」这种退化也满足「不重复」。
      expect(labels, <String>['0', '1', '2', '3']);
    });

    // 小数步长也要满足：轴顶不能落在步长序列之外（真机上曾出现末尾补一个
    // `1.7`，看着像刻度算错了）。
    testWidgets('轴顶落在步长序列上', (WidgetTester tester) async {
      await pumpStats(tester, rides: <Ride>[ride(1, 2026, 9, 22, distanceM: 1400)]);

      final LineChartData data =
          tester.widget<LineChart>(find.byType(LineChart)).data;
      final SideTitles titles = data.titlesData.leftTitles.sideTitles;
      final double interval = titles.interval!;

      expect(interval, 0.5);
      expect(data.maxY, 2.0);
      expect(data.maxY % interval, closeTo(0, 1e-9));

      final List<String> labels = <String>[
        for (double v = data.minY; v <= data.maxY + 1e-9; v += interval)
          axisLabel(v, interval),
      ];
      expect(labels, <String>['0.0', '0.5', '1.0', '1.5', '2.0']);
    });

    test('步长取 1/2/5 序列，最多 4 条刻度', () {
      expect(niceAxisInterval(2.4), 1);
      expect(niceAxisInterval(1.2), 0.5);
      expect(niceAxisInterval(1), 0.5);
      expect(niceAxisInterval(0.6), 0.2);
      expect(niceAxisInterval(24), 10);
      expect(niceAxisInterval(120), 50);
      expect(niceAxisInterval(600), 200);

      for (final double maxY in <double>[0.6, 1, 1.2, 2.4, 10, 24, 120, 600]) {
        expect(maxY / niceAxisInterval(maxY), lessThanOrEqualTo(4));
      }
    });

    test('步长不足 1 时标签保留一位小数，避免刻度互相压成同一个整数', () {
      expect(axisLabel(0.5, 0.5), '0.5');
      expect(axisLabel(1, 0.5), '1.0');
      expect(axisLabel(0.30000000000000004, 0.1), '0.3');
      expect(axisLabel(5, 5), '5');
      expect(axisLabel(4.999999999, 5), '5');
    });
  });
}
