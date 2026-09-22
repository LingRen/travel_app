import 'dart:async';

import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/ble/ble_platform.dart';
import 'package:cycling_app/data/ble/sensor_monitor.dart';
import 'package:cycling_app/data/location/location_service.dart';
import 'package:cycling_app/data/ride_repository.dart';
import 'package:cycling_app/data/sensor_pairing.dart';
import 'package:cycling_app/domain/models/location_fix.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/recording/recording_session.dart';
import 'package:cycling_app/features/record/record_controller.dart';
import 'package:flutter/widgets.dart';
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

/// 内存版仓储：只记录调用，不做任何 IO。
class _FakeRideRepository implements RideRepository {
  final List<TrackPoint> written = <TrackPoint>[];
  final List<RideStatus> statuses = <RideStatus>[];

  int startRideCalls = 0;
  int finishCalls = 0;

  /// startRide 收到的参数，供断言设备名与开始时间是否传对。
  int? startedAtMs;
  String? hrDeviceName;
  String? cadenceDeviceName;

  /// 大于 0 时 `appendPoints` 抛出异常，每次调用减一。
  int failAppendTimes = 0;

  Ride? existingRide;
  List<TrackPoint> existingPoints = <TrackPoint>[];

  @override
  Future<Ride> startRide({
    required int startedAtMs,
    String? hrDeviceName,
    String? cadenceDeviceName,
  }) async {
    startRideCalls++;
    this.startedAtMs = startedAtMs;
    this.hrDeviceName = hrDeviceName;
    this.cadenceDeviceName = cadenceDeviceName;
    return Ride(id: 1, startedAtMs: startedAtMs, status: RideStatus.recording);
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
  Future<void> setStatus(int rideId, RideStatus status) async => statuses.add(status);

  @override
  Future<RideSummary> finishRide(
    int rideId, {
    required int endedAtMs,
    required int durationS,
  }) async {
    finishCalls++;
    return _emptySummary;
  }

  @override
  Future<RideSummary> settleRide(int rideId) async => _emptySummary;

  @override
  Future<List<Ride>> findUnfinished() async => <Ride>[];

  @override
  Future<List<Ride>> listFinished({int? limit, int? offset}) async => <Ride>[];

  @override
  Future<Ride?> getRide(int id) async => existingRide;

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
  void Function()? get onRideDataChanged => null;
}

/// 假的定位服务：readiness 由用例设置，定位点由用例手动推入。
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

void main() {
  late _FakeRideRepository repo;
  late _FakeLocationService location;
  late int clockMs;

  setUp(() {
    repo = _FakeRideRepository();
    location = _FakeLocationService();
    clockMs = 1000;
  });

  /// 只替换 IO 边界的容器：假仓储、假定位、假时钟、假配对、假 BLE 平台。
  ///
  /// BLE 平台默认也给假的：真实实现会走平台通道，`testWidgets` 的 FakeAsync 下
  /// 那个 await 永远不返回（`.timeout` 的定时器也是假的，不 pump 就不触发），
  /// 会把用例挂死。默认假平台找不到任何设备，即「没有配对」。
  ProviderContainer makeContainer({
    _FakeSensorPairing? pairing,
    BlePlatform? platform,
  }) {
    final _FakeSensorPairing sensorPairing = pairing ?? _FakeSensorPairing();
    return ProviderContainer(
      overrides: <Override>[
        rideRepositoryProvider.overrideWithValue(repo),
        locationServiceProvider.overrideWithValue(location),
        nowProvider.overrideWithValue(() => clockMs),
        sensorPairingProvider.overrideWithValue(sensorPairing),
        blePlatformProvider.overrideWithValue(
          platform ?? _FakeBlePlatform(const <String, BleDeviceHandle>{}),
        ),
      ],
    );
  }

  /// 推入一个定位点，并把假时钟与 1Hz 节拍一起推进 1 秒。
  ///
  /// 纬度每 0.0001 度约 11.13 米，足以触发「距离 ≥5m」的写入条件。
  Future<void> rideOneSecond(WidgetTester tester, {required double lat}) async {
    clockMs += 1000;
    location.emit(LocationFix(tMs: clockMs, lat: lat, lon: 121.0));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('定位服务关闭时不创建记录并给出提示', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    location.readiness = LocationReadiness.serviceDisabled;
    final RecordController controller =
        container.read(recordControllerProvider.notifier);

    await controller.start();

    expect(container.read(recordControllerProvider).phase, isNull);
    expect(container.read(recordControllerProvider).errorMessage, contains('定位服务'));
    expect(repo.startRideCalls, 0);
    container.dispose();
  });

  testWidgets('定位权限被永久拒绝时引导去系统设置', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    location.readiness = LocationReadiness.permissionDeniedForever;
    final RecordController controller =
        container.read(recordControllerProvider.notifier);

    await controller.start();

    expect(container.read(recordControllerProvider).errorMessage, contains('系统设置'));
    expect(repo.startRideCalls, 0);
    container.dispose();
  });

