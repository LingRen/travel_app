import 'dart:async';

import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/ble/ble_platform.dart';
import 'package:cycling_app/data/ble/sensor_monitor.dart';
import 'package:cycling_app/data/location/location_service.dart';
import 'package:cycling_app/data/sensor_pairing.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/data/workout_repository.dart';
import 'package:cycling_app/domain/models/activity_type.dart';
import 'package:cycling_app/domain/models/location_fix.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/models/workout.dart';
import 'package:cycling_app/domain/models/workout_status.dart';
import 'package:cycling_app/domain/models/workout_summary.dart';
import 'package:cycling_app/domain/analysis/route_segments.dart';
import 'package:cycling_app/domain/recording/recording_session.dart';
import 'package:cycling_app/domain/recording/ride_cue.dart';
import 'package:cycling_app/features/record/record_controller.dart';
import 'package:cycling_app/features/record/ride_cue_player.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override 在 riverpod 3 里只从 misc 入口导出。
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

const WorkoutSummary _emptySummary = WorkoutSummary(
  distanceM: 0,
  durationS: 0,
  movingS: 0,
  avgSpeedMps: 0,
  movingAvgSpeedMps: 0,
  elevationGainM: 0,
  pointCount: 0,
);

/// 内存版仓储：只记录调用，不做任何 IO。
class _FakeWorkoutRepository implements WorkoutRepository {
  final List<TrackPoint> written = <TrackPoint>[];
  final List<WorkoutStatus> statuses = <WorkoutStatus>[];

  int startWorkoutCalls = 0;
  int finishCalls = 0;

  /// startWorkout 收到的参数，供断言设备名与开始时间是否传对。
  int? startedAtMs;
  ActivityType? activityType;
  String? hrDeviceName;
  String? cadenceDeviceName;
  String? powerDeviceName;

  /// 大于 0 时 `appendPoints` 抛出异常，每次调用减一。
  int failAppendTimes = 0;

  Workout? existingWorkout;
  List<TrackPoint> existingPoints = <TrackPoint>[];

  @override
  Future<Workout> startWorkout({
    required int startedAtMs,
    ActivityType activityType = ActivityType.cycling,
    String? hrDeviceName,
    String? cadenceDeviceName,
    String? powerDeviceName,
  }) async {
    startWorkoutCalls++;
    this.startedAtMs = startedAtMs;
    this.activityType = activityType;
    this.hrDeviceName = hrDeviceName;
    this.cadenceDeviceName = cadenceDeviceName;
    this.powerDeviceName = powerDeviceName;
    return Workout(
      id: 1,
      startedAtMs: startedAtMs,
      status: WorkoutStatus.recording,
    );
  }

  @override
  Future<void> appendPoints(int rideId, List<TrackPoint> points) async {
    if (failAppendTimes > 0) {
      failAppendTimes--;
      throw StateError('模拟写入失败');
    }
    written.addAll(points);
  }

  @override
  Future<void> setStatus(int rideId, WorkoutStatus status) async =>
      statuses.add(status);

  @override
  Future<WorkoutSummary> finishRide(
    int rideId, {
    required int endedAtMs,
    required int durationS,
  }) async {
    finishCalls++;
    return _emptySummary;
  }

  @override
  Future<WorkoutSummary> settleRide(int rideId) async => _emptySummary;

  @override
  Future<List<Workout>> findUnfinished() async => <Workout>[];

  @override
  Future<List<Workout>> listFinished({
    int? limit,
    int? offset,
    ActivityType? activityType,
  }) async => <Workout>[];

  @override
  Future<Workout?> getWorkout(int id) async => existingWorkout;

  @override
  Future<List<TrackPoint>> getPoints(int rideId) async => existingPoints;

  @override
  Future<TrackPoint?> lastPoint(int rideId) async =>
      existingPoints.isEmpty ? null : existingPoints.last;

  @override
  Future<void> updateTitle(int rideId, String? title) async {}

  @override
  Future<void> deleteRide(int rideId) async {}

  @override
  void Function()? get onWorkoutDataChanged => null;
}

/// 假的定位服务：readiness 由用例设置，定位点由用例手动推入。
class _FakeLocationService implements LocationService {
  final StreamController<LocationFix> _fixes =
      StreamController<LocationFix>.broadcast();

  LocationReadiness readiness = LocationReadiness.ready;

  @override
  Future<LocationReadiness> checkReadiness() async => readiness;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Stream<LocationFix> fixes() => _fixes.stream;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  /// 开始记录时的粗略定位；null 表示这次拿不到（超时/室内无 WiFi 定位）。
  LocationFix? previewFix;
  int quickPreviewCalls = 0;

