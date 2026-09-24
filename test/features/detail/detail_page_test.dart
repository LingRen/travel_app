import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/analysis/curve.dart';
import 'package:cycling_app/domain/analysis/gcj02.dart';
import 'package:cycling_app/domain/analysis/heart_rate.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/features/detail/curve_chart.dart';
import 'package:cycling_app/features/detail/detail_page.dart';
import 'package:cycling_app/features/detail/detail_providers.dart';
import 'package:cycling_app/features/detail/hr_zone_bar.dart';
import 'package:cycling_app/features/detail/route_map.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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

Ride rideWith({RideSummary? summary, String? powerDeviceName}) => Ride(
      id: 1,
      startedAtMs: DateTime(2026, 9, 21, 8).millisecondsSinceEpoch,
      endedAtMs: DateTime(2026, 9, 21, 9).millisecondsSinceEpoch,
      status: RideStatus.finished,
      title: '晨骑',
      powerDeviceName: powerDeviceName,
      summary: summary ??
          const RideSummary(
            distanceM: 25300,
            durationS: 3600,
            movingS: 3400,
            avgSpeedMps: 7.03,
            movingAvgSpeedMps: 7.44,
            maxSpeedMps: 12.5,
            elevationGainM: 180,
            avgHr: 142,
            maxHr: 176,
            avgCadence: 78,
            calories: 900,
            pointCount: 4,
          ),
    );

/// 带功率的汇总，用来核对功率区块的读数与标题。
const RideSummary _powerSummary = RideSummary(
  distanceM: 25300,
  durationS: 3600,
  movingS: 3400,
  avgSpeedMps: 7.03,
  movingAvgSpeedMps: 7.44,
  maxSpeedMps: 12.5,
  elevationGainM: 180,
  avgHr: 142,
  maxHr: 176,
  avgCadence: 78,
  avgPowerW: 205.3,
  maxPowerW: 230,
  calories: 900,
  pointCount: 4,
);

/// 每个点都带功率，功率区块才会渲染。
List<TrackPoint> pointsWithPower() => <TrackPoint>[
      for (int i = 0; i < 4; i++)
        TrackPoint(
          rideId: 1,
          tMs: 1000 + i * 1000,
          lat: 31.0 + i * 0.0001,
          lon: 121.0,
          speedMps: 4.0 + i,
          powerW: 200 + i * 10,
        ),
    ];

/// 每秒一个点，速度与心率递增，用来产生可断言的曲线与区间分布。
List<TrackPoint> pointsWithHr() => <TrackPoint>[
      for (int i = 0; i < 4; i++)
        TrackPoint(
          rideId: 1,
          tMs: 1000 + i * 1000,
          lat: 31.0 + i * 0.0001,
          lon: 121.0,
          altitudeM: 10.0 + i,
          speedMps: 4.0 + i,
          hr: 100 + i * 20,
          cadence: 70 + i,
        ),
    ];

Widget wrap({
  required RideDetail detail,
  AppSettings settings = _settings,
}) =>
    ProviderScope(
      overrides: <Override>[
        rideDetailProvider(detail.ride.id!).overrideWith((Ref ref) => detail),
        appSettingsProvider.overrideWithValue(AsyncValue<AppSettings>.data(settings)),
      ],
      child: MaterialApp(home: DetailPage(rideId: detail.ride.id!)),
    );

