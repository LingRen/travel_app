import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/app/theme.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/analysis/curve.dart';
import 'package:cycling_app/domain/analysis/gcj02.dart';
import 'package:cycling_app/domain/analysis/heart_rate.dart';
import 'package:cycling_app/domain/models/activity_type.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/models/workout.dart';
import 'package:cycling_app/domain/models/workout_status.dart';
import 'package:cycling_app/domain/models/workout_summary.dart';
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

Workout rideWith({
  WorkoutSummary? summary,
  String? powerDeviceName,
  ActivityType? activityType,
  String? placeName,
  String? placeShort,
  String? weatherText,
  int? weatherTempC,
}) => Workout(
  id: 1,
  startedAtMs: DateTime(2026, 9, 21, 8).millisecondsSinceEpoch,
  endedAtMs: DateTime(2026, 9, 21, 9).millisecondsSinceEpoch,
  status: WorkoutStatus.finished,
  title: '晨骑',
  activityType: activityType ?? ActivityType.cycling,
  powerDeviceName: powerDeviceName,
  placeName: placeName,
  placeShort: placeShort,
  weatherText: weatherText,
  weatherTempC: weatherTempC,
  summary:
      summary ??
      const WorkoutSummary(
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
const WorkoutSummary _powerSummary = WorkoutSummary(
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

/// 中段丢过 35 秒定位：详情页据此在地图上标断口、写一行中断摘要。
List<TrackPoint> pointsWithGap() => <TrackPoint>[
  const TrackPoint(rideId: 1, tMs: 1000, lat: 31.0, lon: 121.0, speedMps: 4),
  const TrackPoint(rideId: 1, tMs: 2000, lat: 31.0001, lon: 121.0, speedMps: 4),
  // 35 秒空档 + 约 1.1 公里位移：信号真的丢了。
  const TrackPoint(rideId: 1, tMs: 37000, lat: 31.01, lon: 121.0, speedMps: 5),
  const TrackPoint(
    rideId: 1,
    tMs: 38000,
    lat: 31.0101,
    lon: 121.0,
    speedMps: 5,
  ),
];

/// 中段丢过 14 秒定位：短缺口，用虚线跨过，不计入信号中断。
List<TrackPoint> pointsWithShortGap() => <TrackPoint>[
  const TrackPoint(rideId: 1, tMs: 1000, lat: 31.0, lon: 121.0, speedMps: 4),
  const TrackPoint(rideId: 1, tMs: 2000, lat: 31.0001, lon: 121.0, speedMps: 4),
  const TrackPoint(rideId: 1, tMs: 16000, lat: 31.01, lon: 121.0, speedMps: 5),
  const TrackPoint(
    rideId: 1,
    tMs: 17000,
    lat: 31.0101,
    lon: 121.0,
    speedMps: 5,
  ),
];

Widget wrap({
  required WorkoutDetail detail,
  AppSettings settings = _settings,
}) => ProviderScope(
  overrides: <Override>[
    rideDetailProvider(detail.ride.id!).overrideWith((Ref ref) => detail),
    appSettingsProvider.overrideWithValue(
      AsyncValue<AppSettings>.data(settings),
    ),
  ],
  child: MaterialApp(
    theme: buildAppTheme(),
    home: DetailPage(rideId: detail.ride.id!),
  ),
);

/// 详情页是 `ListView`，默认 800x600 的测试视口只会懒构建前两屏；
/// 「三个区块都渲染出来」这类断言必须先把视口调高，否则断言会退化成
/// 「当前滚动位置恰好构建了哪些区块」。
Future<void> pumpDetail(
  WidgetTester tester, {
  required WorkoutDetail detail,
}) async {
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
      detail: WorkoutDetail(ride: rideWith(), points: pointsWithHr()),
    );

    expect(find.text('25.3'), findsOneWidget);
    expect(find.text('km'), findsOneWidget);
    expect(find.text('1:00:00'), findsOneWidget);
    expect(find.text('180'), findsOneWidget);
    expect(find.text('m'), findsOneWidget);
  });

  testWidgets('标题显示骑行标题与日期', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(ride: rideWith(), points: pointsWithHr()),
    );

    expect(find.text('晨骑'), findsOneWidget);
    expect(find.text('09.21'), findsOneWidget);
    expect(find.text('周一 · 08:00'), findsOneWidget);
  });

  testWidgets('标题下显示记录捕获的地点与天气', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(
        ride: rideWith(
          placeName: '成都市 · 龙泉驿区 · 桃花故里',
          placeShort: '龙泉驿区',
          weatherText: '晴',
          weatherTempC: 18,
        ),
        points: pointsWithHr(),
      ),
    );

    expect(find.byKey(const Key('detail-conditions-place')), findsOneWidget);
    expect(find.text('成都市 · 龙泉驿区 · 桃花故里'), findsOneWidget);
    expect(find.byKey(const Key('detail-conditions-weather')), findsOneWidget);
    expect(find.text('晴 18°C'), findsOneWidget);
  });

  testWidgets('没有地点与天气的旧记录不渲染条件行', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(ride: rideWith(), points: pointsWithHr()),
    );

    expect(find.byKey(const Key('detail-conditions-place')), findsNothing);
    expect(find.byKey(const Key('detail-conditions-weather')), findsNothing);
  });

  testWidgets('只有天气时仍显示天气，不编造地点', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(
        ride: rideWith(weatherText: '小雨', weatherTempC: 12),
        points: pointsWithHr(),
      ),
    );

    expect(find.byKey(const Key('detail-conditions-place')), findsNothing);
    expect(find.text('小雨 12°C'), findsOneWidget);
  });

  testWidgets('跑步记录：页眉写「跑步详情」，汇总用配速', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(
        ride: rideWith(activityType: ActivityType.running),
        points: pointsWithHr(),
      ),
    );

    expect(find.text('跑步详情'), findsOneWidget);
    expect(find.text('配速'), findsNWidgets(2), reason: '汇总格 + 曲线标题');
    expect(find.text('09.21'), findsOneWidget);
  });

  testWidgets('无标题的骑行记录：AppBar 显示「骑行详情」而非「跑步详情」', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(
        ride: Workout(id: 1, startedAtMs: 1000, status: WorkoutStatus.finished),
        points: const <TrackPoint>[],
      ),
    );

    expect(find.text('骑行详情'), findsOneWidget);
    expect(find.text('跑步详情'), findsNothing);
  });

  testWidgets('三条曲线区块都渲染出来', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(ride: rideWith(), points: pointsWithHr()),
    );

    expect(find.byKey(const Key('detail-section-speed')), findsOneWidget);
    expect(find.byKey(const Key('detail-section-hr')), findsOneWidget);
    expect(find.byKey(const Key('detail-section-cadence')), findsOneWidget);
    expect(find.byType(CurveChart), findsNWidgets(3));
  });

  // 曲线上的最高 / 最低 / 平均三个标注。极值取自曲线本身（见 `curve_test.dart`
  // 的 curveExtremes 用例），平均值与格式化口径必须和上方读数同源——否则同一屏
  // 里会出现「平均心率 142」和曲线上「平均 141.7」两个数。
  group('曲线标注', () {
    testWidgets('平均线与格式化口径跟着上方读数走', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        detail: WorkoutDetail(ride: rideWith(), points: pointsWithHr()),
      );

      // 顺序与区块一致：速度、心率、踏频。
      final List<CurveChart> charts = tester
          .widgetList<CurveChart>(find.byType(CurveChart))
          .toList();

      // 速度：平均线画在总均速 7.03 m/s 上，标注一位小数、单位 km/h。
      expect(charts[0].averageValue, 7.03);
      expect(charts[0].formatValue(7.03), '25.3');
      expect(charts[0].unitLabel, 'km/h');

      // 心率：平均线画在平均心率 142 上，标注取整。
      expect(charts[1].averageValue, 142);
      expect(charts[1].formatValue(141.6), '142');

      // 踏频同理。
      expect(charts[2].averageValue, 78);
      expect(charts[2].formatValue(78.4), '78');
    });

    testWidgets('带功率的骑行：功率曲线也带上平均线', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        detail: WorkoutDetail(
          ride: rideWith(summary: _powerSummary),
          points: pointsWithPower(),
        ),
      );

      final CurveChart power = tester
          .widgetList<CurveChart>(find.byType(CurveChart))
          .last;
      expect(power.averageValue, 205.3);
      expect(power.formatValue(205.3), '205');
      expect(power.unitLabel, 'W');
    });

    testWidgets('汇总缺失（进行中的骑行）时不画平均线，曲线照常画', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        detail: WorkoutDetail(
          ride: Workout(
            id: 1,
            startedAtMs: 1000,
            status: WorkoutStatus.finished,
          ),
          points: pointsWithHr(),
        ),
      );

      final List<CurveChart> charts = tester
          .widgetList<CurveChart>(find.byType(CurveChart))
          .toList();
      expect(charts, isNotEmpty);
      for (final CurveChart chart in charts) {
        expect(chart.averageValue, isNull);
      }
    });
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
      detail: WorkoutDetail(ride: rideWith(), points: noHr),
    );

    expect(find.byKey(const Key('detail-section-hr')), findsNothing);
    expect(find.byType(HrZoneBar), findsNothing);
    expect(find.byKey(const Key('detail-section-speed')), findsOneWidget);
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
      detail: WorkoutDetail(ride: rideWith(), points: noCadence),
    );

    expect(find.byKey(const Key('detail-section-cadence')), findsNothing);
    expect(find.byKey(const Key('detail-section-hr')), findsOneWidget);
  });

  // 没接功率计的那次骑行，库里存的功率是按速度、坡度与体重估出来的，和实测
  // 功率长得一模一样，只有 `Workout.powerDeviceName` 能区分，所以标题必须跟着变。
  group('功率区块的标题', () {
    testWidgets('没接功率计：标题写明「估算」', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        detail: WorkoutDetail(
          ride: rideWith(summary: _powerSummary),
          points: pointsWithPower(),
        ),
      );

      expect(find.text('功率（估算）'), findsOneWidget);
      // 汇总格的标签也叫「功率」；「估算」只出现在曲线区块标题里。
      expect(find.text('功率'), findsOneWidget);
      expect(find.byKey(const Key('detail-section-power')), findsOneWidget);
      expect(find.textContaining('均 205 W'), findsOneWidget);
      expect(find.textContaining('高 230 W'), findsOneWidget);
    });

    testWidgets('接了功率计：标题就是「功率」', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        detail: WorkoutDetail(
          ride: rideWith(summary: _powerSummary, powerDeviceName: 'ASSIOMA'),
          points: pointsWithPower(),
        ),
      );

      expect(find.text('功率'), findsNWidgets(2), reason: '汇总格 + 曲线标题');
      expect(find.text('功率（估算）'), findsNothing);
    });
  });

  testWidgets('轨迹点为空时显示空数据提示且不崩溃', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(ride: rideWith(), points: const <TrackPoint>[]),
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
      detail: WorkoutDetail(ride: rideWith(), points: const <TrackPoint>[]),
    );

    expect(find.byType(CurveChart), findsNothing);
    expect(find.byKey(const Key('detail-section-speed')), findsNothing);
    expect(find.byKey(const Key('detail-section-hr')), findsNothing);
    expect(find.byKey(const Key('detail-section-cadence')), findsNothing);
    expect(find.byKey(const Key('detail-section-power')), findsNothing);
    expect(find.byType(HrZoneBar), findsNothing);
  });

  testWidgets('心率区间条按区间标出时长占比', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(ride: rideWith(), points: pointsWithHr()),
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
      detail: WorkoutDetail(
        ride: Workout(id: 1, startedAtMs: 1000, status: WorkoutStatus.finished),
        points: const <TrackPoint>[],
      ),
    );

    expect(find.text('这条记录还没有汇总指标'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('轨迹点有坐标时渲染地图区块', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        detail: WorkoutDetail(ride: rideWith(), points: pointsWithHr()),
      ),
    );
    await tester.pumpAndSettle();

    // 实测：flutter_test 的 HttpOverrides 让瓦片请求返回 400 而不是挂起，
    // `pumpAndSettle` 不会超时，也不会有异常逃出来；瓦片自然一张都没画出来
    // （`find.byType(Image)` 为 0），但地图与折线图层本身确实构建了。
    // 只断言 `RouteMap` 的话，这条用例在「永远显示占位提示」的实现下也会通过，
    // 因此把「真的建了 FlutterMap」钉住。
    expect(find.byType(RouteMap), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(PolylineLayer), findsOneWidget);

    // 轨迹必须自带深色描边：慢速端是浅黄，与高德底图的黄白路面对撞，真机上
    // 整段轨迹会糊进路面（「地图上轨迹线条看不清」）。只断言图层存在的话，
    // 把描边去掉这条用例仍然通过。
    final Polyline<Object> line = tester
        .widget<PolylineLayer<Object>>(find.byType(PolylineLayer))
        .polylines
        .first;
    expect(line.strokeWidth, kRouteStrokeWidth);
    expect(line.borderStrokeWidth, kRouteCasingWidth);
    expect(line.borderColor, kRouteCasing);
  });

  // 信号弱导致轨迹断开时，界面必须解释这个缺口：否则用户只看到线断了一截，
  // 会以为记录出了问题。地图标两端 + 顶部写一行摘要，两处一起守。
  testWidgets('信号中断时标出断口并写明段数与总时长', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(ride: rideWith(), points: pointsWithGap()),
    );

    expect(find.textContaining('信号中断 1 段'), findsOneWidget);
    expect(find.textContaining('共 00:35'), findsOneWidget);

    // 断口两侧各一个端点，加上起终点各一个；用 key 断言，不绑数量。
    expect(find.byKey(const Key('detail-gap-end')), findsNWidgets(2));
    expect(find.byKey(const Key('detail-start-marker')), findsOneWidget);
    expect(find.byKey(const Key('detail-finish-marker')), findsOneWidget);
    expect(find.text('起'), findsOneWidget);
    expect(find.text('终'), findsOneWidget);
  });

  // 公交、楼群下十几秒没有定位很常见：这段真没有实测点，但把线彻底断开，
  // 用户会以为整段记录丢了。用虚线跨过并写明「未采到定位」，既不伪造实测
  // 轨迹，也不让地图看着断成两截。
  testWidgets('短缺口用虚线跨过，不算信号中断', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(ride: rideWith(), points: pointsWithShortGap()),
    );

    expect(find.textContaining('信号中断'), findsNothing);
    expect(find.textContaining('短缺口 1 段'), findsOneWidget);
    expect(find.byKey(const Key('detail-gap-end')), findsNothing);

    final List<Polyline<Object>> lines = tester
        .widget<PolylineLayer<Object>>(find.byType(PolylineLayer))
        .polylines;
    final Polyline<Object> bridged = lines.singleWhere(
      (Polyline<Object> line) => line.pattern.segments != null,
    );
    expect(bridged.points.length, 2, reason: '虚线只跨缺口两端，不插值补点');
  });

  testWidgets('没有断口时不显示中断摘要，起终点标记仍在', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(ride: rideWith(), points: pointsWithHr()),
    );

    expect(find.textContaining('信号中断'), findsNothing);
    expect(find.byKey(const Key('detail-gap-end')), findsNothing);
    expect(find.byKey(const Key('detail-start-marker')), findsOneWidget);
    expect(find.byKey(const Key('detail-finish-marker')), findsOneWidget);
  });

  // 横屏可用视口只有约 253dp（333 − 状态栏 − AppBar），固定 260dp 的地图比它还
  // 高：首屏被地图占满，而地图开了拖动会吃掉滑动手势，页面滚不动，下方的汇总与
  // 曲线就够不到了（真机横屏实测）。这两条把「竖屏维持 260dp、矮视口按高度收窄」
  // 钉住。
  testWidgets('矮视口（横屏）下地图按视口高度收窄', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(
        detail: WorkoutDetail(ride: rideWith(), points: pointsWithHr()),
      ),
    );
    await tester.pumpAndSettle();

    final double height = tester.widget<RouteMap>(find.byType(RouteMap)).height;
    expect(height, closeTo(360 * 0.45, 0.01));
    expect(height, lessThan(260));
  });

  testWidgets('竖屏视口下地图保持 260dp', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(
        detail: WorkoutDetail(ride: rideWith(), points: pointsWithHr()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<RouteMap>(find.byType(RouteMap)).height, 260);
  });

  // 轨迹用哪套坐标必须跟着瓦片源走：对 OSM 这类 WGS-84 源再转一次 GCJ-02，
  // 轨迹会整体偏出几百米（真机实测约 310 米）。这里直接读折线收到的坐标，
  // 而不是只断言「传了参数」。
  group('坐标跟随瓦片源', () {
    LatLng firstPolylinePoint(WidgetTester tester) => tester
        .widget<PolylineLayer<Object>>(find.byType(PolylineLayer))
        .polylines
        .first
        .points
        .first;

    testWidgets('高德源：轨迹转成 GCJ-02', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          detail: WorkoutDetail(ride: rideWith(), points: pointsWithHr()),
        ),
      );
      await tester.pumpAndSettle();

      final ({double lat, double lon}) expected = wgs84ToGcj02(31.0, 121.0);
      final LatLng first = firstPolylinePoint(tester);
      expect(first.latitude, closeTo(expected.lat, 1e-9));
      expect(first.longitude, closeTo(expected.lon, 1e-9));
    });

    testWidgets('OSM 源：轨迹保持 WGS-84 原样', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          detail: WorkoutDetail(ride: rideWith(), points: pointsWithHr()),
          settings: const AppSettings(
            maxHeartRate: 190,
            weightKg: 70,
            distanceUnit: DistanceUnit.kilometer,
            mapTileUrlTemplate:
                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          ),
        ),
      );
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

    await tester.pumpWidget(
      wrap(
        detail: WorkoutDetail(ride: rideWith(), points: noPosition),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RouteMap), findsOneWidget);
    expect(find.text('没有可显示的轨迹'), findsOneWidget);
  });

  testWidgets('汇总两行三列：骑行显示功率，功率为空时用破折号', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(
        ride: rideWith(summary: _powerSummary, powerDeviceName: 'ASSIOMA'),
        points: pointsWithPower(),
      ),
    );

    expect(find.text('距离'), findsOneWidget);
    expect(find.text('时长'), findsOneWidget);
    expect(find.text('爬升'), findsOneWidget);
    expect(find.text('均速'), findsOneWidget);
    expect(find.text('心率'), findsOneWidget);
    expect(find.text('功率'), findsNWidgets(2), reason: '汇总格 + 曲线标题');
    expect(find.text('205'), findsOneWidget);
  });

  testWidgets('徒步 / 登山汇总用海拔替代功率', (WidgetTester tester) async {
    for (final ActivityType type in <ActivityType>[
      ActivityType.hiking,
      ActivityType.mountaineering,
    ]) {
      await pumpDetail(
        tester,
        detail: WorkoutDetail(
          ride: rideWith(activityType: type),
          points: pointsWithHr(),
        ),
      );

      expect(find.text('海拔'), findsOneWidget, reason: type.dbValue);
      expect(find.text('功率'), findsNothing, reason: type.dbValue);
      expect(find.text('13'), findsOneWidget, reason: '最高海拔 13 m');
    }
  });

  testWidgets('配速类型详情：曲线叫配速，不出现踏频 / 功率区块', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(
        ride: rideWith(activityType: ActivityType.mountaineering),
        points: pointsWithHr(),
      ),
    );

    expect(find.byKey(const Key('detail-section-speed')), findsOneWidget);
    expect(find.text('配速'), findsNWidgets(2));
    expect(find.byKey(const Key('detail-section-cadence')), findsNothing);
    expect(find.byKey(const Key('detail-section-power')), findsNothing);
    expect(find.textContaining('下滑'), findsNothing);
  });

  testWidgets('详情不展示天气、地点与路线名', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(ride: rideWith(), points: pointsWithHr()),
    );

    for (final String word in <String>['天气', '晴', '成都', '龙泉', '桃花故里', '°C']) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
  });

  testWidgets('详情页提供返回与 GPX 导出入口', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      detail: WorkoutDetail(ride: rideWith(), points: pointsWithHr()),
    );

    expect(find.byKey(const Key('detail-back')), findsOneWidget);
    expect(find.byKey(const Key('gpx-export')), findsOneWidget);
    expect(find.text('导出 GPX'), findsOneWidget);
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

      final List<CurveSample> samples = buildCurve(
        points,
        metric: CurveMetric.speed,
      );

      expect(samples.map((CurveSample s) => s.segment).toList(), <int>[
        0,
        0,
        1,
        1,
      ]);
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

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 400, child: HrZoneBar(breakdown: breakdown)),
          ),
        ),
      );
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

    // 只钉宽度会漏掉上面那条同一处的缺陷：`ColoredBox` 没有子节点，`Row` 缺
    // `CrossAxisAlignment.stretch` 时每段在松高度约束下量成 0 高，整条退化成
    // 「一圈细线边框的空矩形」——真机上图例写着 Z1 41%/Z2 29%/Z3 30%，条上却
    // 一片空白（截图 y 1283–1324 内部全是底色 #0B0E12）。宽度断言照样全绿。
    testWidgets('每段高度撑满 14dp，不会退化成空矩形', (WidgetTester tester) async {
      const HrZoneBreakdown breakdown = HrZoneBreakdown(
        secondsByZone: <int, double>{1: 1.0, 3: 2.0},
        totalSeconds: 3.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 400, child: HrZoneBar(breakdown: breakdown)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder zones = find.descendant(
        of: find.byType(HrZoneBar),
        matching: find.byType(ColoredBox),
      );
      expect(zones, findsNWidgets(2));
      for (int i = 0; i < 2; i++) {
        expect(tester.getSize(zones.at(i)).height, 14);
      }
    });
  });
}