  @override
  Future<LocationFix?> quickPreviewFix() async {
    quickPreviewCalls++;
    return previewFix;
  }

  /// 「始终允许」升级提示。生产由 iOS 权限级别决定，测试里直接设定。
  bool suggestAlwaysPermission = false;

  @override
  Future<bool> shouldSuggestAlwaysPermission() async => suggestAlwaysPermission;

  void emit(LocationFix fix) => _fixes.add(fix);
}

/// 可注入的假特征值，`onValueReceived` 由用例手动推帧。
class _FakeCharacteristic implements BleCharacteristicHandle {
  _FakeCharacteristic({required this.serviceUuid, required this.uuid});

  @override
  final String serviceUuid;

  @override
  final String uuid;

  final StreamController<List<int>> _values =
      StreamController<List<int>>.broadcast();

  @override
  Future<void> setNotifyValue(bool value) async {}

  @override
  Stream<List<int>> get onValueReceived => _values.stream;

  void emit(List<int> frame) => _values.add(frame);
}

/// 可注入的假设备，让控制器里的 [SensorMonitor] 完全不触碰 flutter_blue_plus。
class _FakeBleDevice implements BleDeviceHandle {
  _FakeBleDevice({
    required this.id,
    this.name = '',
    this.characteristics = const <BleCharacteristicHandle>[],
  });

  @override
  final String id;

  @override
  final String name;

  final List<BleCharacteristicHandle> characteristics;

  final StreamController<bool> _state = StreamController<bool>.broadcast();

  int connectCalls = 0;

  @override
  Stream<bool> get connectionState => _state.stream;

  @override
  Future<void> connect({required Duration timeout}) async {
    connectCalls++;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<BleCharacteristicHandle>> discoverCharacteristics() async =>
      characteristics;
}

/// 内存版配对仓储：不碰数据库，FakeAsync 下安全。
class _FakeSensorPairing implements SensorPairingRepository {
  final Map<SensorKind, PairedSensor> stored = <SensorKind, PairedSensor>{};

  @override
  Future<PairedSensor?> load(SensorKind kind) async => stored[kind];

  @override
  Future<void> save(SensorKind kind, PairedSensor sensor) async {
    stored[kind] = sensor;
  }

  @override
  Future<void> clear(SensorKind kind) async {
    stored.remove(kind);
  }
}

/// 只实现 deviceById 的假平台，供自动重连用例使用。
class _FakeBlePlatform implements BlePlatform {
  _FakeBlePlatform(this.devicesById);

  final Map<String, BleDeviceHandle> devicesById;

  @override
  Future<BleDeviceHandle?> deviceById(String id) async => devicesById[id];

  @override
  Future<bool> isAdapterOn() async => true;

  @override
  Stream<List<BleScanEntry>> scanResults() =>
      const Stream<List<BleScanEntry>>.empty();

  @override
  Future<void> startScan({required Duration timeout}) async {}

  @override
  Future<void> stopScan() async {}
}

/// 标准 HRS 特征值：服务 0x180D、测量 0x2A37（故意用 128 位长形式）。
_FakeCharacteristic _hrCharacteristic() => _FakeCharacteristic(
  serviceUuid: '0000180D-0000-1000-8000-00805F9B34FB',
  uuid: '00002a37-0000-1000-8000-00805f9b34fb',
);

/// 标准 CPS 特征值：服务 0x1818、测量 0x2A63。
_FakeCharacteristic _cpsCharacteristic() =>
    _FakeCharacteristic(serviceUuid: '1818', uuid: '2a63');

/// 假提示播报器：不碰 TTS，只记录收到的批次与单位。
///
/// 播报真的会出声，widget 测试里必须换成假的。这里同时收着 [RideCue] 的原文，
/// 方便断言控制器把 session 判定出来的提示原样交到播报出口。
class _FakeRideCuePlayer implements RideCuePlayer {
  final List<List<RideCue>> spokenBatches = <List<RideCue>>[];
  final List<DistanceUnit> spokenUnits = <DistanceUnit>[];
  final List<ActivityType> spokenTypes = <ActivityType>[];
  int disposeCalls = 0;

