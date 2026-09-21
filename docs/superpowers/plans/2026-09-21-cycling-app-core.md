# 骑行记录 App — 核心记录链路 实施计划（Plan A）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让这个 App 能真的骑一次车：连接心率/踏频传感器，用手机 GPS 采集轨迹，增量落盘到本地 SQLite，崩溃后可恢复，并在记录页实时显示指标。

**Architecture:** 三层分离。`domain/` 是纯逻辑（不依赖 Flutter、不做 IO），所有指标计算与状态机都在这里，用普通 `test` 就能测。`data/` 负责 IO（SQLite、定位、BLE）。`features/` 是 Riverpod 控制器 + Widget，只做接线和渲染。记录引擎采用设计文档的方案 B：1Hz tick 驱动内存会话状态，按规则过滤后批量写入 SQLite。

**Tech Stack:** Flutter 3.47.4（fvm）/ Dart 3.13.3、flutter_riverpod、geolocator、flutter_blue_plus、sqflite（测试用 sqflite_common_ffi）、permission_handler、wakelock_plus。

**规格来源：** `docs/superpowers/specs/2026-09-21-cycling-app-design.md`（唯一权威）。本计划覆盖该规格第 4–8、10.1、11、13 节中属于「记录链路」的部分。历史页、详情页、统计页、设置页、地图、GPX/备份导出由 Plan B 覆盖。

**关于目录名：** 工程目录保持 `/Users/ling/code/travel_app` 不变，Flutter 包名使用 `cycling_app`。

**执行前必读：** 本机没有全局 `flutter`/`dart`，只有 `fvm`。**所有 Flutter 命令都必须写成 `fvm flutter ...`**，且必须先完成 Task 1 的 `fvm use`，否则 `fvm flutter` 会因为 `~/fvm/default` 指向不存在的 3.35.2 而报 `flutter: command not found`。

---

## 文件结构

```text
lib/
  main.dart                                   应用入口
  app/
    app.dart                                  MaterialApp 外壳
    theme.dart                                主题与颜色常量
    providers.dart                            Riverpod 依赖装配
    home_shell.dart                           底部四 tab 导航壳
    recovery_gate.dart                        启动时的未结束会话恢复对话框
  core/
    format.dart                               距离/速度/时长的展示格式化（纯函数）
  domain/
    models/
      ride_status.dart                        RideStatus 枚举
      ride_summary.dart                       RideSummary + rides 表列映射
      ride.dart                               Ride + rides 表行映射
      track_point.dart                        TrackPoint + track_points 表行映射
      location_fix.dart                       LocationFix（定位原始结果）
    analysis/
      constants.dart                          全部具名数值常量
      geo.dart                                Haversine 与「有效段距离」
      elevation.dart                          高程中值滤波 + 爬升
      speed.dart                              速度滑动平均 + 移动/静止切分
      heart_rate.dart                         心率区间
      calories.dart                           卡路里估算
      color_scale.dart                        速度→颜色（返回 ARGB int）
      summary.dart                            computeSummary
      ble_payload.dart                        HRS / CSC 数据帧解析（纯函数）
    recording/
      track_point_filter.dart                 6.3 规则 1：是否写入轨迹点
      write_buffer.dart                       6.3 规则 2：批量提交缓冲
      recording_session.dart                  6.1 状态机 + 实时指标
  data/
    db/
      database.dart                           建表 / 打开 / 迁移
      settings_dao.dart                       settings 表 KV 读写
      ride_dao.dart                           rides 表读写
      track_point_dao.dart                    track_points 表读写
    settings_repository.dart                  AppSettings 类型化配置
    ride_repository.dart                      面向业务的数据门面
    location/location_service.dart            定位采集与权限校验
    ble/ble_ids.dart                          GATT UUID 常量与短 UUID 归一化
    ble/ble_scanner.dart                      适配器状态与扫描
    ble/reconnect_backoff.dart                重连退避时长（纯函数，可测）
    ble/sensor_monitor.dart                   心率/踏频订阅 + 指数退避重连
  features/
    record/
      record_controller.dart                  Riverpod 控制器（1Hz tick + 落盘）
      record_page.dart                        记录页（模式分发 + 空态/完成态）
      handlebar_view.dart                     车把模式
      pocket_view.dart                        口袋模式
      device_picker_sheet.dart                扫描并选择传感器设备
test/
  core/                                     格式化纯函数单测
  domain/                                    纯逻辑单测（本计划重点）
  data/                                      DAO 与仓储测试（sqflite_common_ffi）
  features/                                 Widget 测试
```

分层规则（必须遵守）：`domain/` 下的文件**不得** import `package:flutter/*`、`dart:io`、`package:sqflite/*`。`data/` 可以 import `domain/`。`features/` 可以 import 两者。

---

## Task 1: 项目骨架与依赖

**Files:**
- Create: `.fvmrc`（由 fvm 生成）
- Create: `pubspec.yaml`、`lib/main.dart`、`ios/`、`android/`（由 flutter create 生成）
- Modify: `.gitignore`

- [ ] **Step 1: 固定 Flutter 版本**

```bash
cd /Users/ling/code/travel_app
fvm use 3.47.4
```

Expected: 生成 `.fvmrc`（内容含 `"flutter": "3.47.4"`）与 `.fvm/` 软链目录。

- [ ] **Step 2: 验证 fvm 可用**

```bash
fvm flutter --version
```

Expected: 输出 `Flutter 3.47.4 • channel stable`，Tools 行为 `Dart 3.13.3`。
（若出现 `git fetch --tags` 的网络报错但版本号正常输出，可忽略。）

- [ ] **Step 3: 生成工程骨架**

```bash
fvm flutter create --org com.ling --project-name cycling_app --platforms=ios,android .
```

Expected: 生成 `lib/main.dart`、`test/widget_test.dart`、`pubspec.yaml`、`ios/`、`android/`、`analysis_options.yaml`、`.gitignore`。已有的 `docs/` 与 `.git/` 不受影响。

- [ ] **Step 4: 忽略 fvm 软链目录**

在 `.gitignore` 末尾追加：

```gitignore
.fvm/
```

（`.fvmrc` 要提交，`.fvm/` 不提交。）

- [ ] **Step 5: 添加运行时依赖**

```bash
fvm flutter pub add geolocator flutter_blue_plus sqflite flutter_riverpod fl_chart flutter_map latlong2 wakelock_plus permission_handler share_plus path_provider file_picker archive xml
```

Expected: `pubspec.yaml` 的 `dependencies:` 下出现上述 14 个包，命令以 `Changed N dependencies!` 结束。

- [ ] **Step 6: 添加测试依赖**

```bash
fvm flutter pub add dev:sqflite_common_ffi
```

Expected: `pubspec.yaml` 的 `dev_dependencies:` 下出现 `sqflite_common_ffi`。

- [ ] **Step 7: 删除模板测试并跑通静态分析**

```bash
rm test/widget_test.dart
fvm flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 8: 提交**

```bash
git add -A
git commit -m "chore: 初始化 Flutter 工程与依赖"
```

---

## Task 2: 平台权限与后台能力配置

没有这一步，定位在锁屏后会停、蓝牙扫描会直接被系统拒绝。

**Files:**
- Modify: `ios/Runner/Info.plist`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/build.gradle.kts`

- [ ] **Step 1: iOS 权限与后台模式**

在 `ios/Runner/Info.plist` 的最后一个 `</dict>` 之前插入：

```xml
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>用于记录你的骑行轨迹</string>
	<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
	<string>锁屏或切到其他 App 时继续记录骑行轨迹</string>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>用于连接心率带与踏频器</string>
	<key>NSBluetoothPeripheralUsageDescription</key>
	<string>用于连接心率带与踏频器</string>
	<key>UIBackgroundModes</key>
	<array>
		<string>location</string>
		<string>bluetooth-central</string>
	</array>
```

- [ ] **Step 2: Android 权限声明**

在 `android/app/src/main/AndroidManifest.xml` 的 `<manifest>` 标签内、`<application>` 之前插入：

```xml
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

- [ ] **Step 3: Android 前台服务声明**

在 `android/app/src/main/AndroidManifest.xml` 的 `<application>` 标签内插入：

```xml
        <service
            android:name="com.baseflow.geolocator.GeolocatorService"
            android:enabled="true"
            android:exported="false"
            android:foregroundServiceType="location" />
```

- [ ] **Step 4: 提高 minSdk**

在 `android/app/build.gradle.kts` 的 `defaultConfig { ... }` 块中，把 `minSdk` 一行改为：

```kotlin
        minSdk = 23
```

- [ ] **Step 5: 验证 Dart 层未被破坏**

```bash
fvm flutter analyze
```

Expected: `No issues found!`（平台配置的正确性在 Task 3 的真机运行中验证。）

- [ ] **Step 6: 提交**

```bash
git add -A
git commit -m "chore: 配置 iOS/Android 定位与蓝牙权限"
```

---

## Task 3: BLE 风险验证程序（设计文档第 14 节风险 1、2）

这是整个项目**唯一可能推翻方案的前置风险**，所以排在最前面。目标是拿到两个结论：

1. 华为 Fit 3 的心率广播是否暴露标准 BLE HRS 服务 `0x180D` / 特征 `0x2A37`。
2. 开启广播后，Fit 3 是否断开与华为运动健康的连接；断开后能否恢复。

**Files:**
- Create: `lib/features/settings/ble_probe_page.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: 写诊断页**

创建 `lib/features/settings/ble_probe_page.dart`：

```dart
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
    await device.connect(timeout: const Duration(seconds: 15));
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
```

- [ ] **Step 2: 把诊断页设为临时首页**

把 `lib/main.dart` 整体替换为：

```dart
import 'package:flutter/material.dart';

import 'features/settings/ble_probe_page.dart';

void main() {
  runApp(const MaterialApp(home: BleProbePage(), debugShowCheckedModeBanner: false));
}
```

- [ ] **Step 3: 静态分析**

```bash
fvm flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4: 真机运行**

先在 Fit 3 上打开「设置 → 心率广播」（不同固件路径可能是「健康监测 → 心率广播」），然后：

```bash
fvm flutter run
```

（iOS 需要先在 `ios/Runner.xcworkspace` 里配好签名；Android 直接连 USB 调试设备。）

- [ ] **Step 5: 记录风险 1 的结论**

在诊断页点「扫描」，找到 Fit 3，点进去。观察日志里是否出现：

```text
服务 0000180d-0000-1000-8000-00805f9b34fb
  特征 00002a37-0000-1000-8000-00805f9b34fb  ...
已订阅心率测量特征
心率原始帧 [16, 72]
结论：发现标准 HRS（0x180D / 0x2A37）
```

Expected: 出现 `结论：发现标准 HRS（0x180D / 0x2A37）`，且心率原始帧第一字节为 `0` 或 `16`（flags），第二字节是 bpm。

**若未发现标准 HRS**：停止执行本计划，回到用户处说明，需要改用其他心率来源（重新走设计流程）。

- [ ] **Step 6: 记录风险 2 的结论**

保持诊断页连接心率 1 分钟，同时打开手机上的华为运动健康 App，观察：

- 华为运动健康是否提示 Fit 3 断连；
- 断开后关闭手环的「心率广播」，华为运动健康能否自动重连。

把两条实测结论（原样文字）追加到设计文档 `docs/superpowers/specs/2026-09-21-cycling-app-design.md` 第 14 节末尾：

```markdown
**实测结论（日期，华为 Fit 3）**

1. 心率广播为标准 BLE HRS：是 / 否。实测证据：……
2. 开启广播后与华为运动健康的连接：会断开 / 不会断开；断开后可恢复 / 不可恢复。实测证据：……
```

- [ ] **Step 7: 提交**

```bash
git add -A
git commit -m "chore: 添加 BLE 诊断页并记录 Fit 3 心率广播实测结论"
```

---

## Task 4: domain 数据模型

**Files:**
- Create: `lib/domain/models/ride_status.dart`
- Create: `lib/domain/models/location_fix.dart`
- Create: `lib/domain/models/track_point.dart`
- Create: `lib/domain/models/ride_summary.dart`
- Create: `lib/domain/models/ride.dart`
- Test: `test/domain/models/track_point_test.dart`
- Test: `test/domain/models/ride_test.dart`

- [ ] **Step 1: 写 RideStatus**

创建 `lib/domain/models/ride_status.dart`：

```dart
/// 骑行会话状态。与 `rides.status` 列的取值一一对应。
enum RideStatus {
  recording('recording'),
  paused('paused'),
  finished('finished');

  const RideStatus(this.dbValue);

  /// 写入 SQLite 的字符串值。
  final String dbValue;

  /// 从数据库字符串还原。未知值直接抛错，不静默兜底。
  static RideStatus fromDb(String value) {
    for (final RideStatus s in RideStatus.values) {
      if (s.dbValue == value) return s;
    }
    throw ArgumentError('未知的骑行状态: $value');
  }

  /// 是否属于「未结束」，用于启动时的崩溃恢复扫描。
  bool get isUnfinished => this != RideStatus.finished;
}
```

- [ ] **Step 2: 写 LocationFix**

创建 `lib/domain/models/location_fix.dart`：

```dart
/// 一次定位结果。字段全部可空，因为 GPS 丢失时可能只有时间戳。
class LocationFix {
  const LocationFix({
    required this.tMs,
    this.lat,
    this.lon,
    this.altitudeM,
    this.speedMps,
    this.accuracyM,
  });

  final int tMs;
  final double? lat;
  final double? lon;
  final double? altitudeM;
  final double? speedMps;
  final double? accuracyM;

  bool get hasPosition => lat != null && lon != null;
}
```

- [ ] **Step 3: 写 TrackPoint**

创建 `lib/domain/models/track_point.dart`：

```dart
/// 轨迹点与传感器采样的合并行，对应 `track_points` 表。
///
/// `lat`/`lon` 可空：GPS 丢失时仍记录心率与踏频，这类点只画曲线不上地图。
class TrackPoint {
  const TrackPoint({
    this.id,
    required this.rideId,
    required this.tMs,
    this.lat,
    this.lon,
    this.altitudeM,
    this.speedMps,
    this.accuracyM,
    this.hr,
    this.cadence,
  });

  final int? id;
  final int rideId;
  final int tMs;
  final double? lat;
  final double? lon;
  final double? altitudeM;
  final double? speedMps;
  final double? accuracyM;
  final int? hr;
  final int? cadence;

  bool get hasPosition => lat != null && lon != null;

  Map<String, Object?> toDbMap() => <String, Object?>{
        if (id != null) 'id': id,
        'ride_id': rideId,
        't_ms': tMs,
        'lat': lat,
        'lon': lon,
        'altitude_m': altitudeM,
        'speed_mps': speedMps,
        'accuracy_m': accuracyM,
        'hr': hr,
        'cadence': cadence,
      };

  static TrackPoint fromDbMap(Map<String, Object?> m) => TrackPoint(
        id: (m['id'] as num?)?.toInt(),
        rideId: (m['ride_id'] as num).toInt(),
        tMs: (m['t_ms'] as num).toInt(),
        lat: (m['lat'] as num?)?.toDouble(),
        lon: (m['lon'] as num?)?.toDouble(),
        altitudeM: (m['altitude_m'] as num?)?.toDouble(),
        speedMps: (m['speed_mps'] as num?)?.toDouble(),
        accuracyM: (m['accuracy_m'] as num?)?.toDouble(),
        hr: (m['hr'] as num?)?.toInt(),
        cadence: (m['cadence'] as num?)?.toInt(),
      );
}
```

- [ ] **Step 4: 写 TrackPoint 测试**

创建 `test/domain/models/track_point_test.dart`：

```dart
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toDbMap / fromDbMap 往返保持一致', () {
    const TrackPoint p = TrackPoint(
      id: 7,
      rideId: 3,
      tMs: 1000,
      lat: 31.23,
      lon: 121.47,
      altitudeM: 12.5,
      speedMps: 5.5,
      accuracyM: 4.0,
      hr: 132,
      cadence: 85,
    );

    final TrackPoint back = TrackPoint.fromDbMap(p.toDbMap());

    expect(back.id, 7);
    expect(back.rideId, 3);
    expect(back.tMs, 1000);
    expect(back.lat, 31.23);
    expect(back.lon, 121.47);
    expect(back.altitudeM, 12.5);
    expect(back.speedMps, 5.5);
    expect(back.accuracyM, 4.0);
    expect(back.hr, 132);
    expect(back.cadence, 85);
  });

  test('GPS 丢失的点没有坐标但有传感器数据', () {
    const TrackPoint p = TrackPoint(rideId: 3, tMs: 2000, hr: 140, cadence: 90);

    expect(p.hasPosition, isFalse);
    expect(TrackPoint.fromDbMap(p.toDbMap()).hr, 140);
  });
}
```

- [ ] **Step 5: 运行 TrackPoint 测试**

```bash
fvm flutter test test/domain/models/track_point_test.dart
```

Expected: `All tests passed!`（2 个测试）
若报 `Target of URI doesn't exist: package:cycling_app/...`，检查 `pubspec.yaml` 的 `name:` 是否为 `cycling_app`。

- [ ] **Step 6: 写 RideSummary**

创建 `lib/domain/models/ride_summary.dart`：

```dart
/// 一次骑行的汇总指标。冗余存储在 `rides` 表中，列表页与统计页直接读取。
class RideSummary {
  const RideSummary({
    required this.distanceM,
    required this.durationS,
    required this.movingS,
    required this.avgSpeedMps,
    required this.movingAvgSpeedMps,
    this.maxSpeedMps,
    required this.elevationGainM,
    this.avgHr,
    this.maxHr,
    this.avgCadence,
    this.calories,
    required this.pointCount,
  });

  final double distanceM;
  final int durationS;
  final int movingS;
  final double avgSpeedMps;
  final double movingAvgSpeedMps;

  /// 无速度数据时为 null。
  final double? maxSpeedMps;
  final double elevationGainM;

  /// 无心率数据时为 null。
  final double? avgHr;
  final int? maxHr;

  /// 无踏频数据时为 null。
  final double? avgCadence;

  /// 无心率数据时无法估算，为 null。
  final double? calories;

  final int pointCount;

  Map<String, Object?> toDbColumns() => <String, Object?>{
        'distance_m': distanceM,
        'duration_s': durationS,
        'moving_s': movingS,
        'avg_speed_mps': avgSpeedMps,
        'moving_avg_speed_mps': movingAvgSpeedMps,
        'max_speed_mps': maxSpeedMps,
        'elevation_gain_m': elevationGainM,
        'avg_hr': avgHr,
        'max_hr': maxHr,
        'avg_cadence': avgCadence,
        'calories': calories,
        'point_count': pointCount,
      };

  static RideSummary fromDbColumns(Map<String, Object?> m) => RideSummary(
        distanceM: (m['distance_m'] as num?)?.toDouble() ?? 0,
        durationS: (m['duration_s'] as num?)?.toInt() ?? 0,
        movingS: (m['moving_s'] as num?)?.toInt() ?? 0,
        avgSpeedMps: (m['avg_speed_mps'] as num?)?.toDouble() ?? 0,
        movingAvgSpeedMps: (m['moving_avg_speed_mps'] as num?)?.toDouble() ?? 0,
        maxSpeedMps: (m['max_speed_mps'] as num?)?.toDouble(),
        elevationGainM: (m['elevation_gain_m'] as num?)?.toDouble() ?? 0,
        avgHr: (m['avg_hr'] as num?)?.toDouble(),
        maxHr: (m['max_hr'] as num?)?.toInt(),
        avgCadence: (m['avg_cadence'] as num?)?.toDouble(),
        calories: (m['calories'] as num?)?.toDouble(),
        pointCount: (m['point_count'] as num?)?.toInt() ?? 0,
      );
}
```

- [ ] **Step 7: 写 Ride**

创建 `lib/domain/models/ride.dart`：

```dart
import 'ride_status.dart';
import 'ride_summary.dart';

/// 一次骑行，对应 `rides` 表的一行。
class Ride {
  const Ride({
    this.id,
    required this.startedAtMs,
    this.endedAtMs,
    required this.status,
    this.title,
    this.summary,
    this.hrDeviceName,
    this.cadenceDeviceName,
  });

  final int? id;
  final int startedAtMs;
  final int? endedAtMs;
  final RideStatus status;
  final String? title;

  /// 进行中的骑行为 null。
  final RideSummary? summary;
  final String? hrDeviceName;
  final String? cadenceDeviceName;

  Map<String, Object?> toDbMap() => <String, Object?>{
        if (id != null) 'id': id,
        'started_at': startedAtMs,
        'ended_at': endedAtMs,
        'status': status.dbValue,
        'title': title,
        'hr_device_name': hrDeviceName,
        'cadence_device_name': cadenceDeviceName,
        if (summary != null) ...summary!.toDbColumns(),
      };

  static Ride fromDbMap(Map<String, Object?> m) => Ride(
        id: (m['id'] as num?)?.toInt(),
        startedAtMs: (m['started_at'] as num).toInt(),
        endedAtMs: (m['ended_at'] as num?)?.toInt(),
        status: RideStatus.fromDb(m['status'] as String),
        title: m['title'] as String?,
        summary: m['distance_m'] == null ? null : RideSummary.fromDbColumns(m),
        hrDeviceName: m['hr_device_name'] as String?,
        cadenceDeviceName: m['cadence_device_name'] as String?,
      );
}
```

- [ ] **Step 8: 写 Ride 测试**

创建 `test/domain/models/ride_test.dart`：

