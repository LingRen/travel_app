import 'dart:async';

import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/ble/sensor_monitor.dart';
import 'package:cycling_app/data/location/location_service.dart';
import 'package:cycling_app/data/ride_repository.dart';
import 'package:cycling_app/data/sensor_pairing.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/models/location_fix.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/recording/recording_session.dart';
import 'package:cycling_app/features/record/handlebar_view.dart';
import 'package:cycling_app/features/record/pocket_view.dart';
import 'package:cycling_app/features/record/record_controller.dart';
import 'package:cycling_app/features/record/record_page.dart';
import 'package:flutter/material.dart';
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
  // 一次进行中的记录：6 m/s = 21.6 km/h，1.234 km，90 秒，心率 132，踏频 85。
  const RecordState active = RecordState(
    rideId: 1,
    phase: RecordingPhase.recording,
    elapsedMs: 90000,
    distanceM: 1234.0,
    currentSpeedMps: 6.0,
    hr: 132,
    cadence: 85,
    hrConnected: true,
    cadenceConnected: true,
  );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('车把模式与口袋模式', () {
    testWidgets('车把模式主指标字号不小于 72 且五项指标齐全', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(HandlebarView(
        state: active,
        unit: DistanceUnit.kilometer,
        onPause: () {},
        onResume: () {},
        onFinish: () {},
        onSwitchMode: () {},
      )));

      final Text speed =
          tester.widget<Text>(find.byKey(const Key('handlebar-speed')));
      expect(speed.style!.fontSize!, greaterThanOrEqualTo(72));
      expect(find.text('21.6'), findsOneWidget);
      expect(find.text('km/h'), findsOneWidget);
      expect(find.text('1.23 km'), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);
      expect(find.text('132'), findsOneWidget);
      expect(find.text('85'), findsOneWidget);
    });

    testWidgets('口袋模式只保留状态条', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(PocketView(
        state: active,
        unit: DistanceUnit.kilometer,
        onPause: () {},
        onResume: () {},
        onFinish: () {},
        onSwitchMode: () {},
      )));

      expect(find.text('记录中'), findsOneWidget);
      expect(find.text('1.23 km'), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);
      // 口袋模式不渲染大字号主指标
      expect(find.byKey(const Key('handlebar-speed')), findsNothing);
      // 也不渲染心率 / 踏频这类车把模式才看得清的指标
      expect(find.text('132'), findsNothing);
      expect(find.text('85'), findsNothing);
      expect(find.text('心率'), findsNothing);
      expect(find.text('踏频'), findsNothing);
    });

    testWidgets('口袋模式里没有任何 ≥72pt 的文字', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(PocketView(
        state: active,
        unit: DistanceUnit.kilometer,
        onPause: () {},
        onResume: () {},
        onFinish: () {},
        onSwitchMode: () {},
      )));

      final Iterable<Text> texts = tester.widgetList<Text>(find.byType(Text));
      expect(texts, isNotEmpty);
      for (final Text t in texts) {
        expect(
          t.style?.fontSize ?? 0,
          lessThan(72),
          reason: '口袋模式不该出现车把模式级别的大字',
        );
      }
    });

    testWidgets('口袋模式暂停时显示已暂停', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(PocketView(
        state: const RecordState(
          rideId: 1,
          phase: RecordingPhase.paused,
          elapsedMs: 1000,
        ),
        unit: DistanceUnit.kilometer,
        onPause: () {},
        onResume: () {},
        onFinish: () {},
        onSwitchMode: () {},
      )));

      expect(find.text('已暂停'), findsOneWidget);
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

    testWidgets('未开始时显示「开始骑行」，不显示暂停 / 结束', (WidgetTester tester) async {
      await pumpRecordPage(tester);

      expect(find.text('开始骑行'), findsOneWidget);
      expect(find.text('暂停'), findsNothing);
      expect(find.text('继续'), findsNothing);
      expect(find.text('结束'), findsNothing);
      expect(find.byKey(const Key('handlebar-speed')), findsNothing);
    });

    testWidgets('定位权限被拒时把阻断类错误显示在界面上', (WidgetTester tester) async {
      location.readiness = LocationReadiness.permissionDenied;
      await pumpRecordPage(tester);

      await tester.tap(find.text('开始骑行'));
      await tester.pump();

      expect(find.text('未获得定位权限，无法记录骑行'), findsOneWidget);
      expect(repo.startRideCalls, 0, reason: '阻断类错误下不能创建骑行记录');
      expect(find.text('开始骑行'), findsOneWidget, reason: '仍停在未开始状态');
    });

    testWidgets('开始后点「口袋模式」，界面真的从车把切成口袋', (WidgetTester tester) async {
      await pumpRecordPage(tester);

      await tester.tap(find.text('开始骑行'));
      await tester.pump();
      await tester.pump();

      // 默认车把模式：大字号主指标在，状态条不在。
      expect(find.byKey(const Key('handlebar-speed')), findsOneWidget);
      expect(find.text('记录中'), findsNothing);

      await tester.tap(find.text('口袋模式'));
      await tester.pump();

      // 切成口袋模式：大字号主指标消失，状态条出现。
      expect(find.byKey(const Key('handlebar-speed')), findsNothing);
      expect(find.text('记录中'), findsOneWidget);
      expect(find.text('车把模式'), findsOneWidget);
    });

    testWidgets('点「口袋模式」后大字号主指标不再存在于渲染树里', (WidgetTester tester) async {
      await pumpRecordPage(tester);
      await tester.tap(find.text('开始骑行'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('口袋模式'));
      await tester.pump();

      for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.style?.fontSize ?? 0, lessThan(72));
      }
    });
  });
}