  @override
  Future<void> speak(
    List<RideCue> cues,
    DistanceUnit unit,
    ActivityType type,
  ) async {
    spokenBatches.add(cues);
    spokenUnits.add(unit);
    spokenTypes.add(type);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

/// 组装一帧骑行功率数据：flags=0x0000 + sint16 小端瞬时功率。
List<int> _cpsFrame(int watts) => <int>[
  0x00,
  0x00,
  watts & 0xFF,
  (watts >> 8) & 0xFF,
];

void main() {
  late _FakeWorkoutRepository repo;
  late _FakeLocationService location;
  late _FakeRideCuePlayer cuePlayer;
  late int clockMs;

  setUp(() {
    repo = _FakeWorkoutRepository();
    location = _FakeLocationService();
    cuePlayer = _FakeRideCuePlayer();
    clockMs = 1000;
  });

  /// 只替换 IO 边界的容器：假仓储、假定位、假时钟、假配对、假 BLE 平台、假播报器。
  ///
  /// BLE 平台默认也给假的：真实实现会走平台通道，`testWidgets` 的 FakeAsync 下
  /// 那个 await 永远不返回（`.timeout` 的定时器也是假的，不 pump 就不触发），
  /// 会把用例挂死。默认假平台找不到任何设备，即「没有配对」。
  ///
  /// 播报器一律换假的：真实实现走 flutter_tts 的平台通道，测试里既不该出声，
  /// 也不该依赖设备上装没装中文语音包。
  ProviderContainer makeContainer({
    _FakeSensorPairing? pairing,
    BlePlatform? platform,
  }) {
    final _FakeSensorPairing sensorPairing = pairing ?? _FakeSensorPairing();
    return ProviderContainer(
      overrides: <Override>[
        workoutRepositoryProvider.overrideWithValue(repo),
        locationServiceProvider.overrideWithValue(location),
        nowProvider.overrideWithValue(() => clockMs),
        sensorPairingProvider.overrideWithValue(sensorPairing),
        rideCuePlayerProvider.overrideWithValue(cuePlayer),
        blePlatformProvider.overrideWithValue(
          platform ?? _FakeBlePlatform(const <String, BleDeviceHandle>{}),
        ),
      ],
    );
  }

  /// 推入一个定位点，并把假时钟与 1Hz 节拍一起推进 1 秒。
  ///
  /// 纬度每 0.0001 度约 11.13 米，足以触发「距离 ≥5m」的写入条件。
  Future<void> rideOneSecond(
    WidgetTester tester, {
    required double lat,
    double? speedMps,
  }) async {
    clockMs += 1000;
    location.emit(
      LocationFix(tMs: clockMs, lat: lat, lon: 121.0, speedMps: speedMps),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('定位服务关闭时不创建记录并给出提示', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    location.readiness = LocationReadiness.serviceDisabled;
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );

    await controller.start();

    expect(container.read(recordControllerProvider).phase, isNull);
    expect(
      container.read(recordControllerProvider).errorMessage,
      contains('定位服务'),
    );
    expect(repo.startWorkoutCalls, 0);
    container.dispose();
  });

  testWidgets('定位权限被永久拒绝时引导去系统设置', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    location.readiness = LocationReadiness.permissionDeniedForever;
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );

    await controller.start();

    expect(
      container.read(recordControllerProvider).errorMessage,
      contains('系统设置'),
    );
    expect(repo.startWorkoutCalls, 0);
    container.dispose();
  });

  testWidgets('start 成功后进入 recording 并持有 rideId', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );

    await controller.start();