```dart
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('进行中的骑行没有汇总指标', () {
    const Ride ride = Ride(startedAtMs: 1000, status: RideStatus.recording);
    final Map<String, Object?> row = ride.toDbMap();

    expect(row['distance_m'], isNull);
    expect(Ride.fromDbMap(<String, Object?>{...row, 'id': 1}).summary, isNull);
  });

  test('已完成的骑行汇总指标往返一致', () {
    const Ride ride = Ride(
      id: 5,
      startedAtMs: 1000,
      endedAtMs: 3601000,
      status: RideStatus.finished,
      title: '晨骑',
      summary: RideSummary(
        distanceM: 25000,
        durationS: 3600,
        movingS: 3400,
        avgSpeedMps: 6.94,
        movingAvgSpeedMps: 7.35,
        maxSpeedMps: 12.5,
        elevationGainM: 180,
        avgHr: 142,
        maxHr: 176,
        avgCadence: 84,
        calories: 720,
        pointCount: 3600,
      ),
      hrDeviceName: 'HUAWEI WATCH FIT 3',
    );

    final Ride back = Ride.fromDbMap(ride.toDbMap());

    expect(back.id, 5);
    expect(back.status, RideStatus.finished);
    expect(back.title, '晨骑');
    expect(back.summary!.distanceM, 25000);
    expect(back.summary!.maxHr, 176);
    expect(back.summary!.calories, 720);
    expect(back.hrDeviceName, 'HUAWEI WATCH FIT 3');
  });

  test('未知状态字符串直接抛错', () {
    expect(() => RideStatus.fromDb('running'), throwsArgumentError);
  });
}
```

- [ ] **Step 9: 运行全部模型测试**

```bash
fvm flutter test test/domain/models
```

Expected: `All tests passed!`（5 个测试）

- [ ] **Step 10: 提交**

```bash
git add -A
git commit -m "feat: 添加 domain 数据模型与数据库行映射"
```

---

## Task 5: analysis — 数值常量与地理计算

**Files:**
- Create: `lib/domain/analysis/constants.dart`
- Create: `lib/domain/analysis/geo.dart`
- Test: `test/domain/analysis/geo_test.dart`

- [ ] **Step 1: 写常量文件**

创建 `lib/domain/analysis/constants.dart`：

```dart
/// 全部数值阈值集中在此处，便于调整与测试。

/// 高程中值滤波窗口（点数，必须为奇数）。见设计文档 8.1。
const int kElevationFilterWindow = 5;

/// 单次上升超过该值（米）才计入爬升。见设计文档 8.1。
const double kElevationGainThresholdM = 1.0;

/// 速度滑动平均窗口（点数，必须为奇数）。见设计文档 8.1。
const int kSpeedFilterWindow = 5;

/// 静止判定速度阈值（m/s），等于 1 km/h。见设计文档 8.2。
const double kStationarySpeedMps = 1.0 / 3.6;

/// 轨迹点写入：与上一点的最小距离（米）。见设计文档 6.3 规则 1。
const double kMinWriteDistanceM = 5.0;

/// 轨迹点写入：距上次写入的最大时间间隔（毫秒）。见设计文档 6.3 规则 1。
const int kMaxWriteIntervalMs = 2000;

/// GPS 断点判定：相邻点时间间隔超过该值视为信号丢失。见设计文档 9.3。
const int kGpsGapMs = 10000;

/// 传感器批量提交点数。见设计文档 6.3 规则 2。
const int kSensorBatchSize = 10;

/// 速度着色的归一化上限（m/s），约 54 km/h。见设计文档 8.2。
const double kColorScaleMaxSpeedMps = 15.0;

/// 物理合理速度上限（m/s），约 108 km/h。
///
/// 这是补充阈值（设计文档 8.1 只列了爬升与最高速两个陷阱）：相邻两点的
/// 隐含速度超过该值时判定为 GPS 跳变，不计入距离、也不计入移动/静止时长。
const double kMaxPlausibleSpeedMps = 30.0;
```

- [ ] **Step 2: 写失败测试**

创建 `test/domain/analysis/geo_test.dart`：

```dart
import 'package:cycling_app/domain/analysis/geo.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('haversineMeters', () {
    test('同一点距离为 0', () {
      expect(haversineMeters(31.23, 121.47, 31.23, 121.47), 0);
    });

    test('北纬 31.23 处经度相差 0.01 度约等于 950.8 米', () {
      expect(haversineMeters(31.23, 121.47, 31.23, 121.48), closeTo(950.8, 1.0));
    });

    test('纬度相差 0.01 度约等于 1111.9 米', () {
      expect(haversineMeters(31.23, 121.47, 31.24, 121.47), closeTo(1111.9, 1.0));
    });
  });

  group('segmentDistanceMeters', () {
    test('正常相邻两点返回实际距离', () {
      expect(
        segmentDistanceMeters(_p(0, 31.23, 121.47), _p(1000, 31.23, 121.471)),
        closeTo(950.8, 1.0),
      );
    });

    test('任一缺坐标时返回 0', () {
      expect(segmentDistanceMeters(_p(0, 31.23, 121.47), _p(1000, null, null)), 0);
    });

    test('时间间隔超过 10 秒的 GPS 断点返回 0', () {
      expect(segmentDistanceMeters(_p(0, 31.23, 121.47), _p(11000, 31.23, 121.48)), 0);
    });

    test('时间不前进时返回 0', () {
      expect(segmentDistanceMeters(_p(1000, 31.23, 121.47), _p(1000, 31.23, 121.48)), 0);
    });

    test('隐含速度超过上限的 GPS 跳变返回 0', () {
      // 1 秒内跳了约 140 公里
      expect(segmentDistanceMeters(_p(0, 31.23, 121.47), _p(1000, 32.23, 122.47)), 0);
    });
  });
}

TrackPoint _p(int tMs, double? lat, double? lon) =>
    TrackPoint(rideId: 1, tMs: tMs, lat: lat, lon: lon);
```

- [ ] **Step 3: 运行测试确认失败**

```bash
fvm flutter test test/domain/analysis/geo_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist: 'package:cycling_app/domain/analysis/geo.dart'`。

- [ ] **Step 4: 写实现**

创建 `lib/domain/analysis/geo.dart`：

```dart
import 'dart:math' as math;

import '../models/track_point.dart';
import 'constants.dart';

/// 地球平均半径（米），IUGG 平均半径。
const double kEarthRadiusM = 6371008.8;

double _toRadians(double degrees) => degrees * math.pi / 180.0;

/// 两点间大圆距离（米）。
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  final double dLat = _toRadians(lat2 - lat1);
  final double dLon = _toRadians(lon2 - lon1);
  final double sinHalfLat = math.sin(dLat / 2);
  final double sinHalfLon = math.sin(dLon / 2);
  final double a = sinHalfLat * sinHalfLat +
      math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) * sinHalfLon * sinHalfLon;
  return 2 * kEarthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
}

/// 相邻两个轨迹点之间的有效距离（米）。
///
/// 下列情况返回 0，即视为「不可信，不连线也不计距离」：
/// - 任一端点缺坐标（GPS 丢失）
/// - 时间不前进
/// - 时间间隔超过 [kGpsGapMs]（设计文档 9.3 的 GPS 断点）
/// - 隐含速度超过 [kMaxPlausibleSpeedMps]（GPS 跳变）
double segmentDistanceMeters(TrackPoint a, TrackPoint b) {
  if (!a.hasPosition || !b.hasPosition) return 0;
  final int dtMs = b.tMs - a.tMs;
  if (dtMs <= 0 || dtMs > kGpsGapMs) return 0;
  final double d = haversineMeters(a.lat!, a.lon!, b.lat!, b.lon!);
  if (d / (dtMs / 1000.0) > kMaxPlausibleSpeedMps) return 0;
  return d;
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
fvm flutter test test/domain/analysis/geo_test.dart
```

Expected: `All tests passed!`（8 个测试）

- [ ] **Step 6: 提交**

```bash
git add -A
git commit -m "feat: 添加数值常量与 Haversine 距离计算"
```

---

## Task 6: analysis — 高程滤波与爬升

设计文档 8.1 陷阱 1：原始高程噪声会把 100m 爬升算成 800m。

**Files:**
- Create: `lib/domain/analysis/elevation.dart`
- Test: `test/domain/analysis/elevation_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/domain/analysis/elevation_test.dart`：

```dart
import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/analysis/elevation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('medianFilterElevation', () {
    test('窗口为 5 时输出等长序列', () {
      final List<double?> raw = <double?>[100, 100.5, 99.8, 100.2, 99.9, 100.4, 100.0];
      expect(medianFilterElevation(raw, kElevationFilterWindow).length, raw.length);
    });

    test('空值邻域内仍有非空值时会被填充', () {
      final List<double?> out = medianFilterElevation(<double?>[100, null, 102, null, 104], 3);
      expect(out[1], closeTo(101, 1e-9));
      expect(out[3], closeTo(103, 1e-9));
    });
  });

  group('elevationGainMeters', () {
    test('平坦高程噪声不产生爬升', () {
      final List<double?> raw = <double?>[100, 100.5, 99.8, 100.2, 99.9, 100.4, 100.0];
      final List<double?> filtered = medianFilterElevation(raw, kElevationFilterWindow);
      expect(elevationGainMeters(filtered, kElevationGainThresholdM), 0);
    });

    test('线性爬升被完整累加', () {
      final List<double?> raw = <double?>[100, 101, 102, 103, 104, 105, 106];
      final List<double?> filtered = medianFilterElevation(raw, kElevationFilterWindow);
      expect(elevationGainMeters(filtered, kElevationGainThresholdM), closeTo(6, 1e-9));
    });

    test('锯齿噪声不放大爬升', () {
      // 原始序列逐点波动约 4 米，中值滤波后应回到单调上升
      final List<double?> raw = <double?>[100, 103, 99, 104, 100, 105, 101, 106, 102, 107];
      final List<double?> filtered = medianFilterElevation(raw, kElevationFilterWindow);
      final double gain = elevationGainMeters(filtered, kElevationGainThresholdM);
      expect(gain, greaterThan(3));
      expect(gain, lessThan(8));
    });

    test('下降段不计入爬升', () {
      final List<double?> raw = <double?>[200, 190, 180, 170, 160, 150];
      final List<double?> filtered = medianFilterElevation(raw, kElevationFilterWindow);
      expect(elevationGainMeters(filtered, kElevationGainThresholdM), 0);
    });

    test('空值被跳过', () {
      final List<double?> out = medianFilterElevation(<double?>[100, null, 102, null, 104], 3);
      expect(elevationGainMeters(out, kElevationGainThresholdM), closeTo(4, 1e-9));
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
fvm flutter test test/domain/analysis/elevation_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写实现**

创建 `lib/domain/analysis/elevation.dart`：

```dart
import 'dart:math' as math;

/// 对可空高程序列做中值滤波，窗口以当前点为中心并裁剪到序列边界。
/// 窗口内只统计非空值；窗口内全为空时输出 null。
List<double?> medianFilterElevation(List<double?> values, int window) {
  assert(window.isOdd && window > 0, '窗口必须为正奇数');
  final int half = window ~/ 2;
  final List<double?> out = List<double?>.filled(values.length, null);
  for (int i = 0; i < values.length; i++) {
    final int start = math.max(0, i - half);
    final int end = math.min(values.length - 1, i + half);
    final List<double> buf = <double>[];
    for (int j = start; j <= end; j++) {
      final double? v = values[j];
      if (v != null) buf.add(v);
    }
    if (buf.isEmpty) continue;
    buf.sort();
    out[i] = buf.length.isOdd
        ? buf[buf.length ~/ 2]
        : (buf[buf.length ~/ 2 - 1] + buf[buf.length ~/ 2]) / 2;
  }
  return out;
}

/// 累加单次上升超过 [thresholdM] 的区段，得到总爬升（米）。
///
/// 用「滞回」方式实现：小幅波动不推进基准点，因此缓慢但持续的爬坡会被
/// 正确累加，而上下抖动不会；下降超过阈值时才把基准点下移。
double elevationGainMeters(List<double?> filtered, double thresholdM) {
  double gain = 0;
  double? baseline;
  for (final double? v in filtered) {
    if (v == null) continue;
    if (baseline == null) {
      baseline = v;
      continue;
    }
    final double delta = v - baseline;
    if (delta >= thresholdM) {
      gain += delta;
      baseline = v;
    } else if (delta <= -thresholdM) {
      baseline = v;
    }
  }
  return gain;
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
fvm flutter test test/domain/analysis/elevation_test.dart
```

Expected: `All tests passed!`（7 个测试）

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat: 添加高程中值滤波与爬升累加"
```

---

## Task 7: analysis — 速度平滑与移动/静止判定

设计文档 8.1 陷阱 2 与 8.2 的移动均速定义。

**Files:**
- Create: `lib/domain/analysis/speed.dart`
- Test: `test/domain/analysis/speed_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/domain/analysis/speed_test.dart`：

```dart
import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/analysis/speed.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('maxSmoothedSpeed', () {
    test('单点毛刺被滑动平均抹平', () {
      final List<double?> speeds = <double?>[5, 5, 5, 30, 5, 5, 5];
      expect(maxSmoothedSpeed(speeds, kSpeedFilterWindow), closeTo(5, 1e-9));
    });

    test('持续高速保留真实峰值', () {
      final List<double?> speeds = <double?>[5, 5, 12, 12, 12, 12, 12, 5, 5];
      expect(maxSmoothedSpeed(speeds, kSpeedFilterWindow), closeTo(12, 1e-9));
    });

    test('全部为空时返回 null', () {
      expect(maxSmoothedSpeed(<double?>[null, null], kSpeedFilterWindow), isNull);
    });
  });

  group('splitMovingStationary', () {
    test('等红灯的时间计入静止', () {
      final List<TrackPoint> points = <TrackPoint>[
        _p(0, 5.0),
        _p(1000, 5.0),
        _p(2000, 0.1),
        _p(3000, 0.1),
        _p(4000, 5.0),
      ];
      final MovingStats s = splitMovingStationary(points, kStationarySpeedMps);
      expect(s.movingSeconds, closeTo(2.0, 1e-9));
      expect(s.stationarySeconds, closeTo(2.0, 1e-9));
    });

    test('超过 10 秒的 GPS 断点两个区间都不计入', () {
      final MovingStats s =
          splitMovingStationary(<TrackPoint>[_p(0, 5.0), _p(15000, 5.0)], kStationarySpeedMps);
      expect(s.movingSeconds, 0);
      expect(s.stationarySeconds, 0);
    });

    test('缺速度的区间不计入', () {
      final MovingStats s =
          splitMovingStationary(<TrackPoint>[_p(0, null), _p(1000, null)], kStationarySpeedMps);
      expect(s.movingSeconds, 0);
      expect(s.stationarySeconds, 0);
    });
  });
}

TrackPoint _p(int tMs, double? speed) => TrackPoint(rideId: 1, tMs: tMs, speedMps: speed);
```

- [ ] **Step 2: 运行测试确认失败**

```bash
fvm flutter test test/domain/analysis/speed_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写实现**

创建 `lib/domain/analysis/speed.dart`：

```dart
import 'dart:math' as math;

import '../models/track_point.dart';
import 'constants.dart';

/// 滑动平均，窗口以当前点为中心并裁剪到序列边界。
/// 窗口内只统计非空值；窗口内全为空时输出 null。
List<double?> movingAverage(List<double?> values, int window) {
  assert(window > 0, '窗口必须为正数');
  final int half = window ~/ 2;
  final List<double?> out = List<double?>.filled(values.length, null);
  for (int i = 0; i < values.length; i++) {
    final int start = math.max(0, i - half);
    final int end = math.min(values.length - 1, i + half);
    double sum = 0;
    int count = 0;
    for (int j = start; j <= end; j++) {
      final double? v = values[j];
      if (v == null) continue;
      sum += v;
      count++;
    }
    if (count > 0) out[i] = sum / count;
  }
  return out;
}

/// 滑动平均后的峰值速度（m/s）。无数据时返回 null。
double? maxSmoothedSpeed(List<double?> speeds, int window) {
  double? best;
  for (final double? v in movingAverage(speeds, window)) {
    if (v == null) continue;
    if (best == null || v > best) best = v;
  }
  return best;
}

/// 移动时长与静止时长（秒）。
class MovingStats {
  const MovingStats({required this.movingSeconds, required this.stationarySeconds});

  final double movingSeconds;
  final double stationarySeconds;
}

/// 按速度阈值切分移动/静止时长。
///
/// 以相邻两点的时间差作为该区间的时长，速度取区间末点的瞬时速度。
/// 时间不前进、缺速度、或间隔超过 [kGpsGapMs] 的区间不计入任何一侧
/// —— 后者与设计文档 9.3 的 GPS 断点定义保持一致。
MovingStats splitMovingStationary(List<TrackPoint> points, double thresholdMps) {
  double moving = 0;
  double stationary = 0;
  for (int i = 1; i < points.length; i++) {
    final int dtMs = points[i].tMs - points[i - 1].tMs;
    if (dtMs <= 0 || dtMs > kGpsGapMs) continue;
    final double? v = points[i].speedMps;
    if (v == null) continue;
    final double dt = dtMs / 1000.0;
    if (v < thresholdMps) {
      stationary += dt;
    } else {
      moving += dt;
    }
  }
  return MovingStats(movingSeconds: moving, stationarySeconds: stationary);
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
fvm flutter test test/domain/analysis/speed_test.dart
```

Expected: `All tests passed!`（6 个测试）

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat: 添加速度平滑与移动静止判定"
```

---

## Task 8: analysis — 心率区间与卡路里

设计文档 8.2 的心率五区定义与卡路里估算。

**Files:**
- Create: `lib/domain/analysis/heart_rate.dart`
- Create: `lib/domain/analysis/calories.dart`
- Test: `test/domain/analysis/heart_rate_test.dart`
- Test: `test/domain/analysis/calories_test.dart`

- [ ] **Step 1: 写心率区间的失败测试**

创建 `test/domain/analysis/heart_rate_test.dart`：

```dart
import 'package:cycling_app/domain/analysis/heart_rate.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('zoneIndexForHr', () {
    test('边界值归入更高的区间', () {
      expect(zoneIndexForHr(120, 200), 2); // 恰好 60%
      expect(zoneIndexForHr(140, 200), 3); // 恰好 70%
      expect(zoneIndexForHr(160, 200), 4); // 恰好 80%
      expect(zoneIndexForHr(180, 200), 5); // 恰好 90%
    });

    test('边界下方归入更低的区间', () {
      expect(zoneIndexForHr(119, 200), 1);
      expect(zoneIndexForHr(139, 200), 2);
      expect(zoneIndexForHr(159, 200), 3);
      expect(zoneIndexForHr(179, 200), 4);
    });

    test('超出最大心率仍归入 Z5', () {
      expect(zoneIndexForHr(210, 200), 5);
    });

    test('最大心率非正数时返回 null', () {
      expect(zoneIndexForHr(120, 0), isNull);
    });
  });

  group('hrZoneBreakdown', () {
    test('按区间停留时长累计并给出占比', () {
      final List<TrackPoint> points = <TrackPoint>[
        _p(0, 120),
        _p(1000, 120), // Z2
        _p(2000, 160), // Z4
        _p(3000, 160), // Z4
        _p(4000, 190), // Z5
      ];
      final HrZoneBreakdown b = hrZoneBreakdown(points, 200);

      expect(b.totalSeconds, closeTo(4.0, 1e-9));
      expect(b.secondsByZone[2], closeTo(1.0, 1e-9));
      expect(b.secondsByZone[4], closeTo(2.0, 1e-9));
      expect(b.secondsByZone[5], closeTo(1.0, 1e-9));
      expect(b.ratioOf(4), closeTo(0.5, 1e-9));
    });

    test('没有心率数据时总时长为 0', () {
      final List<TrackPoint> points = <TrackPoint>[_p(0, null), _p(1000, null)];
      expect(hrZoneBreakdown(points, 200).totalSeconds, 0);
    });
  });
}

TrackPoint _p(int tMs, int? hr) => TrackPoint(rideId: 1, tMs: tMs, hr: hr);
```

- [ ] **Step 2: 运行测试确认失败**

```bash
fvm flutter test test/domain/analysis/heart_rate_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写心率区间实现**

创建 `lib/domain/analysis/heart_rate.dart`：

```dart
import '../models/track_point.dart';
import 'constants.dart';

/// 心率区间定义。区间为左闭右开：[minRatio, maxRatio)。
class HrZone {
  const HrZone({
    required this.index,
    required this.label,
    required this.minRatio,
    required this.maxRatio,
  });

  final int index;
  final String label;
  final double minRatio;
  final double maxRatio;
}

/// 按最大心率的百分比切分的五个区间。见设计文档 8.2。
const List<HrZone> kHrZones = <HrZone>[
  HrZone(index: 1, label: 'Z1 恢复', minRatio: 0.0, maxRatio: 0.6),
  HrZone(index: 2, label: 'Z2 耐力', minRatio: 0.6, maxRatio: 0.7),
  HrZone(index: 3, label: 'Z3 节奏', minRatio: 0.7, maxRatio: 0.8),
  HrZone(index: 4, label: 'Z4 阈值', minRatio: 0.8, maxRatio: 0.9),
  HrZone(index: 5, label: 'Z5 无氧', minRatio: 0.9, maxRatio: double.infinity),
];

/// 心率落在哪个区间（1..5）。[maxHeartRate] 非正数时返回 null。
int? zoneIndexForHr(int hr, int maxHeartRate) {
  if (maxHeartRate <= 0) return null;
  final double ratio = hr / maxHeartRate;
  for (final HrZone z in kHrZones) {
    if (ratio >= z.minRatio && ratio < z.maxRatio) return z.index;
  }
  return kHrZones.last.index;
}

/// 各心率区间的停留时长分布。
class HrZoneBreakdown {
  const HrZoneBreakdown({required this.secondsByZone, required this.totalSeconds});

  final Map<int, double> secondsByZone;
  final double totalSeconds;

  double ratioOf(int zoneIndex) =>
      totalSeconds <= 0 ? 0 : (secondsByZone[zoneIndex] ?? 0) / totalSeconds;
}

/// 按相邻点的时间差把时长归入各心率区间。
/// 时间不前进、缺心率、或间隔超过 [kGpsGapMs] 的区间不计入。
HrZoneBreakdown hrZoneBreakdown(List<TrackPoint> points, int maxHeartRate) {
  final Map<int, double> seconds = <int, double>{};
  double total = 0;
  for (int i = 1; i < points.length; i++) {
    final int dtMs = points[i].tMs - points[i - 1].tMs;
    if (dtMs <= 0 || dtMs > kGpsGapMs) continue;
    final int? hr = points[i].hr;
    if (hr == null) continue;
    final int? zone = zoneIndexForHr(hr, maxHeartRate);
    if (zone == null) continue;
    final double dt = dtMs / 1000.0;
    seconds[zone] = (seconds[zone] ?? 0) + dt;
    total += dt;
  }
  return HrZoneBreakdown(secondsByZone: seconds, totalSeconds: total);
}

/// 时长时间加权的心率均值。无心率数据时返回 null。
double? averageHr(List<TrackPoint> points) {
  double weighted = 0;
  double total = 0;
  for (int i = 1; i < points.length; i++) {
    final int dtMs = points[i].tMs - points[i - 1].tMs;
    if (dtMs <= 0 || dtMs > kGpsGapMs) continue;
    final int? hr = points[i].hr;
    if (hr == null) continue;
    final double dt = dtMs / 1000.0;
    weighted += hr * dt;
    total += dt;
  }
  return total <= 0 ? null : weighted / total;
}

/// 出现过的最高心率。无心率数据时返回 null。
int? observedMaxHr(List<TrackPoint> points) {
  int? best;
  for (final TrackPoint p in points) {
    final int? hr = p.hr;
    if (hr == null) continue;
    if (best == null || hr > best) best = hr;
  }
  return best;
}
```

- [ ] **Step 4: 运行心率测试确认通过**

```bash
fvm flutter test test/domain/analysis/heart_rate_test.dart
```

Expected: `All tests passed!`（6 个测试）

- [ ] **Step 5: 写卡路里的失败测试**

创建 `test/domain/analysis/calories_test.dart`：

```dart
import 'package:cycling_app/domain/analysis/calories.dart';
import 'package:cycling_app/domain/analysis/heart_rate.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('30 分钟 Z2 区间、70kg 体重约 210 千卡', () {
    // MET 6 × 70kg × 0.5h = 210
    const HrZoneBreakdown zones = HrZoneBreakdown(
      secondsByZone: <int, double>{2: 1800},
      totalSeconds: 1800,
    );
    expect(estimateCalories(zones: zones, weightKg: 70), closeTo(210, 1e-9));
  });

  test('强度越高同一时长消耗越多', () {
    const HrZoneBreakdown easy = HrZoneBreakdown(
      secondsByZone: <int, double>{2: 1800},
      totalSeconds: 1800,
    );
    const HrZoneBreakdown hard = HrZoneBreakdown(
      secondsByZone: <int, double>{5: 1800},
      totalSeconds: 1800,
    );
    final double? low = estimateCalories(zones: easy, weightKg: 70);
    final double? high = estimateCalories(zones: hard, weightKg: 70);
    expect(high! > low!, isTrue);
  });

  test('没有心率数据时返回 null', () {
    final HrZoneBreakdown zones = hrZoneBreakdown(
      <TrackPoint>[TrackPoint(rideId: 1, tMs: 0), TrackPoint(rideId: 1, tMs: 1000)],
      190,
    );
    expect(estimateCalories(zones: zones, weightKg: 70), isNull);
  });

  test('体重非正数时返回 null', () {
    const HrZoneBreakdown zones = HrZoneBreakdown(
      secondsByZone: <int, double>{2: 1800},
      totalSeconds: 1800,
    );
    expect(estimateCalories(zones: zones, weightKg: 0), isNull);
  });
}
```

- [ ] **Step 6: 写卡路里实现**

创建 `lib/domain/analysis/calories.dart`：

```dart
import 'heart_rate.dart';

