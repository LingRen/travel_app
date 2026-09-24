import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
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
    final String title = switch (widget.kind) {
      SensorKind.heartRate => '选择心率设备',
      SensorKind.cadence => '选择踏频设备',
      SensorKind.power => '选择功率计',
    };
    return SafeArea(
      child: SizedBox(
        height: 340,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kSpaceL,
                kSpaceL,
                kSpaceL,
                kSpaceS,
              ),
              child: Text(
                title,
                style: kSectionTextStyle,
              ),
            ),
            if (isHeartRate)
              const Padding(
                padding: EdgeInsets.fromLTRB(kSpaceL, 0, kSpaceL, kSpaceM),
                child: Text(
                  '找不到设备时，请先在华为运动健康里开启手环的心率广播'
                  '（手环设置 > 心率广播），并确认手机蓝牙已打开。',
                  style: kMutedTextStyle,
                ),
              ),
            const Divider(height: 1),
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
                        padding: const EdgeInsets.all(kSpaceL),
                        child: Text(
                          error is StateError ? error.message : '扫描失败：$error',
                          textAlign: TextAlign.center,
                          style: kMutedTextStyle,
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final List<DiscoveredDevice> devices = snapshot.data!;
                  if (devices.isEmpty) {
                    return const Center(
                      child: Text('没有发现设备', style: kMutedTextStyle),
                    );
                  }
                  return ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (BuildContext context, int i) =>
                        const Divider(height: 1),
                    itemBuilder: (BuildContext context, int i) {
                      final DiscoveredDevice d = devices[i];
                      return _DeviceRow(
                        device: d,
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

/// 一行设备。设备名是给人认的，不套等宽；ID 与信号强度是给排查用的，
/// 收成等宽小字右对齐，扫一眼就能比出哪台信号强。
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.onTap});

  final DiscoveredDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String name = device.name.isEmpty ? '(未命名设备)' : device.name;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kSpaceL,
          vertical: kSpaceM,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: kFontSubtitle,
                      fontWeight: FontWeight.w600,
                      color: kAppTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    device.device.id,
                    style: const TextStyle(
                      fontFamily: kMonoFamily,
                      fontSize: kFontLabel,
                      color: kAppTextMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: kSpaceM),
            Text('${device.rssi}', style: _rssiStyle),
          ],
        ),
      ),
    );
  }
}

/// 信号强度读数：等宽 tabular，右对齐成一条竖列。
const TextStyle _rssiStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontSize: kFontBody,
  color: kAppTextMuted,
  fontFeatures: kTabularFigures,
);
