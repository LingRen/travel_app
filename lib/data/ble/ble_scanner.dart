import 'dart:async';

import 'ble_platform.dart';

/// 扫描到的候选设备。
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.device,
    required this.name,
    required this.rssi,
  });

  final BleDeviceHandle device;

  /// 设备名。优先用系统缓存的名字，拿不到再用广播里的名字。
  final String name;

  final int rssi;
}

/// 蓝牙适配器状态与设备扫描。只做 IO，不含任何判断逻辑。
class BleScanner {
  const BleScanner({this._platform = const FlutterBluePlusPlatform()});

  final BlePlatform _platform;

  /// 蓝牙是否已开启。未开启时由 UI 提示，不视为记录阻断项。
  Future<bool> isAdapterOn() => _platform.isAdapterOn();

  /// 扫描 [timeout] 时长，返回按信号强度从强到弱排序的候选设备。
  ///
  /// 不使用 `withServices` 过滤：部分设备不在广播里带服务 UUID，
  /// 过滤会直接漏掉它们。改为连上后枚举服务（见 [SensorMonitor]）。
  Future<List<DiscoveredDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final List<DiscoveredDevice> found = <DiscoveredDevice>[];

    final StreamSubscription<List<BleScanEntry>> sub = _platform
        .scanResults()
        .listen((List<BleScanEntry> entries) {
          for (final BleScanEntry e in entries) {
            final String name = e.device.name.isNotEmpty
                ? e.device.name
                : e.advertisedName;
            final DiscoveredDevice d = DiscoveredDevice(
              device: e.device,
              name: name,
              rssi: e.rssi,
            );
            final int i = found.indexWhere(
              (DiscoveredDevice x) => x.device.id == e.device.id,
            );
            if (i == -1) {
              found.add(d);
            } else {
              found[i] = d;
            }
          }
        });

    await _platform.startScan(timeout: timeout);
    await Future<void>.delayed(timeout);
    await sub.cancel();
    await _platform.stopScan();

    found.sort(
      (DiscoveredDevice a, DiscoveredDevice b) => b.rssi.compareTo(a.rssi),
    );
    return found;
  }
}
