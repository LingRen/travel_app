import 'dart:async';

import 'package:cycling_app/data/ble/ble_platform.dart';
import 'package:cycling_app/data/ble/sensor_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可注入的假特征值，`onValueReceived` 由测试手动推帧。
class FakeCharacteristic implements BleCharacteristicHandle {
  FakeCharacteristic({required this.serviceUuid, required this.uuid});

  @override
  final String serviceUuid;

  @override
  final String uuid;

  /// 记录 `setNotifyValue` 收到的值；null 表示从未被订阅。
  bool? notifyValue;

  final StreamController<List<int>> controller =
      StreamController<List<int>>.broadcast();

  @override
  Future<void> setNotifyValue(bool value) async {
    notifyValue = value;
  }

  @override
  Stream<List<int>> get onValueReceived => controller.stream;

  void emit(List<int> frame) => controller.add(frame);
}

/// 可注入的假设备，让 [SensorMonitor] 完全不触碰 flutter_blue_plus 的静态 API。
class FakeBleDevice implements BleDeviceHandle {
  FakeBleDevice({
    required this.id,
    this.name = '',
    this.characteristics = const <BleCharacteristicHandle>[],
  });

  @override
  final String id;

  @override
  final String name;

  List<BleCharacteristicHandle> characteristics;

  /// 非空时 [connect] 直接抛出，模拟连不上或订阅失败。
  Object? connectError;

  int connectCalls = 0;
  int disconnectCalls = 0;

  final StreamController<bool> stateController =
      StreamController<bool>.broadcast();

  @override
  Stream<bool> get connectionState => stateController.stream;

  @override
  Future<void> connect({required Duration timeout}) async {
    connectCalls++;
    final Object? error = connectError;
    if (error != null) throw error;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }

  @override
  Future<List<BleCharacteristicHandle>> discoverCharacteristics() async =>
      characteristics;

  void emitConnection(bool connected) => stateController.add(connected);
}

/// 可手动点火的假定时器，避免测试真的等待退避时长。
class FakeTimer implements Timer {
  FakeTimer(this._callback);

  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}

class FakeTimers {
  final List<Duration> delays = <Duration>[];
  final List<FakeTimer> timers = <FakeTimer>[];

  Timer create(Duration delay, void Function() callback) {
    delays.add(delay);
    final FakeTimer timer = FakeTimer(callback);
    timers.add(timer);
    return timer;
  }

  FakeTimer get last => timers.last;

  int get pendingCount => timers.where((FakeTimer t) => t.isActive).length;
}

class Reading {
  const Reading(this.kind, this.value);

  final SensorKind kind;
  final num value;

  @override
  String toString() => 'Reading($kind, $value)';
}

class Connection {
  const Connection(this.kind, this.connected);

  final SensorKind kind;
  final bool connected;

  @override
  bool operator ==(Object other) =>
      other is Connection && other.kind == kind && other.connected == connected;

  @override
  int get hashCode => Object.hash(kind, connected);

  @override
  String toString() => 'Connection($kind, $connected)';
}

/// 一次监控的测试夹具：假设备 + 假时钟 + 记录下来的回调。
class Harness {
  Harness({required this.device, required this.kind}) {
    monitor = SensorMonitor(
      device: device,
      kind: kind,
      onReading: (SensorKind k, num v) => readings.add(Reading(k, v)),
      onConnectionChanged: (SensorKind k, bool c) =>
          connections.add(Connection(k, c)),
      timerFactory: timers.create,
    );
  }

  final FakeBleDevice device;
  final SensorKind kind;
  final FakeTimers timers = FakeTimers();
  final List<Reading> readings = <Reading>[];
  final List<Connection> connections = <Connection>[];
  late final SensorMonitor monitor;
}

/// HRS 特征值：服务 0x180D、测量 0x2A37，故意用 128 位长形式。
FakeCharacteristic hrCharacteristic() => FakeCharacteristic(
      serviceUuid: '0000180D-0000-1000-8000-00805F9B34FB',
      uuid: '00002a37-0000-1000-8000-00805f9b34fb',
    );

