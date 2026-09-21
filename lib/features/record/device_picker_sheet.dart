import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/ble/ble_scanner.dart';
import '../../data/ble/sensor_monitor.dart';

/// 扫描并选择传感器设备。选中后由调用方 pop 出 [DiscoveredDevice]。
class DevicePickerSheet extends ConsumerStatefulWidget {
  const DevicePickerSheet({required this.kind, super.key});

  final SensorKind kind;

  @override
  ConsumerState<DevicePickerSheet> createState() => _DevicePickerSheetState();
}

class _DevicePickerSheetState extends ConsumerState<DevicePickerSheet> {
  late final Future<List<DiscoveredDevice>> _scan = _startScan();

  Future<List<DiscoveredDevice>> _startScan() async {
    final BleScanner scanner = ref.read(bleScannerProvider);
    if (!await scanner.isAdapterOn()) {
      throw StateError('手机蓝牙未开启，请先打开蓝牙');
    }
    return scanner.scan();
  }

  @override
  Widget build(BuildContext context) {
    final bool isHeartRate = widget.kind == SensorKind.heartRate;
    return SafeArea(
      child: SizedBox(
        height: 340,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                isHeartRate ? '选择心率设备' : '选择踏频设备',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (isHeartRate)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '找不到设备时，请先在华为运动健康里开启手环的心率广播'
                  '（手环设置 > 心率广播），并确认手机蓝牙已打开。',
                ),
              ),
            Expanded(
              child: FutureBuilder<List<DiscoveredDevice>>(
                future: _scan,
                builder: (
                  BuildContext context,
                  AsyncSnapshot<List<DiscoveredDevice>> snapshot,
                ) {
                  if (snapshot.hasError) {
                    final Object error = snapshot.error!;
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          error is StateError ? error.message : '扫描失败：$error',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final List<DiscoveredDevice> devices = snapshot.data!;
                  if (devices.isEmpty) {
                    return const Center(child: Text('没有发现设备'));
                  }
                  return ListView.builder(
                    itemCount: devices.length,
                    itemBuilder: (BuildContext context, int i) {
                      final DiscoveredDevice d = devices[i];
                      return ListTile(
                        title: Text(d.name.isEmpty ? '(未命名设备)' : d.name),
                        subtitle: Text('${d.device.id}   信号 ${d.rssi}'),
                        onTap: () => Navigator.of(context).pop(d),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
