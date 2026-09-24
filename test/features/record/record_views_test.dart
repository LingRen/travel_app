import 'dart:async';

import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/ble/sensor_monitor.dart';
import 'package:cycling_app/data/location/location_service.dart';
import 'package:cycling_app/data/ride_repository.dart';
import 'package:cycling_app/data/sensor_pairing.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/models/location_fix.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/recording/recording_session.dart';
import 'package:cycling_app/features/record/handlebar_view.dart';
import 'package:cycling_app/features/record/record_controller.dart';
import 'package:cycling_app/features/record/record_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override 在 riverpod 3 里只从 misc 入口导出。
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

const RideSummary _emptySummary = RideSummary(
  distanceM: 0,
  durationS: 0,
  movingS: 0,
  avgSpeedMps: 0,
  movingAvgSpeedMps: 0,
  elevationGainM: 0,
  pointCount: 0,
);

/// 内存版仓储：记录页测试只关心界面，不关心落盘。
class _FakeRideRepository implements RideRepository {
  int startRideCalls = 0;

  @override
  Future<Ride> startRide({
    required int startedAtMs,
    String? hrDeviceName,
    String? cadenceDeviceName,
    String? powerDeviceName,
  }) async {
    startRideCalls++;
    return Ride(id: 1, startedAtMs: startedAtMs, status: RideStatus.recording);
  }

  @override
  Future<void> appendPoints(int rideId, List<TrackPoint> points) async {}

  @override
  Future<void> setStatus(int rideId, RideStatus status) async {}

  @override
  Future<RideSummary> finishRide(
    int rideId, {
    required int endedAtMs,
    required int durationS,
  }) async =>
      _emptySummary;

  @override
  Future<RideSummary> settleRide(int rideId) async => _emptySummary;

  @override
  Future<List<Ride>> findUnfinished() async => <Ride>[];

  @override
  Future<List<Ride>> listFinished({int? limit, int? offset}) async => <Ride>[];

  @override
  Future<Ride?> getRide(int id) async => null;

  @override
  Future<List<TrackPoint>> getPoints(int rideId) async => <TrackPoint>[];

  @override
  Future<TrackPoint?> lastPoint(int rideId) async => null;

  @override
  Future<void> updateTitle(int rideId, String? title) async {}

  @override
  Future<void> deleteRide(int rideId) async {}

  @override
  void Function()? get onRideDataChanged => null;
}

/// 假的定位服务：readiness 由用例设置，不产生任何定位点。
class _FakeLocationService implements LocationService {
  final StreamController<LocationFix> _fixes =
      StreamController<LocationFix>.broadcast();

  LocationReadiness readiness = LocationReadiness.ready;

  @override
  Future<LocationReadiness> checkReadiness() async => readiness;

  @override
  Stream<LocationFix> fixes() => _fixes.stream;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

/// 内存版配对仓储：记录页测试不关心传感器配对，等价于「从没配对过」。
class _FakeSensorPairing implements SensorPairingRepository {
  @override
  Future<PairedSensor?> load(SensorKind kind) async => null;

  @override
  Future<void> save(SensorKind kind, PairedSensor sensor) async {}

