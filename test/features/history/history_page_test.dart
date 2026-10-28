import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/app/theme.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/analysis/curve.dart';
import 'package:cycling_app/domain/models/activity_type.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/models/workout.dart';
import 'package:cycling_app/domain/models/workout_status.dart';
import 'package:cycling_app/domain/models/workout_summary.dart';
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

const WorkoutSummary _summary = WorkoutSummary(
  distanceM: 25300,
  durationS: 3600,
  movingS: 3400,
  avgSpeedMps: 7.03,
  movingAvgSpeedMps: 7.44,
  maxSpeedMps: 12.5,
  elevationGainM: 180,
  pointCount: 4,
);

Workout ride(
  int id, {
  String? title,
  int? startedAtMs,
  WorkoutSummary? summary,
  ActivityType activityType = ActivityType.cycling,
  String? placeName,
  String? placeShort,
  String? weatherText,
  int? weatherTempC,
}) => Workout(
  id: id,
  startedAtMs: startedAtMs ?? DateTime(2026, 9, 21, 8).millisecondsSinceEpoch,
  endedAtMs: DateTime(2026, 9, 21, 9).millisecondsSinceEpoch,
  status: WorkoutStatus.finished,
  title: title,
  activityType: activityType,
  summary: summary ?? _summary,
  placeName: placeName,
  placeShort: placeShort,
  weatherText: weatherText,
  weatherTempC: weatherTempC,
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
WorkoutDetail detailFor(int id) => WorkoutDetail(
  ride: Workout(
    id: id,
    startedAtMs: DateTime(2026, 9, 21, 8).millisecondsSinceEpoch,
    endedAtMs: DateTime(2026, 9, 21, 9).millisecondsSinceEpoch,
    status: WorkoutStatus.finished,
  ),
  points: const <TrackPoint>[],
);

Widget wrap({
  required List<Workout> rides,
  List<TrackPoint>? ridePoints,
  AppSettings settings = _settings,
  WorkoutDetail? detail,
}) => ProviderScope(
  overrides: <Override>[
    // 与真实 provider 同口径：筛选只过滤类型，null（全部）时原样返回。
    historyRidesProvider.overrideWith((Ref ref) {
      final ActivityType? filter = ref.watch(historyFilterProvider);
      return filter == null
          ? rides
          : rides.where((Workout r) => r.activityType == filter).toList();
    }),
    appSettingsProvider.overrideWithValue(
      AsyncValue<AppSettings>.data(settings),
    ),
    // id 为 null 的记录根本不会查询轨迹点（`_MiniCurve` 直接返回占位），
    // 这里也跳过，否则 `r.id!` 会在建 ProviderScope 时就抛。
    for (final Workout r in rides)
      if (r.id != null)
        ridePointsProvider(r.id!)
            .overrideWith((Ref ref) => ridePoints ?? const <TrackPoint>[]),
    if (detail != null)
      rideDetailProvider(detail.ride.id!).overrideWith((Ref ref) => detail),
  ],
  child: MaterialApp(theme: buildAppTheme(), home: const HistoryPage()),
);

/// 历史页是 `ListView.builder`，默认 800x600 的测试视口只懒构建前几屏，
/// 后面的卡片根本不会被 build。多卡片用例必须先把视口调高，否则断言会退化成
/// 「当前视口恰好构建了哪几张卡」。
Future<void> pumpHistory(
  WidgetTester tester, {
  required List<Workout> rides,
  List<TrackPoint>? ridePoints,
  AppSettings settings = _settings,
  WorkoutDetail? detail,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    wrap(
      rides: rides,
      ridePoints: ridePoints,
      settings: settings,
      detail: detail,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  Future<void> selectFilter(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(const Key('sport-filter-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('没有记录时显示空态提示', (WidgetTester tester) async {
    await pumpHistory(tester, rides: const <Workout>[]);

    expect(find.text('还没有运动记录'), findsOneWidget);
    expect(find.byType(WorkoutCard), findsNothing);
  });

  testWidgets('每条记录一张卡片，按传入顺序渲染', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Workout>[
        ride(
          2,
          title: '第二次',
          startedAtMs: DateTime(2026, 9, 22, 8).millisecondsSinceEpoch,
        ),
        ride(1, title: '第一次'),
      ],
      ridePoints: points(),
    );

    expect(find.byType(WorkoutCard), findsNWidgets(2));
    expect(find.text('第二次'), findsOneWidget);
    expect(find.text('第一次'), findsOneWidget);
  });

  testWidgets('卡片显示日期、距离、时长、均速与爬升', (WidgetTester tester) async {
    await pumpHistory(tester, rides: <Workout>[ride(1)], ridePoints: points());

    // 日期列：MM.DD + 星期；时间行写「出发」。
    expect(find.text('09.21'), findsOneWidget);
    expect(find.text('周一'), findsOneWidget);
    expect(find.text('08:00 出发'), findsOneWidget);
    // 距离拆成衬线大数字 + 小单位；移动均速 7.44 m/s → 26.8 km/h。
    expect(find.text('25.3'), findsOneWidget);
    expect(find.text('km'), findsOneWidget);
    expect(find.text('1:00:00'), findsOneWidget);
    expect(find.text('26.8 km/h'), findsOneWidget);
    expect(find.text('180 m'), findsOneWidget);
    expect(find.text('爬升'), findsOneWidget);
    // 这次骑行没有功率数据：列还在，值用破折号，不能摆 `0 W`。
    expect(find.text('功率'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('0 W'), findsNothing);
  });

  testWidgets('日期在固定列宽里保持单行，不折成两行', (WidgetTester tester) async {
    await pumpHistory(tester, rides: <Workout>[ride(1)], ridePoints: points());

    // 测试字体的数字比真实字体宽；没有 FittedBox 时「09.21」会被 52dp 的
    // 日期列折成多行。单行高度应远小于两行。
    final Rect dateRect = tester.getRect(find.text('09.21'));
    expect(dateRect.height, lessThan(30));
  });

  testWidgets('卡片出发时间后拼上记录捕获的具体地点', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Workout>[
        ride(1, placeName: '成都市 · 龙泉驿区 · 桃花故里', placeShort: '龙泉驿区'),
      ],
      ridePoints: points(),
    );

    expect(find.text('08:00 出发 · 桃花故里'), findsOneWidget);
  });

  testWidgets('只有区县的旧记录仍显示区县', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Workout>[ride(1, placeShort: '龙泉驿区')],
      ridePoints: points(),
    );

    expect(find.text('08:00 出发 · 龙泉驿区'), findsOneWidget);
  });

  testWidgets('没有地点数据的旧记录只显示出发时间', (WidgetTester tester) async {
    await pumpHistory(tester, rides: <Workout>[ride(1)], ridePoints: points());

    expect(find.text('08:00 出发'), findsOneWidget);
    expect(find.textContaining('出发 ·'), findsNothing);
  });

  testWidgets('类型筛选：选跑步只留跑步卡片，选全部恢复', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Workout>[
        ride(
          1,
          title: '晨骑',
          startedAtMs: DateTime(2026, 9, 21, 8).millisecondsSinceEpoch,
        ),
        ride(
          2,
          title: '夜跑',
          startedAtMs: DateTime(2026, 9, 22, 8).millisecondsSinceEpoch,
          activityType: ActivityType.running,
        ),
      ],
      ridePoints: points(),
    );

    expect(find.byType(WorkoutCard), findsNWidgets(2));

    await selectFilter(tester, 'sport-filter-running');

    expect(find.text('晨骑'), findsNothing);
    expect(find.text('夜跑'), findsOneWidget);
    expect(find.byType(WorkoutCard), findsOneWidget);

    await selectFilter(tester, 'sport-filter-all');

    expect(find.text('晨骑'), findsOneWidget);
    expect(find.text('夜跑'), findsOneWidget);
    expect(find.byType(WorkoutCard), findsNWidgets(2));
  });

  testWidgets('空态文案随筛选类型变化', (WidgetTester tester) async {
    await pumpHistory(tester, rides: const <Workout>[]);

    expect(find.text('还没有运动记录'), findsOneWidget);

    await selectFilter(tester, 'sport-filter-running');

    expect(find.text('还没有跑步记录'), findsOneWidget);
  });

  testWidgets('跑步卡片次级列显示配速而非 km/h', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Workout>[
        ride(
          1,
          activityType: ActivityType.running,
          summary: const WorkoutSummary(
            distanceM: 10000,
            durationS: 3600,
            movingS: 3400,
            avgSpeedMps: 3.0,
            movingAvgSpeedMps: 2.5,
            maxSpeedMps: 4.0,
            elevationGainM: 60,
            pointCount: 4,
          ),
        ),
      ],
      ridePoints: points(),
    );

    // 2.5 m/s → 1000/2.5 = 400 s/km → 6'40"。
    expect(find.text('配速'), findsOneWidget);
    expect(find.text('6\'40"'), findsOneWidget);
    expect(find.textContaining('km/h'), findsNothing);
  });

  testWidgets('配了功率计时卡片多一项功率读数', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Workout>[
        ride(
          1,
          summary: const WorkoutSummary(
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

    // 平均功率保留到瓦，135.4 → 135 W。单位 `W` 自明，不再加「功率」二字。
    expect(find.text('135 W'), findsOneWidget);
  });

  // 四条读数排成固定四列这件事，只钉文案是钉不住的：换成 `Wrap` 文案照样在，
  // 但列宽会随内容浮动、跨条目对不齐。这里直接量各列左边缘的距离。
  //
  // 第二条记录刻意没有功率：空格子若被抽掉，前三列会跟着变宽，第一条记录的
  // 均速与爬升就会和它对不上。
  testWidgets('四项读数按固定四列排开，跨条目对齐', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Workout>[
        ride(
          1,
          summary: const WorkoutSummary(
            distanceM: 25300,
            durationS: 3600,
            movingS: 3400,
            avgSpeedMps: 7.03,
            movingAvgSpeedMps: 7.44,
            maxSpeedMps: 12.5,
            elevationGainM: 180,
            pointCount: 4,
            avgPowerW: 135.4,
          ),
        ),
        ride(
          2,
          summary: const WorkoutSummary(
            distanceM: 10000,
            durationS: 1800,
            movingS: 1700,
            avgSpeedMps: 6.1,
            movingAvgSpeedMps: 6.0,
            maxSpeedMps: 11.0,
            elevationGainM: 60,
            pointCount: 4,
          ),
        ),
      ],
      ridePoints: points(),
    );

    // 四条标签各自出现两次，值按列对齐：同一列第二行的左边缘与第一行相同。
    for (final String label in <String>['时长', '均速', '爬升', '功率']) {
      expect(find.text(label), findsNWidgets(2), reason: label);
    }
    double left(String text) => tester.getTopLeft(find.text(text)).dx;
    expect(left('30:00'), closeTo(left('1:00:00'), 0.01));
    expect(left('21.6 km/h'), closeTo(left('26.8 km/h'), 0.01));
    expect(left('60 m'), closeTo(left('180 m'), 0.01));
    final Finder powerLabels = find.text('功率');
    expect(
      tester.getTopLeft(powerLabels.first).dx,
      closeTo(tester.getTopLeft(powerLabels.last).dx, 0.01),
    );
  });

  testWidgets('卡片里渲染迷你速度曲线', (WidgetTester tester) async {
    await pumpHistory(tester, rides: <Workout>[ride(1)], ridePoints: points());

    expect(find.byType(MiniSpeedCurve), findsOneWidget);
  });

  // 计划书原本这条用例与「卡片显示日期…」完全重复（同样的输入、同样的断言），
  // 区分力为零。改成同时钉住「有/无标题」两个渲染分支：
  // 无标题时只有一行日期；有标题时标题与日期各一行（日期不会重复出现）。
  testWidgets('无标题时用「{类型}记录」兜底，并保留日期列', (WidgetTester tester) async {
    await pumpHistory(tester, rides: <Workout>[ride(1)], ridePoints: points());

    expect(find.text('骑行记录'), findsOneWidget);
    expect(find.text('09.21'), findsOneWidget);
    expect(find.text('08:00 出发'), findsOneWidget);
    expect(find.text('2026-09-21 08:00'), findsNothing);
  });

  testWidgets('有标题时标题与日期列各自渲染', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Workout>[ride(1, title: '晨骑')],
      ridePoints: points(),
    );

    expect(find.text('晨骑'), findsOneWidget);
    expect(find.text('09.21'), findsOneWidget);
    expect(find.text('08:00 出发'), findsOneWidget);
    expect(find.text('骑行记录'), findsNothing);
  });

  testWidgets('英里单位下按英里显示距离', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Workout>[ride(1)],
      ridePoints: points(),
      settings: const AppSettings(
        maxHeartRate: 190,
        weightKg: 70,
        distanceUnit: DistanceUnit.mile,
        mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
      ),
    );

    expect(find.text('15.7'), findsOneWidget); // 25300 m
    expect(find.text('mi'), findsOneWidget);
  });

  testWidgets('页眉显示记录总数、最近月份与当月摘要', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Workout>[
        ride(
          1,
          title: '晨骑',
          startedAtMs: DateTime(2026, 10, 5, 8).millisecondsSinceEpoch,
        ),
      ],
      ridePoints: points(),
    );

    expect(find.text('运 动 日 志'), findsOneWidget);
    expect(find.text('二〇二六 · 十月'), findsOneWidget);
    expect(find.text('共 1 次'), findsOneWidget);
    // 25.3 km / 1 小时 0 分，按最近有记录的月份汇总。
    expect(find.textContaining('本月 1 次'), findsOneWidget);
    expect(find.textContaining('25.3 km'), findsOneWidget);
    expect(find.textContaining('1 小时 0 分'), findsOneWidget);
    expect(find.byKey(const Key('sport-filter-trigger')), findsOneWidget);
  });

  testWidgets('首屏只渲染最近月份，点「更早的记录」后展开', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Workout>[
        ride(
          1,
          title: '十月记录',
          startedAtMs: DateTime(2026, 10, 5, 8).millisecondsSinceEpoch,
        ),
        ride(
          2,
          title: '九月记录',
          startedAtMs: DateTime(2026, 9, 20, 8).millisecondsSinceEpoch,
        ),
      ],
      ridePoints: points(),
    );

    expect(find.text('十月记录'), findsOneWidget);
    expect(find.text('九月记录'), findsNothing);
    expect(find.byKey(const Key('history-older')), findsOneWidget);
    expect(find.textContaining('更早的记录 · 1 次'), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-older')));
    await tester.pumpAndSettle();

    expect(find.text('九月记录'), findsOneWidget);
    expect(find.text('二〇二六 · 九月'), findsOneWidget);
    expect(find.byKey(const Key('history-older')), findsNothing);
  });

  testWidgets('切换筛选后收起「更早的记录」', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Workout>[
        ride(
          1,
          title: '十月骑行',
          startedAtMs: DateTime(2026, 10, 5, 8).millisecondsSinceEpoch,
        ),
        ride(
          2,
          title: '九月跑步',
          startedAtMs: DateTime(2026, 9, 20, 8).millisecondsSinceEpoch,
          activityType: ActivityType.running,
        ),
      ],
      ridePoints: points(),
    );

    await tester.tap(find.byKey(const Key('history-older')));
    await tester.pumpAndSettle();
    expect(find.text('九月跑步'), findsOneWidget);

    await selectFilter(tester, 'sport-filter-running');
    expect(find.text('十月骑行'), findsNothing);
    expect(find.text('九月跑步'), findsOneWidget);
    // 只剩一个月份，更早入口不存在；再切回全部，展开状态已复位。
    await selectFilter(tester, 'sport-filter-all');
    expect(find.text('十月骑行'), findsOneWidget);
    expect(find.byKey(const Key('history-older')), findsOneWidget);
  });

  testWidgets('筛选空态提供「查看全部运动」', (WidgetTester tester) async {
    await pumpHistory(tester, rides: const <Workout>[]);

    await selectFilter(tester, 'sport-filter-running');
    expect(find.text('还没有跑步记录'), findsOneWidget);
    expect(find.byKey(const Key('history-show-all')), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-show-all')));
    await tester.pumpAndSettle();
    expect(find.text('还没有运动记录'), findsOneWidget);
    expect(find.byKey(const Key('history-show-all')), findsNothing);
  });

  testWidgets('点卡片进入详情页', (WidgetTester tester) async {
    // 必须一并 override `rideDetailProvider`：否则详情页会去读
    // `rideRepositoryProvider` → `databaseProvider`，测试里没有数据库而抛异常。
    await pumpHistory(
      tester,
      rides: <Workout>[ride(1)],
      ridePoints: points(),
      detail: detailFor(1),
    );

    await tester.tap(find.byType(WorkoutCard).first);
    await tester.pumpAndSettle();

    expect(find.byType(DetailPage), findsOneWidget);
    expect(find.text('骑行详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有汇总指标的记录不崩溃，卡片显示占位', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Workout>[
        const Workout(id: 1, startedAtMs: 1000, status: WorkoutStatus.finished),
      ],
    );

    expect(find.byType(WorkoutCard), findsOneWidget);
    expect(find.text('这条记录还没有汇总指标'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 计划书变异表第 5 条（去掉 `_MiniCurve` 里的 id 判空）原本杀不死：
  // 上面那条记录 id 是 1，走的是非空分支。这条用例用 id == null 的记录钉住
  // 「没有 id 就不该去查询轨迹点」。
  testWidgets('没有 id 的记录不查询轨迹点也不崩溃', (WidgetTester tester) async {
    await pumpHistory(
      tester,
      rides: <Workout>[
        const Workout(startedAtMs: 1000, status: WorkoutStatus.finished),
      ],
    );

    expect(find.byType(WorkoutCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // `CustomPaint` 没有可断言的语义节点，`find.byType(MiniSpeedCurve)` 对画笔逻辑
  // 毫无区分力（把 paint 掏空照样通过）。这里直接断言画笔的连线判定纯函数。
  group('迷你曲线的连线判定', () {
    test('样本不足 2 个时不画任何线段', () {
      expect(drawnMiniCurveSegments(const <CurveSample>[]), isEmpty);
      expect(
        drawnMiniCurveSegments(const <CurveSample>[
          CurveSample(xSeconds: 0, y: 5, segment: 0),
        ]),
        isEmpty,
      );
    });

    test('正常输入时线段数等于样本数减一', () {
      final List<CurveSample> samples = buildCurve(
        points(),
        metric: CurveMetric.speed,
      );

      expect(samples.length, 4);
      expect(drawnMiniCurveSegments(samples), <(int, int)>[
        (0, 1),
        (1, 2),
        (2, 3),
      ]);
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
