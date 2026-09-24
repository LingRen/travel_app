import 'dart:async';

import '../../domain/analysis/ble_payload.dart';
import 'ble_ids.dart';
import 'ble_platform.dart';
import 'reconnect_backoff.dart';

/// 传感器类型。
enum SensorKind { heartRate, cadence, power }

/// 传感器读数回调。心率单位为 bpm，踏频单位为 RPM，功率单位为瓦。
typedef SensorReadingCallback = void Function(SensorKind kind, num value);

/// 连接状态回调。
typedef SensorConnectionCallback =
    void Function(SensorKind kind, bool connected);

/// 创建重连定时器。默认走真实时钟，测试注入假实现以免真的等待退避时长。
typedef BleTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// 默认定时器工厂：真实时钟。
Timer defaultBleTimerFactory(Duration delay, void Function() callback) =>
    Timer(delay, callback);

/// 监控一个传感器的连接：枚举服务、订阅特征值、断线后指数退避重连。
///
/// 数据帧解析全部交给 domain 层的 [parseHeartRateMeasurement]、
/// [parseCscMeasurement] 与 [parseCyclingPowerMeasurement]，本类只负责 IO
/// 与重连时序。
class SensorMonitor {
  SensorMonitor({
    required this.device,
    required this.kind,
    required this.onReading,
    required this.onConnectionChanged,
    this._timerFactory = defaultBleTimerFactory,
  });

  final BleDeviceHandle device;
  final SensorKind kind;
  final SensorReadingCallback onReading;
  final SensorConnectionCallback onConnectionChanged;
  final BleTimerFactory _timerFactory;

  StreamSubscription<List<int>>? _valueSub;
  StreamSubscription<bool>? _stateSub;
  Timer? _retryTimer;
  int _attempt = 0;
  bool _disposed = false;

  /// 上一次的曲柄数据，用于算踏频。
  CscMeasurement? _lastCsc;

  /// 最近一次连接或订阅失败的原因；成功后清空。
  ///
  /// 心率广播未开启时是「设备未提供标准心率服务 0x180D」，UI 据此给出针对性
  /// 指引（手环设置 > 心率广播），而不是笼统的「连接失败」。见设计文档 11.2。
  String? lastError;

  String get deviceName => device.name.isNotEmpty ? device.name : device.id;

  /// 开始监控。立即尝试连接，之后断线自动重连。
  Future<void> start() async {
    _stateSub = device.connectionState.listen((bool connected) {
      onConnectionChanged(kind, connected);
      if (!connected) _scheduleReconnect();
    });
    await _connect();
  }

  /// 停止监控并断开设备。
  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _valueSub?.cancel();
    await _stateSub?.cancel();
    await device.disconnect();
  }

  Future<void> _connect() async {
    if (_disposed) return;
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      await _subscribe();
      _attempt = 0;
      lastError = null;
      onConnectionChanged(kind, true);
    } catch (error) {
      // 连接或订阅失败都不阻断骑行，按退避节奏再试。
      lastError = '$error';
      onConnectionChanged(kind, false);
      _scheduleReconnect();
    }
  }

  Future<void> _subscribe() async {
    await _valueSub?.cancel();
    _valueSub = null;

    final String serviceShort = switch (kind) {
      SensorKind.heartRate => kHeartRateServiceShort,
      SensorKind.cadence => kCscServiceShort,
      SensorKind.power => kCpsServiceShort,
    };
    final String characteristicShort = switch (kind) {
      SensorKind.heartRate => kHeartRateMeasurementShort,
      SensorKind.cadence => kCscMeasurementShort,
      SensorKind.power => kCpsMeasurementShort,
    };

    final List<BleCharacteristicHandle> characteristics = await device
        .discoverCharacteristics();
    for (final BleCharacteristicHandle c in characteristics) {
      if (shortUuid(c.serviceUuid) != serviceShort) continue;
      if (shortUuid(c.uuid) != characteristicShort) continue;

      // 换了一段会话，上一帧曲柄数据已经不可比，必须作废。
      _lastCsc = null;
      await c.setNotifyValue(true);
      _valueSub = c.onValueReceived.listen(_onValue);
      return;
    }

    // 走到这里说明没找到标准特征值。抛给 _connect 统一走重连，
    // 「心率广播未开启」的针对性指引由 UI 层根据 [lastError] 给出（设计文档 11.2）。
    throw StateError(switch (kind) {
      SensorKind.heartRate => '设备未提供标准心率服务 0x180D',
      SensorKind.cadence => '设备未提供标准踏频服务 0x1816',
      SensorKind.power => '设备未提供标准功率服务 0x1818',
    });
  }

  void _onValue(List<int> data) {
    switch (kind) {
      case SensorKind.heartRate:
        final int? bpm = parseHeartRateMeasurement(data);
        if (bpm != null) onReading(kind, bpm);
      case SensorKind.cadence:
        final CscMeasurement? cur = parseCscMeasurement(data);
        if (cur == null) return;
        final CscMeasurement? prev = _lastCsc;
        _lastCsc = cur;
        // 第一次收到数据时还没有上一次，无法算踏频，跳过。
        if (prev == null) return;
        final double? rpm = cadenceRpm(prev, cur);
        if (rpm != null) onReading(kind, rpm);
      case SensorKind.power:
        final int? watts = parseCyclingPowerMeasurement(data);
        if (watts != null) onReading(kind, watts);
    }
  }

  void _scheduleReconnect() {
    if (_disposed || _retryTimer != null) return;
    final Duration delay = Duration(milliseconds: backoffDelayMs(_attempt));
    _attempt++;
    _retryTimer = _timerFactory(delay, () {
      _retryTimer = null;
      unawaited(_connect());
    });
  }
}
