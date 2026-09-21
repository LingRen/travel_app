import 'dart:async';

import 'package:cycling_app/data/ble/ble_platform.dart';
import 'package:cycling_app/data/ble/ble_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

/// 扫描期间可注入的假设备：只需要 id 与系统缓存名。
class FakeScanDevice implements BleDeviceHandle {
  FakeScanDevice({required this.id, this.name = ''});

  @override
  final String id;

  @override
  final String name;

  @override
  Stream<bool> get connectionState => const Stream<bool>.empty();

  @override
  Future<void> connect({required Duration timeout}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<BleCharacteristicHandle>> discoverCharacteristics() async =>
      const <BleCharacteristicHandle>[];
}

/// 可注入的假 BLE 平台，让扫描逻辑完全不触碰 flutter_blue_plus 的静态 API。
class FakeBlePlatform implements BlePlatform {
  FakeBlePlatform({this.adapterOn = true});

  bool adapterOn;

  /// `startScan` 被调用时按顺序吐出的广播快照。
  final List<List<BleScanEntry>> batches = <List<BleScanEntry>>[];

  final StreamController<List<BleScanEntry>> controller =
      StreamController<List<BleScanEntry>>.broadcast();

  int startScanCalls = 0;
  int stopScanCalls = 0;
  Duration? capturedTimeout;

  @override
  Future<bool> isAdapterOn() async => adapterOn;

  @override
  Stream<List<BleScanEntry>> scanResults() => controller.stream;

  @override
  Future<void> startScan({required Duration timeout}) async {
    startScanCalls++;
    capturedTimeout = timeout;
    for (final List<BleScanEntry> batch in batches) {
      controller.add(batch);
    }
  }

  @override
  Future<void> stopScan() async {
    stopScanCalls++;
  }
}

BleScanEntry entry(FakeScanDevice device, {required int rssi, String advName = ''}) =>
    BleScanEntry(device: device, advertisedName: advName, rssi: rssi);

void main() {
  group('isAdapterOn', () {
    test('适配器已开启时返回 true', () async {
      expect(await BleScanner(platform: FakeBlePlatform()).isAdapterOn(), isTrue);
    });

    test('适配器关闭时返回 false，由 UI 提示而不阻断记录', () async {
      expect(
        await BleScanner(platform: FakeBlePlatform(adapterOn: false)).isAdapterOn(),
        isFalse,
      );
    });
  });

  group('scan', () {
    test('结果按信号强度从强到弱排序', () async {
      final FakeBlePlatform platform = FakeBlePlatform();
      final FakeScanDevice weak = FakeScanDevice(id: 'AA:01', name: 'weak');
      final FakeScanDevice strong = FakeScanDevice(id: 'AA:02', name: 'strong');
      final FakeScanDevice mid = FakeScanDevice(id: 'AA:03', name: 'mid');
      platform.batches.add(<BleScanEntry>[
        entry(weak, rssi: -80),
        entry(strong, rssi: -30),
        entry(mid, rssi: -55),
      ]);

      final List<DiscoveredDevice> found =
          await BleScanner(platform: platform).scan(timeout: Duration.zero);

      expect(
        found.map((DiscoveredDevice d) => d.device.id).toList(),
        <String>['AA:02', 'AA:03', 'AA:01'],
      );
      expect(found.map((DiscoveredDevice d) => d.rssi).toList(),
          <int>[-30, -55, -80]);
    });

    test('同一设备多次上报只保留一条，且用最新的 RSSI 覆盖旧值', () async {
      final FakeBlePlatform platform = FakeBlePlatform();
      final FakeScanDevice device = FakeScanDevice(id: 'AA:01', name: 'Fit 3');
      platform.batches.add(<BleScanEntry>[entry(device, rssi: -70)]);
      platform.batches.add(<BleScanEntry>[entry(device, rssi: -42)]);

      final List<DiscoveredDevice> found =
          await BleScanner(platform: platform).scan(timeout: Duration.zero);

      expect(found.length, 1);
      expect(found.single.rssi, -42);
    });

    test('设备名优先用系统缓存名，拿不到才回落到广播名', () async {
      final FakeBlePlatform platform = FakeBlePlatform();
      final FakeScanDevice cached = FakeScanDevice(id: 'AA:01', name: 'Fit 3');
      final FakeScanDevice uncached = FakeScanDevice(id: 'AA:02');
      platform.batches.add(<BleScanEntry>[
        entry(cached, rssi: -40, advName: '广播名不该赢'),
        entry(uncached, rssi: -50, advName: 'HRM-Dual'),
      ]);

      final List<DiscoveredDevice> found =
          await BleScanner(platform: platform).scan(timeout: Duration.zero);

      final Map<String, String> names = <String, String>{
        for (final DiscoveredDevice d in found) d.device.id: d.name,
      };
      expect(names['AA:01'], 'Fit 3');
      expect(names['AA:02'], 'HRM-Dual');
    });

    test('扫描超时交给平台，结束后停止扫描', () async {
      final FakeBlePlatform platform = FakeBlePlatform();

      await BleScanner(platform: platform)
          .scan(timeout: const Duration(milliseconds: 3));

      expect(platform.startScanCalls, 1);
      expect(platform.capturedTimeout, const Duration(milliseconds: 3));
      expect(platform.stopScanCalls, 1);
    });

    test('没有任何广播时返回空列表', () async {
      final FakeBlePlatform platform = FakeBlePlatform();

      expect(
        await BleScanner(platform: platform).scan(timeout: Duration.zero),
        isEmpty,
      );
    });

    test('未连接过的无名设备也能被列出（不按服务过滤）', () async {
      final FakeBlePlatform platform = FakeBlePlatform();
      platform.batches.add(<BleScanEntry>[
        entry(FakeScanDevice(id: 'AA:09'), rssi: -60),
      ]);

      final List<DiscoveredDevice> found =
          await BleScanner(platform: platform).scan(timeout: Duration.zero);

      expect(found.length, 1);
      expect(found.single.name, isEmpty);
    });
  });
}