  @override
  Future<void> clear(SensorKind kind) async {}
}

const AppSettings _testSettings = AppSettings(
  maxHeartRate: kDefaultMaxHeartRate,
  weightKg: kDefaultWeightKg,
  distanceUnit: DistanceUnit.kilometer,
  mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
);

void main() {
  // 一次进行中的记录：6 m/s = 21.6 km/h，1.234 km，90 秒，心率 132，踏频 85，功率 210。
  const RecordState active = RecordState(
    rideId: 1,
    phase: RecordingPhase.recording,
    elapsedMs: 90000,
    distanceM: 1234.0,
    currentSpeedMps: 6.0,
    hr: 132,
    cadence: 85,
    power: 210,
    hrConnected: true,
    cadenceConnected: true,
    powerConnected: true,
  );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Widget handlebar(
    RecordState state, {
    void Function(SensorKind)? onPickDevice,
    VoidCallback? onStart,
    VoidCallback? onPause,
    VoidCallback? onResume,
    VoidCallback? onFinish,
  }) =>
      HandlebarView(
        state: state,
        unit: DistanceUnit.kilometer,
        tileUrlTemplate: kDefaultMapTileUrlTemplate,
        onStart: onStart ?? () {},
        onPause: onPause ?? () {},
        onResume: onResume ?? () {},
        onFinish: onFinish ?? () {},
        onPickDevice: onPickDevice ?? (_) {},
      );

  group('骑行界面', () {
    testWidgets('未开始时底部是「开始」，没有暂停 / 结束', (WidgetTester tester) async {
      int starts = 0;
      await tester.pumpWidget(wrap(handlebar(
        const RecordState(),
        onStart: () => starts++,
      )));

      // 记录 tab 落地就是这一页（设计文档 10.1），未开始态即入口态：
      // 状态条写「未开始」，主按钮是「开始」，暂停键不出现（没东西可暂停）。
      expect(find.text('未开始'), findsOneWidget);
      expect(find.text('开始'), findsOneWidget);
      expect(find.text('暂停'), findsNothing);
      expect(find.text('继续'), findsNothing);
      expect(find.text('结束'), findsNothing);

      await tester.tap(find.text('开始'));
      expect(starts, 1);
    });

    testWidgets('记录中主按钮是「结束」，暂停与继续是状态条上那颗小键',
        (WidgetTester tester) async {
      int pauses = 0;
      int resumes = 0;
      int finishes = 0;
      await tester.pumpWidget(wrap(handlebar(
        active,
        onPause: () => pauses++,
        onResume: () => resumes++,
        onFinish: () => finishes++,
      )));

      // 主按钮只剩「结束」：屏幕上不该再出现第二个「结束」，否则骑行中要
      // 分辨两颗几乎是同一个动作的键。
      expect(find.text('进行中'), findsOneWidget);
      expect(find.text('结束'), findsOneWidget);
      expect(find.text('暂停'), findsOneWidget);
      expect(find.text('继续'), findsNothing);

      await tester.tap(find.text('暂停'));
      expect(pauses, 1);

      await tester.tap(find.text('结束'));
      expect(finishes, 1);
      expect(resumes, 0);

      await tester.pumpWidget(wrap(handlebar(
        const RecordState(
          rideId: 1,
          phase: RecordingPhase.paused,
          elapsedMs: 1000,
        ),
        onResume: () => resumes++,
      )));

      expect(find.text('已暂停'), findsOneWidget);
      expect(find.text('继续'), findsOneWidget);
      expect(find.text('暂停'), findsNothing);

      await tester.tap(find.text('继续'));
      expect(resumes, 1);
    });

    testWidgets('并入缩略图后，360×640 的机器上不溢出', (WidgetTester tester) async {
      // 真机是 1080×1920 / 密度 480，即 360×640dp。加缩略图要占 121dp，
      // 靠让渡别处的间距才装得下——所以这条用例量的是余量，不是能不能跑。
      // 溢出在测试里会直接抛 FlutterError，pumpWidget 就会失败。
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(handlebar(active)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      // 主指标被 FittedBox 兜底，但那是给极端窄高比留的：正常尺寸下不该触发，
      // 字号必须还是 120。真缩了说明这一页已经挤到没法扫读了。
      final Text speed =
          tester.widget<Text>(find.byKey(const Key('handlebar-speed')));
      expect(speed.style!.fontSize, HandlebarView.primaryFontSize);
    });

    testWidgets('未开始态再挤进一条阻断类错误，360×640 上仍不溢出',
        (WidgetTester tester) async {
      // 畸形的最紧一屏：未开始（主按钮 + 状态条）+ 缩略图 + 三传感器指标格，
      // 外加一条定位于「开始」失败的提示。这一条量的是主数字外面那层
      // Flexible + FittedBox：多余的高度从它身上扣，而不是让整页溢出。
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(handlebar(const RecordState(
        errorMessage: '定位权限已被永久拒绝，请到系统设置中开启',
      ))));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('定位权限已被永久拒绝，请到系统设置中开启'), findsOneWidget);
      expect(find.text('开始'), findsOneWidget);
    });

    testWidgets('主指标字号不小于 72 且各项指标齐全', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(handlebar(active)));

      final Text speed =
          tester.widget<Text>(find.byKey(const Key('handlebar-speed')));
      expect(speed.style!.fontSize!, greaterThanOrEqualTo(72));
      expect(find.text('21.6'), findsOneWidget);
      expect(find.text('km/h'), findsOneWidget);
      expect(find.text('1.23 km'), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);
      expect(find.text('132'), findsOneWidget);
      expect(find.text('85'), findsOneWidget);
      expect(find.text('功率'), findsOneWidget);
      expect(find.text('210'), findsOneWidget);
    });

