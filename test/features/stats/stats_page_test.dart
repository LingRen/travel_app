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

Ride ride(
  int id,
  int y,
  int m,
  int d, {
  double distanceM = 10000,
  double? avgPowerW,
  int? maxPowerW,
}) =>
    Ride(
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
        avgPowerW: avgPowerW,
        maxPowerW: maxPowerW,
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

  testWidgets('触摸读数保留两位小数，并标出日期与单位', (WidgetTester tester) async {
    await pumpStats(tester, rides: <Ride>[ride(1, 2026, 9, 22, distanceM: 12500)]);

    final LineChartData data =
        tester.widget<LineChart>(find.byType(LineChart)).data;
    final LineChartBarData bar = data.lineBarsData.single;
    // fl_chart 默认的 tooltip 直接印 `touchedSpot.y.toString()`：距离不是整数时
    // 就甩出一长串小数（真机验证看到的就是这个）。直接调构建函数，钉住两位
    // 小数、日期与单位。
    final List<LineTooltipItem?> items = data.lineTouchData.touchTooltipData
        .getTooltipItems(<LineBarSpot>[LineBarSpot(bar, 0, bar.spots[1])]);

    final LineTooltipItem item = items.single!;
    expect(item.text, '09-22', reason: '先标出是哪个日期桶');
    // 12500 米 → 12.5 km，两位小数要补成 12.50；用 toString() 时是 12.5。
    expect(item.children!.single.text!.trim(), '12.50 km');
  });

  testWidgets('切到英里后累计、爬升与趋势图纵轴都换算', (WidgetTester tester) async {
    await pumpStats(
      tester,
      rides: <Ride>[ride(1, 2026, 9, 22)],
      settings: const AppSettings(
        maxHeartRate: 190,
        weightKg: 70,
        distanceUnit: DistanceUnit.mile,
        mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
      ),
    );

    // 10000 米 = 6.21 英里；100 米 = 328 英尺。
    expect(totalsValue(tester, 'distance'), '6.21 mi');
    expect(totalsValue(tester, 'gain'), '328 ft');
    expect(find.text('距离趋势（mi）'), findsOneWidget);
    // 个人最佳里的爬升同样跟着换。
    expect(find.text('328 ft'), findsWidgets);

    // 纵轴数值也要换：只换标题的话会出现「标题写 mi、轴上还是 km 的数」。
    final LineChartData data =
        tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.lineBarsData.single.spots[1].y, closeTo(10000 / 1609.344, 1e-6));
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
    // 这两次骑行都没配功率计，不能凭空多出一行 0 W 的「最佳」。
    // 累计矩阵里本来就有「最高功率」这一格，所以要限定在个人最佳卡片里找。
    expect(
      find.descendant(
        of: find.byType(PersonalBestsCard),
        matching: find.text('最高功率'),
      ),
      findsNothing,
    );
    expect(card.bests.highestPowerW, isNull);
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

  group('功率', () {
    testWidgets('累计矩阵里的平均功率按移动时长加权', (WidgetTester tester) async {
      await pumpStats(tester, rides: <Ride>[
        ride(1, 2026, 9, 22, avgPowerW: 120, maxPowerW: 300),
        ride(2, 2026, 9, 24, avgPowerW: 180, maxPowerW: 420),
      ]);

      // 两次骑行移动时长一样（1700s），加权平均就是算术平均。
      expect(totalsValue(tester, 'avg-power'), '150 W');
      expect(totalsValue(tester, 'max-power'), '420 W');
    });

    testWidgets('范围外的骑行功率不计入累计', (WidgetTester tester) async {
      await pumpStats(tester, rides: <Ride>[
        ride(1, 2026, 9, 20, avgPowerW: 400, maxPowerW: 900), // 上周日，范围外
        ride(2, 2026, 9, 24, avgPowerW: 150, maxPowerW: 300),
      ]);

      expect(totalsValue(tester, 'avg-power'), '150 W');
      expect(totalsValue(tester, 'max-power'), '300 W');
    });

    testWidgets('没有功率数据时累计矩阵显示破折号而不是 0 W', (WidgetTester tester) async {
      await pumpStats(tester, rides: <Ride>[ride(1, 2026, 9, 22)]);

      expect(totalsValue(tester, 'avg-power'), '—');
      expect(totalsValue(tester, 'max-power'), '—');
    });

    testWidgets('个人最佳里的最高功率取单次峰值最大的一次', (WidgetTester tester) async {
      await pumpStats(tester, rides: <Ride>[
        ride(1, 2026, 9, 22, avgPowerW: 260, maxPowerW: 380),
        ride(2, 2026, 9, 24, avgPowerW: 140, maxPowerW: 520),
      ]);

      // 累计矩阵里也有一格叫「最高功率」，这里只看个人最佳卡片里的那一行。
      final Finder card = find.byType(PersonalBestsCard);
      expect(
        find.descendant(of: card, matching: find.text('最高功率')),
        findsOneWidget,
      );
      expect(find.descendant(of: card, matching: find.text('520 W')), findsOneWidget);

      final PersonalBestsCard widget =
          tester.widget<PersonalBestsCard>(card);
      expect(widget.bests.highestPowerW!.rideId, 2);
      expect(widget.bests.highestPowerW!.value, 520);
    });
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
          axisLabel(v),
        ];

      expect(labels.toSet().length, labels.length, reason: '刻度标签重复了：$labels');
      // 具体值也钉一下，避免「只印一个 0」这种退化也满足「不重复」。
      expect(labels, <String>['0.0', '1.0', '2.0', '3.0']);
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
          axisLabel(v),
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

    test('标签一律保留一位小数，不按步长切换精度', () {
      expect(axisLabel(0.5), '0.5');
      expect(axisLabel(1), '1.0');
      expect(axisLabel(0.30000000000000004), '0.3');
      expect(axisLabel(5), '5.0');
      expect(axisLabel(4.999999999), '5.0');
      expect(axisLabel(2.4), '2.4');
    });
  });

  group('底部日期轴', () {
    // 真机上月视图底下日期叠成一团，早先的做法是隔几个跳一个；跳过之后
    // 剩下的日期对不上自己关心的那天，等于没标。现在改成竖排 + 全部列出。
    testWidgets('周视图把 7 个日期全部列出来', (WidgetTester tester) async {
      await pumpStats(tester, rides: <Ride>[ride(1, 2026, 9, 22)]);

      for (int d = 21; d <= 27; d++) {
        final String label = '09-$d';
        expect(find.text(label), findsOneWidget, reason: '缺少日期标签 $label');
      }
    });

    testWidgets('月视图把整月 30 个日期全部列出来且不溢出', (WidgetTester tester) async {
      await pumpStats(tester, rides: <Ride>[ride(1, 2026, 9, 22)]);
      await tester.tap(find.text('月'));
      await tester.pumpAndSettle();

      for (int d = 1; d <= 30; d++) {
        final String label = '09-${d.toString().padLeft(2, '0')}';
        expect(find.text(label), findsOneWidget, reason: '缺少日期标签 $label');
      }
      // 30 个日期全列出来，横排一定放不下；这条顺带确认竖排没把布局撑爆。
      expect(tester.takeException(), isNull);
    });

    testWidgets('年视图把 12 个月份全部列出来', (WidgetTester tester) async {
      await pumpStats(tester, rides: <Ride>[ride(1, 2026, 9, 22)]);
      await tester.tap(find.text('年'));
      await tester.pumpAndSettle();

      for (int m = 1; m <= 12; m++) {
        final String label = '2026-${m.toString().padLeft(2, '0')}';
        expect(find.text(label), findsOneWidget, reason: '缺少月份标签 $label');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('日期标签竖排，避免相邻日期横向叠在一起', (WidgetTester tester) async {
      await pumpStats(tester, rides: <Ride>[ride(1, 2026, 9, 22)]);

      // fl_chart 自己也会在图表外层套一个 `RotatedBox`（`quarterTurns` 为 0），
      // 所以不能只数「有没有 RotatedBox」，要看其中有没有真的转 90° 的那个。
      final Iterable<RotatedBox> boxes = tester.widgetList<RotatedBox>(
        find.ancestor(
          of: find.text('09-22'),
          matching: find.byType(RotatedBox),
        ),
      );
      expect(boxes.map((RotatedBox b) => b.quarterTurns), contains(3));
    });
  });
}