/// 各心率区间对应的 MET 系数（骑行，估算用）。
const Map<int, double> kZoneMet = <int, double>{
  1: 4.0, // 轻松骑行
  2: 6.0, // 中等强度
  3: 8.0, // 较大强度
  4: 10.0, // 高强度
  5: 12.0, // 极限强度
};

/// 卡路里估算：按各心率区间停留时长做 MET 加权。
///
/// `kcal = Σ(MET_i × 体重kg × 该区间小时数)`。这是参考值，不是精确测量。
/// 无心率数据或体重非正数时返回 null，UI 显示为「—」。
double? estimateCalories({required HrZoneBreakdown zones, required double weightKg}) {
  if (weightKg <= 0) return null;
  if (zones.totalSeconds <= 0) return null;
  double kcal = 0;
  kZoneMet.forEach((int zone, double met) {
    final double hours = (zones.secondsByZone[zone] ?? 0) / 3600.0;
    kcal += met * weightKg * hours;
  });
  return kcal;
}
```

- [ ] **Step 7: 运行测试确认通过**

```bash
fvm flutter test test/domain/analysis
```

Expected: `All tests passed!`

- [ ] **Step 8: 提交**

```bash
git add -A
git commit -m "feat: 添加心率区间与卡路里估算"
```

---

## Task 9: analysis — 速度到颜色的映射

设计文档 8.2：同一函数同时用于速度曲线与地图轨迹着色。

**Files:**
- Create: `lib/domain/analysis/color_scale.dart`
- Test: `test/domain/analysis/color_scale_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/domain/analysis/color_scale_test.dart`：

```dart
import 'package:cycling_app/domain/analysis/color_scale.dart';
import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('速度为 0 时返回色带起点', () {
    expect(speedColorArgb(0), kSpeedColorSlow);
  });

  test('速度达到上限时返回色带终点', () {
    expect(speedColorArgb(kColorScaleMaxSpeedMps), kSpeedColorFast);
  });

  test('超出上限被钳制到终点', () {
    expect(speedColorArgb(100), kSpeedColorFast);
  });

  test('中点为色带中段色', () {
    expect(speedColorArgb(kColorScaleMaxSpeedMps / 2), kSpeedColorMid);
  });

  test('速度越快颜色越深', () {
    final int slow = speedColorArgb(2);
    final int mid = speedColorArgb(7.5);
    final int fast = speedColorArgb(14);
    expect(_luminance(slow), greaterThan(_luminance(mid)));
    expect(_luminance(mid), greaterThan(_luminance(fast)));
  });

  test('输出不透明', () {
    expect(speedColorArgb(5) >> 24 & 0xFF, 0xFF);
  });
}

/// 感知亮度，用于验证「越快越深」。
double _luminance(int argb) {
  final int r = (argb >> 16) & 0xFF;
  final int g = (argb >> 8) & 0xFF;
  final int b = argb & 0xFF;
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
fvm flutter test test/domain/analysis/color_scale_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写实现**

创建 `lib/domain/analysis/color_scale.dart`：

```dart
import 'dart:math' as math;

import 'constants.dart';

/// 色带起点：慢（浅黄）。
const int kSpeedColorSlow = 0xFFFFF176;

/// 色带中段：中速（橙）。
const int kSpeedColorMid = 0xFFFB8C00;

/// 色带终点：快（深红）。
const int kSpeedColorFast = 0xFFB71C1C;

/// 速度到颜色的映射，返回 0xAARRGGBB 整数。
///
/// 返回 int 而不是 `Color`，是为了让 domain 层不依赖 Flutter。
/// UI 层用 `Color(speedColorArgb(v))` 转换即可。
/// 速度越快颜色越深；超出 [maxSpeedMps] 的部分被钳制。
int speedColorArgb(double speedMps, {double maxSpeedMps = kColorScaleMaxSpeedMps}) {
  final double t = (speedMps / maxSpeedMps).clamp(0.0, 1.0);
  if (t <= 0.5) {
    return _lerpArgb(kSpeedColorSlow, kSpeedColorMid, t * 2);
  }
  return _lerpArgb(kSpeedColorMid, kSpeedColorFast, (t - 0.5) * 2);
}

int _lerpArgb(int from, int to, double t) {
  final int a = _lerpChannel((from >> 24) & 0xFF, (to >> 24) & 0xFF, t);
  final int r = _lerpChannel((from >> 16) & 0xFF, (to >> 16) & 0xFF, t);
  final int g = _lerpChannel((from >> 8) & 0xFF, (to >> 8) & 0xFF, t);
  final int b = _lerpChannel(from & 0xFF, to & 0xFF, t);
  return (a << 24) | (r << 16) | (g << 8) | b;
}

int _lerpChannel(int from, int to, double t) =>
    (from + (to - from) * t).round().clamp(0, 255).toInt();

/// 两个速度之间的线段颜色，取平均速度着色。供地图轨迹分段使用。
int segmentColorArgb(
  double speedA,
  double speedB, {
  double maxSpeedMps = kColorScaleMaxSpeedMps,
}) =>
    speedColorArgb(math.max(0, (speedA + speedB) / 2), maxSpeedMps: maxSpeedMps);
```

- [ ] **Step 4: 运行测试确认通过**

```bash
fvm flutter test test/domain/analysis/color_scale_test.dart
```

Expected: `All tests passed!`（6 个测试）

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat: 添加速度到颜色的映射函数"
```

---

## Task 10: analysis — computeSummary 汇总

设计文档 8.3：骑行结束时调用一次，结果写入 `rides` 的汇总字段。

**Files:**
- Create: `lib/domain/analysis/summary.dart`
- Test: `test/domain/analysis/summary_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/domain/analysis/summary_test.dart`：

```dart
import 'package:cycling_app/domain/analysis/geo.dart';
import 'package:cycling_app/domain/analysis/summary.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('距离按时长与坐标累加，均速按总时长、移动均速按移动时长', () {
    final List<TrackPoint> points = <TrackPoint>[
      _p(0, 121.4700, speed: 5.0, alt: 10),
      _p(1000, 121.4701, speed: 5.0, alt: 10),
      _p(2000, 121.4702, speed: 0.0, alt: 10),
      _p(3000, 121.4703, speed: 0.0, alt: 10),
    ];
    final double segment = haversineMeters(31.23, 121.4700, 31.23, 121.4701);

    final RideSummary s = computeSummary(
      points: points,
      durationS: 4,
      maxHeartRate: 190,
      weightKg: 70,
    );

    expect(s.distanceM, closeTo(segment * 3, 1e-6));
    expect(s.durationS, 4);
    expect(s.movingS, 2);
    expect(s.avgSpeedMps, closeTo(segment * 3 / 4, 1e-6));
    expect(s.movingAvgSpeedMps, closeTo(segment * 3 / 2, 1e-6));
    expect(s.elevationGainM, 0);
    expect(s.pointCount, 4);
    expect(s.maxHr, isNull);
    expect(s.calories, isNull);
  });

  test('GPS 跳变不计入距离', () {
    final RideSummary s = computeSummary(
      points: <TrackPoint>[_p(0, 121.47, speed: 5.0), _p(1000, 122.47, lat: 32.23, speed: 5.0)],
      durationS: 1,
      maxHeartRate: 190,
      weightKg: 70,
    );
    expect(s.distanceM, 0);
  });

  test('爬升经过滤波后累加，最高速经过平滑后取峰值', () {
    final List<TrackPoint> points = <TrackPoint>[
      _p(0, 121.4700, alt: 100, speed: 5),
      _p(1000, 121.4701, alt: 101, speed: 5),
      _p(2000, 121.4702, alt: 102, speed: 30),
      _p(3000, 121.4703, alt: 103, speed: 5),
      _p(4000, 121.4704, alt: 104, speed: 5),
      _p(5000, 121.4705, alt: 105, speed: 5),
    ];
    final RideSummary s = computeSummary(
      points: points,
      durationS: 5,
      maxHeartRate: 190,
      weightKg: 70,
    );
    expect(s.elevationGainM, closeTo(5, 1e-9));
    expect(s.maxSpeedMps! < 30, isTrue);
  });

  test('有心率时给出心率均值、峰值与卡路里', () {
    final List<TrackPoint> points = <TrackPoint>[
      _p(0, 121.4700, speed: 5, hr: 120),
      _p(1000, 121.4701, speed: 5, hr: 120),
      _p(2000, 121.4702, speed: 5, hr: 120),
    ];
    final RideSummary s = computeSummary(
      points: points,
      durationS: 2,
      maxHeartRate: 200,
      weightKg: 70,
    );
    expect(s.avgHr, closeTo(120, 1e-9));
    expect(s.maxHr, 120);
    // 2 秒全在 Z2（MET 6）：6 × 70 × 2 / 3600
    expect(s.calories, closeTo(6 * 70 * 2 / 3600, 1e-9));
  });

  test('空轨迹返回全零汇总', () {
    final RideSummary s = computeSummary(
      points: const <TrackPoint>[],
      durationS: 0,
      maxHeartRate: 190,
      weightKg: 70,
    );
    expect(s.distanceM, 0);
    expect(s.pointCount, 0);
    expect(s.avgSpeedMps, 0);
    expect(s.movingAvgSpeedMps, 0);
  });
}

TrackPoint _p(
  int tMs,
  double lon, {
  double lat = 31.23,
  double? alt,
  double? speed,
  int? hr,
}) =>
    TrackPoint(
      rideId: 1,
      tMs: tMs,
      lat: lat,
      lon: lon,
      altitudeM: alt,
      speedMps: speed,
      hr: hr,
    );
```

- [ ] **Step 2: 运行测试确认失败**

```bash
fvm flutter test test/domain/analysis/summary_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写实现**

创建 `lib/domain/analysis/summary.dart`：

```dart
import '../models/ride_summary.dart';
import '../models/track_point.dart';
import 'calories.dart';
import 'constants.dart';
import 'elevation.dart';
import 'geo.dart';
import 'heart_rate.dart';
import 'speed.dart';

/// 由轨迹点算出一次骑行的全部汇总指标。
///
/// [durationS] 由调用方给出：正常结束时用会话累计时长（不含暂停），
/// 崩溃恢复结算时用「末点时间 − 起始时间」近似。
RideSummary computeSummary({
  required List<TrackPoint> points,
  required int durationS,
  required int maxHeartRate,
  required double weightKg,
}) {
  double distanceM = 0;
  for (int i = 1; i < points.length; i++) {
    distanceM += segmentDistanceMeters(points[i - 1], points[i]);
  }

  final MovingStats moving = splitMovingStationary(points, kStationarySpeedMps);

  final double elevationGainM = elevationGainMeters(
    medianFilterElevation(
      <double?>[for (final TrackPoint p in points) p.altitudeM],
      kElevationFilterWindow,
    ),
    kElevationGainThresholdM,
  );

  final double? maxSpeedMps = maxSmoothedSpeed(
    <double?>[for (final TrackPoint p in points) p.speedMps],
    kSpeedFilterWindow,
  );

  final HrZoneBreakdown zones = hrZoneBreakdown(points, maxHeartRate);

  final List<double> cadences = <double>[
    for (final TrackPoint p in points)
      if (p.cadence != null) p.cadence!.toDouble(),
  ];

  final int movingS = moving.movingSeconds.round();

  return RideSummary(
    distanceM: distanceM,
    durationS: durationS,
    movingS: movingS,
    avgSpeedMps: durationS <= 0 ? 0 : distanceM / durationS,
    movingAvgSpeedMps: movingS <= 0 ? 0 : distanceM / movingS,
    maxSpeedMps: maxSpeedMps,
    elevationGainM: elevationGainM,
    avgHr: averageHr(points),
    maxHr: observedMaxHr(points),
    avgCadence: cadences.isEmpty
        ? null
        : cadences.reduce((double a, double b) => a + b) / cadences.length,
    calories: estimateCalories(zones: zones, weightKg: weightKg),
    pointCount: points.length,
  );
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
fvm flutter test test/domain/analysis/summary_test.dart
```

Expected: `All tests passed!`（5 个测试）

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat: 添加 computeSummary 汇总计算"
```

---

## Task 11: analysis — BLE 数据帧解析

把 BLE 协议解析做成纯函数，就能在没有硬件的情况下用单测覆盖掉最容易出错的位运算。

**Files:**
- Create: `lib/domain/analysis/ble_payload.dart`
- Test: `test/domain/analysis/ble_payload_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/domain/analysis/ble_payload_test.dart`：

```dart
import 'package:cycling_app/domain/analysis/ble_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseHeartRateMeasurement', () {
    test('flags 最低位为 0 时心率是 1 字节', () {
      expect(parseHeartRateMeasurement(<int>[0x00, 72]), 72);
    });

    test('flags 最低位为 1 时心率是 2 字节小端', () {
      expect(parseHeartRateMeasurement(<int>[0x01, 0x2C, 0x01]), 300);
    });

    test('带能量消耗字段时仍能正确取到心率', () {
      // flags=0x08 表示后面有能量消耗字段，心率仍在第 2 字节
      expect(parseHeartRateMeasurement(<int>[0x08, 88, 0x10, 0x00]), 88);
    });

    test('数据过短返回 null', () {
      expect(parseHeartRateMeasurement(<int>[]), isNull);
      expect(parseHeartRateMeasurement(<int>[0x01, 0x2C]), isNull);
    });
  });

  group('parseCscMeasurement', () {
    test('只有曲柄数据时解析转数与事件时间', () {
      // flags=0x02（仅曲柄），转数=1，事件时间=1024
      final CscMeasurement? m = parseCscMeasurement(<int>[0x02, 0x01, 0x00, 0x00, 0x04]);
      expect(m!.crankRevolutions, 1);
      expect(m.crankEventTime1024, 1024);
    });

    test('同时有车轮数据时跳过前 6 字节', () {
      final CscMeasurement? m = parseCscMeasurement(
        <int>[0x03, 0, 0, 0, 0, 0, 0, 0x05, 0x00, 0x00, 0x08],
      );
      expect(m!.crankRevolutions, 5);
      expect(m.crankEventTime1024, 2048);
    });

    test('没有曲柄数据返回 null', () {
      expect(parseCscMeasurement(<int>[0x01, 0, 0, 0, 0, 0, 0]), isNull);
    });

    test('数据过短返回 null', () {
      expect(parseCscMeasurement(<int>[0x02, 0x01]), isNull);
    });
  });

  group('cadenceRpm', () {
    test('1 秒转 1 圈等于 60 rpm', () {
      const CscMeasurement prev = CscMeasurement(crankRevolutions: 0, crankEventTime1024: 0);
      const CscMeasurement cur = CscMeasurement(crankRevolutions: 1, crankEventTime1024: 1024);
      expect(cadenceRpm(prev, cur), closeTo(60, 1e-9));
    });

    test('16 位回绕时仍能算出正确踏频', () {
      const CscMeasurement prev =
          CscMeasurement(crankRevolutions: 65535, crankEventTime1024: 65535);
      const CscMeasurement cur = CscMeasurement(crankRevolutions: 0, crankEventTime1024: 1023);
      expect(cadenceRpm(prev, cur), closeTo(60, 1e-9));
    });

    test('事件时间未前进时返回 null', () {
      const CscMeasurement m = CscMeasurement(crankRevolutions: 5, crankEventTime1024: 100);
      expect(cadenceRpm(m, m), isNull);
    });

    test('间隔超过 5 秒返回 null', () {
      const CscMeasurement prev = CscMeasurement(crankRevolutions: 0, crankEventTime1024: 0);
      const CscMeasurement cur =
          CscMeasurement(crankRevolutions: 5, crankEventTime1024: 1024 * 6);
      expect(cadenceRpm(prev, cur), isNull);
    });

    test('超出合理范围的踏频返回 null', () {
      const CscMeasurement prev = CscMeasurement(crankRevolutions: 0, crankEventTime1024: 0);
      const CscMeasurement cur = CscMeasurement(crankRevolutions: 10, crankEventTime1024: 1024);
      expect(cadenceRpm(prev, cur), isNull);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
fvm flutter test test/domain/analysis/ble_payload_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写实现**

创建 `lib/domain/analysis/ble_payload.dart`：

```dart
/// 标准心率测量特征（0x2A37）的解析。
///
/// flags 字节的最低位表示心率值占用 1 字节还是 2 字节（小端）。
int? parseHeartRateMeasurement(List<int> data) {
  if (data.isEmpty) return null;
  final int flags = data[0];
  final bool isUint16 = (flags & 0x01) != 0;
  if (isUint16) {
    if (data.length < 3) return null;
    return data[1] | (data[2] << 8);
  }
  if (data.length < 2) return null;
  return data[1];
}

/// 骑行速度与踏频测量特征（0x2A2B）中的曲柄部分。
class CscMeasurement {
  const CscMeasurement({required this.crankRevolutions, required this.crankEventTime1024});

  /// 累计曲柄转数（16 位，会回绕）。
  final int crankRevolutions;

  /// 最后一次曲柄事件的时刻，单位 1/1024 秒（16 位，会回绕）。
  final int crankEventTime1024;
}

/// 解析 CSC 测量特征值。没有曲柄数据或长度不足时返回 null。
///
/// flags bit0 表示含车轮数据（6 字节），bit1 表示含曲柄数据（4 字节）。
CscMeasurement? parseCscMeasurement(List<int> data) {
  if (data.isEmpty) return null;
  final int flags = data[0];
  int offset = 1;
  if ((flags & 0x01) != 0) offset += 6;
  if ((flags & 0x02) == 0) return null;
  if (data.length < offset + 4) return null;
  final int revolutions = data[offset] | (data[offset + 1] << 8);
  final int eventTime = data[offset + 2] | (data[offset + 3] << 8);
  return CscMeasurement(crankRevolutions: revolutions, crankEventTime1024: eventTime);
}

/// 由两次 CSC 测量计算踏频（RPM）。无法判定时返回 null。
///
/// 转数与事件时间都是 16 位会回绕的量，用按位与 0xFFFF 处理回绕。
double? cadenceRpm(CscMeasurement prev, CscMeasurement cur) {
  final int dRev = (cur.crankRevolutions - prev.crankRevolutions) & 0xFFFF;
  final int dTime = (cur.crankEventTime1024 - prev.crankEventTime1024) & 0xFFFF;
  if (dTime == 0) return null;
  final double seconds = dTime / 1024.0;
  if (seconds > 5) return null;
  final double rpm = dRev / seconds * 60.0;
  if (rpm > 250) return null;
  return rpm;
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
fvm flutter test test/domain/analysis/ble_payload_test.dart
```

Expected: `All tests passed!`（13 个测试）

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat: 添加 BLE 心率与踏频数据帧解析"
```

---

## Task 12: data/db — 数据库与 settings DAO

**Files:**
- Create: `lib/data/db/database.dart`
- Create: `lib/data/db/settings_dao.dart`
- Test: `test/data/db/database_test.dart`
- Test: `test/data/db/settings_dao_test.dart`

- [ ] **Step 1: 写数据库打开的失败测试**

创建 `test/data/db/database_test.dart`：

```dart
import 'package:cycling_app/data/db/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('建表后三张表都存在', () async {
    final Database db = await openAppDatabase(path: inMemoryDatabasePath);
    addTearDown(db.close);

    final List<Map<String, Object?>> tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
    );
    final Set<String> names =
        tables.map((Map<String, Object?> r) => r['name'] as String).toSet();

    expect(names, containsAll(<String>['rides', 'track_points', 'settings']));
  });

  test('track_points 上有 (ride_id, t_ms) 索引', () async {
    final Database db = await openAppDatabase(path: inMemoryDatabasePath);
    addTearDown(db.close);

    final List<Map<String, Object?>> indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'track_points'",
    );
    final Set<String> names =
        indexes.map((Map<String, Object?> r) => r['name'] as String).toSet();

    expect(names, contains('idx_track_points_ride_t'));
  });

  test('删除 rides 行会级联删除 track_points', () async {
    final Database db = await openAppDatabase(path: inMemoryDatabasePath);
    addTearDown(db.close);

    final int rideId = await db.insert('rides', <String, Object?>{
      'started_at': 1000,
      'status': 'finished',
    });
    await db.insert('track_points', <String, Object?>{
      'ride_id': rideId,
      't_ms': 1000,
      'lat': 31.23,
      'lon': 121.47,
    });

    await db.delete('rides', where: 'id = ?', whereArgs: <Object?>[rideId]);

    expect(await db.query('track_points'), isEmpty);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
fvm flutter test test/data/db/database_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist: 'package:cycling_app/data/db/database.dart'`。

- [ ] **Step 3: 写数据库实现**

创建 `lib/data/db/database.dart`：

```dart
import 'package:sqflite/sqflite.dart';

/// 当前 schema 版本。备份文件的 manifest.json 会带上这个数字。
const int kSchemaVersion = 1;

/// 打开（必要时创建）本地数据库。
///
/// 测试时传入 [inMemoryDatabasePath] 并事先把全局 `databaseFactory`
/// 设为 `databaseFactoryFfi`，即可在桌面环境跑真实 SQLite。
Future<Database> openAppDatabase({String? path}) async {
  final String dbPath = path ?? '${await databaseFactory.getDatabasesPath()}/cycling_app.db';
  return databaseFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: kSchemaVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
    ),
  );
}