/// 详情页是 `ListView`，默认 800x600 的测试视口只会懒构建前两屏；
/// 「三个区块都渲染出来」这类断言必须先把视口调高，否则断言会退化成
/// 「当前滚动位置恰好构建了哪些区块」。
Future<void> pumpDetail(WidgetTester tester, {required RideDetail detail}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(detail: detail));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('显示汇总指标网格里的距离、时长与爬升', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: RideDetail(ride: rideWith(), points: pointsWithHr()),
    );

    expect(find.text('25.30 km'), findsOneWidget);
    expect(find.text('1:00:00'), findsOneWidget);
    expect(find.text('180 m'), findsOneWidget);
  });

  testWidgets('标题显示骑行标题与日期', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: RideDetail(ride: rideWith(), points: pointsWithHr()),
    );

    expect(find.text('晨骑'), findsOneWidget);
    expect(find.text('2026-09-21 08:00'), findsOneWidget);
  });

  testWidgets('三条曲线区块都渲染出来', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: RideDetail(ride: rideWith(), points: pointsWithHr()),
    );

    expect(find.text('速度'), findsOneWidget);
    expect(find.text('心率'), findsOneWidget);
    expect(find.text('踏频'), findsOneWidget);
    expect(find.byType(CurveChart), findsNWidgets(3));
  });

  testWidgets('没有心率数据时不渲染心率曲线与区间条', (WidgetTester tester) async {
    final List<TrackPoint> noHr = <TrackPoint>[
      for (final TrackPoint p in pointsWithHr())
        TrackPoint(
          rideId: p.rideId,
          tMs: p.tMs,
          lat: p.lat,
          lon: p.lon,
          speedMps: p.speedMps,
          cadence: p.cadence,
        ),
    ];

    await pumpDetail(
      tester,
      detail: RideDetail(ride: rideWith(), points: noHr),
    );

    expect(find.text('心率'), findsNothing);
    expect(find.byType(HrZoneBar), findsNothing);
    expect(find.text('速度'), findsOneWidget);
  });

  testWidgets('没有踏频数据时不渲染踏频曲线', (WidgetTester tester) async {
    final List<TrackPoint> noCadence = <TrackPoint>[
      for (final TrackPoint p in pointsWithHr())
        TrackPoint(
          rideId: p.rideId,
          tMs: p.tMs,
          lat: p.lat,
          lon: p.lon,
          speedMps: p.speedMps,
          hr: p.hr,
        ),
    ];

    await pumpDetail(
      tester,
      detail: RideDetail(ride: rideWith(), points: noCadence),
    );

    expect(find.text('踏频'), findsNothing);
    expect(find.text('心率'), findsOneWidget);
  });

  // 没接功率计的那次骑行，库里存的功率是按速度、坡度与体重估出来的，和实测
  // 功率长得一模一样，只有 `Ride.powerDeviceName` 能区分，所以标题必须跟着变。
  group('功率区块的标题', () {
    testWidgets('没接功率计：标题写明「估算」', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        detail: RideDetail(
          ride: rideWith(summary: _powerSummary),
          points: pointsWithPower(),
        ),
      );

      expect(find.text('功率（估算）'), findsOneWidget);
      expect(find.text('功率'), findsNothing);
      expect(find.text('平均功率'), findsOneWidget);
      expect(find.text('205 W'), findsOneWidget);
      expect(find.text('230 W'), findsOneWidget);
    });

    testWidgets('接了功率计：标题就是「功率」', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        detail: RideDetail(
          ride: rideWith(summary: _powerSummary, powerDeviceName: 'ASSIOMA'),
          points: pointsWithPower(),
        ),
      );

      expect(find.text('功率'), findsOneWidget);
      expect(find.text('功率（估算）'), findsNothing);
    });
  });

  testWidgets('轨迹点为空时显示空数据提示且不崩溃', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: RideDetail(ride: rideWith(), points: const <TrackPoint>[]),
    );

    expect(find.text('这次骑行没有轨迹数据'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 计划书的变异表第 1 条（`speed.length >= 2` 改成 `>= 0`）原本没有杀死点：
  // 上面那条用例只断言提示文本与「不崩溃」，而空样本画不出线，也不会抛异常。
  // 这条用例把「一个曲线区块都不该出现」钉住。
  testWidgets('轨迹点为空时一个曲线区块都不渲染', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: RideDetail(ride: rideWith(), points: const <TrackPoint>[]),
    );

    expect(find.byType(CurveChart), findsNothing);
    expect(find.text('速度'), findsNothing);
    expect(find.text('心率'), findsNothing);
    expect(find.text('踏频'), findsNothing);
    expect(find.byType(HrZoneBar), findsNothing);
  });

  testWidgets('心率区间条按区间标出时长占比', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: RideDetail(ride: rideWith(), points: pointsWithHr()),
    );

    // 四个点共 3 秒：心率 120/140/160 分别落在 Z2/Z3/Z4（最大心率 190）。
    final HrZoneBar bar = tester.widget<HrZoneBar>(find.byType(HrZoneBar));
    expect(bar.breakdown.totalSeconds, 3.0);
    expect(bar.breakdown.ratioOf(2), closeTo(1 / 3, 1e-9));
    expect(bar.breakdown.ratioOf(3), closeTo(1 / 3, 1e-9));
    expect(bar.breakdown.ratioOf(4), closeTo(1 / 3, 1e-9));
    expect(bar.breakdown.ratioOf(1), 0);
    expect(bar.breakdown.ratioOf(5), 0);
  });

  testWidgets('汇总缺失（进行中的骑行）时显示提示而不是崩溃', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: RideDetail(
        ride: Ride(id: 1, startedAtMs: 1000, status: RideStatus.finished),
        points: const <TrackPoint>[],
      ),
    );

    expect(find.text('这条记录还没有汇总指标'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('轨迹点有坐标时渲染地图区块', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      detail: RideDetail(ride: rideWith(), points: pointsWithHr()),
    ));
    await tester.pumpAndSettle();

    // 实测：flutter_test 的 HttpOverrides 让瓦片请求返回 400 而不是挂起，
    // `pumpAndSettle` 不会超时，也不会有异常逃出来；瓦片自然一张都没画出来
    // （`find.byType(Image)` 为 0），但地图与折线图层本身确实构建了。
    // 只断言 `RouteMap` 的话，这条用例在「永远显示占位提示」的实现下也会通过，
    // 因此把「真的建了 FlutterMap」钉住。
    expect(find.byType(RouteMap), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(PolylineLayer), findsOneWidget);
  });

  // 轨迹用哪套坐标必须跟着瓦片源走：对 OSM 这类 WGS-84 源再转一次 GCJ-02，
  // 轨迹会整体偏出几百米（真机实测约 310 米）。这里直接读折线收到的坐标，
  // 而不是只断言「传了参数」。
  group('坐标跟随瓦片源', () {
    LatLng firstPolylinePoint(WidgetTester tester) =>
        tester
            .widget<PolylineLayer<Object>>(find.byType(PolylineLayer))
            .polylines
            .first
            .points
            .first;

    testWidgets('高德源：轨迹转成 GCJ-02', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(
        detail: RideDetail(ride: rideWith(), points: pointsWithHr()),
      ));
      await tester.pumpAndSettle();

      final ({double lat, double lon}) expected = wgs84ToGcj02(31.0, 121.0);
      final LatLng first = firstPolylinePoint(tester);
      expect(first.latitude, closeTo(expected.lat, 1e-9));
      expect(first.longitude, closeTo(expected.lon, 1e-9));
    });

    testWidgets('OSM 源：轨迹保持 WGS-84 原样', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(
        detail: RideDetail(ride: rideWith(), points: pointsWithHr()),
        settings: const AppSettings(
          maxHeartRate: 190,
          weightKg: 70,
          distanceUnit: DistanceUnit.kilometer,
          mapTileUrlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        ),
      ));
      await tester.pumpAndSettle();

      final LatLng first = firstPolylinePoint(tester);
      expect(first.latitude, 31.0);
      expect(first.longitude, 121.0);
    });
  });

  testWidgets('轨迹点没有坐标时不渲染地图，显示占位提示', (WidgetTester tester) async {
    final List<TrackPoint> noPosition = <TrackPoint>[
      for (int i = 0; i < 3; i++)
        TrackPoint(rideId: 1, tMs: 1000 + i * 1000, speedMps: 5, hr: 140),
    ];

    await tester.pumpWidget(wrap(
      detail: RideDetail(ride: rideWith(), points: noPosition),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(RouteMap), findsOneWidget);
    expect(find.text('这次骑行没有可显示的轨迹'), findsOneWidget);
  });

  group('曲线断点分段', () {
    test('跨 segment 的相邻两点不连线', () {
      const List<CurveSample> samples = <CurveSample>[
        CurveSample(xSeconds: 0, y: 10, segment: 0),
        CurveSample(xSeconds: 1, y: 11, segment: 0),
        CurveSample(xSeconds: 2, y: 12, segment: 1),
        CurveSample(xSeconds: 3, y: 13, segment: 1),
      ];

      // 只有 (0,1) 与 (2,3) 能连；(1,2) 跨段必须被跳过。
      expect(drawnCurveSegments(samples), <(int, int)>[(0, 1), (2, 3)]);
    });

    test('GPS 断点让 buildCurve 递增 segment，画笔据此断开', () {
      // 第三点比第二点晚 20 秒（> kGpsGapMs = 10 秒）→ 断点。
      final List<TrackPoint> points = <TrackPoint>[
        TrackPoint(rideId: 1, tMs: 0, speedMps: 5),
        TrackPoint(rideId: 1, tMs: 1000, speedMps: 5),
        TrackPoint(rideId: 1, tMs: 21000, speedMps: 5),
        TrackPoint(rideId: 1, tMs: 22000, speedMps: 5),
      ];

      final List<CurveSample> samples =
          buildCurve(points, metric: CurveMetric.speed);

      expect(samples.map((CurveSample s) => s.segment).toList(), <int>[0, 0, 1, 1]);
      expect(drawnCurveSegments(samples), <(int, int)>[(0, 1), (2, 3)]);
    });

    test('全部点同属一个 segment 时相邻点全部连线', () {
      const List<CurveSample> samples = <CurveSample>[
        CurveSample(xSeconds: 0, y: 1, segment: 0),
        CurveSample(xSeconds: 1, y: 2, segment: 0),
        CurveSample(xSeconds: 2, y: 3, segment: 0),
      ];

      expect(drawnCurveSegments(samples), <(int, int)>[(0, 1), (1, 2)]);
    });
  });

  group('心率区间条', () {
    testWidgets('占比极小的区间仍占一条可见宽度，不会整段消失', (WidgetTester tester) async {
      // 2.001 秒里 Z2 只占 1 毫秒：ratio ≈ 0.0005，乘 1000 取整后是 0。
      // `Expanded(flex: 0)` 会被当成非弹性子节点量出零宽（实测宽度 0.0px），
      // 这个区间就从条上凭空消失了。
      const HrZoneBreakdown breakdown = HrZoneBreakdown(
        secondsByZone: <int, double>{1: 2.0, 2: 0.001},
        totalSeconds: 2.001,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, child: HrZoneBar(breakdown: breakdown)),
        ),
      ));
      await tester.pumpAndSettle();

      final Finder zones = find.descendant(
        of: find.byType(HrZoneBar),
        matching: find.byType(ColoredBox),
      );
      expect(zones, findsNWidgets(2));
      expect(tester.getSize(zones.at(0)).width, greaterThan(0));
      expect(tester.getSize(zones.at(1)).width, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  });
}