    testWidgets('没连功率计时显示占位，标签写明是估算值', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(handlebar(const RecordState(
        rideId: 1,
        phase: RecordingPhase.recording,
        elapsedMs: 1000,
      ))));

      // 这一格的值是 app 按速度、坡度、体重估出来的，标签必须说清楚，
      // 否则会被当成功率计的读数。
      expect(find.text('功率（估算）'), findsOneWidget);
      expect(find.text('功率'), findsNothing);
      // 距离、时长、心率、踏频、功率五项都没数据，全是占位符。
      expect(find.text('--'), findsNWidgets(3));
      expect(find.text('0'), findsNothing);
    });

    testWidgets('骑行中点传感器灯就是配对入口', (WidgetTester tester) async {
      final List<SensorKind> picked = <SensorKind>[];
      await tester.pumpWidget(wrap(handlebar(active, onPickDevice: picked.add)));

      await tester.tap(find.byTooltip('心率已连接，点击更换设备'));
      await tester.tap(find.byTooltip('踏频已连接，点击更换设备'));
      await tester.tap(find.byTooltip('功率计已连接，点击更换设备'));

      expect(picked, <SensorKind>[
        SensorKind.heartRate,
        SensorKind.cadence,
        SensorKind.power,
      ]);
    });

    testWidgets('未连接的传感器灯提示的是「点击连接」', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(handlebar(const RecordState(
        rideId: 1,
        phase: RecordingPhase.recording,
        elapsedMs: 1000,
      ))));

      expect(find.byTooltip('点击连接心率设备'), findsOneWidget);
      expect(find.byTooltip('点击连接踏频设备'), findsOneWidget);
      expect(find.byTooltip('点击连接功率计'), findsOneWidget);
    });

    testWidgets('未连接时点指标格就是配对入口', (WidgetTester tester) async {
      final List<SensorKind> picked = <SensorKind>[];
      await tester.pumpWidget(wrap(handlebar(const RecordState(
        rideId: 1,
        phase: RecordingPhase.recording,
        elapsedMs: 1000,
      ), onPickDevice: picked.add)));

      // 骑行中看到「--」最直接的动作就是点那一格；文案与顶部传感器灯区分开，
      // 否则两边都会命中同一个 tooltip。
      await tester.tap(find.byTooltip('心率未连接，点击连接'));
      await tester.tap(find.byTooltip('踏频未连接，点击连接'));
      await tester.tap(find.byTooltip('功率计未连接，点击连接'));

      expect(picked, <SensorKind>[
        SensorKind.heartRate,
        SensorKind.cadence,
        SensorKind.power,
      ]);
    });

    testWidgets('已连接的指标格不给点击入口，避免误触弹选设备面板', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(handlebar(active)));

      // 三格都是有效读数：不该再挂「+」，也不该有「点击连接」的提示。
      // 入口只由 onTap 决定（_MetricCell 里 Tooltip 与 InkWell 同时挂）
      // ，所以这两样不在就等于不可点——直接 tap 反而证不了：没有 InkWell
      // 的格子点下去什么也不会发生，两种实现都会「通过」。
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      expect(find.byTooltip('心率未连接，点击连接'), findsNothing);
      expect(find.byTooltip('踏频未连接，点击连接'), findsNothing);
      expect(find.byTooltip('功率计未连接，点击连接'), findsNothing);
    });

    testWidgets('没有定位点时缩略图占位，不渲染地图', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(handlebar(active)));

      expect(find.byKey(const Key('live-route-map')), findsOneWidget);
      expect(find.text('等待定位…'), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
    });

    testWidgets('有定位点时缩略图真的把轨迹画出来', (WidgetTester tester) async {
      // 两点之间要够远，才不会被抽稀规则丢掉（见 kLiveTrackMinDistanceM）。
      final List<TrackPoint> track = <TrackPoint>[
        const TrackPoint(rideId: 1, tMs: 1000, lat: 30.0, lon: 120.0),
        const TrackPoint(rideId: 1, tMs: 2000, lat: 30.001, lon: 120.001),
        const TrackPoint(rideId: 1, tMs: 3000, lat: 30.002, lon: 120.002),
      ];
      await tester.pumpWidget(wrap(handlebar(RecordState(
        rideId: 1,
        phase: RecordingPhase.recording,
        elapsedMs: 3000,
        liveTrack: track,
      ))));

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('等待定位…'), findsNothing);
    });
  });

  group('速度刻度尺', () {
    // 刻度尺是自绘的 `CustomPaint`，没有语义节点也拿不到画出来的像素，
    // 所以把「当前速度换算成多少格」抽成纯函数再断言——这是项目里自绘画笔
    // 的惯例（另有 `drawnMiniCurveSegments` / `drawnCurveSegments`）。
    test('按满量程换算成 0..1 的填充比例', () {
      expect(speedScaleFraction(0, maxMps: 12), 0);
      expect(speedScaleFraction(6, maxMps: 12), 0.5);
      expect(speedScaleFraction(12, maxMps: 12), 1);
    });

    test('超出量程被截到满格，不会画到轨道外', () {
      expect(speedScaleFraction(30, maxMps: 12), 1);
    });

    // 对照组：不做钳制的话超速会得到 2.5，轨道外的填充会溢出到刻度尺外面。
    test('对照组：不钳制时超速的比例会大于 1', () {
      expect(30 / 12, greaterThan(1));
    });

    test('量程为 0 或负数时返回 0，不做除零', () {
      expect(speedScaleFraction(6, maxMps: 0), 0);
      expect(speedScaleFraction(6, maxMps: -1), 0);
    });

    test('默认量程等于数据色带的满速，满速时刚好满格', () {
      expect(speedScaleFraction(kColorScaleMaxSpeedMps), 1);
    });
  });

  group('记录页', () {
    late _FakeRideRepository repo;
    late _FakeLocationService location;

    setUp(() {
      repo = _FakeRideRepository();
      location = _FakeLocationService();
    });

    Future<void> pumpRecordPage(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          appSettingsProvider.overrideWithValue(
            const AsyncValue<AppSettings>.data(_testSettings),
          ),
          rideRepositoryProvider.overrideWithValue(repo),
          locationServiceProvider.overrideWithValue(location),
          nowProvider.overrideWithValue(() => 1000),
          sensorPairingProvider.overrideWithValue(_FakeSensorPairing()),
        ],
        child: const MaterialApp(home: RecordPage()),
      ));
      await tester.pump();
    }

    testWidgets('落地就是骑行界面，底部是「开始」而不是跳转前的准备页',
        (WidgetTester tester) async {
      await pumpRecordPage(tester);

      // 原来的准备页已经并进这一屏（设计文档 10.1）：进来就能看到读数区、
      // 缩略图与传感器灯，只是还没开始。
      expect(find.text('未开始'), findsOneWidget);
      expect(find.text('开始'), findsOneWidget);
      expect(find.byKey(const Key('handlebar-speed')), findsOneWidget);
      expect(find.byKey(const Key('live-route-map')), findsOneWidget);
      expect(find.text('准备骑行'), findsNothing);
      expect(find.text('开始骑行'), findsNothing);
      expect(find.text('骑行方式'), findsNothing);
      expect(find.text('暂停'), findsNothing);
      expect(find.text('结束'), findsNothing);
    });

    testWidgets('定位权限被拒时把阻断类错误显示在界面上', (WidgetTester tester) async {
      location.readiness = LocationReadiness.permissionDenied;
      await pumpRecordPage(tester);

      await tester.tap(find.text('开始'));
      await tester.pump();

      expect(find.text('未获得定位权限，无法记录骑行'), findsOneWidget);
      expect(repo.startRideCalls, 0, reason: '阻断类错误下不能创建骑行记录');
      expect(find.text('开始'), findsOneWidget, reason: '仍停在未开始状态');
      // 失败时不该顺手把用户推进记录中：状态条与主按钮都得留在未开始态。
      expect(find.text('未开始'), findsOneWidget);
      expect(find.text('结束'), findsNothing);
    });

    testWidgets('点「开始」后同一颗键变成「结束」，状态转进行中',
        (WidgetTester tester) async {
      await pumpRecordPage(tester);

      await tester.tap(find.text('开始'));
      await tester.pump();
      await tester.pump();

      expect(find.text('进行中'), findsOneWidget);
      expect(find.text('结束'), findsOneWidget);
      expect(find.text('开始'), findsNothing);
      expect(find.text('暂停'), findsOneWidget);
      expect(find.byKey(const Key('handlebar-speed')), findsOneWidget);
      expect(find.byKey(const Key('live-route-map')), findsOneWidget);
    });
  });
}
