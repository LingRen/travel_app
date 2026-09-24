import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/analysis/curve.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/features/detail/detail_page.dart';
import 'package:cycling_app/features/detail/detail_providers.dart';
import 'package:cycling_app/features/history/history_page.dart';
import 'package:cycling_app/features/history/history_providers.dart';
import 'package:cycling_app/features/history/mini_speed_curve.dart';
import 'package:cycling_app/features/history/ride_card.dart';
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

const RideSummary _summary = RideSummary(
  distanceM: 25300,
  durationS: 3600,
  movingS: 3400,
  avgSpeedMps: 7.03,
  movingAvgSpeedMps: 7.44,
  maxSpeedMps: 12.5,
  elevationGainM: 180,
  pointCount: 4,
);

Ride ride(int id, {String? title, int? startedAtMs, RideSummary? summary}) => Ride(
      id: id,
      startedAtMs: startedAtMs ?? DateTime(2026, 9, 21, 8).millisecondsSinceEpoch,
      endedAtMs: DateTime(2026, 9, 21, 9).millisecondsSinceEpoch,
      status: RideStatus.finished,
      title: title,
      summary: summary ?? _summary,
    );

List<TrackPoint> points() => <TrackPoint>[
      for (int i = 0; i < 4; i++)
        TrackPoint(
          rideId: 1,
          tMs: 1000 + i * 1000,
          lat: 31.0 + i * 0.0001,
          lon: 121.0,
          speedMps: 4.0 + i,
        ),
    ];

/// 点卡片进入详情页时要用的假详情：标题为空，因此 AppBar 会退回 `骑行详情`。
RideDetail detailFor(int id) => RideDetail(
      ride: Ride(
        id: id,
        startedAtMs: DateTime(2026, 9, 21, 8).millisecondsSinceEpoch,
        endedAtMs: DateTime(2026, 9, 21, 9).millisecondsSinceEpoch,
        status: RideStatus.finished,
      ),
      points: const <TrackPoint>[],
    );

Widget wrap({
  required List<Ride> rides,
  List<TrackPoint>? ridePoints,
  AppSettings settings = _settings,
  RideDetail? detail,
}) =>
    ProviderScope(
      overrides: <Override>[
        historyRidesProvider.overrideWith((Ref ref) => rides),
        appSettingsProvider.overrideWithValue(AsyncValue<AppSettings>.data(settings)),
        // id 为 null 的记录根本不会查询轨迹点（`_MiniCurve` 直接返回占位），
        // 这里也跳过，否则 `r.id!` 会在建 ProviderScope 时就抛。
        for (final Ride r in rides)
          if (r.id != null)
            ridePointsProvider(r.id!).overrideWith(
              (Ref ref) => ridePoints ?? const <TrackPoint>[],
            ),
        if (detail != null)
          rideDetailProvider(detail.ride.id!).overrideWith((Ref ref) => detail),
      ],
      child: const MaterialApp(home: HistoryPage()),
    );