Future<void> _onConfigure(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
}

Future<void> _onCreate(Database db, int version) async {
  await db.execute('''
    CREATE TABLE rides (
      id                   INTEGER PRIMARY KEY AUTOINCREMENT,
      started_at           INTEGER NOT NULL,
      ended_at             INTEGER,
      status               TEXT    NOT NULL,
      title                TEXT,
      distance_m           REAL,
      duration_s           INTEGER,
      moving_s             INTEGER,
      avg_speed_mps        REAL,
      moving_avg_speed_mps REAL,
      max_speed_mps        REAL,
      elevation_gain_m     REAL,
      avg_hr               REAL,
      max_hr               INTEGER,
      avg_cadence          REAL,
      calories             REAL,
      hr_device_name       TEXT,
      cadence_device_name  TEXT,
      point_count          INTEGER
    )
  ''');

  await db.execute('''
    CREATE TABLE track_points (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      ride_id    INTEGER NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
      t_ms       INTEGER NOT NULL,
      lat        REAL,
      lon        REAL,
      altitude_m REAL,
      speed_mps  REAL,
      accuracy_m REAL,
      hr         INTEGER,
      cadence    INTEGER
    )
  ''');

  await db.execute('CREATE INDEX idx_track_points_ride_t ON track_points(ride_id, t_ms)');

  await db.execute('''
    CREATE TABLE settings (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
fvm flutter test test/data/db/database_test.dart
```

Expected: `All tests passed!`（3 个测试）

- [ ] **Step 5: 写 settings DAO 的失败测试**

创建 `test/data/db/settings_dao_test.dart`：

```dart
import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/settings_dao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late SettingsDao dao;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    dao = SettingsDao(db);
  });

  tearDown(() => db.close());

  test('未设置的键返回 null', () async {
    expect(await dao.getString('missing'), isNull);
  });

  test('写入后可读回', () async {
    await dao.setString('max_heart_rate', '185');
    expect(await dao.getString('max_heart_rate'), '185');
  });

  test('重复写入同一键会覆盖而不是报错', () async {
    await dao.setString('weight_kg', '70');
    await dao.setString('weight_kg', '72');
    expect(await dao.getString('weight_kg'), '72');
  });

  test('getAll 返回全部键值', () async {
    await dao.setString('a', '1');
    await dao.setString('b', '2');
    expect(await dao.getAll(), <String, String>{'a': '1', 'b': '2'});
  });
}
```

- [ ] **Step 6: 写 settings DAO 实现**

创建 `lib/data/db/settings_dao.dart`：

```dart
import 'package:sqflite/sqflite.dart';

/// `settings` 表的键值读写。
class SettingsDao {
  SettingsDao(this._db);

  final Database _db;

  Future<String?> getString(String key) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'settings',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setString(String key, String value) async {
    await _db.insert(
      'settings',
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String>> getAll() async {
    final List<Map<String, Object?>> rows = await _db.query('settings');
    return <String, String>{
      for (final Map<String, Object?> r in rows) r['key'] as String: r['value'] as String,
    };
  }
}
```

- [ ] **Step 7: 运行测试确认通过**

```bash
fvm flutter test test/data/db
```

Expected: `All tests passed!`（7 个测试）

- [ ] **Step 8: 提交**

```bash
git add -A
git commit -m "feat: 添加数据库建表与 settings DAO"
```

---

## Task 13: data/db — ride DAO 与 track_point DAO

**Files:**
- Create: `lib/data/db/track_point_dao.dart`
- Create: `lib/data/db/ride_dao.dart`
- Test: `test/data/db/track_point_dao_test.dart`
- Test: `test/data/db/ride_dao_test.dart`

- [ ] **Step 1: 写 track_point DAO 的失败测试**

创建 `test/data/db/track_point_dao_test.dart`：

```dart
import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/ride_dao.dart';
import 'package:cycling_app/data/db/track_point_dao.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late TrackPointDao dao;
  late int rideId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    dao = TrackPointDao(db);
    rideId = await RideDao(db).insert(
      const Ride(startedAtMs: 1000, status: RideStatus.recording),
    );
  });

  tearDown(() => db.close());

  test('批量插入后按时间升序读出', () async {
    await dao.insertBatch(<TrackPoint>[
      TrackPoint(rideId: rideId, tMs: 3000, lat: 31.23, lon: 121.47, hr: 130),
      TrackPoint(rideId: rideId, tMs: 1000, lat: 31.23, lon: 121.46, hr: 120),
      TrackPoint(rideId: rideId, tMs: 2000, lat: 31.23, lon: 121.465, hr: 125),
    ]);

    final List<TrackPoint> points = await dao.listByRide(rideId);
    expect(points.map((TrackPoint p) => p.tMs).toList(), <int>[1000, 2000, 3000]);
    expect(points.first.hr, 120);
  });

  test('空列表不产生任何写入', () async {
    await dao.insertBatch(const <TrackPoint>[]);
    expect(await dao.countByRide(rideId), 0);
  });

  test('lastByRide 返回时间最大的点', () async {
    await dao.insertBatch(<TrackPoint>[
      TrackPoint(rideId: rideId, tMs: 1000, lat: 31.23, lon: 121.46),
      TrackPoint(rideId: rideId, tMs: 5000, lat: 31.23, lon: 121.48),
    ]);
    expect((await dao.lastByRide(rideId))!.tMs, 5000);
  });

  test('没有点时 lastByRide 返回 null', () async {
    expect(await dao.lastByRide(rideId), isNull);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
fvm flutter test test/data/db/track_point_dao_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写 track_point DAO 实现**

创建 `lib/data/db/track_point_dao.dart`：

```dart
import 'package:sqflite/sqflite.dart';

import '../../domain/models/track_point.dart';

/// `track_points` 表的读写。
class TrackPointDao {
  TrackPointDao(this._db);

  final Database _db;

  /// 一个事务内批量插入。空列表直接返回，不开启事务。
  Future<void> insertBatch(List<TrackPoint> points) async {
    if (points.isEmpty) return;
    final Batch batch = _db.batch();
    for (final TrackPoint p in points) {
      final Map<String, Object?> row = p.toDbMap()..remove('id');
      batch.insert('track_points', row);
    }
    await batch.commit(noResult: true);
  }

  Future<List<TrackPoint>> listByRide(int rideId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'track_points',
      where: 'ride_id = ?',
      whereArgs: <Object?>[rideId],
      orderBy: 't_ms ASC',
    );
    return rows.map(TrackPoint.fromDbMap).toList();
  }

  Future<int> countByRide(int rideId) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM track_points WHERE ride_id = ?',
      <Object?>[rideId],
    );
    return (rows.first['c'] as num).toInt();
  }

  Future<TrackPoint?> lastByRide(int rideId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'track_points',
      where: 'ride_id = ?',
      whereArgs: <Object?>[rideId],
      orderBy: 't_ms DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : TrackPoint.fromDbMap(rows.first);
  }

  Future<void> deleteByRide(int rideId) async {
    await _db.delete('track_points', where: 'ride_id = ?', whereArgs: <Object?>[rideId]);
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
fvm flutter test test/data/db/track_point_dao_test.dart
```

Expected: `All tests passed!`（4 个测试）

- [ ] **Step 5: 写 ride DAO 的失败测试**

创建 `test/data/db/ride_dao_test.dart`：

```dart
import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/ride_dao.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late RideDao dao;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    dao = RideDao(db);
  });

  tearDown(() => db.close());

  test('插入进行中的骑行后可按 id 读回', () async {
    final int id = await dao.insert(
      const Ride(startedAtMs: 1000, status: RideStatus.recording, hrDeviceName: 'FIT 3'),
    );

    final Ride ride = (await dao.findById(id))!;
    expect(ride.status, RideStatus.recording);
    expect(ride.summary, isNull);
    expect(ride.hrDeviceName, 'FIT 3');
  });

  test('findUnfinished 只返回未结束的骑行', () async {
    await dao.insert(const Ride(startedAtMs: 1000, status: RideStatus.recording));
    await dao.insert(const Ride(startedAtMs: 2000, status: RideStatus.paused));
    await dao.insert(const Ride(startedAtMs: 3000, status: RideStatus.finished));

    final List<Ride> unfinished = await dao.findUnfinished();
    expect(unfinished.length, 2);
    expect(unfinished.first.startedAtMs, 2000); // 按开始时间倒序
  });

  test('listFinished 按开始时间倒序且不含未结束的骑行', () async {
    await dao.insert(const Ride(startedAtMs: 1000, status: RideStatus.finished));
    await dao.insert(const Ride(startedAtMs: 3000, status: RideStatus.finished));
    await dao.insert(const Ride(startedAtMs: 5000, status: RideStatus.recording));

    final List<Ride> rides = await dao.listFinished();
    expect(rides.map((Ride r) => r.startedAtMs).toList(), <int>[3000, 1000]);
  });

  test('markFinished 写入结束时间与全部汇总列', () async {
    final int id = await dao.insert(const Ride(startedAtMs: 1000, status: RideStatus.recording));

    await dao.markFinished(
      id: id,
      endedAtMs: 3601000,
      summary: const RideSummary(
        distanceM: 25000,
        durationS: 3600,
        movingS: 3400,
        avgSpeedMps: 6.94,
        movingAvgSpeedMps: 7.35,
        maxSpeedMps: 12.5,
        elevationGainM: 180,
        avgHr: 142,
        maxHr: 176,
        avgCadence: 84,
        calories: 720,
        pointCount: 3600,
      ),
    );

    final Ride ride = (await dao.findById(id))!;
    expect(ride.status, RideStatus.finished);
    expect(ride.endedAtMs, 3601000);
    expect(ride.summary!.distanceM, 25000);
    expect(ride.summary!.pointCount, 3600);
  });

  test('updateStatus 只改状态列', () async {
    final int id = await dao.insert(const Ride(startedAtMs: 1000, status: RideStatus.recording));

    await dao.updateStatus(id, RideStatus.paused);

    final Ride ride = (await dao.findById(id))!;
    expect(ride.status, RideStatus.paused);
    expect(ride.startedAtMs, 1000);
    expect(ride.endedAtMs, isNull);
  });

  test('updateTitle 修改标题', () async {
    final int id = await dao.insert(const Ride(startedAtMs: 1000, status: RideStatus.finished));
    await dao.updateTitle(id, '晨骑');
    expect((await dao.findById(id))!.title, '晨骑');
  });

  test('delete 后查不到', () async {
    final int id = await dao.insert(const Ride(startedAtMs: 1000, status: RideStatus.finished));
    await dao.delete(id);
    expect(await dao.findById(id), isNull);
  });
}
```

- [ ] **Step 6: 写 ride DAO 实现**

创建 `lib/data/db/ride_dao.dart`：

```dart
import 'package:sqflite/sqflite.dart';

import '../../domain/models/ride.dart';
import '../../domain/models/ride_status.dart';
import '../../domain/models/ride_summary.dart';

/// `rides` 表的读写。
class RideDao {
  RideDao(this._db);

  final Database _db;

  /// 插入一行并返回新 id。进行中的骑行汇总列全部为 NULL。
  Future<int> insert(Ride ride) async {
    final Map<String, Object?> row = ride.toDbMap()..remove('id');
    return _db.insert('rides', row);
  }

  Future<Ride?> findById(int id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'rides',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Ride.fromDbMap(rows.first);
  }

  /// 扫描未结束的骑行，用于启动时的崩溃恢复。按开始时间倒序。
  Future<List<Ride>> findUnfinished() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'rides',
      where: "status IN ('recording', 'paused')",
      orderBy: 'started_at DESC',
    );
    return rows.map(Ride.fromDbMap).toList();
  }

  /// 已完成的骑行，按开始时间倒序。
  Future<List<Ride>> listFinished({int? limit, int? offset}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'rides',
      where: "status = 'finished'",
      orderBy: 'started_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Ride.fromDbMap).toList();
  }

  Future<void> markFinished({
    required int id,
    required int endedAtMs,
    required RideSummary summary,
  }) async {
    await _db.update(
      'rides',
      <String, Object?>{
        'ended_at': endedAtMs,
        'status': RideStatus.finished.dbValue,
        ...summary.toDbColumns(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> updateStatus(int id, RideStatus status) async {
    await _db.update(
      'rides',
      <String, Object?>{'status': status.dbValue},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> updateTitle(int id, String? title) async {
    await _db.update(
      'rides',
      <String, Object?>{'title': title},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> delete(int id) async {
    await _db.delete('rides', where: 'id = ?', whereArgs: <Object?>[id]);
  }
}
```

- [ ] **Step 7: 运行测试确认通过**

```bash
fvm flutter test test/data/db
```

Expected: `All tests passed!`（14 个测试）

- [ ] **Step 8: 提交**

```bash
git add -A
git commit -m "feat: 添加 ride 与 track_point DAO"
```

---

## Task 14: data — AppSettings 与 RideRepository

**Files:**
- Create: `lib/data/settings_repository.dart`
- Create: `lib/data/ride_repository.dart`
- Test: `test/data/settings_repository_test.dart`
- Test: `test/data/ride_repository_test.dart`

- [ ] **Step 1: 写 AppSettings 的失败测试**

创建 `test/data/settings_repository_test.dart`：

```dart
import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/settings_dao.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late SettingsRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = SettingsRepository(SettingsDao(db));
  });

  tearDown(() => db.close());

  test('首次读取返回默认值', () async {
    final AppSettings s = await repo.load();
    expect(s.maxHeartRate, kDefaultMaxHeartRate);
    expect(s.weightKg, kDefaultWeightKg);
    expect(s.distanceUnit, DistanceUnit.kilometer);
    expect(s.mapTileUrlTemplate, kDefaultMapTileUrlTemplate);
  });

  test('保存后可读回', () async {
    await repo.save(
      const AppSettings(
        maxHeartRate: 185,
        weightKg: 72.5,
        distanceUnit: DistanceUnit.mile,
        mapTileUrlTemplate: 'https://example.com/{z}/{x}/{y}.png',
      ),
    );

    final AppSettings s = await repo.load();
    expect(s.maxHeartRate, 185);
    expect(s.weightKg, 72.5);
    expect(s.distanceUnit, DistanceUnit.mile);
    expect(s.mapTileUrlTemplate, 'https://example.com/{z}/{x}/{y}.png');
  });

  test('存储值损坏时回退到默认值而不是抛错', () async {
    await SettingsDao(db).setString('weight_kg', 'not-a-number');
    expect((await repo.load()).weightKg, kDefaultWeightKg);
  });

  test('最大心率越界时回退到默认值', () async {
    await SettingsDao(db).setString('max_heart_rate', '10');
    expect((await repo.load()).maxHeartRate, kDefaultMaxHeartRate);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
fvm flutter test test/data/settings_repository_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写 AppSettings 实现**

创建 `lib/data/settings_repository.dart`：

```dart
import 'db/settings_dao.dart';

/// 距离单位。仅支持公里与英里两种，不涉及多语言。
enum DistanceUnit {
  kilometer('km'),
  mile('mi');

  const DistanceUnit(this.dbValue);

  final String dbValue;

  static DistanceUnit fromDb(String? value) => DistanceUnit.values.firstWhere(
        (DistanceUnit u) => u.dbValue == value,
        orElse: () => DistanceUnit.kilometer,
      );
}

const int kDefaultMaxHeartRate = 190;
const double kDefaultWeightKg = 70;
const int kMinPlausibleMaxHeartRate = 100;
const int kMaxPlausibleMaxHeartRate = 230;

/// 高德栅格瓦片。无需 Key，但属于非官方接口，因此做成可配置项（设计文档 9.1）。
const String kDefaultMapTileUrlTemplate =
    'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}';

const List<String> kDefaultMapTileSubdomains = <String>['1', '2', '3', '4'];

/// 用户可配置项。
class AppSettings {
  const AppSettings({
    required this.maxHeartRate,
    required this.weightKg,
    required this.distanceUnit,
    required this.mapTileUrlTemplate,
  });

  final int maxHeartRate;
  final double weightKg;
  final DistanceUnit distanceUnit;
  final String mapTileUrlTemplate;

  AppSettings copyWith({
    int? maxHeartRate,
    double? weightKg,
    DistanceUnit? distanceUnit,
    String? mapTileUrlTemplate,
  }) =>
      AppSettings(
        maxHeartRate: maxHeartRate ?? this.maxHeartRate,
        weightKg: weightKg ?? this.weightKg,
        distanceUnit: distanceUnit ?? this.distanceUnit,
        mapTileUrlTemplate: mapTileUrlTemplate ?? this.mapTileUrlTemplate,
      );
}

/// 类型化的设置读写。存储值损坏或越界时回退到默认值，不让 UI 崩掉。
class SettingsRepository {
  SettingsRepository(this._dao);

  final SettingsDao _dao;

  Future<AppSettings> load() async {
    final Map<String, String> raw = await _dao.getAll();

    final int? hr = int.tryParse(raw['max_heart_rate'] ?? '');
    final double? weight = double.tryParse(raw['weight_kg'] ?? '');
    final String tileUrl = raw['map_tile_url'] ?? '';

    return AppSettings(
      maxHeartRate:
          (hr != null && hr >= kMinPlausibleMaxHeartRate && hr <= kMaxPlausibleMaxHeartRate)
              ? hr
              : kDefaultMaxHeartRate,
      weightKg: (weight != null && weight > 0) ? weight : kDefaultWeightKg,
      distanceUnit: DistanceUnit.fromDb(raw['distance_unit']),
      mapTileUrlTemplate: tileUrl.isEmpty ? kDefaultMapTileUrlTemplate : tileUrl,
    );
  }

  Future<void> save(AppSettings settings) async {
    await _dao.setString('max_heart_rate', settings.maxHeartRate.toString());
    await _dao.setString('weight_kg', settings.weightKg.toString());
    await _dao.setString('distance_unit', settings.distanceUnit.dbValue);
    await _dao.setString('map_tile_url', settings.mapTileUrlTemplate);
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
fvm flutter test test/data/settings_repository_test.dart
```

Expected: `All tests passed!`（4 个测试）

- [ ] **Step 5: 写 RideRepository 的失败测试**

创建 `test/data/ride_repository_test.dart`：

```dart
import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/ride_dao.dart';
import 'package:cycling_app/data/db/settings_dao.dart';
import 'package:cycling_app/data/db/track_point_dao.dart';
import 'package:cycling_app/data/ride_repository.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late RideRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = RideRepository(
      rides: RideDao(db),
      points: TrackPointDao(db),
      settings: SettingsRepository(SettingsDao(db)),
    );
  });

  tearDown(() => db.close());

  test('startRide 建立一条 recording 状态的记录', () async {
    final Ride ride = await repo.startRide(startedAtMs: 1000, hrDeviceName: 'FIT 3');

    expect(ride.id, isNotNull);
    expect(ride.status, RideStatus.recording);
    expect(ride.hrDeviceName, 'FIT 3');
  });

  test('appendPoints 与 getPoints 往返一致', () async {
    final Ride ride = await repo.startRide(startedAtMs: 1000);
    await repo.appendPoints(ride.id!, <TrackPoint>[
      TrackPoint(rideId: ride.id!, tMs: 1000, lat: 31.23, lon: 121.47, hr: 120),
      TrackPoint(rideId: ride.id!, tMs: 2000, lat: 31.23, lon: 121.471, hr: 122),
    ]);

    final List<TrackPoint> points = await repo.getPoints(ride.id!);
    expect(points.length, 2);
    expect(points.last.hr, 122);
  });

  test('finishRide 写入汇总并把状态改为 finished', () async {
    final Ride ride = await repo.startRide(startedAtMs: 0);
    await repo.appendPoints(ride.id!, <TrackPoint>[
      TrackPoint(rideId: ride.id!, tMs: 0, lat: 31.23, lon: 121.4700, speedMps: 5, hr: 120),
      TrackPoint(rideId: ride.id!, tMs: 1000, lat: 31.23, lon: 121.4701, speedMps: 5, hr: 120),
      TrackPoint(rideId: ride.id!, tMs: 2000, lat: 31.23, lon: 121.4702, speedMps: 5, hr: 120),
    ]);

    await repo.finishRide(ride.id!, endedAtMs: 2000, durationS: 2);

    final Ride done = (await repo.getRide(ride.id!))!;
    expect(done.status, RideStatus.finished);
    expect(done.endedAtMs, 2000);
    expect(done.summary!.pointCount, 3);
    expect(done.summary!.distanceM, greaterThan(0));
    expect(done.summary!.avgHr, closeTo(120, 1e-9));
  });

  test('findUnfinished 能找到未结束的骑行', () async {
    final Ride ride = await repo.startRide(startedAtMs: 1000);
    expect((await repo.findUnfinished()).single.id, ride.id);
  });

  test('settleRide 从已有轨迹点结算一条崩溃遗留的骑行', () async {
    final Ride ride = await repo.startRide(startedAtMs: 0);
    await repo.appendPoints(ride.id!, <TrackPoint>[
      TrackPoint(rideId: ride.id!, tMs: 0, lat: 31.23, lon: 121.4700, speedMps: 5),
      TrackPoint(rideId: ride.id!, tMs: 10000, lat: 31.23, lon: 121.4710, speedMps: 5),
    ]);

    await repo.settleRide(ride.id!);

    final Ride done = (await repo.getRide(ride.id!))!;
    expect(done.status, RideStatus.finished);
    expect(done.endedAtMs, 10000);
    expect(done.summary!.durationS, 10);
    expect(done.summary!.pointCount, 2);
  });

  test('deleteRide 同时删除轨迹点', () async {
    final Ride ride = await repo.startRide(startedAtMs: 0);
    await repo.appendPoints(ride.id!, <TrackPoint>[
      TrackPoint(rideId: ride.id!, tMs: 0, lat: 31.23, lon: 121.47),
    ]);

    await repo.deleteRide(ride.id!);

    expect(await repo.getRide(ride.id!), isNull);
    expect(await repo.getPoints(ride.id!), isEmpty);
  });
}
```

- [ ] **Step 6: 写 RideRepository 实现**

创建 `lib/data/ride_repository.dart`：

```dart
import '../domain/analysis/summary.dart';
import '../domain/models/ride.dart';
import '../domain/models/ride_status.dart';
import '../domain/models/ride_summary.dart';
import '../domain/models/track_point.dart';
import 'db/ride_dao.dart';
import 'db/track_point_dao.dart';
import 'settings_repository.dart';

/// 骑行数据的统一入口：组合 DAO 与 domain 分析层，供上层调用。
class RideRepository {
  RideRepository({
    required RideDao rides,
    required TrackPointDao points,
    required SettingsRepository settings,
  })  : _rides = rides,
        _points = points,
        _settings = settings;

  final RideDao _rides;
  final TrackPointDao _points;
  final SettingsRepository _settings;

  /// 新建一条进行中的骑行记录。
  Future<Ride> startRide({
    required int startedAtMs,
    String? hrDeviceName,
    String? cadenceDeviceName,
  }) async {
    final int id = await _rides.insert(Ride(
      startedAtMs: startedAtMs,
      status: RideStatus.recording,
      hrDeviceName: hrDeviceName,
      cadenceDeviceName: cadenceDeviceName,
    ));
    return Ride(
      id: id,
      startedAtMs: startedAtMs,
      status: RideStatus.recording,
      hrDeviceName: hrDeviceName,
      cadenceDeviceName: cadenceDeviceName,
    );
  }

  Future<void> appendPoints(int rideId, List<TrackPoint> points) =>
      _points.insertBatch(points);

  Future<void> setStatus(int rideId, RideStatus status) => _rides.updateStatus(rideId, status);

  /// 正常结束：用会话给出的时长（不含暂停）计算汇总。
  Future<RideSummary> finishRide(
    int rideId, {
    required int endedAtMs,
    required int durationS,
  }) async {
    final List<TrackPoint> points = await _points.listByRide(rideId);
    final AppSettings settings = await _settings.load();
    final RideSummary summary = computeSummary(
      points: points,
      durationS: durationS,
      maxHeartRate: settings.maxHeartRate,
      weightKg: settings.weightKg,
    );
    await _rides.markFinished(id: rideId, endedAtMs: endedAtMs, summary: summary);
    return summary;
  }

  /// 崩溃恢复时选择「结算」：只用已有轨迹点推算，时长取末点与首点之差。
  Future<RideSummary> settleRide(int rideId) async {
    final Ride? ride = await _rides.findById(rideId);
    if (ride == null) {
      throw ArgumentError('骑行记录不存在: $rideId');
    }
    final List<TrackPoint> points = await _points.listByRide(rideId);
    final AppSettings settings = await _settings.load();

    final int endedAtMs = points.isEmpty ? ride.startedAtMs : points.last.tMs;
    final int durationS =
        points.length < 2 ? 0 : ((points.last.tMs - points.first.tMs) / 1000).round();

    final RideSummary summary = computeSummary(
      points: points,
      durationS: durationS,
      maxHeartRate: settings.maxHeartRate,
      weightKg: settings.weightKg,
    );
    await _rides.markFinished(id: rideId, endedAtMs: endedAtMs, summary: summary);
    return summary;
  }

  Future<List<Ride>> findUnfinished() => _rides.findUnfinished();

  Future<List<Ride>> listFinished({int? limit, int? offset}) =>
      _rides.listFinished(limit: limit, offset: offset);

  Future<Ride?> getRide(int id) => _rides.findById(id);

  Future<List<TrackPoint>> getPoints(int rideId) => _points.listByRide(rideId);

  Future<TrackPoint?> lastPoint(int rideId) => _points.lastByRide(rideId);

  Future<void> updateTitle(int rideId, String? title) => _rides.updateTitle(rideId, title);

  Future<void> deleteRide(int rideId) async {
    await _points.deleteByRide(rideId);
    await _rides.delete(rideId);
  }
}
```

- [ ] **Step 7: 运行测试确认通过**

```bash
fvm flutter test test/data
```

Expected: `All tests passed!`（17 个测试）

- [ ] **Step 8: 提交**

```bash
git add -A
git commit -m "feat: 添加设置读写与 RideRepository 数据门面"
```

---

## Task 15: domain/recording — 写入过滤与批量缓冲

设计文档 6.3 的规则 1（轨迹点过滤）与规则 2（传感器批量提交）。

**Files:**
- Create: `lib/domain/recording/track_point_filter.dart`
- Create: `lib/domain/recording/write_buffer.dart`
- Test: `test/domain/recording/track_point_filter_test.dart`
- Test: `test/domain/recording/write_buffer_test.dart`

- [ ] **Step 1: 写过滤函数的失败测试**

创建 `test/domain/recording/track_point_filter_test.dart`：

```dart
import 'package:cycling_app/domain/models/location_fix.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/recording/track_point_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 纬度 1 度约 111320 米，故 0.0001 度约 11.13 米、0.00001 度约 1.11 米。
  TrackPoint pointAt(int tMs, double lat, double lon) =>
      TrackPoint(rideId: 1, tMs: tMs, lat: lat, lon: lon);

  group('shouldWriteTrackPoint', () {
    test('没有上一点时写入', () {
      const LocationFix fix = LocationFix(tMs: 1000, lat: 31.0, lon: 121.0);
      expect(shouldWriteTrackPoint(lastWritten: null, fix: fix), isTrue);
    });

    test('距离达到 5 米时写入', () {
      final TrackPoint last = pointAt(0, 31.0, 121.0);
      const LocationFix fix = LocationFix(tMs: 1000, lat: 31.0001, lon: 121.0);
      expect(shouldWriteTrackPoint(lastWritten: last, fix: fix), isTrue);
    });

    test('距离与时间都不足时不写入', () {
      final TrackPoint last = pointAt(0, 31.0, 121.0);
      const LocationFix fix = LocationFix(tMs: 1000, lat: 31.00001, lon: 121.0);
      expect(shouldWriteTrackPoint(lastWritten: last, fix: fix), isFalse);
    });

    test('距离不足但间隔达到 2 秒时写入', () {
      final TrackPoint last = pointAt(0, 31.0, 121.0);
      const LocationFix fix = LocationFix(tMs: 2000, lat: 31.0, lon: 121.0);
      expect(shouldWriteTrackPoint(lastWritten: last, fix: fix), isTrue);
    });

    test('没有定位的点不写入', () {
      const LocationFix fix = LocationFix(tMs: 2000);
      expect(shouldWriteTrackPoint(lastWritten: null, fix: fix), isFalse);
    });

    test('时间倒退不写入', () {
      final TrackPoint last = pointAt(5000, 31.0, 121.0);
      const LocationFix fix = LocationFix(tMs: 4000, lat: 31.0, lon: 121.0);
      expect(shouldWriteTrackPoint(lastWritten: last, fix: fix), isFalse);
    });

    test('上一点没有坐标时写入', () {
      const TrackPoint last = TrackPoint(rideId: 1, tMs: 0);
      const LocationFix fix = LocationFix(tMs: 1000, lat: 31.0, lon: 121.0);
      expect(shouldWriteTrackPoint(lastWritten: last, fix: fix), isTrue);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
fvm flutter test test/domain/recording/track_point_filter_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写过滤函数实现**

创建 `lib/domain/recording/track_point_filter.dart`：

```dart
import '../analysis/constants.dart';
import '../analysis/geo.dart';
import '../models/location_fix.dart';
import '../models/track_point.dart';

/// 设计文档 6.3 规则 1：判断一次定位结果是否应写成轨迹点。
///
/// 距上一点 ≥ [kMinWriteDistanceM]，或距上次写入 ≥ [kMaxWriteIntervalMs]，
/// 满足其一即写入。移动时由距离触发（约 1Hz），静止时由时间触发（约 0.5Hz）。
///
/// GPS 跳变（隐含速度超过 [kMaxPlausibleSpeedMps]）不在这里拦截：跳变点照常
/// 落盘，但 [segmentDistanceMeters] 与移动/静止切分都不会把它计入距离，
/// 地图上的断线渲染由详情页负责（Plan B）。
bool shouldWriteTrackPoint({
  required TrackPoint? lastWritten,
  required LocationFix fix,
}) {
  if (!fix.hasPosition) return false;
  if (lastWritten == null) return true;
  // 上一点是 GPS 丢失期间写下的纯传感器点，定位恢复后立刻补一个轨迹点。
  if (!lastWritten.hasPosition) return true;

  final int dtMs = fix.tMs - lastWritten.tMs;
  if (dtMs <= 0) return false;
  if (dtMs >= kMaxWriteIntervalMs) return true;

  final double d =
      haversineMeters(lastWritten.lat!, lastWritten.lon!, fix.lat!, fix.lon!);
  return d >= kMinWriteDistanceM;
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
fvm flutter test test/domain/recording/track_point_filter_test.dart
```

Expected: `All tests passed!`（7 个测试）

- [ ] **Step 5: 写批量缓冲的失败测试**

创建 `test/domain/recording/write_buffer_test.dart`：

```dart
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/recording/write_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TrackPoint pointAt(int tMs) => TrackPoint(rideId: 1, tMs: tMs, lat: 31.0, lon: 121.0);

  group('WriteBuffer', () {
    test('初始为空', () {
      final WriteBuffer buffer = WriteBuffer();
      expect(buffer.length, 0);
      expect(buffer.isEmpty, isTrue);
      expect(buffer.isFull, isFalse);
    });

    test('未达容量时 isFull 为 false', () {
      final WriteBuffer buffer = WriteBuffer();
      for (int i = 0; i < 9; i++) {
        buffer.add(pointAt(i));
      }
      expect(buffer.length, 9);
      expect(buffer.isFull, isFalse);
    });

    test('达到容量时 isFull 为 true', () {
      final WriteBuffer buffer = WriteBuffer();
      for (int i = 0; i < 10; i++) {
        buffer.add(pointAt(i));
      }
      expect(buffer.isFull, isTrue);
    });

    test('drain 返回全部待写点并清空', () {
      final WriteBuffer buffer = WriteBuffer();
      buffer.add(pointAt(1));
      buffer.add(pointAt(2));
      final List<TrackPoint> batch = buffer.drain();
      expect(batch.length, 2);
      expect(batch.first.tMs, 1);
      expect(batch.last.tMs, 2);
      expect(buffer.isEmpty, isTrue);
      expect(buffer.isFull, isFalse);
    });

    test('空缓冲 drain 返回空列表', () {
      final WriteBuffer buffer = WriteBuffer();
      expect(buffer.drain(), isEmpty);
    });

    test('容量可自定义', () {
      final WriteBuffer buffer = WriteBuffer(capacity: 2);
      buffer.add(pointAt(1));
      expect(buffer.isFull, isFalse);
      buffer.add(pointAt(2));
      expect(buffer.isFull, isTrue);
    });
  });
}
```

- [ ] **Step 6: 运行测试确认失败**

```bash
fvm flutter test test/domain/recording/write_buffer_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 7: 写批量缓冲实现**

创建 `lib/domain/recording/write_buffer.dart`：

```dart
import '../analysis/constants.dart';
import '../models/track_point.dart';

/// 设计文档 6.3 规则 2：攒够 [capacity] 个点提交一个事务。
///
/// 本类只管攒与取，不做任何 IO，因此可以脱离 Flutter 与数据库单独测试。
class WriteBuffer {
  WriteBuffer({this.capacity = kSensorBatchSize});

  /// 触发提交的点数阈值。
  final int capacity;

  final List<TrackPoint> _pending = <TrackPoint>[];

  int get length => _pending.length;

  bool get isEmpty => _pending.isEmpty;

  /// 是否已达提交阈值。调用方据此决定何时 [drain]。
  bool get isFull => _pending.length >= capacity;

  void add(TrackPoint point) {
    _pending.add(point);
  }

  /// 取出并清空全部待写点。返回的列表不可修改。
  List<TrackPoint> drain() {
    if (_pending.isEmpty) return const <TrackPoint>[];
    final List<TrackPoint> batch = List<TrackPoint>.unmodifiable(_pending);
    _pending.clear();
    return batch;
  }
}
```

- [ ] **Step 8: 运行测试确认通过**

```bash
fvm flutter test test/domain/recording
```

Expected: `All tests passed!`（13 个测试）

- [ ] **Step 9: 提交**

```bash
git add -A
git commit -m "feat: 添加轨迹点写入过滤与批量提交缓冲"
```

---

## Task 16: domain/recording — RecordingSession 状态机

设计文档 6.1 的状态机与 6.2 的实时指标。所有时间由外部注入（`nowMs`），因此不依赖真实时钟，测试完全确定。

> 说明：设计文档 6.1 中的 `idle` 与 `preparing`（申请权限、连接传感器）由控制器与 UI 承担，`RecordingSession` 只在真正开始记录时创建，因此内部阶段只有 `recording` / `paused` / `finished` 三个。

**Files:**
- Create: `lib/domain/recording/recording_session.dart`
- Test: `test/domain/recording/recording_session_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/domain/recording/recording_session_test.dart`：

```dart
import 'package:cycling_app/domain/models/location_fix.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/recording/recording_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 纬度 0.0001 度约 11.13 米。
  LocationFix fixAt(
    int tMs, {
    double lat = 31.0,
    double? lon = 121.0,
    double? speedMps,
  }) =>
      LocationFix(tMs: tMs, lat: lat, lon: lon, speedMps: speedMps);

  group('RecordingSession 时长', () {
    test('tick 累计有效时长', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.tick(1000);
      expect(s.snapshot.elapsedMs, 1000);
      s.tick(3000);
      expect(s.snapshot.elapsedMs, 3000);
    });

    test('暂停期间不累计时长', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.tick(1000);
      s.pause(1000);
      s.tick(5000);
      expect(s.snapshot.elapsedMs, 1000);
      expect(s.snapshot.phase, RecordingPhase.paused);
    });

    test('恢复后继续累计', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.tick(1000);
      s.pause(1000);
      s.tick(5000);
      s.resume(5000);
      s.tick(6000);
      expect(s.snapshot.elapsedMs, 2000);
      expect(s.snapshot.phase, RecordingPhase.recording);
    });

    test('结束之后 tick 不再累计', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.tick(1000);
      s.finish(1000);
      s.tick(9000);
      expect(s.snapshot.elapsedMs, 1000);
      expect(s.snapshot.phase, RecordingPhase.finished);
    });
  });

  group('RecordingSession 距离与速度', () {
    test('累计位移距离', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      s.ingestFix(fixAt(1000, lat: 31.0001));
      expect(s.snapshot.distanceM, closeTo(11.13, 0.2));
    });

    test('GPS 跳变不计入距离', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      s.ingestFix(fixAt(1000, lat: 31.01));
      expect(s.snapshot.distanceM, 0);
    });

    test('优先使用 GPS 上报速度', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0, speedMps: 6.0));
      expect(s.snapshot.currentSpeedMps, 6.0);
    });

    test('GPS 长时间无更新后速度归零', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0, speedMps: 6.0));
      s.tick(11000);
      expect(s.snapshot.currentSpeedMps, 0);
    });
  });

  group('RecordingSession 落盘', () {
    test('首个定位点写入', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      expect(s.takePendingPoints().length, 1);
    });

    test('静止时按 2 秒节拍写入', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      s.ingestFix(fixAt(1000));
      s.ingestFix(fixAt(2000));
      expect(s.takePendingPoints().length, 2);
    });

    test('攒够 10 个点后 shouldFlush 为 true', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      for (int i = 0; i < 10; i++) {
        s.ingestFix(fixAt(i * 2000));
      }
      expect(s.shouldFlush, isTrue);
      expect(s.takePendingPoints().length, 10);
      expect(s.shouldFlush, isFalse);
    });

    test('暂停期间不写入轨迹点', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      s.takePendingPoints();
      s.pause(0);
      s.ingestFix(fixAt(2000));
      expect(s.takePendingPoints(), isEmpty);
    });

    test('心率与踏频附加到写入的点上', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestHeartRate(120);
      s.ingestCadence(85.4);
      s.ingestFix(fixAt(0));
      final TrackPoint p = s.takePendingPoints().single;
      expect(p.hr, 120);
      expect(p.cadence, 85);
    });

    test('GPS 丢失超过 10 秒时写入纯传感器点', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestHeartRate(120);
      s.ingestFix(fixAt(0));
      s.takePendingPoints();
      s.tick(12000);
      final List<TrackPoint> batch = s.takePendingPoints();
      expect(batch.length, 1);
      expect(batch.single.hasPosition, isFalse);
      expect(batch.single.hr, 120);
    });

    test('结束时返回缓冲中剩余的点', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      s.takePendingPoints();
      s.ingestFix(fixAt(1000));
      expect(s.takePendingPoints(), isEmpty);
      s.ingestFix(fixAt(2000));
      expect(s.finish(2000).length, 1);
      expect(s.takePendingPoints(), isEmpty);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
fvm flutter test test/domain/recording/recording_session_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写实现**

创建 `lib/domain/recording/recording_session.dart`：

```dart
import '../analysis/constants.dart';
import '../analysis/geo.dart';
import '../models/location_fix.dart';
import '../models/track_point.dart';
import 'track_point_filter.dart';
import 'write_buffer.dart';

/// 记录会话的阶段。
///
/// 设计文档 6.1 中的 `idle` 与 `preparing`（申请权限、连接传感器）由控制器与
/// UI 承担，本对象只在真正开始记录时创建，因此内部阶段只有三个。
enum RecordingPhase { recording, paused, finished }

/// 实时快照，供 UI 每秒渲染一次。
class RecordingSnapshot {
  const RecordingSnapshot({
    required this.phase,
    required this.elapsedMs,
    required this.distanceM,
    required this.currentSpeedMps,
    required this.hr,
    required this.cadence,
    required this.pointCount,
  });

  final RecordingPhase phase;

  /// 有效记录时长（毫秒），暂停期间不增长。
  final int elapsedMs;

  final double distanceM;
  final double currentSpeedMps;
  final int? hr;
  final int? cadence;

  /// 已写入的点数（含仍在缓冲中、尚未提交事务的点）。
  final int pointCount;

  int get elapsedSeconds => elapsedMs ~/ 1000;
}

/// 记录引擎的状态机与实时指标。
///
/// 所有时间都由外部注入（`nowMs`），因此不依赖真实时钟，测试完全确定。
/// 落盘由调用方负责：每次 [ingestFix] / [tick] 之后检查 [shouldFlush]，
/// 需要时调用 [takePendingPoints] 取走一批点写库；结束前必须调用 [finish]
/// 取走缓冲中剩余的点。
class RecordingSession {
  RecordingSession({required this.rideId, required this.startedAtMs})
      : _lastTickMs = startedAtMs,
        _lastWrittenMs = startedAtMs;

  final int rideId;
  final int startedAtMs;

  final WriteBuffer _buffer = WriteBuffer();

  RecordingPhase _phase = RecordingPhase.recording;
  int _elapsedMs = 0;
  int _lastTickMs;
  int _lastWrittenMs;
  double _distanceM = 0;
  double _currentSpeedMps = 0;
  int? _hr;
  double? _cadence;
  LocationFix? _lastFix;
  TrackPoint? _lastWritten;
  int _pointCount = 0;

  RecordingPhase get phase => _phase;

  /// 是否已攒够 [kSensorBatchSize] 个点，可以提交一个事务。
  bool get shouldFlush => _buffer.isFull;

  RecordingSnapshot get snapshot => RecordingSnapshot(
        phase: _phase,
        elapsedMs: _elapsedMs,
        distanceM: _distanceM,
        currentSpeedMps: _currentSpeedMps,
        hr: _hr,
        cadence: _cadence?.round(),
        pointCount: _pointCount,
      );

  /// 取出并清空待落盘的点。返回非空列表时调用方应写库。
  List<TrackPoint> takePendingPoints() => _buffer.drain();

  /// 接收一次定位结果。暂停或已结束时直接忽略。
  void ingestFix(LocationFix fix) {
    if (_phase != RecordingPhase.recording || !fix.hasPosition) return;

    final LocationFix? prev = _lastFix;
    double segmentM = 0;
    if (prev != null && prev.hasPosition) {
      segmentM = segmentDistanceMeters(_toPoint(prev), _toPoint(fix));
      _distanceM += segmentM;
    }

    final double? reported = fix.speedMps;
    if (reported != null && reported >= 0 && reported <= kMaxPlausibleSpeedMps) {
      _currentSpeedMps = reported;
    } else {
      // GPS 没给速度，或给的数值不合理，就用位移除以时间推算。
      final int dtMs = prev == null ? 0 : fix.tMs - prev.tMs;
      _currentSpeedMps = dtMs > 0 ? segmentM / (dtMs / 1000.0) : 0;
    }

    _lastFix = fix;

    if (shouldWriteTrackPoint(lastWritten: _lastWritten, fix: fix)) {
      _write(_toPoint(fix));
    }
  }

  /// 接收一次心率采样（bpm）。
  void ingestHeartRate(int bpm) => _hr = bpm;

  /// 接收一次踏频采样（RPM）。
  void ingestCadence(double rpm) => _cadence = rpm;

  /// 由控制器以 1Hz 调用，推进时长、衰减速度、补写纯传感器点。
  void tick(int nowMs) {
    if (_phase == RecordingPhase.finished) return;
    _advanceElapsed(nowMs);
    _decaySpeed(nowMs);
    _writeSensorOnlyPointIfNeeded(nowMs);
  }

  /// 暂停采样。暂停期间不产生轨迹点，时长也不增长。
  void pause(int nowMs) {
    if (_phase != RecordingPhase.recording) return;
    _advanceElapsed(nowMs);
    _phase = RecordingPhase.paused;
    _currentSpeedMps = 0;
  }

  /// 恢复采样。暂停期间的位移不属于骑行，因此断开与暂停前状态的关联。
  void resume(int nowMs) {
    if (_phase != RecordingPhase.paused) return;
    _phase = RecordingPhase.recording;
    _lastTickMs = nowMs;
    _lastFix = null;
    _lastWritten = null;
    _lastWrittenMs = nowMs;
  }

  /// 结束记录，返回缓冲中剩余待落盘的点（未满一批不会自动提交）。
  ///
  /// 结束后的有效时长从 `snapshot.elapsedSeconds` 读取。
  List<TrackPoint> finish(int nowMs) {
    if (_phase != RecordingPhase.finished) {
      _advanceElapsed(nowMs);
      _phase = RecordingPhase.finished;
      _currentSpeedMps = 0;
    }
    return _buffer.drain();
  }

  void _advanceElapsed(int nowMs) {
    final int dt = nowMs - _lastTickMs;
    if (dt > 0 && _phase == RecordingPhase.recording) {
      _elapsedMs += dt;
    }
    _lastTickMs = nowMs;
  }

  void _decaySpeed(int nowMs) {
    final LocationFix? last = _lastFix;
    if (_phase == RecordingPhase.recording &&
        (last == null || nowMs - last.tMs > kGpsGapMs)) {
      _currentSpeedMps = 0;
    }
  }

  /// GPS 长时间没有更新时，仍按 2 秒节拍写纯传感器点，
  /// 使心率与踏频曲线不断（这类点只有时间与传感器值，不上地图）。
  void _writeSensorOnlyPointIfNeeded(int nowMs) {
    if (_phase != RecordingPhase.recording) return;
    if (_hr == null && _cadence == null) return;

    final LocationFix? last = _lastFix;
    final bool gpsLost = last == null || nowMs - last.tMs >= kGpsGapMs;
    if (!gpsLost || nowMs - _lastWrittenMs < kMaxWriteIntervalMs) return;

    _write(TrackPoint(
      rideId: rideId,
      tMs: nowMs,
      hr: _hr,
      cadence: _cadence?.round(),
    ));
  }

  void _write(TrackPoint point) {
    _lastWritten = point;
    _lastWrittenMs = point.tMs;
    _pointCount++;
    _buffer.add(point);
  }

  TrackPoint _toPoint(LocationFix fix) => TrackPoint(
        rideId: rideId,
        tMs: fix.tMs,
        lat: fix.lat,
        lon: fix.lon,
        altitudeM: fix.altitudeM,
        speedMps: fix.speedMps,
        accuracyM: fix.accuracyM,
        hr: _hr,
        cadence: _cadence?.round(),
      );
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
fvm flutter test test/domain/recording
```

Expected: `All tests passed!`（28 个测试）

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat: 添加记录会话状态机与实时指标"
```

---

## Task 17: data/location — 定位服务

设计文档 11.1 的阻断类校验，以及把 geolocator 的 `Position` 翻译成 domain 层的 `LocationFix`。

**Files:**
- Create: `lib/data/location/location_service.dart`

> 本任务不写单元测试：设计文档 13 明确「真实 GPS 不自动化」。本文件只做权限校验与字段翻译，真正的采集行为由 Task 22 真机验证。

- [ ] **Step 1: 写实现**

创建 `lib/data/location/location_service.dart`：

```dart
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import '../../domain/models/location_fix.dart';

/// 开始记录前的定位前置校验结果。见设计文档 11.1（阻断类）。
enum LocationReadiness {
  ready,

  /// 系统定位开关关闭。
  serviceDisabled,

  /// 权限被拒，可以再次申请。
  permissionDenied,

  /// 权限被永久拒绝，只能去系统设置里改。
  permissionDeniedForever,
}

/// 把 geolocator 的定位结果翻译成 domain 层的 [LocationFix]。
///
/// iOS 在速度不可用时会给 `-1`，这里原样保留，由
/// [RecordingSession] 判断是否可用。
LocationFix toLocationFix(Position position) => LocationFix(
      tMs: position.timestamp.millisecondsSinceEpoch,
      lat: position.latitude,
      lon: position.longitude,
      altitudeM: position.altitude,
      speedMps: position.speed,
      accuracyM: position.accuracy,
    );

/// 定位采集。只负责权限校验与字段翻译，不含任何业务判断。
class LocationService {
  const LocationService();

  /// 检查定位服务与权限。不满足时返回具体原因，由 UI 引导用户处理。
  Future<LocationReadiness> checkReadiness() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationReadiness.serviceDisabled;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationReadiness.permissionDeniedForever;
    }
    if (permission == LocationPermission.denied) {
      return LocationReadiness.permissionDenied;
    }
    return LocationReadiness.ready;
  }

  /// 跳转系统设置页，供权限被拒时引导用户。
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// 跳转系统定位开关页，供定位服务关闭时引导用户。
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// 定位流。1Hz 的落盘节拍由 [RecordingSession] 的 tick 保证，
  /// 这里不做系统侧距离过滤，避免丢掉用于平滑的原始点。
  Stream<LocationFix> fixes() => Geolocator.getPositionStream(
        locationSettings: _settings(),
      ).map(toLocationFix);

  LocationSettings _settings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        // 前台服务通知：Android 10+ 后台持续定位必需，与 Task 2 声明的
        // com.baseflow.geolocator.GeolocatorService 配套。
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: '骑行记录中',
          notificationText: '正在记录轨迹与心率',
          notificationChannelName: '骑行记录',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return AppleSettings(
      accuracy: LocationAccuracy.best,
      activityType: ActivityType.fitness,
      distanceFilter: 0,
      // 骑行中自动暂停定位会让轨迹断掉，必须关掉。
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: true,
    );
  }
}
```

- [ ] **Step 2: 静态检查**

```bash
fvm flutter analyze lib/data/location
```

Expected: `No issues found!`

- [ ] **Step 3: 提交**

```bash
git add -A
git commit -m "feat: 添加定位服务与权限校验"
```

---

## Task 18: data/ble — 扫描、订阅与重连

设计文档 11.2 的传感器处理：心率广播未开启给出针对性指引、中途断开指数退避重连（1s→2s→4s，上限 30s）。

**Files:**
- Create: `lib/data/ble/ble_ids.dart`
- Create: `lib/data/ble/reconnect_backoff.dart`
- Create: `lib/data/ble/ble_scanner.dart`
- Create: `lib/data/ble/sensor_monitor.dart`
- Test: `test/data/ble/ble_ids_test.dart`
- Test: `test/data/ble/reconnect_backoff_test.dart`

- [ ] **Step 1: 写退避与 UUID 归一化的失败测试**

创建 `test/data/ble/reconnect_backoff_test.dart`：

```dart
import 'package:cycling_app/data/ble/reconnect_backoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('backoffDelayMs', () {
    test('按 1s → 2s → 4s → 8s → 16s 递增并封顶 30s', () {
      expect(backoffDelayMs(0), 1000);
      expect(backoffDelayMs(1), 2000);
      expect(backoffDelayMs(2), 4000);
      expect(backoffDelayMs(3), 8000);
      expect(backoffDelayMs(4), 16000);
      expect(backoffDelayMs(5), 30000);
      expect(backoffDelayMs(10), 30000);
    });

    test('负数次数按首次处理', () {
      expect(backoffDelayMs(-1), 1000);
    });
  });
}
```

创建 `test/data/ble/ble_ids_test.dart`：

```dart
import 'package:cycling_app/data/ble/ble_ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shortUuid', () {
    test('短形式原样返回', () {
      expect(shortUuid('180d'), '180d');
      expect(shortUuid('2A37'), '2a37');
    });

    test('128 位长形式归一化为短形式', () {
      expect(shortUuid('0000180D-0000-1000-8000-00805F9B34FB'), '180d');
      expect(shortUuid('00002a2b-0000-1000-8000-00805f9b34fb'), '2a2b');
    });

    test('32 位形式归一化为短形式', () {
      expect(shortUuid('00001816'), '1816');
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
fvm flutter test test/data/ble
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写两个纯函数实现**

创建 `lib/data/ble/reconnect_backoff.dart`：

```dart
/// 传感器断线重连的指数退避。见设计文档 11.2：1s → 2s → 4s，上限 30s。
const int kInitialBackoffMs = 1000;

/// 退避上限。
const int kMaxBackoffMs = 30000;

/// 第 [attempt] 次重连（从 0 开始）应等待的毫秒数。
int backoffDelayMs(int attempt) {
  int delay = kInitialBackoffMs;
  for (int i = 0; i < attempt && delay < kMaxBackoffMs; i++) {
    delay *= 2;
  }
  return delay > kMaxBackoffMs ? kMaxBackoffMs : delay;
}
```

创建 `lib/data/ble/ble_ids.dart`：

```dart
/// 标准 GATT 标识的 16 位短 UUID。见设计文档 4 与 14。
///
/// 华为 Fit 3 的心率广播是否为标准 HRS（0x180D）由 Task 3 的真机验证确认，
/// 结论记录在设计文档第 14 节。
const String kHeartRateServiceShort = '180d';
const String kHeartRateMeasurementShort = '2a37';
const String kCscServiceShort = '1816';
const String kCscMeasurementShort = '2a2b';

/// 把任意形式的 UUID 归一化成 16 位短形式（小写）。
///
/// 设备上报的 UUID 可能是 `180d`、`0000180d` 或
/// `0000180d-0000-1000-8000-00805f9b34fb` 三种形式之一，
/// 直接字符串比较会漏匹配，所以统一先归一化。
String shortUuid(String uuid) {
  final String firstGroup = uuid.toLowerCase().split('-').first;
  final String trimmed = firstGroup.replaceFirst(RegExp('^0+'), '');
  return trimmed.isEmpty ? '0' : trimmed;
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
fvm flutter test test/data/ble
```

Expected: `All tests passed!`（5 个测试）

- [ ] **Step 5: 写扫描实现**

创建 `lib/data/ble/ble_scanner.dart`：

```dart
import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// 扫描到的候选设备。
class DiscoveredDevice {
  const DiscoveredDevice({required this.device, required this.name, required this.rssi});

  final BluetoothDevice device;

  /// 设备名。优先用系统缓存的名字，拿不到再用广播里的名字。
  final String name;

  final int rssi;
}

/// 蓝牙适配器状态与设备扫描。只做 IO，不含任何判断逻辑。
class BleScanner {
  const BleScanner();

  /// 蓝牙是否已开启。未开启时由 UI 提示，不视为记录阻断项。
  Future<bool> isAdapterOn() async =>
      await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;

  /// 扫描 [timeout] 时长，返回按信号强度从强到弱排序的候选设备。
  ///
  /// 不使用 `withServices` 过滤：部分设备不在广播里带服务 UUID，
  /// 过滤会直接漏掉它们。改为连上后枚举服务（见 [SensorMonitor]）。
  Future<List<DiscoveredDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final List<DiscoveredDevice> found = <DiscoveredDevice>[];

    final StreamSubscription<List<ScanResult>> sub =
        FlutterBluePlus.scanResults.listen((List<ScanResult> results) {
      for (final ScanResult r in results) {
        final String name =
            r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.advName;
        final DiscoveredDevice d =
            DiscoveredDevice(device: r.device, name: name, rssi: r.rssi);
        final int i = found.indexWhere(
          (DiscoveredDevice e) => e.device.remoteId == r.device.remoteId,
        );
        if (i == -1) {
          found.add(d);
        } else {
          found[i] = d;
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: timeout);
    await Future<void>.delayed(timeout);
    await sub.cancel();
    await FlutterBluePlus.stopScan();

    found.sort((DiscoveredDevice a, DiscoveredDevice b) => b.rssi.compareTo(a.rssi));
    return found;
  }
}
```

- [ ] **Step 6: 写订阅与重连实现**

创建 `lib/data/ble/sensor_monitor.dart`：

```dart
import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../domain/analysis/ble_payload.dart';
import 'ble_ids.dart';
import 'reconnect_backoff.dart';

/// 传感器类型。
enum SensorKind { heartRate, cadence }

/// 传感器读数回调。心率单位为 bpm，踏频单位为 RPM。
typedef SensorReadingCallback = void Function(SensorKind kind, num value);

/// 连接状态回调。
typedef SensorConnectionCallback = void Function(SensorKind kind, bool connected);

/// 监控一个传感器的连接：枚举服务、订阅特征值、断线后指数退避重连。
///
/// 数据帧解析全部交给 domain 层的 [parseHeartRateMeasurement] 与
/// [parseCscMeasurement]，本类只负责 IO 与重连时序。
class SensorMonitor {
  SensorMonitor({
    required this.device,
    required this.kind,
    required this.onReading,
    required this.onConnectionChanged,
  });

  final BluetoothDevice device;
  final SensorKind kind;
  final SensorReadingCallback onReading;
  final SensorConnectionCallback onConnectionChanged;

  StreamSubscription<List<int>>? _valueSub;
  StreamSubscription<BluetoothConnectionState>? _stateSub;
  Timer? _retryTimer;
  int _attempt = 0;
  bool _disposed = false;

  /// 上一次的曲柄数据，用于算踏频。
  CscMeasurement? _lastCsc;

  String get deviceName =>
      device.platformName.isNotEmpty ? device.platformName : device.remoteId.str;

  /// 开始监控。立即尝试连接，之后断线自动重连。
  Future<void> start() async {
    _stateSub = device.connectionState.listen((BluetoothConnectionState s) {
      final bool connected = s == BluetoothConnectionState.connected;
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
      onConnectionChanged(kind, true);
    } catch (_) {
      // 连接或订阅失败都不阻断骑行，按退避节奏再试。
      onConnectionChanged(kind, false);
      _scheduleReconnect();
    }
  }

  Future<void> _subscribe() async {
    await _valueSub?.cancel();
    _valueSub = null;

    final List<BluetoothService> services = await device.discoverServices();
    for (final BluetoothService service in services) {
      final String serviceShort = shortUuid(service.uuid.str);
      final bool serviceMatches = kind == SensorKind.heartRate
          ? serviceShort == kHeartRateServiceShort
          : serviceShort == kCscServiceShort;
      if (!serviceMatches) continue;

      for (final BluetoothCharacteristic c in service.characteristics) {
        final String charShort = shortUuid(c.uuid.str);
        final bool charMatches = kind == SensorKind.heartRate
            ? charShort == kHeartRateMeasurementShort
            : charShort == kCscMeasurementShort;
        if (!charMatches) continue;

        await c.setNotifyValue(true);
        _valueSub = c.onValueReceived.listen(_onValue);
        return;
      }
    }

    // 走到这里说明没找到标准特征值。抛给 _connect 统一走重连，
    // 「心率广播未开启」的针对性指引由 UI 层给出（设计文档 11.2）。
    throw StateError(kind == SensorKind.heartRate
        ? '设备未提供标准心率服务 0x180D'
        : '设备未提供标准踏频服务 0x1816');
  }

  void _onValue(List<int> data) {
    if (kind == SensorKind.heartRate) {
      final int? bpm = parseHeartRateMeasurement(data);
      if (bpm != null) onReading(kind, bpm);
      return;
    }

    final CscMeasurement? cur = parseCscMeasurement(data);
    if (cur == null) return;
    final CscMeasurement? prev = _lastCsc;
    _lastCsc = cur;
    // 第一次收到数据时还没有上一次，无法算踏频，跳过。
    if (prev == null) return;
    final double? rpm = cadenceRpm(prev, cur);
    if (rpm != null) onReading(kind, rpm);
  }

  void _scheduleReconnect() {
    if (_disposed || _retryTimer != null) return;
    final Duration delay = Duration(milliseconds: backoffDelayMs(_attempt));
    _attempt++;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_connect());
    });
  }
}
```

- [ ] **Step 7: 静态检查**

```bash
fvm flutter analyze lib/data/ble
```

Expected: `No issues found!`

- [ ] **Step 8: 提交**

```bash
git add -A
git commit -m "feat: 添加 BLE 扫描、传感器订阅与指数退避重连"
```

---

## Task 19: app 外壳 — 主题、依赖装配、导航壳与恢复入口

设计文档 10 的四 tab 结构与 6.4 的崩溃恢复入口。

**Files:**
- Create: `lib/app/theme.dart`
- Create: `lib/app/providers.dart`
- Create: `lib/app/home_shell.dart`
- Create: `lib/app/recovery_gate.dart`
- Create: `lib/app/app.dart`
- Modify: `lib/main.dart`（替换 flutter create 生成的计数器示例）

> 本任务不写 Widget 测试：设计文档 13 只要求覆盖「记录页两种模式的渲染」与「详情页空数据态」，分别落在 Task 21 与 Plan B。

- [ ] **Step 1: 写主题**

创建 `lib/app/theme.dart`：

```dart
import 'package:flutter/material.dart';

/// 全局主题。车把模式要在户外强光下可读，因此整体用深色高对比。
const Color kAppBackground = Color(0xFF121212);
const Color kAppSurface = Color(0xFF1E1E1E);
const Color kAppAccent = Color(0xFF4CAF50);
const Color kAppWarning = Color(0xFFFFB300);

ThemeData buildAppTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: kAppAccent,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: kAppBackground,
    );
```

- [ ] **Step 2: 写依赖装配**

创建 `lib/app/providers.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../data/ble/ble_scanner.dart';
import '../data/db/database.dart';
import '../data/db/ride_dao.dart';
import '../data/db/settings_dao.dart';
import '../data/db/track_point_dao.dart';
import '../data/location/location_service.dart';
import '../data/ride_repository.dart';
import '../data/settings_repository.dart';

/// 数据库连接。在 `main()` 里打开后用 override 注入，因此这里不需要异步。
final Provider<Database> databaseProvider = Provider<Database>(
  (Ref ref) => throw UnimplementedError('databaseProvider 必须在 main() 中 override'),
);

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
  (Ref ref) => SettingsRepository(SettingsDao(ref.watch(databaseProvider))),
);

final Provider<RideRepository> rideRepositoryProvider = Provider<RideRepository>(
  (Ref ref) => RideRepository(
    rides: RideDao(ref.watch(databaseProvider)),
    points: TrackPointDao(ref.watch(databaseProvider)),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

/// 当前生效的设置。修改设置后 invalidate 本 provider 即可刷新。
final FutureProvider<AppSettings> appSettingsProvider = FutureProvider<AppSettings>(
  (Ref ref) => ref.watch(settingsRepositoryProvider).load(),
);

final Provider<LocationService> locationServiceProvider =
    Provider<LocationService>((Ref ref) => const LocationService());

/// 当前时间（epoch 毫秒）。做成 provider 是为了让记录控制器能在测试里
/// 用假时钟驱动，而不必等待真实时间流逝。
final Provider<int Function()> nowProvider =
    Provider<int Function()>((Ref ref) => () => DateTime.now().millisecondsSinceEpoch);

final Provider<BleScanner> bleScannerProvider =
    Provider<BleScanner>((Ref ref) => const BleScanner());

/// 崩溃恢复时用户选择「继续」的骑行 id。记录页读到后调用
/// `RecordController.resumeExisting` 续写该会话。
final StateProvider<int?> resumeRideIdProvider = StateProvider<int?>((Ref ref) => null);
```

- [ ] **Step 3: 写导航壳**

创建 `lib/app/home_shell.dart`：

```dart
import 'package:flutter/material.dart';

/// 底部四 tab 导航壳。见设计文档 10。
///
/// 本计划先让四个 tab 都指向占位页，保证导航结构一次成型；Task 21 会把
/// 「记录」换成真实的 RecordPage，历史 / 统计 / 设置由 Plan B 实现。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(
          index: _index,
          children: const <Widget>[
            PlaceholderPage(title: '记录'),
            PlaceholderPage(title: '历史'),
            PlaceholderPage(title: '统计'),
            PlaceholderPage(title: '设置'),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (int i) => setState(() => _index = i),
          destinations: const <NavigationDestination>[
            NavigationDestination(icon: Icon(Icons.directions_bike), label: '记录'),
            NavigationDestination(icon: Icon(Icons.history), label: '历史'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: '统计'),
            NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
          ],
        ),
      );
}

/// 尚未实现的页面占位。Plan B 会逐个替换成真实页面。
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Text('$title 页尚未实现')),
      );
}
```

- [ ] **Step 4: 写崩溃恢复入口**

创建 `lib/app/recovery_gate.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/ride.dart';
import 'providers.dart';

/// 启动时扫描未结束的骑行，弹窗让用户选择「继续」或「结算」。见设计文档 6.4。
class RecoveryGate extends ConsumerStatefulWidget {
  const RecoveryGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<RecoveryGate> createState() => _RecoveryGateState();
}

class _RecoveryGateState extends ConsumerState<RecoveryGate> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (_checked) return;
    _checked = true;

    final List<Ride> unfinished = await ref.read(rideRepositoryProvider).findUnfinished();
    if (!mounted || unfinished.isEmpty) return;

    final Ride ride = unfinished.first;
    final bool? resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('检测到未结束的骑行'),
        content: Text('开始于 ${_formatTime(ride.startedAtMs)}，是否继续？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('结算保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (resume == null) return;

    if (resume) {
      ref.read(resumeRideIdProvider.notifier).state = ride.id;
    } else {
      // 结算：用已有轨迹点算出汇总指标，置为 finished。见设计文档 6.4。
      await ref.read(rideRepositoryProvider).settleRide(ride.id!);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String _formatTime(int ms) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
```

- [ ] **Step 5: 写应用外壳与入口**

创建 `lib/app/app.dart`：

```dart
import 'package:flutter/material.dart';

import 'home_shell.dart';
import 'recovery_gate.dart';
import 'theme.dart';

/// 应用外壳。启动时先过 [RecoveryGate] 处理未结束会话，再进入四 tab 主界面。
class CyclingApp extends StatelessWidget {
  const CyclingApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '骑行记录',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const RecoveryGate(child: HomeShell()),
      );
}
```

覆盖 `lib/main.dart`（整份替换）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/db/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 数据库在启动时打开一次，之后所有仓储都复用这个连接。
  final Database db = await openAppDatabase();
  runApp(
    ProviderScope(
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      child: const CyclingApp(),
    ),
  );
}
```

- [ ] **Step 6: 静态检查**

```bash
fvm flutter analyze lib
```

Expected: `No issues found!`

- [ ] **Step 7: 提交**

```bash
git add -A
git commit -m "feat: 添加应用外壳、依赖装配与崩溃恢复入口"
```

---

## Task 20: features/record — 记录控制器

把定位流、传感器流、1Hz 节拍与落盘串起来。设计文档 6.2 的数据流与 11.2 的写入失败重试。

**Files:**
- Create: `lib/features/record/record_controller.dart`
- Create: `test/features/record/record_controller_test.dart`

> 控制器之所以可测，是因为时钟与定位服务都从 provider 读：测试里换成假实现，就能在 `testWidgets` 的 FakeAsync 下确定地跑完，不需要真实 GPS，也不需要真实 SQLite。
>
> **注意不要在这个测试里用 sqflite_ffi**：FakeAsync 下真实 IO 的 Future 永远不会完成，测试会挂死。仓储自身的正确性由 Task 13/14 的内存库测试覆盖，这里只验证编排。

- [ ] **Step 1: 写失败测试**

创建 `test/features/record/record_controller_test.dart`：

```dart
import 'dart:async';

import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/location/location_service.dart';
import 'package:cycling_app/data/ride_repository.dart';
import 'package:cycling_app/domain/models/location_fix.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/recording/recording_session.dart';
import 'package:cycling_app/features/record/record_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

void main() {
  late _FakeRideRepository repo;
  late _FakeLocationService location;
  late int clockMs;

  setUp(() {
    repo = _FakeRideRepository();
    location = _FakeLocationService();
    clockMs = 1000;
  });

  /// 只替换 IO 边界的容器：假仓储、假定位、假时钟。
  ProviderContainer makeContainer() => ProviderContainer(
        overrides: <Override>[
          rideRepositoryProvider.overrideWithValue(repo),
          locationServiceProvider.overrideWithValue(location),
          nowProvider.overrideWithValue(() => clockMs),
        ],
      );

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
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
fvm flutter test test/features/record/record_controller_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`（`record_controller.dart` 还没建）。

- [ ] **Step 3: 写实现**

创建 `lib/features/record/record_controller.dart`：

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/ble/sensor_monitor.dart';
import '../../data/location/location_service.dart';
import '../../domain/analysis/constants.dart';
import '../../domain/analysis/geo.dart';
import '../../domain/models/location_fix.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/ride_status.dart';
import '../../domain/models/track_point.dart';
import '../../domain/recording/recording_session.dart';

/// 记录页的界面模式。见设计文档 10.1。
enum RecordViewMode { handlebar, pocket }

/// 记录页的界面状态。
class RecordState {
  const RecordState({
    this.rideId,
    this.phase,
    this.mode = RecordViewMode.handlebar,
    this.elapsedMs = 0,
    this.distanceM = 0,
    this.currentSpeedMps = 0,
    this.hr,
    this.cadence,
    this.hrConnected = false,
    this.cadenceConnected = false,
    this.gpsWeak = false,
    this.errorMessage,
  });

  final int? rideId;

  /// null 表示尚未开始记录。
  final RecordingPhase? phase;

  final RecordViewMode mode;
  final int elapsedMs;
  final double distanceM;
  final double currentSpeedMps;
  final int? hr;
  final int? cadence;
  final bool hrConnected;
  final bool cadenceConnected;

  /// GPS 超过 10 秒没有新点。见设计文档 11.2 的「信号弱」。
  final bool gpsWeak;

  /// 阻断类错误（定位权限 / 定位服务）或写入连续失败提示，非空时界面需展示。
  final String? errorMessage;

  bool get isActive =>
      phase == RecordingPhase.recording || phase == RecordingPhase.paused;

  bool get isPaused => phase == RecordingPhase.paused;

  bool get isFinished => phase == RecordingPhase.finished;

  int get elapsedSeconds => elapsedMs ~/ 1000;
}

final NotifierProvider<RecordController, RecordState> recordControllerProvider =
    NotifierProvider<RecordController, RecordState>(RecordController.new);

/// 记录会话的编排层：把定位流、传感器流、1Hz 节拍与批量落盘串起来。
class RecordController extends Notifier<RecordState> {
  /// 时钟与定位服务都从 provider 取，测试里可换成假实现。
  LocationService get _location => ref.read(locationServiceProvider);

  RecordingSession? _session;
  Timer? _ticker;
  StreamSubscription<LocationFix>? _fixSub;
  SensorMonitor? _hrMonitor;
  SensorMonitor? _cadenceMonitor;

  int? _rideId;
  RecordViewMode _mode = RecordViewMode.handlebar;
  bool _hrConnected = false;
  bool _cadenceConnected = false;
  bool _finished = false;
  int _lastFixMs = 0;
  int _writeFailures = 0;
  String? _error;
  Future<void>? _pendingWrite;

  @override
  RecordState build() {
    ref.onDispose(_teardown);
    return const RecordState();
  }

  /// 切换界面模式。只影响渲染，不触碰记录逻辑。见设计文档 10.1。
  void setMode(RecordViewMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _publish();
  }

  /// 开始一次新记录。定位权限或定位服务不满足时直接返回并给出提示。
  Future<void> start() async {
    if (_session != null) return;
    _error = null;

    final LocationReadiness readiness = await _location.checkReadiness();
    if (readiness != LocationReadiness.ready) {
      _error = switch (readiness) {
        LocationReadiness.serviceDisabled => '系统定位服务未开启，请先打开定位',
        LocationReadiness.permissionDenied => '未获得定位权限，无法记录骑行',
        LocationReadiness.permissionDeniedForever => '定位权限已被永久拒绝，请到系统设置中开启',
        LocationReadiness.ready => null,
      };
      _publish();
      return;
    }

    final Ride ride = await ref.read(rideRepositoryProvider).startRide(
          startedAtMs: _now(),
          hrDeviceName: _hrMonitor?.deviceName,
          cadenceDeviceName: _cadenceMonitor?.deviceName,
        );
    _rideId = ride.id;
    _session = RecordingSession(rideId: ride.id!, startedAtMs: ride.startedAtMs);
    _startStreams();
    _publish();
  }

  /// 崩溃恢复：接着写已有的会话。见设计文档 6.4。
  ///
  /// 已落盘的那段时长与距离不在内存里，这里按「相邻点间隔之和」补算，
  /// 让界面从正确的基数继续显示；最终汇总仍由 computeSummary 从全部点算出。
  Future<void> resumeExisting(int rideId) async {
    if (_session != null) return;

    final RideRepository repo = ref.read(rideRepositoryProvider);
    final Ride? ride = await repo.getRide(rideId);
    if (ride == null) return;
    final List<TrackPoint> points = await repo.getPoints(rideId);

    int elapsedMs = 0;
    double distanceM = 0;
    for (int i = 1; i < points.length; i++) {
      final int dt = points[i].tMs - points[i - 1].tMs;
      if (dt <= 0 || dt > kGpsGapMs) continue;
      elapsedMs += dt;
      distanceM += segmentDistanceMeters(points[i - 1], points[i]);
    }

    _rideId = rideId;
    _session = RecordingSession(
      rideId: rideId,
      startedAtMs: ride.startedAtMs,
      initialElapsedMs: elapsedMs,
      initialDistanceM: distanceM,
      lastWritten: points.isEmpty ? null : points.last,
    );
    _startStreams();
    _publish();
  }

  void pause() {
    final RecordingSession? session = _session;
    if (session == null || _finished) return;
    session.pause(_now());
    unawaited(_flush(force: true));
    unawaited(ref.read(rideRepositoryProvider).setStatus(_rideId!, RideStatus.paused));
    _publish();
  }

  void resume() {
    final RecordingSession? session = _session;
    if (session == null || _finished) return;
    session.resume(_now());
    unawaited(ref.read(rideRepositoryProvider).setStatus(_rideId!, RideStatus.recording));
    _publish();
  }

  /// 结束记录并结算汇总。结束后状态保留在 [RecordState] 里供界面展示。
  Future<void> finish() async {
    final RecordingSession? session = _session;
    if (session == null || _finished) return;
    _finished = true;

    _ticker?.cancel();
    _ticker = null;
    await _fixSub?.cancel();
    _fixSub = null;
    await _hrMonitor?.dispose();
    await _cadenceMonitor?.dispose();
    _hrMonitor = null;
    _cadenceMonitor = null;
    _hrConnected = false;
    _cadenceConnected = false;

    final int now = _now();
    final List<TrackPoint> remaining = session.finish(now);
    await _persist(remaining);
    await _flush(force: true);

    await ref.read(rideRepositoryProvider).finishRide(
          _rideId!,
          endedAtMs: now,
          durationS: session.snapshot.elapsedSeconds,
        );
    _publish();
  }

  /// 回到「未开始」状态，供用户开始下一次记录。
  void reset() {
    _session = null;
    _rideId = null;
    _finished = false;
    _error = null;
    _writeFailures = 0;
    _lastFixMs = 0;
    state = const RecordState();
  }

  /// 连接一个传感器。失败不阻断骑行，[SensorMonitor] 会自动退避重连。
  Future<void> connectSensor(SensorKind kind, BluetoothDevice device) async {
    if (kind == SensorKind.heartRate) {
      await _hrMonitor?.dispose();
      _hrMonitor = SensorMonitor(
        device: device,
        kind: kind,
        onReading: _onSensorReading,
        onConnectionChanged: _onSensorConnection,
      );
      await _hrMonitor!.start();
      return;
    }

    await _cadenceMonitor?.dispose();
    _cadenceMonitor = SensorMonitor(
      device: device,
      kind: kind,
      onReading: _onSensorReading,
      onConnectionChanged: _onSensorConnection,
    );
    await _cadenceMonitor!.start();
  }

  /// App 退到后台时强制落盘一次，缩小崩溃丢数据的窗口。见设计文档 6.3。
  void handleLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      unawaited(_flush(force: true));
    }
  }

  void _startStreams() {
    _fixSub = _location.fixes().listen(_onFix, onError: (Object _) {});
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onFix(LocationFix fix) {
    final RecordingSession? session = _session;
    if (session == null) return;
    _lastFixMs = fix.tMs;
    session.ingestFix(fix);
    // 实时 UI 按 1Hz 刷新（见设计文档 6.2），因此这里不 publish，
    // 由 _onTick 统一推送，避免每秒几十次重建。
    unawaited(_flush());
  }

  void _onTick() {
    final RecordingSession? session = _session;
    if (session == null || _finished) return;
    session.tick(_now());
    _publish();
    unawaited(_flush());
  }

  void _onSensorReading(SensorKind kind, num value) {
    final RecordingSession? session = _session;
    if (session == null) return;
    if (kind == SensorKind.heartRate) {
      session.ingestHeartRate(value.round());
    } else {
      session.ingestCadence(value.toDouble());
    }
  }

  void _onSensorConnection(SensorKind kind, bool connected) {
    if (kind == SensorKind.heartRate) {
      _hrConnected = connected;
    } else {
      _cadenceConnected = connected;
    }
    _publish();
  }

  /// 攒够一批就提交一个事务；[force] 为真时无条件提交（暂停、结束、退后台）。
  Future<void> _flush({bool force = false}) async {
    final RecordingSession? session = _session;
    if (session == null) return;

    // 等上一次写库结束，避免并发写同一张表。
    final Future<void>? inflight = _pendingWrite;
    if (inflight != null) await inflight;

    if (!force && !session.shouldFlush) return;
    final List<TrackPoint> batch = session.takePendingPoints();
    if (batch.isEmpty) return;

    final Future<void> write = _persist(batch);
    _pendingWrite = write;
    await write;
    if (identical(_pendingWrite, write)) _pendingWrite = null;
  }

  /// 写库失败先重试一次；连续三次失败才提示用户。见设计文档 11.2。
  Future<void> _persist(List<TrackPoint> points) async {
    if (points.isEmpty) return;
    final RideRepository repo = ref.read(rideRepositoryProvider);
    final int rideId = _rideId!;

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        await repo.appendPoints(rideId, points);
        _writeFailures = 0;
        return;
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    }

    _writeFailures++;
    if (_writeFailures >= 3) {
      _error = '轨迹写入连续失败，请检查手机存储空间';
      _publish();
    }
  }

  void _publish() {
    final RecordingSnapshot? snap = _session?.snapshot;
    state = RecordState(
      rideId: _rideId,
      phase: snap?.phase,
      mode: _mode,
      elapsedMs: snap?.elapsedMs ?? 0,
      distanceM: snap?.distanceM ?? 0,
      currentSpeedMps: snap?.currentSpeedMps ?? 0,
      hr: snap?.hr,
      cadence: snap?.cadence,
      hrConnected: _hrConnected,
      cadenceConnected: _cadenceConnected,
      gpsWeak: _isGpsWeak(),
      errorMessage: _error,
    );
  }

  bool _isGpsWeak() {
    if (_session == null || _lastFixMs == 0) return false;
    return _now() - _lastFixMs > kGpsGapMs;
  }

  int _now() => ref.read(nowProvider)();

  void _teardown() {
    _ticker?.cancel();
    _fixSub?.cancel();
    _hrMonitor?.dispose();
    _cadenceMonitor?.dispose();
  }
}
```

- [ ] **Step 4: 给 RecordingSession 补上续写所需的可选参数**

修改 `lib/domain/recording/recording_session.dart` 的构造函数与字段初始化：

```dart
  RecordingSession({
    required this.rideId,
    required this.startedAtMs,
    int initialElapsedMs = 0,
    double initialDistanceM = 0,
    TrackPoint? lastWritten,
  })  : _elapsedMs = initialElapsedMs,
        _distanceM = initialDistanceM,
        _lastWritten = lastWritten,
        _lastTickMs = startedAtMs,
        _lastWrittenMs = lastWritten?.tMs ?? startedAtMs;
```

同时把对应字段改为非 final 的可赋初值形式（去掉字段声明上的初始化）：

```dart
  int _elapsedMs;
  int _lastTickMs;
  int _lastWrittenMs;
  double _distanceM;
  TrackPoint? _lastWritten;
```

- [ ] **Step 5: 补一个续写测试并运行**

在 `test/domain/recording/recording_session_test.dart` 的「落盘」分组里追加：

```dart
    test('可以用已落盘的点续写会话', () {
      const TrackPoint last = TrackPoint(rideId: 1, tMs: 5000, lat: 31.0, lon: 121.0);
      final RecordingSession s = RecordingSession(
        rideId: 1,
        startedAtMs: 0,
        initialElapsedMs: 5000,
        initialDistanceM: 120.0,
        lastWritten: last,
      );
      expect(s.snapshot.elapsedMs, 5000);
      expect(s.snapshot.distanceM, 120.0);

      // 距上一点不足 5 米且不足 2 秒：不写入
      s.ingestFix(const LocationFix(tMs: 6000, lat: 31.00001, lon: 121.0));
      expect(s.takePendingPoints(), isEmpty);

      // 距上一点超过 2 秒：写入
      s.ingestFix(const LocationFix(tMs: 8000, lat: 31.00001, lon: 121.0));
      expect(s.takePendingPoints().length, 1);
    });
```

```bash
fvm flutter test test/domain/recording
```

Expected: `All tests passed!`（29 个测试）

- [ ] **Step 6: 运行控制器测试确认通过**

```bash
fvm flutter test test/features/record/record_controller_test.dart
```

Expected: `All tests passed!`（11 个测试）

- [ ] **Step 7: 静态检查**

```bash
fvm flutter analyze lib test
```

Expected: `No issues found!`

- [ ] **Step 8: 提交**

```bash
git add -A
git commit -m "feat: 添加记录控制器、1Hz 落盘编排与控制器测试"
```

---

## Task 21: features/record — 记录页与两种模式

设计文档 10.1：车把模式（主指标 ≥72pt、屏幕常亮）与口袋模式（不常亮、只留一条状态条），开始前可选模式、途中可切。

**Files:**
- Create: `lib/core/format.dart`
- Create: `test/core/format_test.dart`
- Create: `lib/features/record/handlebar_view.dart`
- Create: `lib/features/record/pocket_view.dart`
- Create: `lib/features/record/device_picker_sheet.dart`
- Create: `lib/features/record/record_page.dart`
- Create: `test/features/record/record_views_test.dart`
- Modify: `lib/app/home_shell.dart`（把「记录」tab 的占位换成 RecordPage）

- [ ] **Step 1: 写格式化函数的失败测试**

创建 `test/core/format_test.dart`：

```dart
import 'package:cycling_app/core/format.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDistance', () {
    test('不足 1 公里用米', () {
      expect(formatDistance(500, DistanceUnit.kilometer), '500 m');
    });

    test('超过 1 公里用公里', () {
      expect(formatDistance(1234, DistanceUnit.kilometer), '1.23 km');
    });

    test('英里单位', () {
      expect(formatDistance(1609.344, DistanceUnit.mile), '1.00 mi');
    });

    test('不足 0.1 英里用英尺', () {
      expect(formatDistance(30, DistanceUnit.mile), '98 ft');
    });
  });

  group('速度与时长', () {
    test('速度数值按单位换算', () {
      expect(formatSpeedValue(6.0, DistanceUnit.kilometer), '21.6');
      expect(formatSpeedValue(6.0, DistanceUnit.mile), '13.4');
    });

    test('速度单位标签', () {
      expect(speedUnitLabel(DistanceUnit.kilometer), 'km/h');
      expect(speedUnitLabel(DistanceUnit.mile), 'mph');
    });

    test('不足一小时用 mm:ss', () {
      expect(formatDuration(90), '01:30');
    });

    test('超过一小时用 h:mm:ss', () {
      expect(formatDuration(3661), '1:01:01');
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
fvm flutter test test/core/format_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写格式化实现**

创建 `lib/core/format.dart`：

```dart
import '../data/settings_repository.dart';

/// 距离文本。不足 1 公里（英里）时换用更小的单位，短距离也能看清。
String formatDistance(double meters, DistanceUnit unit) {
  if (unit == DistanceUnit.mile) {
    final double miles = meters / 1609.344;
    return miles < 0.1
        ? '${(meters * 3.28084).round()} ft'
        : '${miles.toStringAsFixed(2)} mi';
  }
  return meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(2)} km';
}

/// 速度数值，不含单位。
String formatSpeedValue(double mps, DistanceUnit unit) => unit == DistanceUnit.mile
    ? (mps * 3600 / 1609.344).toStringAsFixed(1)
    : (mps * 3.6).toStringAsFixed(1);

/// 速度单位标签。
String speedUnitLabel(DistanceUnit unit) => unit == DistanceUnit.mile ? 'mph' : 'km/h';

/// 时长文本。不足一小时用 mm:ss，超过用 h:mm:ss。
String formatDuration(int seconds) {
  final int safe = seconds < 0 ? 0 : seconds;
  final int h = safe ~/ 3600;
  final int m = (safe % 3600) ~/ 60;
  final int s = safe % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
fvm flutter test test/core/format_test.dart
```

Expected: `All tests passed!`（8 个测试）

- [ ] **Step 5: 写两种模式的失败测试**

创建 `test/features/record/record_views_test.dart`：

```dart
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/recording/recording_session.dart';
import 'package:cycling_app/features/record/handlebar_view.dart';
import 'package:cycling_app/features/record/pocket_view.dart';
import 'package:cycling_app/features/record/record_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const RecordState active = RecordState(
    rideId: 1,
    phase: RecordingPhase.recording,
    elapsedMs: 90000,
    distanceM: 1234.0,
    currentSpeedMps: 6.0,
    hr: 132,
    cadence: 85,
    hrConnected: true,
    cadenceConnected: true,
  );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('车把模式主指标字号不小于 72 且五项指标齐全', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(HandlebarView(
      state: active,
      unit: DistanceUnit.kilometer,
      onPause: () {},
      onResume: () {},
      onFinish: () {},
      onSwitchMode: () {},
    )));

    final Text speed = tester.widget<Text>(find.byKey(const Key('handlebar-speed')));
    expect(speed.style!.fontSize!, greaterThanOrEqualTo(72));
    expect(find.text('21.6'), findsOneWidget);
    expect(find.text('1.23 km'), findsOneWidget);
    expect(find.text('01:30'), findsOneWidget);
    expect(find.text('132'), findsOneWidget);
    expect(find.text('85'), findsOneWidget);
  });

  testWidgets('口袋模式只保留状态条', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(PocketView(
      state: active,
      unit: DistanceUnit.kilometer,
      onPause: () {},
      onResume: () {},
      onFinish: () {},
      onSwitchMode: () {},
    )));

    expect(find.text('记录中'), findsOneWidget);
    expect(find.text('1.23 km'), findsOneWidget);
    expect(find.text('01:30'), findsOneWidget);
    // 口袋模式不渲染大字号主指标
    expect(find.byKey(const Key('handlebar-speed')), findsNothing);
  });

  testWidgets('口袋模式暂停时显示已暂停', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(PocketView(
      state: const RecordState(
        rideId: 1,
        phase: RecordingPhase.paused,
        elapsedMs: 1000,
      ),
      unit: DistanceUnit.kilometer,
      onPause: () {},
      onResume: () {},
      onFinish: () {},
      onSwitchMode: () {},
    )));

    expect(find.text('已暂停'), findsOneWidget);
  });
}
```

- [ ] **Step 6: 运行测试确认失败**

```bash
fvm flutter test test/features/record
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 7: 写车把模式**

创建 `lib/features/record/handlebar_view.dart`：

```dart
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/settings_repository.dart';
import 'record_controller.dart';

/// 车把模式。见设计文档 10.1。
///
/// 主指标字号 ≥72pt、深色高对比；屏幕常亮由 [RecordPage] 用 wakelock 控制。
class HandlebarView extends StatelessWidget {
  const HandlebarView({
    required this.state,
    required this.unit,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.onSwitchMode,
    super.key,
  });

  /// 主指标字号。设计文档 10.1 要求不小于 72。
  static const double primaryFontSize = 76;

  final RecordState state;
  final DistanceUnit unit;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;
  final VoidCallback onSwitchMode;

  @override
  Widget build(BuildContext context) {
    final bool paused = state.isPaused;
    return SafeArea(
      child: Column(
        children: <Widget>[
          _StatusBar(state: state, onSwitchMode: onSwitchMode),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    formatSpeedValue(state.currentSpeedMps, unit),
                    key: const Key('handlebar-speed'),
                    style: const TextStyle(
                      fontSize: primaryFontSize,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    speedUnitLabel(unit),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _Metric(label: '距离', value: formatDistance(state.distanceM, unit)),
                _Metric(label: '时长', value: formatDuration(state.elapsedSeconds)),
                _Metric(label: '心率', value: state.hr?.toString() ?? '--'),
                _Metric(label: '踏频', value: state.cadence?.toString() ?? '--'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: paused ? onResume : onPause,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      backgroundColor: paused ? Colors.green : Colors.orange,
                    ),
                    child: Text(paused ? '继续' : '暂停', style: const TextStyle(fontSize: 22)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onFinish,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('结束', style: TextStyle(fontSize: 22)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state, required this.onSwitchMode});

  final RecordState state;
  final VoidCallback onSwitchMode;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            if (state.gpsWeak)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text('GPS 信号弱', style: TextStyle(color: Colors.orange)),
              ),
            Icon(
              Icons.favorite,
              size: 16,
              color: state.hrConnected ? Colors.red : Colors.grey,
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.sync,
              size: 16,
              color: state.cadenceConnected ? Colors.blue : Colors.grey,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onSwitchMode,
              icon: const Icon(Icons.pocket, size: 18),
              label: const Text('口袋模式'),
            ),
          ],
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
```

- [ ] **Step 8: 写口袋模式**

创建 `lib/features/record/pocket_view.dart`：

```dart
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/settings_repository.dart';
import 'record_controller.dart';

/// 口袋模式。见设计文档 10.1。
///
/// 屏幕不常亮（由 [RecordPage] 关掉 wakelock）、只保留一条状态条，
/// 采集照常进行。
class PocketView extends StatelessWidget {
  const PocketView({
    required this.state,
    required this.unit,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.onSwitchMode,
    super.key,
  });

  final RecordState state;
  final DistanceUnit unit;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;
  final VoidCallback onSwitchMode;

  @override
  Widget build(BuildContext context) {
    final bool paused = state.isPaused;
    final String status = paused ? '已暂停' : '记录中';
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (state.gpsWeak)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('GPS 信号弱', style: TextStyle(color: Colors.orange)),
            ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(status, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                Text(formatDistance(state.distanceM, unit), style: const TextStyle(fontSize: 18)),
                Text(formatDuration(state.elapsedSeconds), style: const TextStyle(fontSize: 18)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              OutlinedButton(
                onPressed: paused ? onResume : onPause,
                child: Text(paused ? '继续' : '暂停'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: onFinish,
                child: const Text('结束'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onSwitchMode,
                icon: const Icon(Icons.phone_android, size: 18),
                label: const Text('车把模式'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 9: 运行测试确认通过**

```bash
fvm flutter test test/features/record
```

Expected: `All tests passed!`（14 个测试：11 个控制器测试 + 3 个 Widget 测试）

- [ ] **Step 10: 写设备选择面板**

创建 `lib/features/record/device_picker_sheet.dart`：

```dart
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
                          error is StateError ? '${error.message}' : '扫描失败：$error',
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
                        subtitle: Text('${d.device.remoteId.str}   信号 ${d.rssi}'),
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
```

- [ ] **Step 11: 写记录页**

创建 `lib/features/record/record_page.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/ble/ble_scanner.dart';
import '../../data/ble/sensor_monitor.dart';
import '../../data/settings_repository.dart';
import 'device_picker_sheet.dart';
import 'handlebar_view.dart';
import 'pocket_view.dart';
import 'record_controller.dart';

/// 记录页。见设计文档 10.1：两种模式共用同一个记录引擎，只切换渲染层。
class RecordPage extends ConsumerStatefulWidget {
  const RecordPage({super.key});

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<RecordPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeResumeRequest());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_setWakelock(false));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 退到后台时强制落盘一次，缩小崩溃丢数据的窗口。
    ref.read(recordControllerProvider.notifier).handleLifecycle(state);
  }

  /// 崩溃恢复时用户在启动弹窗里选了「继续」，这里接着写那个会话。
  void _consumeResumeRequest() {
    final int? rideId = ref.read(resumeRideIdProvider);
    if (rideId == null) return;
    ref.read(resumeRideIdProvider.notifier).state = null;
    unawaited(ref.read(recordControllerProvider.notifier).resumeExisting(rideId));
  }

  Future<void> _setWakelock(bool enable) async {
    try {
      if (enable) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // 没有 wakelock 通道的环境（测试、桌面）忽略即可。
    }
  }

  Future<void> _pickDevice(SensorKind kind) async {
    final DiscoveredDevice? device = await showModalBottomSheet<DiscoveredDevice>(
      context: context,
      builder: (BuildContext context) => DevicePickerSheet(kind: kind),
    );
    if (device == null) return;
    await ref.read(recordControllerProvider.notifier).connectSensor(kind, device.device);
  }

  Future<void> _confirmFinish(RecordController controller) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('结束本次骑行？'),
        content: const Text('结束后会保存记录并结算指标，无法再继续记录。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('结束'),
          ),
        ],
      ),
    );
    if (ok ?? false) await controller.finish();
  }

  @override
  Widget build(BuildContext context) {
    final RecordState state = ref.watch(recordControllerProvider);
    final RecordController controller = ref.read(recordControllerProvider.notifier);
    final DistanceUnit unit =
        ref.watch(appSettingsProvider).value?.distanceUnit ?? DistanceUnit.kilometer;

    // 车把模式且正在记录时屏幕常亮。见设计文档 10.1。
    ref.listen<RecordState>(recordControllerProvider, (RecordState? _, RecordState next) {
      unawaited(_setWakelock(
        next.isActive && !next.isPaused && next.mode == RecordViewMode.handlebar,
      ));
    });

    final Widget body;
    if (state.isFinished) {
      body = _FinishedView(state: state, unit: unit, onReset: controller.reset);
    } else if (state.isActive) {
      body = state.mode == RecordViewMode.handlebar
          ? HandlebarView(
              state: state,
              unit: unit,
              onPause: controller.pause,
              onResume: controller.resume,
              onFinish: () => _confirmFinish(controller),
              onSwitchMode: () => controller.setMode(RecordViewMode.pocket),
            )
          : PocketView(
              state: state,
              unit: unit,
              onPause: controller.pause,
              onResume: controller.resume,
              onFinish: () => _confirmFinish(controller),
              onSwitchMode: () => controller.setMode(RecordViewMode.handlebar),
            );
    } else {
      body = _IdleView(
        state: state,
        onStart: controller.start,
        onPickDevice: _pickDevice,
        onModeChanged: controller.setMode,
      );
    }

    return Scaffold(body: body);
  }
}

/// 未开始时的准备界面：选模式、连传感器、开始。见设计文档 6.1 与 10.1。
class _IdleView extends StatelessWidget {
  const _IdleView({
    required this.state,
    required this.onStart,
    required this.onPickDevice,
    required this.onModeChanged,
  });

  final RecordState state;
  final Future<void> Function() onStart;
  final void Function(SensorKind kind) onPickDevice;
  final void Function(RecordViewMode mode) onModeChanged;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Spacer(),
              const Icon(Icons.directions_bike, size: 64),
              const SizedBox(height: 16),
              Text(
                '准备骑行',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 32),
              SegmentedButton<RecordViewMode>(
                segments: const <ButtonSegment<RecordViewMode>>[
                  ButtonSegment<RecordViewMode>(
                    value: RecordViewMode.handlebar,
                    label: Text('车把'),
                    icon: Icon(Icons.phone_android),
                  ),
                  ButtonSegment<RecordViewMode>(
                    value: RecordViewMode.pocket,
                    label: Text('口袋'),
                    icon: Icon(Icons.pocket),
                  ),
                ],
                selected: <RecordViewMode>{state.mode},
                onSelectionChanged: (Set<RecordViewMode> selected) =>
                    onModeChanged(selected.first),
              ),
              const SizedBox(height: 24),
              // 传感器连不上不阻断开始记录。见设计文档 6.1。
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onPickDevice(SensorKind.heartRate),
                      icon: Icon(state.hrConnected ? Icons.favorite : Icons.favorite_border),
                      label: Text(state.hrConnected ? '心率已连接' : '连接心率'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onPickDevice(SensorKind.cadence),
                      icon: Icon(state.cadenceConnected ? Icons.sync : Icons.sync_disabled),
                      label: Text(state.cadenceConnected ? '踏频已连接' : '连接踏频'),
                    ),
                  ),
                ],
              ),
              if (state.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    state.errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),
              const Spacer(),
              FilledButton(
                onPressed: onStart,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                child: const Text('开始骑行', style: TextStyle(fontSize: 22)),
              ),
            ],
          ),
        ),
      );
}

/// 结束后的结算界面。
class _FinishedView extends StatelessWidget {
  const _FinishedView({required this.state, required this.unit, required this.onReset});

  final RecordState state;
  final DistanceUnit unit;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Spacer(),
              const Icon(Icons.check_circle, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              Text(
                '记录已保存',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _FinishedMetric(label: '距离', value: formatDistance(state.distanceM, unit)),
                  _FinishedMetric(label: '时长', value: formatDuration(state.elapsedSeconds)),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: onReset,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                child: const Text('完成', style: TextStyle(fontSize: 22)),
              ),
            ],
          ),
        ),
      );
}

class _FinishedMetric extends StatelessWidget {
  const _FinishedMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
```

- [ ] **Step 12: 把「记录」tab 换成真实页面**

修改 `lib/app/home_shell.dart`：加上 import，并把 children 的第一项换掉。

```dart
import 'package:flutter/material.dart';

import '../features/record/record_page.dart';
```

```dart
          children: const <Widget>[
            RecordPage(),
            PlaceholderPage(title: '历史'),
            PlaceholderPage(title: '统计'),
            PlaceholderPage(title: '设置'),
          ],
```

- [ ] **Step 13: 静态检查**

```bash
fvm flutter analyze lib
```

Expected: `No issues found!`

- [ ] **Step 14: 提交**

```bash
git add -A
git commit -m "feat: 添加记录页的车把与口袋两种模式"
```

---

## Task 22: 端到端真机验证

设计文档 13 明确「真实 BLE 硬件、真实 GPS、地图渲染」三项手动验证。本任务覆盖前两项（地图属于 Plan B）。

**Files:**
- 无（只做验证与记录）

- [ ] **Step 1: 跑全部自动化测试**

```bash
fvm flutter test
```

Expected: `All tests passed!`

- [ ] **Step 2: 在真机上跑起来**

```bash
fvm flutter devices
fvm flutter run -d <你的设备 id>
```

Expected: 应用启动后停在「记录」tab 的准备界面，四个 tab 可切换。

- [ ] **Step 3: 验证阻断类校验**

先关掉系统定位，点「开始骑行」。

Expected: 显示「系统定位服务未开启，请先打开定位」，不进入记录态。
再打开定位、在系统设置里拒绝本应用的定位权限，重试。

Expected: 显示「未获得定位权限，无法记录骑行」。

- [ ] **Step 4: 验证定位与落盘**

恢复定位权限，点「开始骑行」，带手机在户外走 2 分钟（或骑行）。

Expected:
- 车把模式主指标随速度变化，距离、时长持续增长
- 时长每秒 +1，暂停后停住，继续后接着走
- 结束后出现「记录已保存」

- [ ] **Step 5: 验证数据库真的写进去了**

在电脑上拉出数据库文件查看：

```bash
fvm flutter run -d <你的设备 id> --dart-define=DEBUG_DUMP=true
```

或者用 `adb`（Android）：

```bash
adb exec-out run-as com.ling.cycling_app cat databases/cycling_app.db > /tmp/cycling_app.db
sqlite3 /tmp/cycling_app.db "select id, status, started_at_ms, ended_at_ms, distance_m, duration_s from rides;"
sqlite3 /tmp/cycling_app.db "select count(*) from track_points;"
```

Expected: `rides` 里有一条 `status = finished` 的记录，`track_points` 行数与实际骑行时间大致相符（移动时约 1 点/秒）。

- [ ] **Step 6: 验证崩溃恢复**

重新点「开始骑行」，骑 30 秒后从系统里强杀 App（不要点结束），再重新打开。

Expected: 弹出「检测到未结束的骑行」，选择「继续」后界面从原距离与时长接着走；
再次强杀并选择「结算保存」，该条记录变成 `finished`，重启后不再弹窗。

- [ ] **Step 7: 验证心率广播（设计文档第 14 节的风险 1）**

在华为运动健康里开启 Fit 3 的心率广播，回到 App，点「连接心率」，选中 Fit 3。

Expected:
- 连接成功后「心率已连接」变亮，车把模式心率数字随实际心率变化
- 若列表里找不到 Fit 3，或连上后心率一直为 `--`，说明不是标准 BLE HRS，
  把结论写进设计文档第 14 节，并据此调整心率来源方案

- [ ] **Step 8: 验证心率广播与华为运动健康的连接冲突（风险 2）**

在 Fit 3 已连接华为运动健康的情况下开启心率广播，观察运动健康是否掉线，以及关闭广播后能否自动恢复。

Expected: 记录实际现象到设计文档第 14 节。

- [ ] **Step 9: 验证踏频器**

给踏频器装上电池，点「连接踏频」，选中设备，转动曲柄。

Expected: 踏频数字随转速变化；停转 5 秒以上后数字保持不变（不再刷新），重新转动后恢复。
把踏频器拿到远处直到断连，再拿回来。

Expected: 图标变灰后按 1s → 2s → 4s 的节奏自动重连，最终恢复连接。

- [ ] **Step 10: 验证两种模式与功耗**

记录中切到口袋模式，锁屏放进兜里骑 5 分钟，再解锁切回车把模式。

Expected:
- 口袋模式下屏幕不常亮（会自动息屏）
- 切回车把模式后屏幕保持常亮
- 两种模式下距离与时长都在持续增长

- [ ] **Step 11: 提交验证结论**

把第 7、8 步的实测结论追加到 `docs/superpowers/specs/2026-09-21-cycling-app-design.md` 第 14 节，然后：

```bash
git add -A
git commit -m "docs: 补充 Fit 3 心率广播的真机验证结论"
```

---

## 自审记录

写完后按 writing-plans 的要求做了一遍检查，结论如下。

### 规格覆盖

| 设计文档章节 | 落在哪个任务 |
| --- | --- |
| 4 技术栈 | Task 1 |
| 5 架构与目录结构 | 文件结构章节 + 每个任务的 import 约束 |
| 6.1 状态机 | Task 16（引擎内阶段）+ Task 21（preparing 由准备界面承担） |
| 6.2 数据流 | Task 20 |
| 6.3 落盘策略 | Task 15（规则 1、2）+ Task 13/14（规则 3 的 status 标记） |
| 6.4 崩溃恢复 | Task 19（入口）+ Task 20（resumeExisting） |
| 7 数据模型 | Task 4、12、13 |
| 8.1 数值陷阱 | Task 5（常量与距离）、6（爬升）、7（最高速） |
| 8.2 指标定义 | Task 7（移动/静止）、8（心率区间、卡路里）、9（颜色映射）、10（汇总） |
| 8.3 计算时机 | Task 10 + Task 14（finishRide / settleRide） |
| 9.2 轨迹着色 | Task 9 的 `segmentColorArgb`（渲染在 Plan B） |
| 10.1 记录页 | Task 21（两种模式）+ Task 20（模式不影响记录逻辑） |
| 11.1 阻断类 | Task 17 + Task 20 的 start 前置校验 |
| 11.2 非阻断类 | Task 18（断线重连、心率广播指引）+ Task 20（写库重试）+ Task 19（恢复） |
| 13 测试策略 | Task 15/16（状态机与批量落盘）、Task 20（控制器编排，11 个用例）、Task 21（Widget 测试）；BLE 与 GPS 手动验证见 Task 22 |
| 14 待验证风险 | Task 3（最小 BLE 扫描验证）+ Task 22（真机复验） |

未覆盖的部分都属于 Plan B：9.1 地图、10.2 历史页、10.3 详情页、10.4 统计页、10.5 设置页、12 导出与备份。

### 留给 Plan B 的已知缺口（必须在 Plan B 里解决）

1. **坐标系偏移**：设计文档 9.1 用高德栅格瓦片，高德是 GCJ-02 坐标系，而手机 GPS 输出 WGS-84。
   直接把 WGS-84 经纬度画在 GCJ-02 瓦片上，轨迹会偏移数百米。
   Plan B 需要新增 `lib/domain/analysis/gcj02.dart`，提供 `wgs84ToGcj02(lat, lon)`（含「是否在中国境外」的判断），
   并让地图图层使用转换后的坐标——注意只转换显示用的坐标，**落盘的仍是 WGS-84 原始坐标**，
   否则 GPX 导出会给出一份偏移过的数据。
2. **地图上的 GPS 跳变断线**：本计划让跳变点照常落盘（分析层已不计入距离），
   Plan B 的地图渲染需要按「时间间隔 > 10s」**或**「隐含速度 > `kMaxPlausibleSpeedMps`」断开折线。
3. **传感器配对持久化**：本计划每次开始前手动连接，`settings` 表里预留了传感器相关字段但未使用；
   Plan B 的设置页需要把选中的设备 id 存下来并自动重连。

### 占位符扫描

全文没有 TBD / TODO / 「稍后实现」；每个代码步骤都给了可直接粘贴的完整代码与确切路径。
`PlaceholderPage` 是 Task 19 里真实存在的 UI 占位组件（有实际渲染内容），不是计划占位符，Task 21 会替换掉记录 tab 的那一个。

### 类型一致性

逐个核对了跨任务引用的名字，确认一致：

- `RideStatus.recording/paused/finished`（Task 4）↔ Task 14 的 `setStatus` ↔ Task 20 的 pause/resume
- `TrackPoint.hasPosition`（Task 4）↔ Task 15 的过滤 ↔ Task 16 的纯传感器点
- `haversineMeters` / `segmentDistanceMeters`（Task 5）↔ Task 15、16、20
- `kMinWriteDistanceM` / `kMaxWriteIntervalMs` / `kGpsGapMs` / `kSensorBatchSize` / `kMaxPlausibleSpeedMps`（Task 5）↔ Task 15、16、20
- `parseHeartRateMeasurement` / `parseCscMeasurement` / `cadenceRpm` / `CscMeasurement`（Task 11）↔ Task 18
- `RideRepository.startRide/appendPoints/setStatus/finishRide/settleRide/findUnfinished/getRide/getPoints/lastPoint`（Task 14）↔ Task 19、20
- `AppSettings.distanceUnit` + `DistanceUnit.kilometer/mile`（Task 14）↔ Task 21 的 `format.dart` 与两个 view
- `WriteBuffer.isFull/drain`（Task 15）↔ `RecordingSession.shouldFlush/takePendingPoints`（Task 16）↔ Task 20 的 `_flush`
- `RecordingSession` 的 `initialElapsedMs` / `initialDistanceM` / `lastWritten`（Task 20 Step 4 补充）↔ Task 20 的 `resumeExisting`
- `nowProvider` / `locationServiceProvider`（Task 19）↔ Task 20 的 `_now()` / `_location` ↔ Task 20 的控制器测试 override
- `SensorKind.heartRate/cadence`（Task 18）↔ Task 20 的 `connectSensor` ↔ Task 21 的 `DevicePickerSheet`
- `resumeRideIdProvider`（Task 19）↔ Task 20 的 `resumeExisting` ↔ Task 21 的 `_consumeResumeRequest`
- `DiscoveredDevice`（Task 18）↔ Task 21 的 `DevicePickerSheet` 返回值

### 控制器测试的取舍

设计文档 13 要求「注入假的定位流与传感器流，测试记录引擎」，这一点分两层满足：

- **domain 层**（Task 15/16）：状态机、批量落盘、GPS 丢失、续写，全部用注入时间的方式测试，不碰任何 IO。
- **编排层**（Task 20）：时钟走 `nowProvider`、定位走 `locationServiceProvider`，测试里换成假实现，11 个用例覆盖前置校验、批量提交、暂停落盘、结束结算、信号弱、写入失败提示、崩溃续写、reset、模式切换。

之所以在控制器测试里**不**接真实的 `sqflite_ffi` 内存库，是因为 `testWidgets` 跑在 FakeAsync 里，真实 IO 的 Future 不会完成，测试会挂死；
仓储本身的正确性已经由 Task 13/14 的内存库测试覆盖，这里用假仓储只验证编排。

### 执行方式

按 writing-plans 的要求，实施时二选一：

1. **Subagent-Driven（推荐）**：每个任务派一个全新的 subagent 执行，任务之间我来审查，迭代快、上下文干净。
2. **Inline Execution**：在当前会话里按批次执行，到检查点停下来给你确认。

两种方式都要用 `fvm flutter`（本机没有全局 flutter/dart），且每个任务结束都要单独提交。
