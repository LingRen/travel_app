import 'dart:async';

import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/app/theme.dart';
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
import 'package:cycling_app/domain/recording/ride_cue.dart';
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
  // 一次进行中的记录：6 m/s = 21.6 km/h，1.234 km，90 秒，心率 132，踏频 85，
  // 功率 210，海拔 128 米，累计爬升 342 米。
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
    currentAltitudeM: 128.0,
    elevationGainM: 342.0,
  );

  /// 状态栏高度（dp）。真机 1080×1920 / 密度 480 上实测 54px。
  const double statusBarHeight = 18;

  /// 底部 `NavigationBar` 高度（dp），见 `theme.dart` 的 `navigationBarTheme`。
  const double navBarHeight = 64;

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  /// 真机几何：360×640dp 的屏幕上，状态栏占 18dp、底部 `NavigationBar` 占 64dp，
  /// 骑行界面拿到的正文区因此只有 558dp。
  ///
  /// 量「中间留了多少地图」必须用这个盒子而不是裸的 640dp：少了这两条，正文区凭空
  /// 多出 82dp，量出来的余量会比真机宽出一大截，阈值也就守不住真机。
  Widget wrapDevice(Widget child) => MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              padding: EdgeInsets.only(top: statusBarHeight),
            ),
            child: child,
          ),
          bottomNavigationBar: const SizedBox(height: navBarHeight),
        ),
      );

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

    testWidgets('记录中底部按频率分宽：「结束」1/3，「暂停 / 继续」2/3',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(handlebar(active)));

      // 骑行中真正频繁按的是暂停（红灯、休息），它拿走 2/3 宽并落在右下拇指
      // 区；一次骑行只按一次的「结束」只占 1/3，被推到左侧并隔开一个 kSpaceL。
      expect(find.text('进行中'), findsOneWidget);
      expect(find.text('结束'), findsOneWidget);
      expect(find.text('暂停'), findsOneWidget);
      expect(find.text('继续'), findsNothing);

      final Finder finish = find.widgetWithText(OutlinedButton, '结束');
      final Finder toggle = find.widgetWithText(FilledButton, '暂停');
      final Size finishSize = tester.getSize(finish);
      final Size toggleSize = tester.getSize(toggle);

      expect(
        toggleSize.width / finishSize.width,
        closeTo(HandlebarView.toggleFlex / HandlebarView.finishFlex, 0.05),
      );
      // 两颗键同高同底：拇指在同一个高度带里找键，不必分辨上下。
      expect(finishSize.height, closeTo(HandlebarView.buttonHeight, 0.01));
      expect(toggleSize.height, closeTo(HandlebarView.buttonHeight, 0.01));
      expect(
        tester.getBottomLeft(toggle).dx - tester.getBottomRight(finish).dx,
        closeTo(kSpaceL, 0.01),
        reason: '主动作与「结束」之间要有实体间隔，阻止连击误触',
      );
      expect(tester.getCenter(finish).dx, lessThan(tester.getCenter(toggle).dx),
          reason: '右下角留给主动作，破坏性的「结束」推到左侧');
    });

    testWidgets('暂停 / 继续 落在底部动作区，状态条只剩状态与传感器灯',
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

      // 这条量的是「够得着」：暂停曾经是状态条上那颗 40dp 小键，既在屏幕最难
      // 够到的顶部，又紧挨三盏配对入口的灯（误触会弹出模态选设备面板）。现在
      // 它必须落在页面下部的动作区里。
      final double pageHeight = tester.getSize(find.byType(HandlebarView)).height;
      final Rect toggle = tester.getRect(find.widgetWithText(FilledButton, '暂停'));
      expect(toggle.center.dy, greaterThan(pageHeight * 0.6));

      await tester.tap(find.text('暂停'));
      expect(pauses, 1);

      await tester.tap(find.text('结束'));
      expect(finishes, 1);
      expect(resumes, 0);

      // 暂停后同一颗键换成「继续」：它就在拇指刚才落下的位置，不必重新找。
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
      expect(find.text('结束'), findsOneWidget);

      await tester.tap(find.text('继续'));
      expect(resumes, 1);
    });

    testWidgets('整页铺满地图后，360×640 的机器上不溢出', (WidgetTester tester) async {
      // 真机是 1080×1920 / 密度 480，即 360×640dp。地图从一条 120dp 的缩略图
      // 变成整页底，读数与按钮压在上面。溢出在测试里会直接抛 FlutterError，
      // pumpWidget 就会失败。
      //
      // 用真机几何（正文区只有 558dp）而不是裸的 640dp：溢出是高度不够才会发生的
      // 事，给多了反而测不出窄屏上的问题。
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrapDevice(handlebar(active)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      // 主指标被 FittedBox 兜底，但那是给极端窄高比留的：正常尺寸下不该触发，
      // 字号必须还是 120。真缩了说明这一页已经挤到没法扫读了。
      final Text speed =
          tester.widget<Text>(find.byKey(const Key('handlebar-speed')));
      expect(speed.style!.fontSize, HandlebarView.primaryFontSize);
    });

    testWidgets('地图铺满整页，读数浮在它上面', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrapDevice(handlebar(active)));
      await tester.pump();

      // 「全屏」是可断言的：地图容器与整页同尺寸，而不是某一条高度。
      final Size page = tester.getSize(find.byType(HandlebarView));
      final Size map = tester.getSize(find.byKey(const Key('live-route-map')));
      expect(map, page);

      // 浮层在竖直方向上落在地图范围内：上块贴顶、下块贴底，中间那块空出来。
      final Rect top = tester.getRect(find.text('距离'));
      final Rect bottom = tester.getRect(find.widgetWithText(FilledButton, '暂停'));
      expect(top.top, lessThan(page.height * 0.35));
      expect(bottom.bottom, greaterThan(page.height * 0.8));

      // 中间那条**完全没有读数压着的**地图带有多高：上块的下沿（顶部四格里最低
      // 的那个值，即「爬升」的数值）到下块的上沿（速度大数字）。
      //
      // 阈值取 200（实测 221.9）。这条是**兜底**，不是主判据：真正把地图还回来的是
      // 「读数不再压在不透明底色上」（见下一条用例）。面板的 12dp 内边距去掉后这条
      // 带子只长高了 24dp，真正让人能看路的，是原来被面板盖住的那一大片现在透出来了。
      // 所以阈值定得松一些——它只负责在有人把上下两块堆到一起时报警。
      final double band =
          tester.getRect(find.byKey(const Key('handlebar-speed'))).top -
              tester.getRect(find.text('342 m')).bottom;
      expect(band, greaterThan(200),
          reason: '上下两块之间要留出能看路的地图带，实测 ${band.toStringAsFixed(1)}dp');
    });

    testWidgets('读数下面没有底色块，整页地图是露出来的', (WidgetTester tester) async {
      // 浮层曾经是 0.86 不透明的实体面板，真机上把整页地图上下各切掉一大块，
      // 「全屏地图」名存实亡。这条用例守的就是那件事：从每个读数往上找，一路
      // 都不该碰到铺了不透明底色的容器——对比度只能来自文字自带的投影。
      //
      // 断言放在「祖先链上有没有不透明底色」而不是量高度：遮挡感来自底色块，
      // 不是来自块的高度。读数之间空出来的地图本来就是能看见的。
      await tester.pumpWidget(wrap(handlebar(active)));

      // 名字单独给：`Finder.description` 已废弃，用 (名字, Finder) 成对写更直接。
      for (final (String name, Finder probe) in <(String, Finder)>[
        ('距离', find.text('距离')),
        ('爬升', find.text('爬升')),
        ('心率', find.text('心率')),
        ('主速度', find.byKey(const Key('handlebar-speed'))),
      ]) {
        final List<Type> opaque = <Type>[];
        tester.element(probe).visitAncestorElements((Element element) {
          final Widget widget = element.widget;
          // 两种都要认：`Container(color:)` 内部建的是 [ColoredBox]，
          // `Container(decoration:)` 建的才是 [DecoratedBox]。只认后者会漏掉最
          // 常见的那种写法——变异自证时正是这里漏掉了回归。
          final Color? fill = switch (widget) {
            ColoredBox(:final Color color) => color,
            DecoratedBox(:final Decoration decoration) =>
              decoration is BoxDecoration ? decoration.color : null,
            _ => null,
          };
          if (fill != null && fill.a > 0.5) opaque.add(widget.runtimeType);
          return true;
        });
        expect(opaque, isEmpty, reason: '「$name」压在不透明底色上，地图被它挡住了');
      }
    });

    testWidgets('每一项读数都在：距离 / 时长 / 海拔 / 爬升 / 心率 / 踏频 / 功率',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(handlebar(active)));

      expect(find.text('距离'), findsOneWidget);
      expect(find.text('1.23 km'), findsOneWidget);
      expect(find.text('时长'), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);
      expect(find.text('海拔'), findsOneWidget);
      expect(find.text('128 m'), findsOneWidget);
      expect(find.text('爬升'), findsOneWidget);
      expect(find.text('342 m'), findsOneWidget);
    });

    testWidgets('设备不给高程时海拔是「--」，爬升仍是具体读数',
        (WidgetTester tester) async {
      // 0 米海拔是一个具体读数，会和「没有数据」混起来；爬升则永远有值
      // （平路就是 0 米），所以两者不用同一种占位策略。
      await tester.pumpWidget(wrap(handlebar(const RecordState(
        rideId: 1,
        phase: RecordingPhase.recording,
        elapsedMs: 1000,
        distanceM: 1234.0,
        hrConnected: true,
        cadenceConnected: true,
        powerConnected: true,
      ))));

      expect(find.text('1.23 km'), findsOneWidget);
      expect(find.text('0 m'), findsOneWidget, reason: '爬升平路就是 0 米');
      // 海拔加上三格传感器（有连接但还没读数）一共四个「--」。
      expect(find.text('--'), findsNWidgets(4));
    });

    testWidgets('来提示时横幅浮在地图可见带里，不挤压上下两块', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(handlebar(active)));
      final Rect before = tester.getRect(find.text('距离'));

      await tester.pumpWidget(wrap(handlebar(const RecordState(
        rideId: 1,
        phase: RecordingPhase.recording,
        elapsedMs: 90000,
        distanceM: 1234.0,
        currentSpeedMps: 6.0,
        lastCue: LapCue(lapKm: 3, durationS: 167, avgSpeedMps: 5.98),
        cueSeq: 1,
      ))));
      await tester.pump();

      // 第 3 公里：均速 21.5 km/h（5.98 m/s 换算），耗时 02:47。
      expect(find.text('第 3 公里 · 均速 21.5 km/h · 耗时 02:47'), findsOneWidget);
      // 横幅是浮层：它的出现不能让上半块挪位置，否则每闪一次整页都在跳。
      expect(tester.getRect(find.text('距离')), before);

      // 到点自己收回，不需要用户操作（它是事件通知，不是常驻读数）。
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('第 3 公里 · 均速 21.5 km/h · 耗时 02:47'), findsNothing);
    });

    testWidgets('每秒的界面刷新不会把横幅的倒计时清零', (WidgetTester tester) async {
      RecordState withCue(int seq) => RecordState(
            rideId: 1,
            phase: RecordingPhase.recording,
            elapsedMs: 90000,
            distanceM: 1234.0,
            currentSpeedMps: 6.0,
            lastCue: const DistanceCue(10),
            cueSeq: seq,
          );

      await tester.pumpWidget(wrap(handlebar(withCue(1))));
      await tester.pump(const Duration(seconds: 3));
      // 同一条提示（seq 不变）继续重建：还剩 2 秒，不能重新计时。
      await tester.pumpWidget(wrap(handlebar(withCue(1))));
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('已骑行 10 公里'), findsNothing, reason: '总时长 6 秒已超过 5 秒');
    });

    testWidgets('新提示重置计时，同一句也会重新展示', (WidgetTester tester) async {
      RecordState withCue(int seq) => RecordState(
            rideId: 1,
            phase: RecordingPhase.recording,
            elapsedMs: 90000,
            distanceM: 1234.0,
            currentSpeedMps: 6.0,
            lastCue: const DistanceCue(10),
            cueSeq: seq,
          );

      await tester.pumpWidget(wrap(handlebar(withCue(1))));
      await tester.pump(const Duration(seconds: 3));
      // seq 变了＝来了一条新提示。两次「已骑行 10 公里」对象相等，只看 cue
      // 是分不出新旧来的。
      await tester.pumpWidget(wrap(handlebar(withCue(2))));

      expect(find.text('已骑行 10 公里'), findsOneWidget);
    });

    testWidgets('未开始态再挤进一条阻断类错误，360×640 上仍不溢出',
        (WidgetTester tester) async {
      // 畸形的最紧一屏：未开始（主按钮 + 状态条）+ 上下两块浮层 + 三传感器
      // 指标格，外加一条定位于「开始」失败的提示。这一条量的是上下两块浮层
      // 之外的余量：多出来的高度从中间那条看路窗口里扣，而不是让整页溢出。
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
      // 心率、踏频、功率三格没数据，加上没高程数据的海拔，一共四个占位符。
      expect(find.text('--'), findsNWidgets(4));
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

    testWidgets('没有定位点时地图整页占位，不渲染地图', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(handlebar(active)));

      expect(find.byKey(const Key('live-route-map')), findsOneWidget);
      expect(find.text('等待定位…'), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
    });

    testWidgets('有定位点时地图真的把轨迹画出来', (WidgetTester tester) async {
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

    testWidgets('点「开始」后底部换成两键动作区，状态转进行中',
        (WidgetTester tester) async {
      await pumpRecordPage(tester);

      await tester.tap(find.text('开始'));
      await tester.pump();
      await tester.pump();

      // 未开始只有一件事可做，那颗「开始」整宽独占；进入记录后底部换成按频率
      // 分宽的两键（设计文档 10.1），主动作是那颗 2/3 宽的「暂停」。
      expect(find.text('进行中'), findsOneWidget);
      expect(find.text('结束'), findsOneWidget);
      expect(find.text('暂停'), findsOneWidget);
      expect(find.text('开始'), findsNothing);
      expect(
        tester.getSize(find.widgetWithText(FilledButton, '暂停')).width,
        greaterThan(tester.getSize(find.widgetWithText(OutlinedButton, '结束')).width),
      );
      expect(find.byKey(const Key('handlebar-speed')), findsOneWidget);
      expect(find.byKey(const Key('live-route-map')), findsOneWidget);
    });
  });
}
