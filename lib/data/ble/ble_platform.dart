import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// 一条扫描广播记录。
class BleScanEntry {
  const BleScanEntry({
    required this.device,
    required this.advertisedName,
    required this.rssi,
  });

  final BleDeviceHandle device;

  /// 广播里带的名字，部分设备为空。
  final String advertisedName;

  final int rssi;
}

/// 一个可订阅的 BLE 特征值。
abstract class BleCharacteristicHandle {
  /// 所属服务的 UUID，可能是短形式或 128 位长形式。
  String get serviceUuid;

  /// 特征值自身的 UUID，可能是短形式或 128 位长形式。
  String get uuid;

  Future<void> setNotifyValue(bool value);

  Stream<List<int>> get onValueReceived;
}

/// 一个 BLE 设备的连接与发现能力。
///
/// 抽这一层是为了让 [SensorMonitor] 可单测：`BluetoothDevice` 的方法都会走
/// 平台通道，单测里既连不上也会挂住，所以只依赖这个接口，测试注入假实现。
abstract class BleDeviceHandle {
  /// 平台侧的设备标识（Android 是 MAC，iOS 是 UUID）。
  String get id;

  /// 系统缓存的名字；从未扫到过或系统没给名字时为空串。
  String get name;

  /// 连接状态变化。true 表示已连接。
  Stream<bool> get connectionState;

  Future<void> connect({required Duration timeout});

  Future<void> disconnect();

  /// 枚举所有服务的全部特征值。
  Future<List<BleCharacteristicHandle>> discoverCharacteristics();
}

/// flutter_blue_plus 静态 API 的可注入抽象。
abstract class BlePlatform {
  /// 蓝牙适配器是否已开启。
  Future<bool> isAdapterOn();

  /// 扫描结果流。每次回调是该时刻的全量快照。
  Stream<List<BleScanEntry>> scanResults();

  Future<void> startScan({required Duration timeout});

  Future<void> stopScan();

  /// 按平台侧 id 找回一个设备句柄，用于自动重连已配对的传感器。
  ///
  /// 找不到时返回 null。注意这里拿到的句柄没有广播信息，连接前也读不到
  /// 系统缓存名——因此配对时要把名字一起存下来。
  Future<BleDeviceHandle?> deviceById(String id);
}

/// 生产实现：转发到 flutter_blue_plus。
class FlutterBluePlusPlatform implements BlePlatform {
  const FlutterBluePlusPlatform();

  @override
  Future<bool> isAdapterOn() async =>
      await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;

  @override
  Stream<List<BleScanEntry>> scanResults() => FlutterBluePlus.scanResults.map(
        (List<ScanResult> results) => <BleScanEntry>[
          for (final ScanResult r in results)
            BleScanEntry(
              device: FlutterBluePlusDevice(r.device),
              advertisedName: r.advertisementData.advName,
              rssi: r.rssi,
            ),
        ],
      );

  @override
  Future<void> startScan({required Duration timeout}) =>
      FlutterBluePlus.startScan(timeout: timeout);

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Future<BleDeviceHandle?> deviceById(String id) async =>
      id.isEmpty ? null : FlutterBluePlusDevice(BluetoothDevice.fromId(id));
}

/// 生产实现：包装一个 [BluetoothDevice]。
class FlutterBluePlusDevice implements BleDeviceHandle {
  const FlutterBluePlusDevice(this.device);

  final BluetoothDevice device;

  @override
  String get id => device.remoteId.str;

  @override
  String get name => device.platformName;

  @override
  Stream<bool> get connectionState => device.connectionState.map(
        (BluetoothConnectionState s) =>
            s == BluetoothConnectionState.connected,
      );

  @override
  Future<void> connect({required Duration timeout}) =>
      device.connect(license: License.nonprofit, timeout: timeout);

  @override
  Future<void> disconnect() => device.disconnect();

  @override
  Future<List<BleCharacteristicHandle>> discoverCharacteristics() async {
    final List<BluetoothService> services = await device.discoverServices();
    return <BleCharacteristicHandle>[
      for (final BluetoothService service in services)
        for (final BluetoothCharacteristic c in service.characteristics)
          FlutterBluePlusCharacteristic(
            serviceUuid: service.uuid.str,
            characteristic: c,
          ),
    ];
  }
}

/// 生产实现：包装一个 [BluetoothCharacteristic]。
class FlutterBluePlusCharacteristic implements BleCharacteristicHandle {
  const FlutterBluePlusCharacteristic({
    required this.serviceUuid,
    required this.characteristic,
  });

  @override
  final String serviceUuid;

  final BluetoothCharacteristic characteristic;

  @override
  String get uuid => characteristic.uuid.str;

  @override
  Future<void> setNotifyValue(bool value) =>
      characteristic.setNotifyValue(value);

  @override
  Stream<List<int>> get onValueReceived => characteristic.onValueReceived;
}