    final RecordState state = container.read(recordControllerProvider);
    expect(state.phase, RecordingPhase.recording);
    expect(state.rideId, 1);
    expect(state.errorMessage, isNull);
    expect(repo.statuses, isEmpty);
    container.dispose();
  });

  testWidgets('开始后先展示粗略定位，第一个真实点到达即清除', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    location.previewFix = const LocationFix(tMs: 900, lat: 31.2, lon: 121.4);
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );

    await controller.start();
    await tester.pump();

    final RecordState preview = container.read(recordControllerProvider);
    expect(preview.phase, RecordingPhase.recording);
    expect(preview.previewFix?.lat, 31.2);
    // 粗略定位只进界面，不落盘、不进轨迹。
    expect(preview.liveTrack, isEmpty);
    expect(repo.written, isEmpty);

    await rideOneSecond(tester, lat: 31.0);

    expect(container.read(recordControllerProvider).previewFix, isNull);
    container.dispose();
  });

  testWidgets('拿不到粗略定位时开始记录照常进行', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );

    await controller.start();
    await tester.pump();

    final RecordState state = container.read(recordControllerProvider);
    expect(state.phase, RecordingPhase.recording);
    expect(state.previewFix, isNull);
    expect(location.quickPreviewCalls, 1);
    container.dispose();
  });

  testWidgets('定位点攒够一批才提交事务', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();

    for (int i = 1; i <= 9; i++) {
      await rideOneSecond(tester, lat: 31.0 + i * 0.0001);
    }
    expect(repo.written, isEmpty);

    await rideOneSecond(tester, lat: 31.001);
    expect(repo.written.length, 10);
    container.dispose();
  });

  testWidgets('暂停时立刻落盘剩余点并标记 rides.status', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();

    for (int i = 1; i <= 3; i++) {
      await rideOneSecond(tester, lat: 31.0 + i * 0.0001);
    }
    expect(repo.written, isEmpty);

    controller.pause();
    await tester.pump();

    expect(repo.written.length, 3);
    expect(
      container.read(recordControllerProvider).phase,
      RecordingPhase.paused,
    );
    expect(repo.statuses, <WorkoutStatus>[WorkoutStatus.paused]);

    controller.resume();
    await tester.pump();

    expect(
      container.read(recordControllerProvider).phase,
      RecordingPhase.recording,
    );
    expect(repo.statuses.last, WorkoutStatus.recording);
    container.dispose();
  });

  testWidgets('结束时结算并清空缓冲', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();

    for (int i = 1; i <= 3; i++) {
      await rideOneSecond(tester, lat: 31.0 + i * 0.0001);
    }

    await controller.finish();
    await tester.pump();

    expect(repo.written.length, 3);
    expect(repo.finishCalls, 1);
    expect(
      container.read(recordControllerProvider).phase,
      RecordingPhase.finished,
    );
    container.dispose();
  });

  testWidgets('GPS 超过 10 秒没有新点时标记信号弱', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();

    await rideOneSecond(tester, lat: 31.0);
    expect(container.read(recordControllerProvider).gpsWeak, isFalse);

    clockMs += 11000;
    await tester.pump(const Duration(seconds: 11));

    expect(container.read(recordControllerProvider).gpsWeak, isTrue);
    container.dispose();
  });

  testWidgets('信号丢失与恢复各播报一次，不重复刷屏', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();

    await rideOneSecond(tester, lat: 31.0);
    cuePlayer.spokenBatches.clear();

    // 11 秒没有新定位：只播一条「信号弱」，之后每秒的节拍不再重复播。
    clockMs += 11000;
    await tester.pump(const Duration(seconds: 11));

    expect(cuePlayer.spokenBatches, <List<RideCue>>[
      <RideCue>[const GpsWeakCue()],
    ]);

    // 定位回来：补一条「定位已恢复」。
    await rideOneSecond(tester, lat: 31.001);

    expect(
      cuePlayer.spokenBatches
          .map((List<RideCue> batch) => batch.single)
          .toList(),
      <RideCue>[const GpsWeakCue(), const GpsRecoveredCue()],
    );
    container.dispose();
  });

  testWidgets('写入连续失败三次后提示用户', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    repo.failAppendTimes = 1000;
    await controller.start();

    // 20 个点 = 两批，都失败，但还没到「连续三次」的阈值。
    for (int i = 1; i <= 20; i++) {
      await rideOneSecond(tester, lat: 31.0 + i * 0.0001);
    }
    expect(container.read(recordControllerProvider).errorMessage, isNull);

    // 第三批失败后提示用户。
    for (int i = 21; i <= 30; i++) {
      await rideOneSecond(tester, lat: 31.0 + i * 0.0001);
    }
    await tester.pump(const Duration(seconds: 1));

    expect(
      container.read(recordControllerProvider).errorMessage,
      contains('写入连续失败'),
    );
    container.dispose();
  });

  testWidgets('写库失败先重试一次，重试成功不算失败', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    repo.failAppendTimes = 1; // 只让第一次尝试失败
    await controller.start();

    for (int i = 1; i <= 10; i++) {
      await rideOneSecond(tester, lat: 31.0 + i * 0.0001);
    }
    await tester.pump(const Duration(seconds: 1));

    expect(repo.written.length, 10, reason: '重试成功的那一批必须落盘');
    expect(container.read(recordControllerProvider).errorMessage, isNull);
    container.dispose();
  });

  testWidgets('恢复未结束会话时按已落盘点补算时长与距离', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    repo.existingWorkout = const Workout(
      id: 7,
      startedAtMs: 0,
      status: WorkoutStatus.recording,
    );
    repo.existingPoints = const <TrackPoint>[
      TrackPoint(rideId: 7, tMs: 0, lat: 31.0, lon: 121.0),
      TrackPoint(rideId: 7, tMs: 1000, lat: 31.0001, lon: 121.0),
      TrackPoint(rideId: 7, tMs: 2000, lat: 31.0002, lon: 121.0),
    ];

    await controller.resumeExisting(7);

    final RecordState state = container.read(recordControllerProvider);
    expect(state.rideId, 7);
    expect(state.phase, RecordingPhase.recording);
    expect(state.elapsedMs, 2000);
    expect(state.distanceM, closeTo(22.26, 0.5));
    container.dispose();
  });

  testWidgets('恢复很久以前开始的会话后，时长只从恢复时刻继续累计', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    // 一小时前开始、最后落盘点在一小时前的会话；崩溃后 5 分钟才重新打开 App。
    repo.existingWorkout = const Workout(
      id: 7,
      startedAtMs: -3599000,
      status: WorkoutStatus.recording,
    );
    repo.existingPoints = const <TrackPoint>[
      TrackPoint(rideId: 7, tMs: -2000, lat: 31.0, lon: 121.0),
      TrackPoint(rideId: 7, tMs: -1000, lat: 31.0001, lon: 121.0),
      TrackPoint(rideId: 7, tMs: 0, lat: 31.0002, lon: 121.0),
    ];
    clockMs = 300000;

    await controller.resumeExisting(7);
    expect(container.read(recordControllerProvider).elapsedMs, 2000);

    clockMs += 1000;
    await tester.pump(const Duration(seconds: 1));

    expect(
      container.read(recordControllerProvider).elapsedMs,
      3000,
      reason:
          '恢复后的第一次 tick 只能加恢复后的 1 秒，'
          '既不能算上「开始到现在」整段，也不能算上崩溃到重启的空档',
    );
    container.dispose();
  });

  testWidgets('恢复时跳过时间倒流与 GPS 断档的点对', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    repo.existingWorkout = const Workout(
      id: 7,
      startedAtMs: 0,
      status: WorkoutStatus.recording,
    );
    repo.existingPoints = const <TrackPoint>[
      TrackPoint(rideId: 7, tMs: 0, lat: 31.0, lon: 121.0),
      TrackPoint(rideId: 7, tMs: 1000, lat: 31.0001, lon: 121.0),
      // 时间倒流 0.5 秒：整对跳过，不能倒扣时长。
      TrackPoint(rideId: 7, tMs: 500, lat: 31.0002, lon: 121.0),
      // 断档 19.5 秒：不属于有效骑行，整段跳过。
      TrackPoint(rideId: 7, tMs: 20000, lat: 31.0012, lon: 121.0),
      TrackPoint(rideId: 7, tMs: 21000, lat: 31.0013, lon: 121.0),
    ];

    await controller.resumeExisting(7);

    final RecordState state = container.read(recordControllerProvider);
    expect(state.elapsedMs, 2000);
    expect(state.distanceM, closeTo(22.26, 0.5));
    container.dispose();
  });

  testWidgets('退到后台时强制落盘未满一批的点', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();

    for (int i = 1; i <= 3; i++) {
      await rideOneSecond(tester, lat: 31.0 + i * 0.0001);
    }
    expect(repo.written, isEmpty);

    controller.handleLifecycle(AppLifecycleState.paused);
    await tester.pump();

    expect(repo.written.length, 3);
    container.dispose();
  });

  testWidgets('切到 inactive 也强制落盘', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();

    for (int i = 1; i <= 2; i++) {
      await rideOneSecond(tester, lat: 31.0 + i * 0.0001);
    }
    expect(repo.written, isEmpty);

    controller.handleLifecycle(AppLifecycleState.inactive);
    await tester.pump();

    expect(repo.written.length, 2);
    container.dispose();
  });

  testWidgets('连接心率传感器后读数进入会话，设备名写入骑行记录', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    final _FakeCharacteristic hr = _hrCharacteristic();
    final _FakeBleDevice device = _FakeBleDevice(
      id: 'AA:01',
      name: 'Fit 3',
      characteristics: <BleCharacteristicHandle>[hr],
    );

    await controller.connectSensor(SensorKind.heartRate, device);
    expect(container.read(recordControllerProvider).hrConnected, isTrue);
    expect(device.connectCalls, 1);

    await controller.start();
    expect(repo.hrDeviceName, 'Fit 3');
    expect(repo.cadenceDeviceName, isNull);

    hr.emit(<int>[0x00, 72]);
    await tester.pump(const Duration(seconds: 1));

    final RecordState state = container.read(recordControllerProvider);
    expect(state.hr, 72);
    expect(state.hrConnected, isTrue);
    container.dispose();
  });

  testWidgets('连接功率计后读数进入会话，设备名写入骑行记录', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    final _FakeCharacteristic cps = _cpsCharacteristic();
    final _FakeBleDevice device = _FakeBleDevice(
      id: 'AA:03',
      name: 'ASSIOMA',
      characteristics: <BleCharacteristicHandle>[cps],
    );

    await controller.connectSensor(SensorKind.power, device);
    expect(container.read(recordControllerProvider).powerConnected, isTrue);
    expect(device.connectCalls, 1);

    await controller.start();
    expect(repo.powerDeviceName, 'ASSIOMA');
    // 没连心率与踏频时这两项不该被写成空串之外的东西。
    expect(repo.hrDeviceName, isNull);
    expect(repo.cadenceDeviceName, isNull);

    cps.emit(_cpsFrame(210));
    await tester.pump(const Duration(seconds: 1));

    final RecordState state = container.read(recordControllerProvider);
    expect(state.power, 210);
    expect(state.powerConnected, isTrue);
    container.dispose();
  });

  testWidgets('reset 回到未开始状态', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();
    await rideOneSecond(tester, lat: 31.0);
    await controller.finish();

    controller.reset();

    final RecordState state = container.read(recordControllerProvider);
    expect(state.phase, isNull);
    expect(state.rideId, isNull);
    expect(state.distanceM, 0);
    container.dispose();
  });

  testWidgets('selectActivityType 未开始时更新状态，记录中忽略，reset 保留选择', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );

    // 默认骑行。
    expect(
      container.read(recordControllerProvider).selectedActivityType,
      ActivityType.cycling,
    );

    // 未开始时切换生效。
    controller.selectActivityType(ActivityType.running);
    expect(
      container.read(recordControllerProvider).selectedActivityType,
      ActivityType.running,
    );

    // 开始后类型冻结落库：startWorkout 收到 running，界面上的再切换被忽略。
    await controller.start();
    expect(repo.activityType, ActivityType.running);
    controller.selectActivityType(ActivityType.walking);
    expect(
      container.read(recordControllerProvider).selectedActivityType,
      ActivityType.running,
    );

    // reset 保留上次选择：下一次进来还是跑步，不用重选。
    controller.reset();
    expect(
      container.read(recordControllerProvider).selectedActivityType,
      ActivityType.running,
    );
    container.dispose();
  });

  testWidgets('退到后台不重建界面状态，回到前台补一次 publish', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();
    await rideOneSecond(tester, lat: 31.0);
    await rideOneSecond(tester, lat: 31.0001);

    controller.handleLifecycle(AppLifecycleState.paused);
    final int backgroundElapsedMs = container
        .read(recordControllerProvider)
        .elapsedMs;
    expect(container.read(recordControllerProvider).foreground, isFalse);

    // 后台期间 1Hz 节拍照常走（时长、超速衰减都挂在它上面），但界面状态原地
    // 不动：界面看不见，重建纯属白烧 CPU，缩略图也跟着白重绘。
    clockMs += 1000;
    await tester.pump(const Duration(seconds: 1));
    expect(
      container.read(recordControllerProvider).elapsedMs,
      backgroundElapsedMs,
      reason: '后台不该每秒重建界面状态',
    );

    // 亮屏回来补一次：读数不会停在熄屏那一刻。
    controller.handleLifecycle(AppLifecycleState.resumed);
    final RecordState state = container.read(recordControllerProvider);
    expect(state.foreground, isTrue);
    expect(state.elapsedMs, greaterThan(backgroundElapsedMs));
    expect(state.phase, RecordingPhase.recording);
    container.dispose();
  });

  testWidgets('仅有「使用期间」权限时开始后给出始终允许提示，reset 撤掉', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = makeContainer();
    location.suggestAlwaysPermission = true;
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );

    await controller.start();

    expect(
      container.read(recordControllerProvider).suggestAlwaysPermission,
      isTrue,
    );

    controller.reset();
    expect(
      container.read(recordControllerProvider).suggestAlwaysPermission,
      isFalse,
    );
    container.dispose();
  });

  testWidgets('去系统设置改成始终允许后回前台，提示自动撤掉', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    location.suggestAlwaysPermission = true;
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();
    expect(
      container.read(recordControllerProvider).suggestAlwaysPermission,
      isTrue,
    );

    // 用户离开 App 去系统设置，把权限升到「始终允许」再回来。
    controller.handleLifecycle(AppLifecycleState.paused);
    location.suggestAlwaysPermission = false;
    controller.handleLifecycle(AppLifecycleState.resumed);
    await tester.pump();

    expect(
      container.read(recordControllerProvider).suggestAlwaysPermission,
      isFalse,
    );
    container.dispose();
  });

  testWidgets('实时轨迹按距离抽稀，且没追加时不换列表对象', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();

    // 第一个定位点无条件留下。
    await rideOneSecond(tester, lat: 31.0);
    final List<TrackPoint> first = container
        .read(recordControllerProvider)
        .liveTrack;
    expect(first.length, 1);

    // 11.13 米：够落盘（kMinWriteDistanceM = 5），但不够进缩略图
    // （kLiveTrackMinDistanceM = 25）——缩略图只要形状，不需要一个点一像素。
    await rideOneSecond(tester, lat: 31.0001);
    expect(
      identical(container.read(recordControllerProvider).liveTrack, first),
      isTrue,
      reason: '没追加点就该复用同一个列表对象，界面才敢跳过硬折线',
    );

    // 累计 22 米，仍不够。
    await rideOneSecond(tester, lat: 31.0002);
    expect(container.read(recordControllerProvider).liveTrack.length, 1);

    // 累计 33 米，超过阈值，留下第二个点。
    await rideOneSecond(tester, lat: 31.0003);
    expect(container.read(recordControllerProvider).liveTrack.length, 2);
    container.dispose();
  });

  // 缩略图上的点是抽稀过的：慢速骑行时相邻两点隔 15 秒是常态，画线若按
  // `kGpsGapMs`（10 秒）判断，一条连续轨迹会被切成一截截——这就是真机上看到的
  // 「断断续续」。断点必须由采集侧在确实丢信号时显式标出来。
  testWidgets('慢速骑行的时间跨度不算断点，真丢信号才断', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();

    // 每秒 1.1 米（0.00001 度）：25 米要走 22 秒，缩略图只能靠 15 秒的时间规则
    // 追加点，于是相邻两点必然超过 10 秒。
    for (int i = 0; i < 46; i++) {
      await rideOneSecond(tester, lat: 31.0 + i * 0.00001);
    }

    final RecordState slow = container.read(recordControllerProvider);
    expect(slow.liveTrack.length, greaterThanOrEqualTo(2));
    expect(slow.liveTrackBreaks, isEmpty, reason: '一路都有定位，不该有断点');
    expect(
      buildRouteSegments(
        slow.liveTrack,
        breakBefore: slow.liveTrackBreaks,
      ).length,
      1,
      reason: '抽稀造成的 15 秒间隔不能把轨迹切开',
    );

    // 12 秒没有定位：再恢复时，下一个被缩略图收下的点必须是段首。
    clockMs += 12000;
    location.emit(
      LocationFix(tMs: clockMs, lat: 31.0005, lon: 121.0, speedMps: 5),
    );
    await tester.pump(const Duration(seconds: 1));
    // 恢复后按 ~11 m/s 推进 12 秒：断点那个点之后还要再攒一个点，否则断出来的
    // 尾段只有一个顶点、会被 `_flush` 丢掉，看不出「断成两段」。
    for (int i = 0; i < 12; i++) {
      await rideOneSecond(tester, lat: 31.0005 + i * 0.0001, speedMps: 5);
    }

    final RecordState after = container.read(recordControllerProvider);
    expect(after.liveTrackBreaks, isNotEmpty, reason: '真丢了 12 秒信号');
    expect(
      buildRouteSegments(
        after.liveTrack,
        breakBefore: after.liveTrackBreaks,
      ).length,
      2,
    );
    container.dispose();
  });

  testWidgets('start 时自动重连已配对的心率传感器，并把设备名写进骑行记录', (WidgetTester tester) async {
    final _FakeSensorPairing pairing = _FakeSensorPairing();
    pairing.stored[SensorKind.heartRate] = const PairedSensor(
      id: 'AA:01',
      name: 'FIT 3',
    );
    final _FakeBleDevice device = _FakeBleDevice(
      id: 'AA:01',
      name: 'FIT 3',
      characteristics: <BleCharacteristicHandle>[_hrCharacteristic()],
    );
    final ProviderContainer container = makeContainer(
      pairing: pairing,
      platform: _FakeBlePlatform(<String, BleDeviceHandle>{'AA:01': device}),
    );

    await container.read(recordControllerProvider.notifier).start();
    await tester.pump();

    expect(device.connectCalls, 1);
    expect(container.read(recordControllerProvider).hrConnected, isTrue);
    expect(repo.hrDeviceName, 'FIT 3');
    container.dispose();
  });

  testWidgets('没有配对时 start 不尝试连接任何传感器', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer(
      platform: _FakeBlePlatform(<String, BleDeviceHandle>{}),
    );

    await container.read(recordControllerProvider.notifier).start();
    await tester.pump();

    expect(container.read(recordControllerProvider).hrConnected, isFalse);
    expect(container.read(recordControllerProvider).cadenceConnected, isFalse);
    expect(container.read(recordControllerProvider).powerConnected, isFalse);
    expect(repo.hrDeviceName, isNull);
    expect(
      container.read(recordControllerProvider).phase,
      RecordingPhase.recording,
    );
    container.dispose();
  });

  testWidgets('配对里的设备找不回来时照常开始记录，不报错', (WidgetTester tester) async {
    final _FakeSensorPairing pairing = _FakeSensorPairing();
    pairing.stored[SensorKind.heartRate] = const PairedSensor(
      id: 'AA:01',
      name: 'FIT 3',
    );
    final ProviderContainer container = makeContainer(
      pairing: pairing,
      platform: _FakeBlePlatform(<String, BleDeviceHandle>{}), // 空表，找不到
    );

    await container.read(recordControllerProvider.notifier).start();
    await tester.pump();

    final RecordState state = container.read(recordControllerProvider);
    expect(state.phase, RecordingPhase.recording);
    expect(state.errorMessage, isNull);
    expect(state.hrConnected, isFalse);
    container.dispose();
  });

  testWidgets('连接传感器成功后记住设备，供下次自动重连', (WidgetTester tester) async {
    final _FakeSensorPairing pairing = _FakeSensorPairing();
    final ProviderContainer container = makeContainer(pairing: pairing);
    final _FakeBleDevice device = _FakeBleDevice(
      id: 'AA:01',
      name: 'FIT 3',
      characteristics: <BleCharacteristicHandle>[_hrCharacteristic()],
    );

    await container
        .read(recordControllerProvider.notifier)
        .connectSensor(SensorKind.heartRate, device);
    await tester.pump();

    expect(pairing.stored[SensorKind.heartRate]!.id, 'AA:01');
    expect(pairing.stored[SensorKind.heartRate]!.name, 'FIT 3');
    container.dispose();
  });

  testWidgets('骑行提示写入状态并交给播报器念出来', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();

    // 12 m/s = 43.2 km/h，向上跨过 40 档。报的是实际速度 43.2，不是档位下沿。
    await rideOneSecond(tester, lat: 31.0, speedMps: 12.0);

    final RecordState state = container.read(recordControllerProvider);
    expect(state.cueSeq, 1);
    final RideCue? cue = state.lastCue;
    expect(cue, isA<SpeedCue>());
    expect((cue! as SpeedCue).kmh, closeTo(43.2, 1e-9));

    expect(cuePlayer.spokenBatches.length, 1);
    expect(cuePlayer.spokenBatches.single.single, cue);
    expect(cuePlayer.spokenUnits.single, DistanceUnit.kilometer);
    container.dispose();
  });

  testWidgets('同一速档的后续节拍不重复播报', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();

    await rideOneSecond(tester, lat: 31.0, speedMps: 12.0);
    await rideOneSecond(tester, lat: 31.0001, speedMps: 12.2);
    await rideOneSecond(tester, lat: 31.0002, speedMps: 12.4);

    expect(
      container.read(recordControllerProvider).cueSeq,
      1,
      reason: '还在 40 档里，插话只会变成噪音',
    );
    expect(cuePlayer.spokenBatches.length, 1);
    container.dispose();
  });

  testWidgets('定位点到达立即刷新速度读数，不等 1 秒节拍', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();

    await rideOneSecond(tester, lat: 31.0, speedMps: 6.0);
    expect(container.read(recordControllerProvider).currentSpeedMps, 6.0);

    // 只过 200 毫秒：1Hz 节拍还没到，但定位点已经来了。数值必须马上变——
    // 原来这里要等下一拍，加上定位解算本身的延迟，体感就是「速度慢半拍」。
    clockMs += 200;
    location.emit(
      LocationFix(tMs: clockMs, lat: 31.0001, lon: 121.0, speedMps: 9.5),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(recordControllerProvider).currentSpeedMps, 9.5);
    container.dispose();
  });

  testWidgets('熄屏进后台时照常播报，但不重建界面状态', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller = container.read(
      recordControllerProvider.notifier,
    );
    await controller.start();

    // 7.2 km/h，落在 0 档，先不产生提示。
    await rideOneSecond(tester, lat: 31.0, speedMps: 2.0);
    expect(cuePlayer.spokenBatches, isEmpty);

    controller.handleLifecycle(AppLifecycleState.paused);
    final int backgroundElapsedMs = container
        .read(recordControllerProvider)
        .elapsedMs;

    // 熄屏放口袋里跨过一次速档：屏内横幅看不见，语音必须照念。
    await rideOneSecond(tester, lat: 31.0001, speedMps: 12.0);

    expect(
      cuePlayer.spokenBatches.length,
      1,
      reason: '选语音播报的全部理由就是熄屏场景，后台不播等于没做',
    );
    expect(cuePlayer.spokenBatches.single.single, isA<SpeedCue>());
    expect(
      container.read(recordControllerProvider).elapsedMs,
      backgroundElapsedMs,
      reason: '后台仍不重建界面状态，读数回到前台时再补',
    );
    container.dispose();
  });
}