/// 历史页是 `ListView.builder`，默认 800x600 的测试视口只懒构建前几屏，
/// 后面的卡片根本不会被 build。多卡片用例必须先把视口调高，否则断言会退化成
/// 「当前视口恰好构建了哪几张卡」。
Future<void> pumpHistory(
  WidgetTester tester, {
  required List<Ride> rides,
  List<TrackPoint>? ridePoints,
  AppSettings settings = _settings,
  RideDetail? detail,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(
    rides: rides,
    ridePoints: ridePoints,
    settings: settings,
    detail: detail,
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('没有记录时显示空态提示', (WidgetTester tester) async {
    await pumpHistory(tester, rides: const <Ride>[]);

    expect(find.text('还没有骑行记录'), findsOneWidget);
    expect(find.byType(RideCard), findsNothing);
  });

  testWidgets('每条记录一张卡片，按传入顺序渲染', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Ride>[
        ride(2, title: '第二次', startedAtMs: DateTime(2026, 9, 22, 8).millisecondsSinceEpoch),
        ride(1, title: '第一次'),
      ],
      ridePoints: points(),
    );

    expect(find.byType(RideCard), findsNWidgets(2));
    expect(find.text('第二次'), findsOneWidget);
    expect(find.text('第一次'), findsOneWidget);
  });

  testWidgets('卡片显示日期、距离、时长、均速与爬升', (WidgetTester tester) async {
    await pumpHistory(tester, rides: <Ride>[ride(1)], ridePoints: points());

    expect(find.text('2026-09-21 08:00'), findsOneWidget);
    expect(find.text('25.30 km'), findsOneWidget);
    expect(find.text('1:00:00'), findsOneWidget);
    // 卡片渲染的是移动均速（7.44 m/s），不是 avgSpeedMps（7.03 m/s）。
    expect(find.text('26.8 km/h'), findsOneWidget);
    expect(find.text('爬升 180 m'), findsOneWidget);
    // 这次骑行没有功率数据，不能摆一个 `功率 0 W`。
    expect(find.textContaining('功率'), findsNothing);
  });

  testWidgets('配了功率计时卡片多一项功率读数', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Ride>[
        ride(
          1,
          summary: const RideSummary(
            distanceM: 25300,
            durationS: 3600,
            movingS: 3400,
            avgSpeedMps: 7.03,
            movingAvgSpeedMps: 7.44,
            maxSpeedMps: 12.5,
            elevationGainM: 180,
            pointCount: 4,
            avgPowerW: 135.4,
            maxPowerW: 412,
          ),
        ),
      ],
      ridePoints: points(),
    );

    // 平均功率保留到瓦，135.4 → 135 W。
    expect(find.text('功率 135 W'), findsOneWidget);
  });

  testWidgets('卡片里渲染迷你速度曲线', (WidgetTester tester) async {
    await pumpHistory(tester, rides: <Ride>[ride(1)], ridePoints: points());

    expect(find.byType(MiniSpeedCurve), findsOneWidget);
  });

  // 计划书原本这条用例与「卡片显示日期…」完全重复（同样的输入、同样的断言），
  // 区分力为零。改成同时钉住「有/无标题」两个渲染分支：
  // 无标题时只有一行日期；有标题时标题与日期各一行（日期不会重复出现）。
  testWidgets('无标题时只渲染一行日期', (WidgetTester tester) async {
    await pumpHistory(tester, rides: <Ride>[ride(1)], ridePoints: points());

    expect(find.text('2026-09-21 08:00'), findsOneWidget);
  });

  testWidgets('有标题时标题与日期各渲染一行', (WidgetTester tester) async {
    await pumpHistory(tester, rides: <Ride>[ride(1, title: '晨骑')], ridePoints: points());

    expect(find.text('晨骑'), findsOneWidget);
    expect(find.text('2026-09-21 08:00'), findsOneWidget);
  });

  testWidgets('英里单位下按英里显示距离', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Ride>[ride(1)],
      ridePoints: points(),
      settings: const AppSettings(
        maxHeartRate: 190,
        weightKg: 70,
        distanceUnit: DistanceUnit.mile,
        mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
      ),
    );

    expect(find.text('15.72 mi'), findsOneWidget); // 25300 m
  });

  testWidgets('点卡片进入详情页', (WidgetTester tester) async {
    // 必须一并 override `rideDetailProvider`：否则详情页会去读
    // `rideRepositoryProvider` → `databaseProvider`，测试里没有数据库而抛异常。
    await pumpHistory(
      tester,
      rides: <Ride>[ride(1)],
      ridePoints: points(),
      detail: detailFor(1),
    );

    await tester.tap(find.byType(RideCard).first);
    await tester.pumpAndSettle();

    expect(find.byType(DetailPage), findsOneWidget);
    expect(find.text('骑行详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有汇总指标的记录不崩溃，卡片显示占位', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Ride>[
        const Ride(id: 1, startedAtMs: 1000, status: RideStatus.finished),
      ],
    );

    expect(find.byType(RideCard), findsOneWidget);
    expect(find.text('这条记录还没有汇总指标'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 计划书变异表第 5 条（去掉 `_MiniCurve` 里的 id 判空）原本杀不死：
  // 上面那条记录 id 是 1，走的是非空分支。这条用例用 id == null 的记录钉住
  // 「没有 id 就不该去查询轨迹点」。
  testWidgets('没有 id 的记录不查询轨迹点也不崩溃', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Ride>[
        const Ride(startedAtMs: 1000, status: RideStatus.finished),
      ],
    );

    expect(find.byType(RideCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // `CustomPaint` 没有可断言的语义节点，`find.byType(MiniSpeedCurve)` 对画笔逻辑
  // 毫无区分力（把 paint 掏空照样通过）。这里直接断言画笔的连线判定纯函数。
  group('迷你曲线的连线判定', () {
    test('样本不足 2 个时不画任何线段', () {
      expect(drawnMiniCurveSegments(const <CurveSample>[]), isEmpty);
      expect(
        drawnMiniCurveSegments(
          const <CurveSample>[CurveSample(xSeconds: 0, y: 5, segment: 0)],
        ),
        isEmpty,
      );
    });

    test('正常输入时线段数等于样本数减一', () {
      final List<CurveSample> samples =
          buildCurve(points(), metric: CurveMetric.speed);

      expect(samples.length, 4);
      expect(
        drawnMiniCurveSegments(samples),
        <(int, int)>[(0, 1), (1, 2), (2, 3)],
      );
      expect(drawnMiniCurveSegments(samples).length, samples.length - 1);
    });

    test('跨 segment 的相邻两点不连线', () {
      const List<CurveSample> samples = <CurveSample>[
        CurveSample(xSeconds: 0, y: 10, segment: 0),
        CurveSample(xSeconds: 1, y: 11, segment: 0),
        CurveSample(xSeconds: 2, y: 12, segment: 1),
        CurveSample(xSeconds: 3, y: 13, segment: 1),
      ];

      expect(drawnMiniCurveSegments(samples), <(int, int)>[(0, 1), (2, 3)]);
    });
  });
}
