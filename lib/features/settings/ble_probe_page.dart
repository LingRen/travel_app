import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// 开发期诊断页：验证华为 Fit 3 是否以标准 BLE HRS（0x180D）广播心率。
/// 对应设计文档第 14 节的风险 1、2。验证完成后可删除。
class BleProbePage extends StatefulWidget {
  const BleProbePage({super.key});

  @override
  State<BleProbePage> createState() => _BleProbePageState();
}

class _BleProbePageState extends State<BleProbePage> {
  static const String _hrMeasurementUuid = '00002a37-0000-1000-8000-00805f9b34fb';

  final List<ScanResult> _results = <ScanResult>[];
  final List<String> _log = <String>[];

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<List<int>>? _hrSub;
  BluetoothDevice? _device;

  @override
  void initState() {
    super.initState();
    FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);
    _adapterSub = FlutterBluePlus.adapterState.listen((s) => _append('适配器状态: $s'));
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _results
          ..clear()
          ..addAll(results);
      });
    });
  }

  void _append(String line) {
    setState(() => _log.insert(0, '${DateTime.now().toIso8601String()}  $line'));
  }

  Future<void> _startScan() async {
    _append('开始扫描（15 秒）');
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    _append('停止扫描');
  }

  Future<void> _connect(BluetoothDevice device) async {
    _device = device;
    _append('连接 ${device.platformName} / ${device.remoteId}');
    await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 15));
    _append('已连接，开始发现服务');
    final List<BluetoothService> services = await device.discoverServices();
    bool foundHrs = false;
    for (final BluetoothService s in services) {
      _append('服务 ${s.uuid.str128}');
      for (final BluetoothCharacteristic c in s.characteristics) {
        _append('  特征 ${c.uuid.str128}  ${c.properties}');
        if (c.uuid.str128.toLowerCase() == _hrMeasurementUuid) {
          foundHrs = true;
          await c.setNotifyValue(true);
          _hrSub = c.onValueReceived.listen((v) => _append('心率原始帧 $v'));
          _append('已订阅心率测量特征');
        }
      }
    }
    _append(foundHrs ? '结论：发现标准 HRS（0x180D / 0x2A37）' : '结论：未发现标准 HRS');
  }

  @override
  void dispose() {
    _hrSub?.cancel();
    _scanSub?.cancel();
    _adapterSub?.cancel();
    FlutterBluePlus.stopScan();
    _device?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BLE 诊断')),
      body: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              ElevatedButton(onPressed: _startScan, child: const Text('扫描')),
              ElevatedButton(onPressed: _stopScan, child: const Text('停止')),
            ],
          ),
          Expanded(
            flex: 2,
            child: ListView(
              children: <Widget>[
                for (final ScanResult r in _results)
                  ListTile(
                    title: Text('${r.device.platformName}  RSSI ${r.rssi}'),
                    subtitle: Text(
                      '${r.device.remoteId}  广播服务 ${r.advertisementData.serviceUuids}',
                    ),
                    onTap: () => _connect(r.device),
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            flex: 3,
            child: ListView(
              children: <Widget>[
                for (final String l in _log)
                  Text(l, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