  testWidgets('start 成功后进入 recording 并持有 rideId', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller =
        container.read(recordControllerProvider.notifier);

    await controller.start();

    final RecordState state = container.read(recordControllerProvider);
    expect(state.phase, RecordingPhase.recording);
    expect(state.rideId, 1);
    expect(state.errorMessage, isNull);
    expect(repo.statuses, isEmpty);
    container.dispose();
  });

  testWidgets('定位点攒够一批才提交事务', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller =
        container.read(recordControllerProvider.notifier);
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
    final RecordController controller =
        container.read(recordControllerProvider.notifier);
    await controller.start();

    for (int i = 1; i <= 3; i++) {
      await rideOneSecond(tester, lat: 31.0 + i * 0.0001);
    }
    expect(repo.written, isEmpty);

    controller.pause();
    await tester.pump();

    expect(repo.written.length, 3);
    expect(container.read(recordControllerProvider).phase, RecordingPhase.paused);
    expect(repo.statuses, <RideStatus>[RideStatus.paused]);

    controller.resume();
    await tester.pump();

    expect(container.read(recordControllerProvider).phase, RecordingPhase.recording);
    expect(repo.statuses.last, RideStatus.recording);
    container.dispose();
  });

  testWidgets('结束时结算并清空缓冲', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller =
        container.read(recordControllerProvider.notifier);
    await controller.start();

    for (int i = 1; i <= 3; i++) {
      await rideOneSecond(tester, lat: 31.0 + i * 0.0001);
    }

    await controller.finish();
    await tester.pump();

    expect(repo.written.length, 3);
    expect(repo.finishCalls, 1);
    expect(container.read(recordControllerProvider).phase, RecordingPhase.finished);
    container.dispose();
  });

  testWidgets('GPS 超过 10 秒没有新点时标记信号弱', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller =
        container.read(recordControllerProvider.notifier);
    await controller.start();

    await rideOneSecond(tester, lat: 31.0);
    expect(container.read(recordControllerProvider).gpsWeak, isFalse);

    clockMs += 11000;
    await tester.pump(const Duration(seconds: 11));

    expect(container.read(recordControllerProvider).gpsWeak, isTrue);
    container.dispose();
  });

  testWidgets('写入连续失败三次后提示用户', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller =
        container.read(recordControllerProvider.notifier);
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
    final RecordController controller =
        container.read(recordControllerProvider.notifier);
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
    final RecordController controller =
        container.read(recordControllerProvider.notifier);
    repo.existingRide = const Ride(id: 7, startedAtMs: 0, status: RideStatus.recording);
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

  testWidgets('恢复很久以前开始的会话后，时长只从恢复时刻继续累计',
      (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller =
        container.read(recordControllerProvider.notifier);
    // 一小时前开始、最后落盘点在一小时前的会话；崩溃后 5 分钟才重新打开 App。
    repo.existingRide = const Ride(
      id: 7,
      startedAtMs: -3599000,
      status: RideStatus.recording,
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
      reason: '恢复后的第一次 tick 只能加恢复后的 1 秒，'
          '既不能算上「开始到现在」整段，也不能算上崩溃到重启的空档',
    );
    container.dispose();
  });

  testWidgets('恢复时跳过时间倒流与 GPS 断档的点对', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller =
        container.read(recordControllerProvider.notifier);
    repo.existingRide = const Ride(id: 7, startedAtMs: 0, status: RideStatus.recording);
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
    final RecordController controller =
        container.read(recordControllerProvider.notifier);
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
    final RecordController controller =
        container.read(recordControllerProvider.notifier);
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

  testWidgets('连接心率传感器后读数进入会话，设备名写入骑行记录',
      (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller =
        container.read(recordControllerProvider.notifier);
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

  testWidgets('reset 回到未开始状态', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller =
        container.read(recordControllerProvider.notifier);
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

  testWidgets('切换模式不影响记录状态', (WidgetTester tester) async {
    final ProviderContainer container = makeContainer();
    final RecordController controller =
        container.read(recordControllerProvider.notifier);
    await controller.start();
    await rideOneSecond(tester, lat: 31.0);
    await rideOneSecond(tester, lat: 31.0001);

    controller.setMode(RecordViewMode.pocket);

    final RecordState state = container.read(recordControllerProvider);
    expect(state.mode, RecordViewMode.pocket);
    expect(state.phase, RecordingPhase.recording);
    expect(state.distanceM, greaterThan(0));
    container.dispose();
  });

  testWidgets('start 时自动重连已配对的心率传感器，并把设备名写进骑行记录',
      (WidgetTester tester) async {
    final _FakeSensorPairing pairing = _FakeSensorPairing();
    pairing.stored[SensorKind.heartRate] =
        const PairedSensor(id: 'AA:01', name: 'FIT 3');
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
    expect(repo.hrDeviceName, isNull);
    expect(container.read(recordControllerProvider).phase, RecordingPhase.recording);
    container.dispose();
  });

  testWidgets('配对里的设备找不回来时照常开始记录，不报错', (WidgetTester tester) async {
    final _FakeSensorPairing pairing = _FakeSensorPairing();
    pairing.stored[SensorKind.heartRate] =
        const PairedSensor(id: 'AA:01', name: 'FIT 3');
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
}