/// CSC 特征值：服务 0x1816、测量 0x2A2B，故意用短形式。
FakeCharacteristic cscCharacteristic() =>
    FakeCharacteristic(serviceUuid: '1816', uuid: '2a2b');

/// 组装一帧 CSC 曲柄数据（flags bit1，只带曲柄）。
List<int> cscFrame({required int revolutions, required int eventTime1024}) =>
    <int>[
      0x02,
      revolutions & 0xFF,
      (revolutions >> 8) & 0xFF,
      eventTime1024 & 0xFF,
      (eventTime1024 >> 8) & 0xFF,
    ];

void main() {
  group('心率订阅', () {
    test('订阅标准 HRS 特征值并把 bpm 原样交给回调', () async {
      final FakeCharacteristic hr = hrCharacteristic();
      final FakeCharacteristic csc = cscCharacteristic();
      final FakeBleDevice device = FakeBleDevice(
        id: 'AA:01',
        name: 'Fit 3',
        characteristics: <BleCharacteristicHandle>[csc, hr],
      );
      final Harness h = Harness(device: device, kind: SensorKind.heartRate);

      await h.monitor.start();

      expect(hr.notifyValue, isTrue);
      expect(csc.notifyValue, isNull, reason: '不能订阅到踏频特征值上');
      expect(h.connections.last, const Connection(SensorKind.heartRate, true));
      expect(h.monitor.deviceName, 'Fit 3');

      hr.emit(<int>[0x00, 72]);
      await pumpEventQueue();

      expect(h.readings.single.kind, SensorKind.heartRate);
      expect(h.readings.single.value, 72);
      expect(h.readings.single.value, isA<int>());
    });

    test('16 位格式的心率值按 flags 解析，不做截断', () async {
      final FakeCharacteristic hr = hrCharacteristic();
      final FakeBleDevice device = FakeBleDevice(
        id: 'AA:01',
        characteristics: <BleCharacteristicHandle>[hr],
      );
      final Harness h = Harness(device: device, kind: SensorKind.heartRate);
      await h.monitor.start();

      hr.emit(<int>[0x01, 0x2C, 0x01]); // flags bit0 → uint16 小端 = 300
      await pumpEventQueue();

      expect(h.readings.single.value, 300);
    });

    test('空帧与长度不足的帧不产生读数', () async {
      final FakeCharacteristic hr = hrCharacteristic();
      final FakeBleDevice device = FakeBleDevice(
        id: 'AA:01',
        characteristics: <BleCharacteristicHandle>[hr],
      );
      final Harness h = Harness(device: device, kind: SensorKind.heartRate);
      await h.monitor.start();

      hr.emit(<int>[]);
      hr.emit(<int>[0x01, 0x2C]); // 声明 16 位但只有 2 字节
      await pumpEventQueue();

      expect(h.readings, isEmpty);
    });
  });

  group('踏频订阅', () {
    test('第二帧起才产生 RPM，且每帧都用上一帧算', () async {
      final FakeCharacteristic csc = cscCharacteristic();
      final FakeCharacteristic hr = hrCharacteristic();
      final FakeBleDevice device = FakeBleDevice(
        id: 'AA:02',
        characteristics: <BleCharacteristicHandle>[hr, csc],
      );
      final Harness h = Harness(device: device, kind: SensorKind.cadence);

      await h.monitor.start();

      expect(csc.notifyValue, isTrue);
      expect(hr.notifyValue, isNull, reason: '不能订阅到心率特征值上');

      csc.emit(cscFrame(revolutions: 100, eventTime1024: 1024));
      await pumpEventQueue();
      expect(h.readings, isEmpty, reason: '首帧没有上一帧可比，不能上报');

      // 4 转 / 1 秒 = 240 RPM
      csc.emit(cscFrame(revolutions: 104, eventTime1024: 2048));
      await pumpEventQueue();
      expect(h.readings.single.kind, SensorKind.cadence);
      expect(h.readings.single.value, 240.0);

      // 2 转 / 1 秒 = 120 RPM；若沿用首帧则算出 180 RPM
      csc.emit(cscFrame(revolutions: 106, eventTime1024: 3072));
      await pumpEventQueue();
      expect(h.readings.length, 2);
      expect(h.readings.last.value, 120.0);
    });

    test('只带车轮数据、没有曲柄数据时不产生读数', () async {
      final FakeCharacteristic csc = cscCharacteristic();
      final FakeBleDevice device = FakeBleDevice(
        id: 'AA:02',
        characteristics: <BleCharacteristicHandle>[csc],
      );
      final Harness h = Harness(device: device, kind: SensorKind.cadence);
      await h.monitor.start();

      // flags bit0（有车轮数据）置位、bit1（有曲柄数据）清零
      csc.emit(<int>[0x01, 1, 2, 3, 4, 5, 6]);
      await pumpEventQueue();

      expect(h.readings, isEmpty);
    });
  });

  group('心率广播未开启的针对性指引', () {
    test('心率设备缺少标准 HRS 服务时给出指向 0x180D 的原因，并进入重连', () async {
      final FakeBleDevice device = FakeBleDevice(
        id: 'AA:01',
        name: '手环',
        characteristics: <BleCharacteristicHandle>[cscCharacteristic()],
      );
      final Harness h = Harness(device: device, kind: SensorKind.heartRate);

      await h.monitor.start();

      expect(h.connections.last, const Connection(SensorKind.heartRate, false));
      expect(h.monitor.lastError, isNotNull);
      expect(h.monitor.lastError, contains('0x180D'));
      expect(h.monitor.lastError, contains('心率'));
      expect(h.timers.delays, <Duration>[const Duration(seconds: 1)]);
    });

    test('踏频设备缺少标准 CSC 服务时给出指向 0x1816 的原因', () async {
      final FakeBleDevice device = FakeBleDevice(
        id: 'AA:02',
        characteristics: <BleCharacteristicHandle>[hrCharacteristic()],
      );
      final Harness h = Harness(device: device, kind: SensorKind.cadence);

      await h.monitor.start();

      expect(h.connections.last, const Connection(SensorKind.cadence, false));
      expect(h.monitor.lastError, contains('0x1816'));
    });

    test('连接成功后清空上一次的失败原因', () async {
      final FakeBleDevice device = FakeBleDevice(
        id: 'AA:01',
        characteristics: <BleCharacteristicHandle>[hrCharacteristic()],
      );
      device.connectError = Exception('connect failed');
      final Harness h = Harness(device: device, kind: SensorKind.heartRate);

      await h.monitor.start();
      expect(h.monitor.lastError, isNotNull);

      device.connectError = null;
      h.timers.last.fire();
      await pumpEventQueue();

      expect(h.connections.last, const Connection(SensorKind.heartRate, true));
      expect(h.monitor.lastError, isNull);
    });
  });

  group('指数退避重连', () {
    test('连接失败不阻断 start，按 1s 起排一次重连', () async {
      final FakeBleDevice device = FakeBleDevice(id: 'AA:01');
      device.connectError = Exception('boom');
      final Harness h = Harness(device: device, kind: SensorKind.heartRate);

      await h.monitor.start(); // 不抛异常，记录继续

      expect(h.connections.last, const Connection(SensorKind.heartRate, false));
      expect(device.connectCalls, 1);
      expect(h.timers.delays, <Duration>[const Duration(seconds: 1)]);
      expect(h.timers.pendingCount, 1, reason: '不能同时排多个定时器');
    });

    test('连接失败同时设备又上报断开时，只排一个重连定时器', () async {
      final FakeBleDevice device = FakeBleDevice(id: 'AA:01');
      device.connectError = Exception('boom');
      final Harness h = Harness(device: device, kind: SensorKind.heartRate);

      await h.monitor.start();
      // 平台在连接失败时通常也会推一条「已断开」，与 _connect 的 catch
      // 同时触发重连；不能因此排两个定时器把退避次数翻倍。
      device.emitConnection(false);
      await pumpEventQueue();

      expect(h.timers.delays, <Duration>[const Duration(seconds: 1)]);
      expect(h.timers.pendingCount, 1);
    });

    test('退避按 1s→2s→4s→8s→16s→30s→30s 递增并封顶', () async {
      final FakeBleDevice device = FakeBleDevice(id: 'AA:01');
      device.connectError = Exception('boom');
      final Harness h = Harness(device: device, kind: SensorKind.heartRate);
      await h.monitor.start();

      for (int i = 0; i < 6; i++) {
        h.timers.last.fire();
        await pumpEventQueue();
      }

      expect(h.timers.delays, <Duration>[
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 4),
        const Duration(seconds: 8),
        const Duration(seconds: 16),
        const Duration(seconds: 30),
        const Duration(seconds: 30),
      ]);
      expect(device.connectCalls, 7);
      expect(h.timers.pendingCount, 1);
    });

    test('重连成功后再次断开，退避从 1s 重新开始', () async {
      final FakeBleDevice device = FakeBleDevice(
        id: 'AA:01',
        characteristics: <BleCharacteristicHandle>[hrCharacteristic()],
      );
      device.connectError = Exception('boom');
      final Harness h = Harness(device: device, kind: SensorKind.heartRate);
      await h.monitor.start();
      expect(h.timers.delays, <Duration>[const Duration(seconds: 1)]);

      device.connectError = null;
      h.timers.last.fire();
      await pumpEventQueue();
      expect(h.connections.last, const Connection(SensorKind.heartRate, true));

      // 骑行中途传感器断开（设计文档 11.2）
      device.emitConnection(false);
      await pumpEventQueue();

      expect(h.connections.last, const Connection(SensorKind.heartRate, false));
      expect(
        h.timers.delays,
        <Duration>[const Duration(seconds: 1), const Duration(seconds: 1)],
        reason: '成功一次后次数必须归零，不能接着上次的 2s 往上翻',
      );
    });

    test('断开重连后第一帧不产生踏频读数（跨断层的上一帧作废）', () async {
      final FakeCharacteristic csc = cscCharacteristic();
      final FakeBleDevice device = FakeBleDevice(
        id: 'AA:02',
        characteristics: <BleCharacteristicHandle>[csc],
      );
      final Harness h = Harness(device: device, kind: SensorKind.cadence);
      await h.monitor.start();

      csc.emit(cscFrame(revolutions: 100, eventTime1024: 1024));
      csc.emit(cscFrame(revolutions: 104, eventTime1024: 2048));
      await pumpEventQueue();
      expect(h.readings.single.value, 240.0);

      device.emitConnection(false);
      await pumpEventQueue();
      expect(h.timers.delays, <Duration>[const Duration(seconds: 1)]);

      h.timers.last.fire();
      await pumpEventQueue();
      expect(device.connectCalls, 2);
      expect(csc.notifyValue, isTrue);

      csc.emit(cscFrame(revolutions: 106, eventTime1024: 3072));
      await pumpEventQueue();

      expect(
        h.readings.length,
        1,
        reason: '重连后没有可比的上一帧，首帧不能算出 60 RPM 的假踏频',
      );
    });

    test('dispose 取消待执行的重连并断开设备，之后不再重连', () async {
      final FakeBleDevice device = FakeBleDevice(id: 'AA:01');
      device.connectError = Exception('boom');
      final Harness h = Harness(device: device, kind: SensorKind.heartRate);
      await h.monitor.start();
      expect(h.timers.pendingCount, 1);

      await h.monitor.dispose();

      expect(device.disconnectCalls, 1);
      expect(h.timers.pendingCount, 0, reason: 'dispose 必须取消定时器');

      h.timers.last.fire(); // 已被取消，不应再发起连接
      await pumpEventQueue();
      expect(device.connectCalls, 1);

      device.emitConnection(false);
      await pumpEventQueue();
      expect(h.timers.delays.length, 1);
    });
  });

  group('deviceName', () {
    test('系统缓存名为空时回落到设备 id', () {
      final Harness h = Harness(
        device: FakeBleDevice(id: 'AA:09'),
        kind: SensorKind.cadence,
      );

      expect(h.monitor.deviceName, 'AA:09');
    });
  });
}
