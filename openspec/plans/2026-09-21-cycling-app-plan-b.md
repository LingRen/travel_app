# 骑行记录与分析 App — Plan B 实施计划（历史 / 详情 / 地图 / 统计 / 设置 / 导出与备份）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在已完成的记录链路（Plan A）之上补齐「事后分析」的全部能力：历史列表、单次详情（地图轨迹 + 三条曲线 + 心率区间）、长期统计与个人最佳、设置页、GPX 导出与全量备份恢复。

**Architecture:** 沿用 Plan A 的分层。`domain/` 放全部纯函数（坐标转换、曲线准备、轨迹分段、趋势聚合），可脱离 Flutter 单测；`data/` 放 IO（DAO 扩展、GPX 生成、ZIP 备份、传感器配对持久化）；`features/` 放 Riverpod + Widget。**所有渲染都消费 domain 算好的数据**——因此地图与图表本身不做自动化测试（设计文档 13 明确「地图渲染」属于手动验证项），但喂给它们的数据全部有测试兜住。

**Tech Stack:** Flutter 3.47.4 / Dart 3.13.3、flutter_riverpod 3.4.3、sqflite 2.4.4（测试用 sqflite_common_ffi 2.4.3）、fl_chart 1.2.0、flutter_map 8.3.2 + latlong2 0.10.1、share_plus 13.3.0、path_provider 2.1.6、file_picker 13.1.0、archive 4.3.0、xml 7.0.1、wakelock_plus 1.8.0。
**依赖已在 Plan A 的 `pubspec.yaml` 里全部就位，本计划不新增、不升级任何依赖。**

---

## 前置：Plan A 已完成的接口（本计划直接依赖，不要重新实现）

实施本计划前必须知道这些**已经存在**的符号。签名已按真实代码核对过。

### domain 层

| 文件 | 已有符号 |
| --- | --- |
| `lib/domain/models/ride.dart` | `class Ride { int? id; int startedAtMs; int? endedAtMs; RideStatus status; String? title; RideSummary? summary; String? hrDeviceName; String? cadenceDeviceName; }` |
| `lib/domain/models/track_point.dart` | `class TrackPoint { int? id; int rideId; int tMs; double? lat; double? lon; double? altitudeM; double? speedMps; double? accuracyM; int? hr; int? cadence; bool get hasPosition; }` |
| `lib/domain/models/ride_summary.dart` | `class RideSummary { double distanceM; int durationS; int movingS; double avgSpeedMps; double movingAvgSpeedMps; double? maxSpeedMps; double elevationGainM; double? avgHr; int? maxHr; double? avgCadence; double? calories; int pointCount; }` |
| `lib/domain/models/ride_status.dart` | `enum RideStatus { recording, paused, finished }`，`String get dbValue`、`static RideStatus fromDb(String)` |
| `lib/domain/analysis/constants.dart` | `kElevationFilterWindow = 5`、`kElevationGainThresholdM = 1.0`、`kSpeedFilterWindow = 5`、`kStationarySpeedMps`、`kMinWriteDistanceM = 5.0`、`kMaxWriteIntervalMs = 2000`、`kGpsGapMs = 10000`、`kSensorBatchSize = 10`、`kColorScaleMaxSpeedMps = 15.0`、`kMaxPlausibleSpeedMps = 30.0` |
| `lib/domain/analysis/geo.dart` | `double haversineMeters(double lat1, double lon1, double lat2, double lon2)`、`bool isTrustedSegment(TrackPoint a, TrackPoint b)`、`double segmentDistanceMeters(TrackPoint a, TrackPoint b)` |
| `lib/domain/analysis/speed.dart` | `List<double?> movingAverage(List<double?> values, int window)`、`double? maxSmoothedSpeed(List<double?> speeds, int window)`、`class MovingStats { double movingSeconds; double stationarySeconds; }`、`MovingStats splitMovingStationary(List<TrackPoint> points, double thresholdMps)` |
| `lib/domain/analysis/elevation.dart` | `List<double?> medianFilterElevation(List<double?> values, int window)`、`double elevationGainMeters(List<double?> filtered, double thresholdM)` |
| `lib/domain/analysis/heart_rate.dart` | `class HrZone { int index; String label; double minRatio; double maxRatio; }`、`const List<HrZone> kHrZones`、`int? zoneIndexForHr(int hr, int maxHeartRate)`、`class HrZoneBreakdown { Map<int,double> secondsByZone; double totalSeconds; double ratioOf(int) }`、`HrZoneBreakdown hrZoneBreakdown(List<TrackPoint> points, int maxHeartRate)`、`double? averageHr(List<TrackPoint>)`、`int? observedMaxHr(List<TrackPoint>)` |
| `lib/domain/analysis/color_scale.dart` | `int speedColorArgb(double speedMps, {double maxSpeedMps = kColorScaleMaxSpeedMps})`、`int segmentColorArgb(double speedA, double speedB, {double maxSpeedMps = kColorScaleMaxSpeedMps})`、`kSpeedColorSlow/Mid/Fast` |
| `lib/domain/analysis/summary.dart` | `RideSummary computeSummary({required List<TrackPoint> points, required int durationS, required int maxHeartRate, required double weightKg})` |

### data 层

| 文件 | 已有符号 |
| --- | --- |
| `lib/data/db/database.dart` | `const int kSchemaVersion = 1`、`Future<Database> openAppDatabase({String? path})` |
| `lib/data/db/ride_dao.dart` | `RideDao(Database)`，`insert(Ride)`、`findById(int)`、`findUnfinished()`、`listFinished({int? limit, int? offset})`、`markFinished({required int id, required int endedAtMs, required RideSummary summary})`、`updateStatus(int, RideStatus)`、`updateTitle(int, String?)`、`delete(int)` |
| `lib/data/db/track_point_dao.dart` | `TrackPointDao(Database)`，`insertBatch(List<TrackPoint>)`、`listByRide(int)`、`countByRide(int)`、`lastByRide(int)`、`deleteByRide(int)` |
| `lib/data/db/settings_dao.dart` | `SettingsDao(Database)`，`getString(String)`、`setString(String, String)`、`getAll()`。**注意：没有 `remove`，Task 5 要补** |
| `lib/data/ride_repository.dart` | `RideRepository({required RideDao rides, required TrackPointDao points, required SettingsRepository settings})`，`startRide/appendPoints/setStatus/finishRide/settleRide/findUnfinished/listFinished/getRide/getPoints/lastPoint/updateTitle/deleteRide` |
| `lib/data/settings_repository.dart` | `enum DistanceUnit { kilometer('km'), mile('mi') }`、`kDefaultMaxHeartRate = 190`、`kDefaultWeightKg = 70`、`kMinPlausibleMaxHeartRate = 100`、`kMaxPlausibleMaxHeartRate = 230`、`kDefaultMapTileUrlTemplate`、`kDefaultMapTileSubdomains`、`class AppSettings { int maxHeartRate; double weightKg; DistanceUnit distanceUnit; String mapTileUrlTemplate; AppSettings copyWith({...}) }`、`class SettingsRepository { Future<AppSettings> load(); Future<void> save(AppSettings); }` |
| `lib/data/ble/ble_platform.dart` | `class BleScanEntry { BleDeviceHandle device; String advertisedName; int rssi; }`、`abstract class BleCharacteristicHandle { String get serviceUuid; String get uuid; Future<void> setNotifyValue(bool); Stream<List<int>> get onValueReceived; }`、`abstract class BleDeviceHandle { String get id; String get name; Stream<bool> get connectionState; Future<void> connect({required Duration timeout}); Future<void> disconnect(); Future<List<BleCharacteristicHandle>> discoverCharacteristics(); }`、`abstract class BlePlatform { Future<bool> isAdapterOn(); Stream<List<BleScanEntry>> scanResults(); Future<void> startScan({required Duration timeout}); Future<void> stopScan(); }`、`class FlutterBluePlusPlatform`、`class FlutterBluePlusDevice`、`class FlutterBluePlusCharacteristic` |
| `lib/data/ble/ble_scanner.dart` | `class DiscoveredDevice { BleDeviceHandle device; String name; int rssi; }`、`class BleScanner { const BleScanner({BlePlatform _platform = const FlutterBluePlusPlatform()}); Future<bool> isAdapterOn(); Future<List<DiscoveredDevice>> scan({Duration timeout = const Duration(seconds: 10)}); }` |
| `lib/data/ble/sensor_monitor.dart` | `enum SensorKind { heartRate, cadence }`、`class SensorMonitor { SensorMonitor({required BleDeviceHandle device, required SensorKind kind, required SensorReadingCallback onReading, required SensorConnectionCallback onConnectionChanged, BleTimerFactory _timerFactory = defaultBleTimerFactory}); String get deviceName; String? lastError; Future<void> start(); Future<void> dispose(); }` |

### app / features 层

| 文件 | 已有符号 |
| --- | --- |
| `lib/app/providers.dart` | `databaseProvider`(Provider&lt;Database&gt;，必须 override)、`settingsRepositoryProvider`、`rideRepositoryProvider`、`appSettingsProvider`(FutureProvider&lt;AppSettings&gt;)、`locationServiceProvider`、`nowProvider`(Provider&lt;int Function()&gt;)、`bleScannerProvider`、`resumeRideIdProvider`(StateProvider&lt;int?&gt;) |
| `lib/app/theme.dart` | `kAppBackground = Color(0xFF121212)`、`kAppSurface = Color(0xFF1E1E1E)`、`kAppAccent = Color(0xFF4CAF50)`、`kAppWarning = Color(0xFFFFB300)`、`ThemeData buildAppTheme()` |
| `lib/app/home_shell.dart` | `class HomeShell`（`IndexedStack` + `NavigationBar`，tab 顺序 `['记录','历史','统计','设置']`）、`class PlaceholderPage({required String title, super.key})`。**「记录」tab 已是 `RecordPage()`；历史/统计/设置仍是 `PlaceholderPage`，本计划替换它们** |
| `lib/app/app.dart` | `class CyclingApp`，`MaterialApp(theme: buildAppTheme(), home: const RecoveryGate(child: HomeShell()))`。**没有命名路由，页面跳转一律用 `Navigator.push(MaterialPageRoute(...))`** |
| `lib/core/format.dart` | `String formatDistance(double meters, DistanceUnit unit)`、`String formatSpeedValue(double mps, DistanceUnit unit)`、`String speedUnitLabel(DistanceUnit unit)`、`String formatDuration(int seconds)` |
| `lib/features/record/record_controller.dart` | `enum RecordViewMode`、`class RecordState`、`recordControllerProvider`(NotifierProvider&lt;RecordController, RecordState&gt;)、`RecordController` 的 `start/resumeExisting/pause/resume/finish/reset/setMode/handleLifecycle/connectSensor(SensorKind, BleDeviceHandle)` |

---

## 工具链与执行约束（每个任务的实施者都必须遵守）

1. **本机没有全局 `flutter` / `dart`。** 用 **`.fvm/flutter_sdk/bin/flutter`**（相对仓库根目录）。
   `fvm flutter ...` 有时会因联网检查版本失败而整个命令报错（`✗ Failed to retrieve the Flutter SDK from: https://storage.googleapis.com/...`），遇到就改用上面的直接路径。
2. **`flutter test` / `analyze` 的退出码可能是 1 但实际成功**：沙箱会拦截 `.dartServer` / `.dart_tool` 并打印 `TRAE Sandbox Error: hit restricted`。
   **判据是输出内容**：`All tests passed!` / `No issues found!`，不是退出码。
3. **本机完全访问不了 github.com。严禁** `flutter pub get` / `pub clean` / `pub upgrade`，**严禁**增删改任何依赖版本。
   手工配置的 sqlite3 native asset 缓存 `.dart_tool/hooks_runner/shared/sqlite3/build/download-6d80ba56/libsqlite3.dylib` 被 gitignore，删掉就要重做。
4. **`flutter test` 首次编译约 3.5 分钟**，Shell 的 timeout 一律设 `600000`。
5. **SQLite 相关测试**：`setUpAll` 里 `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;`，用 `openAppDatabase(path: inMemoryDatabasePath)` 开内存库。参考已有的 `test/data/db/ride_dao_test.dart`。
6. **Widget 测试**：FakeAsync 下真实 IO 的 Future 永不完成，**必须用 `databaseFactoryFfiNoIsolate`**（不是 `databaseFactoryFfi`）；或者干脆用 override 注入假数据，不碰数据库。参考已有的 `test/app/home_shell_test.dart` 与 `test/features/record/record_views_test.dart`。
7. **`SensorMonitor.dispose()` 在 FakeAsync 下有挂死风险**：它内部 `await <广播流订阅>.cancel()` 的续延在 FakeAsync 下永不 flush。
   生产环境无影响，但**任何「已连接传感器 + `finish()`」的 widget 测试都会挂死**。写测试时避开这条组合路径。
8. **Riverpod 3 的导入位置**：`StateProvider` 在 `package:flutter_riverpod/legacy.dart`；`Override` 类型在 `package:flutter_riverpod/misc.dart`。
9. **每个任务结束都要单独提交**，提交前确认 `git status` 干净。
10. **不要默认本计划是对的。** Plan A 的 22 个任务里，有 11 个任务的计划书代码照抄会编译失败或测试挂死（详见 Plan A 文档末尾「实施偏差记录」）。
    实施时若发现本计划的代码有错：**先用实测数字确认，再做最小修正**，并在报告里写清「计划原文 → 实际做法 → 证据（测试输出/analyze 输出/行号）」。**不得为了让测试变绿而削弱测试意图。**
11. **每个任务必须做变异测试自证**：把实现改坏，确认至少有一个用例变红，然后改回来。没被杀死的变异要补用例并报告。

---

## 文件结构

本计划新增/修改的全部文件，以及每个文件的唯一职责。

```text
lib/
  domain/analysis/
    gcj02.dart              # WGS-84 → GCJ-02 坐标转换（纯函数，无 IO）
    curve.dart              # 把轨迹点整理成图表可用的曲线序列（含降采样与断点分段）
    route_segments.dart     # 把轨迹点整理成地图可用的分段折线（含 GCJ-02 转换与断点断开）
    trend.dart              # 周/月/年聚合、趋势桶、个人最佳（纯函数）
  data/
    db/
      settings_dao.dart     # 修改：补 remove(key)
      ride_dao.dart         # 修改：补日期范围查询、countFinished、insertWithId、deleteAll
      track_point_dao.dart  # 修改：补 listAll、deleteAll
    sensor_pairing.dart     # 新增：已配对传感器的持久化读写
    ble/ble_platform.dart   # 修改：BlePlatform 补 deviceById
    ble/ble_scanner.dart    # 修改：BleScanner 补 deviceById
    export/
      gpx.dart              # 新增：GPX 1.1 文本生成（含 gpxtpx 扩展）
      backup.dart           # 新增：ZIP 备份打包与恢复解析（纯逻辑，无 IO）
      backup_store.dart     # 新增：备份数据的读写（取全部数据 / 写回），抽象 + SQLite 实现
      backup_io.dart        # 新增：备份文件的读写（系统分享 / 文件选择器），抽象 + 生产实现
  features/
    history/
      history_page.dart     # 历史列表页
      ride_card.dart        # 单张骑行卡片（含迷你速度曲线）
      mini_speed_curve.dart # 迷你速度曲线缩略图
      history_providers.dart# 历史列表相关的 provider
    detail/
      detail_page.dart      # 详情页骨架（自上而下组装各区块）
      detail_providers.dart # 详情页 provider
      summary_grid.dart     # 汇总指标网格
      curve_chart.dart      # 通用曲线图（速度/心率/踏频共用）
      hr_zone_bar.dart      # 心率区间分布条
      route_map.dart        # 地图轨迹图层（flutter_map）
      gpx_export.dart       # 导出 GPX 到文件并调起系统分享
    stats/
      stats_page.dart       # 长期统计页
      stats_providers.dart  # 统计页 provider
      trend_chart.dart      # 趋势折线（fl_chart）
      personal_bests_card.dart # 个人最佳纪录卡片
    settings/
      settings_page.dart    # 设置页（个人参数 + 传感器配对 + 备份入口）
      backup_section.dart   # 备份与恢复区块
  core/
    format.dart             # 修改：补 formatDateTime
  app/
    providers.dart          # 修改：补 blePlatformProvider、sensorPairingProvider、
                            #       backupStoreProvider、backupIoProvider
    home_shell.dart         # 修改：三个占位页换成真实页面
```

**Plan A 遗留的清理项**：`lib/features/settings/ble_probe_page.dart` 是 Task 3 的临时 BLE 诊断页，现在已无任何引用，本计划最后一个任务删掉它。

---

## Task 1: domain/analysis — WGS-84 → GCJ-02 坐标转换

设计文档 9.1：地图用高德栅格瓦片，高德是 **GCJ-02** 坐标系，而手机 GPS 输出 **WGS-84**。直接把 WGS-84 经纬度画在 GCJ-02 瓦片上，轨迹会偏移数百米（实测天安门一带偏移约 0.0014° 纬度、0.0062° 经度）。

**关键约束：只转换「显示用」的坐标。落盘与 GPX 导出的仍是 WGS-84 原始坐标**，否则导出给 Strava 的数据会带上偏移。

**Files:**
- Create: `lib/domain/analysis/gcj02.dart`
- Create: `test/domain/analysis/gcj02_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/domain/analysis/gcj02_test.dart`：

```dart
import 'package:cycling_app/domain/analysis/gcj02.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isOutOfChina', () {
    test('中国境内的点返回 false', () {
      expect(isOutOfChina(39.90750, 116.39123), isFalse); // 天安门
      expect(isOutOfChina(31.23042, 121.47370), isFalse); // 上海人民广场
    });

    test('经度超出东界返回 true', () {
      expect(isOutOfChina(35.6762, 139.6503), isTrue); // 东京
    });

    test('纬度超出北界返回 true', () {
      expect(isOutOfChina(55.9, 100.0), isTrue);
    });

    test('纬度低于南界返回 true', () {
      expect(isOutOfChina(0.5, 100.0), isTrue);
    });

    test('经度低于西界返回 true', () {
      expect(isOutOfChina(39.9, 71.0), isTrue);
    });

    test('边界值本身算境内（判定用开区间）', () {
      expect(isOutOfChina(55.8271, 100.0), isFalse);
      expect(isOutOfChina(0.8293, 100.0), isFalse);
      expect(isOutOfChina(39.9, 72.004), isFalse);
      expect(isOutOfChina(39.9, 137.8347), isFalse);
    });
  });

  group('wgs84ToGcj02', () {
    test('天安门：偏移量落在已知区间', () {
      final ({double lat, double lon}) g = wgs84ToGcj02(39.90750, 116.39123);
      // 期望值由标准 GCJ-02 算法独立算得，见实施偏差记录。
      expect(g.lat, closeTo(39.90890124, 1e-6));
      expect(g.lon, closeTo(116.39747114, 1e-6));
    });

    test('上海人民广场：纬度偏移为负、经度偏移为正', () {
      final ({double lat, double lon}) g = wgs84ToGcj02(31.23042, 121.47370);
      expect(g.lat, closeTo(31.22847775, 1e-6));
      expect(g.lon, closeTo(121.47822306, 1e-6));
      expect(g.lat, lessThan(31.23042));
      expect(g.lon, greaterThan(121.47370));
    });

    test('境外点原样返回', () {
      final ({double lat, double lon}) g = wgs84ToGcj02(35.6762, 139.6503);
      expect(g.lat, 35.6762);
      expect(g.lon, 139.6503);
    });

    test('偏移量在经度方向约 0.004~0.007 度，量级正确', () {
      final ({double lat, double lon}) g = wgs84ToGcj02(39.90750, 116.39123);
      expect((g.lon - 116.39123).abs(), inInclusiveRange(0.004, 0.007));
    });

    test('转换是纯函数：同一输入两次结果完全相同', () {
      final ({double lat, double lon}) a = wgs84ToGcj02(23.12911, 113.26439);
      final ({double lat, double lon}) b = wgs84ToGcj02(23.12911, 113.26439);
      expect(a.lat, b.lat);
      expect(a.lon, b.lon);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
.fvm/flutter_sdk/bin/flutter test test/domain/analysis/gcj02_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`（`gcj02.dart` 还没建）。

- [ ] **Step 3: 写实现**

创建 `lib/domain/analysis/gcj02.dart`：

```dart
/// WGS-84 到 GCJ-02 的坐标转换。见设计文档 9.1。
///
/// 高德瓦片用 GCJ-02（俗称「火星坐标」），手机 GPS 输出 WGS-84，直接叠加会
/// 偏移数百米。本文件只服务**显示**：落盘的轨迹点与导出的 GPX 一律保持
/// WGS-84 原始坐标，否则导出给第三方平台的数据会带上偏移。
///
/// 反解（GCJ-02 → WGS-84）本计划不需要，不做，避免无用代码。
library;

/// 克拉索夫斯基椭球长半轴（米）。GCJ-02 算法规定值。
const double _axis = 6378245.0;

/// 偏心率平方。GCJ-02 算法规定值。
const double _eccentricitySquared = 0.00669342162296594323;

/// 是否在中国境外。境外不做偏移（算法只在中国境内标定）。
///
/// 判定用闭区间：恰好落在边界上的点算境内。
bool isOutOfChina(double lat, double lon) =>
    lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271;

/// 把 WGS-84 经纬度转成 GCJ-02 经纬度。
///
/// 境外点原样返回。返回记录类型而不是自定义类，是为了让测试能直接用
/// 结构化相等，也避免 domain 层引入多余的模型。
({double lat, double lon}) wgs84ToGcj02(double lat, double lon) {
  if (isOutOfChina(lat, lon)) return (lat: lat, lon: lon);

  final double dLat = _transformLat(lon - 105.0, lat - 35.0);
  final double dLon = _transformLon(lon - 105.0, lat - 35.0);

  final double radLat = lat / 180.0 * _pi;
  double magic = _sin(radLat);
  magic = 1 - _eccentricitySquared * magic * magic;
  final double sqrtMagic = _sqrt(magic);

  final double correctedLat = (dLat * 180.0) /
      ((_axis * (1 - _eccentricitySquared)) / (magic * sqrtMagic) * _pi);
  final double correctedLon =
      (dLon * 180.0) / (_axis / sqrtMagic * _cos(radLat) * _pi);

  return (lat: lat + correctedLat, lon: lon + correctedLon);
}

double _transformLat(double x, double y) {
  double ret = -100.0 +
      2.0 * x +
      3.0 * y +
      0.2 * y * y +
      0.1 * x * y +
      0.2 * _sqrt(x.abs());
  ret += (20.0 * _sin(6.0 * x * _pi) + 20.0 * _sin(2.0 * x * _pi)) * 2.0 / 3.0;
  ret += (20.0 * _sin(y * _pi) + 40.0 * _sin(y / 3.0 * _pi)) * 2.0 / 3.0;
  ret +=
      (160.0 * _sin(y / 12.0 * _pi) + 320 * _sin(y * _pi / 30.0)) * 2.0 / 3.0;
  return ret;
}

double _transformLon(double x, double y) {
  double ret =
      300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * _sqrt(x.abs());
  ret += (20.0 * _sin(6.0 * x * _pi) + 20.0 * _sin(2.0 * x * _pi)) * 2.0 / 3.0;
  ret += (20.0 * _sin(x * _pi) + 40.0 * _sin(x / 3.0 * _pi)) * 2.0 / 3.0;
  ret +=
      (150.0 * _sin(x / 12.0 * _pi) + 300.0 * _sin(x / 30.0 * _pi)) * 2.0 / 3.0;
  return ret;
}
```

在文件顶部（`library;` 之前）补上数学函数的本地别名，让实现体保持与公开算法一致、便于对照：

```dart
import 'dart:math' as math;

const double _pi = math.pi;
double _sin(double v) => math.sin(v);
double _cos(double v) => math.cos(v);
double _sqrt(double v) => math.sqrt(v);
```

- [ ] **Step 4: 运行测试确认通过**

```bash
.fvm/flutter_sdk/bin/flutter test test/domain/analysis/gcj02_test.dart
```

Expected: `All tests passed!`（10 个测试）

- [ ] **Step 5: 变异自证**

依次改坏实现并跑测试，确认至少一个用例变红，然后改回：

| 变异点 | 应被杀死 |
| --- | --- |
| `isOutOfChina` 的 `lat > 55.8271` 改成 `lat > 60` | 纬度超出北界 / 边界值本身算境内 |
| `_eccentricitySquared` 改成 `0.0` | 天安门 / 上海人民广场的期望值断言 |
| 删掉 `isOutOfChina` 的提前返回 | 境外点原样返回 |
| `_transformLon` 首行 `300.0` 改成 `0.0` | 上海人民广场（经度偏移变负） |

- [ ] **Step 6: 静态检查与提交**

```bash
.fvm/flutter_sdk/bin/flutter analyze lib test
```

Expected: `No issues found!`

```bash
git add lib/domain/analysis/gcj02.dart test/domain/analysis/gcj02_test.dart
git commit -m "feat: 添加 WGS-84 到 GCJ-02 坐标转换"
```

---

## Task 2: domain/analysis — 曲线数据准备

设计文档 10.3 的详情页要画速度、心率、踏频三条曲线。原始轨迹点动辄几千个，直接交给图表会卡；且 GPS 断点（时间间隔 > 10s）必须拆成多段，否则曲线会把隧道两侧连成一条假直线。

本任务只产出**数据**，不碰任何图表库（domain 层不许 import Flutter）。

**Files:**
- Create: `lib/domain/analysis/curve.dart`
- Create: `test/domain/analysis/curve_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/domain/analysis/curve_test.dart`：

```dart
import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/analysis/curve.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一串等间隔的轨迹点。`hr`/`cadence` 与序号绑定，便于断言取到的是哪个点。
List<TrackPoint> buildPoints(int count, {int stepMs = 1000, int? gapAfter}) {
  return <TrackPoint>[
    for (int i = 0; i < count; i++)
      TrackPoint(
        rideId: 1,
        tMs: (gapAfter != null && i > gapAfter)
            ? i * stepMs + kGpsGapMs + 1
            : i * stepMs,
        lat: 31.0 + i * 0.0001,
        lon: 121.0,
        speedMps: i.toDouble(),
        hr: 100 + i,
        cadence: 60 + i,
      ),
  ];
}

void main() {
  group('buildCurve 基本行为', () {
    test('速度曲线取平滑后的速度，x 是相对首点的秒数', () {
      final List<TrackPoint> points = buildPoints(5);
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.speed);

      expect(curve.length, 5);
      expect(curve.first.xSeconds, 0);
      expect(curve.last.xSeconds, 4);
      // 速度 0,1,2,3,4 经过 5 点滑动平均，中点附近应落在区间内。
      expect(curve[2].y, inInclusiveRange(1.0, 3.0));
    });

    test('心率曲线取原始心率值，不做平滑', () {
      final List<CurveSample> curve = buildCurve(
        buildPoints(3),
        metric: CurveMetric.heartRate,
      );
      expect(curve.map((CurveSample s) => s.y).toList(), <double>[100, 101, 102]);
    });

    test('踏频曲线取原始踏频值', () {
      final List<CurveSample> curve = buildCurve(
        buildPoints(3),
        metric: CurveMetric.cadence,
      );
      expect(curve.map((CurveSample s) => s.y).toList(), <double>[60, 61, 62]);
    });

    test('缺该指标的轨迹点被跳过', () {
      final List<TrackPoint> points = <TrackPoint>[
        const TrackPoint(rideId: 1, tMs: 0, hr: 100),
        const TrackPoint(rideId: 1, tMs: 1000), // 没有心率
        const TrackPoint(rideId: 1, tMs: 2000, hr: 120),
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.heartRate);
      expect(curve.length, 2);
      expect(curve.map((CurveSample s) => s.y).toList(), <double>[100, 120]);
    });

    test('空输入返回空曲线', () {
      expect(buildCurve(<TrackPoint>[], metric: CurveMetric.speed), isEmpty);
    });
  });

  group('buildCurve 断点分段', () {
    test('时间间隔超过 kGpsGapMs 时 segment 递增', () {
      final List<TrackPoint> points = buildPoints(6, gapAfter: 2);
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.heartRate);

      // 前 3 个点（下标 0,1,2）同段；下标 3 起时间跳变，进入新段。
      expect(curve[0].segment, 0);
      expect(curve[2].segment, 0);
      expect(curve[3].segment, 1);
      expect(curve[5].segment, 1);
    });

    test('时间不前进时也递增 segment', () {
      final List<TrackPoint> points = <TrackPoint>[
        const TrackPoint(rideId: 1, tMs: 1000, hr: 100),
        const TrackPoint(rideId: 1, tMs: 500, hr: 110), // 时间倒流
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.heartRate);
      expect(curve[0].segment, 0);
      expect(curve[1].segment, 1);
    });

    test('恰好等于 kGpsGapMs 不算断点', () {
      final List<TrackPoint> points = <TrackPoint>[
        const TrackPoint(rideId: 1, tMs: 0, hr: 100),
        const TrackPoint(rideId: 1, tMs: kGpsGapMs, hr: 110),
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.heartRate);
      expect(curve[1].segment, 0);
    });
  });

  group('buildCurve 降采样', () {
    test('点数超过 maxSamples 时抽稀到不超过上限', () {
      final List<TrackPoint> points = buildPoints(1000);
      final List<CurveSample> curve = buildCurve(
        points,
        metric: CurveMetric.heartRate,
        maxSamples: 100,
      );
      expect(curve.length, lessThanOrEqualTo(100));
      expect(curve.length, greaterThan(50));
    });

    test('降采样保留首点与末点', () {
      final List<TrackPoint> points = buildPoints(1000);
      final List<CurveSample> curve = buildCurve(
        points,
        metric: CurveMetric.heartRate,
        maxSamples: 100,
      );
      expect(curve.first.y, 100); // 首点 hr = 100
      expect(curve.last.y, 100 + 999); // 末点 hr = 1099
    });

    test('点数不超上限时原样返回，不抽稀', () {
      final List<CurveSample> curve = buildCurve(
        buildPoints(10),
        metric: CurveMetric.heartRate,
        maxSamples: 100,
      );
      expect(curve.length, 10);
    });

    test('降采样后 x 仍单调不减', () {
      final List<CurveSample> curve = buildCurve(
        buildPoints(1000),
        metric: CurveMetric.heartRate,
        maxSamples: 50,
      );
      for (int i = 1; i < curve.length; i++) {
        expect(curve[i].xSeconds, greaterThanOrEqualTo(curve[i - 1].xSeconds));
      }
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
.fvm/flutter_sdk/bin/flutter test test/domain/analysis/curve_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写实现**

创建 `lib/domain/analysis/curve.dart`：

```dart
import '../models/track_point.dart';
import 'constants.dart';
import 'speed.dart';

/// 曲线要画哪个指标。
enum CurveMetric { speed, heartRate, cadence }

/// 曲线上的一个采样点。
///
/// [segment] 是断点分段号：GPS 断点（时间间隔超过 [kGpsGapMs]）或时间不前进时
/// 递增，图表按它拆成多条折线，避免把隧道两侧连成假直线。见设计文档 9.3。
class CurveSample {
  const CurveSample({
    required this.xSeconds,
    required this.y,
    required this.segment,
  });

  /// 相对首个有效点的秒数。
  final double xSeconds;

  final double y;
  final int segment;
}

/// 把轨迹点整理成图表可用的曲线序列。
///
/// - 速度曲线先做 [kSpeedFilterWindow] 点滑动平均：GPS 瞬时速度毛刺严重，
///   直接画出来是一团噪声（设计文档 8.1）。
/// - 心率与踏频不做平滑，原始值本身就是传感器的输出。
/// - 点数超过 [maxSamples] 时等步长抽稀，**首点与末点一定保留**。
List<CurveSample> buildCurve(
  List<TrackPoint> points, {
  required CurveMetric metric,
  int maxSamples = 240,
}) {
  final List<double?> raw = _rawValues(points, metric);
  final List<double?> values =
      metric == CurveMetric.speed ? movingAverage(raw, kSpeedFilterWindow) : raw;

  final List<CurveSample> all = <CurveSample>[];
  int segment = 0;
  int? prevTMs;
  double? originTMs;

  for (int i = 0; i < points.length; i++) {
    final double? y = values[i];
    if (y == null) continue;

    final int tMs = points[i].tMs;
    if (prevTMs != null) {
      final int dt = tMs - prevTMs;
      if (dt <= 0 || dt > kGpsGapMs) segment++;
    }
    prevTMs = tMs;
    originTMs ??= tMs.toDouble();

    all.add(CurveSample(
      xSeconds: (tMs - originTMs) / 1000.0,
      y: y,
      segment: segment,
    ));
  }

  return _downsample(all, maxSamples);
}

List<double?> _rawValues(List<TrackPoint> points, CurveMetric metric) {
  switch (metric) {
    case CurveMetric.speed:
      return <double?>[for (final TrackPoint p in points) p.speedMps];
    case CurveMetric.heartRate:
      return <double?>[
        for (final TrackPoint p in points) p.hr?.toDouble(),
      ];
    case CurveMetric.cadence:
      return <double?>[
        for (final TrackPoint p in points) p.cadence?.toDouble(),
      ];
  }
}

/// 等步长抽稀。首末点必留；被抽掉的位置不改变 segment 的相对顺序。
List<CurveSample> _downsample(List<CurveSample> samples, int maxSamples) {
  if (maxSamples < 2 || samples.length <= maxSamples) return samples;

  final int last = samples.length - 1;
  final List<CurveSample> out = <CurveSample>[];
  for (int i = 0; i < maxSamples; i++) {
    final int index = (i * last / (maxSamples - 1)).round();
    final CurveSample s = samples[index];
    // 抽稀后相邻两点可能落在不同 segment，这里保持原样即可：
    // 图表按 segment 分组，跨段的两点不会被连起来。
    if (out.isNotEmpty && identical(out.last, s)) continue;
    out.add(s);
  }
  return out;
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
.fvm/flutter_sdk/bin/flutter test test/domain/analysis/curve_test.dart
```

Expected: `All tests passed!`（14 个测试）

- [ ] **Step 5: 变异自证**

| 变异点 | 应被杀死 |
| --- | --- |
| 断点判定 `dt > kGpsGapMs` 改成 `dt > kGpsGapMs * 10` | 时间间隔超过 kGpsGapMs 时 segment 递增 |
| 断点判定 `dt <= 0` 改成 `dt < 0` | 时间不前进时也递增 segment |
| `_downsample` 里 `maxSamples - 1` 改成 `maxSamples` | 降采样保留首点与末点 |
| 速度曲线去掉 `movingAverage` | 速度曲线取平滑后的速度 |

- [ ] **Step 6: 静态检查与提交**

```bash
.fvm/flutter_sdk/bin/flutter analyze lib test
```

Expected: `No issues found!`

```bash
git add lib/domain/analysis/curve.dart test/domain/analysis/curve_test.dart
git commit -m "feat: 添加曲线数据准备与降采样"
```

---

## Task 3: domain/analysis — 周/月/年聚合与个人最佳

设计文档 10.4：周 / 月 / 年范围切换 → 累计距离、时长、爬升 → 趋势折线 → 个人最佳纪录卡片。

**范围定义（本计划钉死的语义，实施时不要改）**：按**日历对齐**，不是滚动窗口。

| 范围 | 起止 | 桶 |
| --- | --- | --- |
| `week` | 本周一 00:00 起，7 天 | 7 个「日」桶，标签 `MM-DD` |
| `month` | 本月 1 日 00:00 起，当月天数 | 当月天数个「日」桶，标签 `MM-DD` |
| `year` | 本年 1 月 1 日 00:00 起，12 个月 | 12 个「月」桶，标签 `YYYY-MM` |

骑行按 `startedAtMs` 落桶（左闭右开）。只统计 `status == finished` 且 `summary != null` 的骑行。

**Files:**
- Create: `lib/domain/analysis/trend.dart`
- Create: `test/domain/analysis/trend_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/domain/analysis/trend_test.dart`：

```dart
import 'package:cycling_app/domain/analysis/trend.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试用的固定「现在」：2026-09-24（周四）12:00 本地时间。
///
/// 因此本周一是 2026-09-21，本周桶依次是 09-21 … 09-27；
/// 本月是 2026-09，共 30 天；本年共 12 个月。
int get nowMs => DateTime(2026, 9, 24, 12).millisecondsSinceEpoch;

int ms(int y, int m, int d, [int h = 12]) =>
    DateTime(y, m, d, h).millisecondsSinceEpoch;

Ride ride({
  int id = 1,
  required int startedAtMs,
  RideStatus status = RideStatus.finished,
  RideSummary? summary = const RideSummary(
    distanceM: 10000,
    durationS: 1800,
    movingS: 1700,
    avgSpeedMps: 5.56,
    movingAvgSpeedMps: 5.88,
    maxSpeedMps: 11.1,
    elevationGainM: 100,
    pointCount: 1800,
  ),
}) =>
    Ride(id: id, startedAtMs: startedAtMs, status: status, summary: summary);

void main() {
  group('buildTrend 范围与桶结构', () {
    test('week 返回 7 个日桶，首桶是本周一', () {
      final TrendSummary t = buildTrend(<Ride>[], range: TrendRange.week, nowMs: nowMs);
      expect(t.buckets.length, 7);
      expect(t.buckets.first.label, '09-21');
      expect(t.buckets.last.label, '09-27');
      expect(t.rangeStartMs, ms(2026, 9, 21, 0));
      expect(t.rangeEndMs, ms(2026, 9, 28, 0));
    });

    test('month 返回当月天数的日桶', () {
      final TrendSummary t = buildTrend(<Ride>[], range: TrendRange.month, nowMs: nowMs);
      expect(t.buckets.length, 30); // 2026-09 有 30 天
      expect(t.buckets.first.label, '09-01');
      expect(t.buckets.last.label, '09-30');
    });

    test('year 返回 12 个月桶，标签为 YYYY-MM', () {
      final TrendSummary t = buildTrend(<Ride>[], range: TrendRange.year, nowMs: nowMs);
      expect(t.buckets.length, 12);
      expect(t.buckets.first.label, '2026-01');
      expect(t.buckets.last.label, '2026-12');
    });

    test('空输入时累计值全为 0', () {
      final TrendSummary t = buildTrend(<Ride>[], range: TrendRange.week, nowMs: nowMs);
      expect(t.distanceM, 0);
      expect(t.durationS, 0);
      expect(t.elevationGainM, 0);
      expect(t.rideCount, 0);
    });
  });

  group('buildTrend 落桶', () {
    test('骑行落在 startedAtMs 所属的那一天', () {
      final TrendSummary t = buildTrend(
        <Ride>[ride(id: 1, startedAtMs: ms(2026, 9, 23, 8))],
        range: TrendRange.week,
        nowMs: nowMs,
      );
      expect(t.buckets[2].label, '09-23');
      expect(t.buckets[2].rideCount, 1);
      expect(t.buckets[2].distanceM, 10000);
      expect(t.buckets[1].rideCount, 0);
    });

    test('同一天多条骑行累加', () {
      final TrendSummary t = buildTrend(
        <Ride>[
          ride(id: 1, startedAtMs: ms(2026, 9, 22, 7)),
          ride(id: 2, startedAtMs: ms(2026, 9, 22, 19)),
        ],
        range: TrendRange.week,
        nowMs: nowMs,
      );
      expect(t.buckets[1].rideCount, 2);
      expect(t.buckets[1].distanceM, 20000);
      expect(t.buckets[1].durationS, 3600);
    });

    test('范围外的骑行不计入', () {
      final TrendSummary t = buildTrend(
        <Ride>[ride(id: 1, startedAtMs: ms(2026, 9, 20, 8))], // 上周日
        range: TrendRange.week,
        nowMs: nowMs,
      );
      expect(t.rideCount, 0);
      expect(t.buckets.every((TrendBucket b) => b.rideCount == 0), isTrue);
    });

    test('桶的右端点属于下一个桶（左闭右开）', () {
      final TrendSummary t = buildTrend(
        <Ride>[ride(id: 1, startedAtMs: ms(2026, 9, 22, 0))],
        range: TrendRange.week,
        nowMs: nowMs,
      );
      expect(t.buckets[1].rideCount, 1);
      expect(t.buckets[0].rideCount, 0);
    });

    test('未结束的骑行不计入', () {
      final TrendSummary t = buildTrend(
        <Ride>[
          ride(id: 1, startedAtMs: ms(2026, 9, 22, 8), status: RideStatus.recording, summary: null),
          ride(id: 2, startedAtMs: ms(2026, 9, 22, 9), status: RideStatus.paused, summary: null),
        ],
        range: TrendRange.week,
        nowMs: nowMs,
      );
      expect(t.rideCount, 0);
    });

    test('summary 为 null 的已结束骑行不计入', () {
      final TrendSummary t = buildTrend(
        <Ride>[ride(id: 1, startedAtMs: ms(2026, 9, 22, 8), summary: null)],
        range: TrendRange.week,
        nowMs: nowMs,
      );
      expect(t.rideCount, 0);
    });

    test('year 范围下按月份落桶', () {
      final TrendSummary t = buildTrend(
        <Ride>[
          ride(id: 1, startedAtMs: ms(2026, 3, 15)),
          ride(id: 2, startedAtMs: ms(2026, 3, 28)),
          ride(id: 3, startedAtMs: ms(2026, 9, 24)),
        ],
        range: TrendRange.year,
        nowMs: nowMs,
      );
      expect(t.buckets[2].label, '2026-03');
      expect(t.buckets[2].rideCount, 2);
      expect(t.buckets[8].label, '2026-09');
      expect(t.buckets[8].rideCount, 1);
    });

    test('累计值等于各桶之和', () {
      final TrendSummary t = buildTrend(
        <Ride>[
          ride(id: 1, startedAtMs: ms(2026, 9, 22, 7)),
          ride(id: 2, startedAtMs: ms(2026, 9, 24, 7)),
        ],
        range: TrendRange.week,
        nowMs: nowMs,
      );
      final double bucketDistance = t.buckets.fold(
        0,
        (double sum, TrendBucket b) => sum + b.distanceM,
      );
      final int bucketDuration = t.buckets.fold(
        0,
        (int sum, TrendBucket b) => sum + b.durationS,
      );
      expect(t.distanceM, bucketDistance);
      expect(t.durationS, bucketDuration);
      expect(t.distanceM, 20000);
      expect(t.rideCount, 2);
    });
  });

  group('personalBests', () {
    test('四项最佳各取最大的一条，并带上骑行 id 与开始时间', () {
      final PersonalBests b = personalBests(<Ride>[
        ride(
          id: 1,
          startedAtMs: ms(2026, 9, 1),
          summary: const RideSummary(
            distanceM: 30000,
            durationS: 5400,
            movingS: 5200,
            avgSpeedMps: 5.56,
            movingAvgSpeedMps: 5.77,
            elevationGainM: 200,
            pointCount: 5000,
          ),
        ),
        ride(
          id: 2,
          startedAtMs: ms(2026, 9, 2),
          summary: const RideSummary(
            distanceM: 15000,
            durationS: 9000,
            movingS: 8000,
            avgSpeedMps: 1.67,
            movingAvgSpeedMps: 8.33,
            elevationGainM: 600,
            pointCount: 9000,
          ),
        ),
      ]);

      expect(b.longestDistanceM!.rideId, 1);
      expect(b.longestDistanceM!.value, 30000);
      expect(b.longestDurationS!.rideId, 2);
      expect(b.longestDurationS!.value, 9000);
      expect(b.fastestMovingAvgMps!.rideId, 2);
      expect(b.fastestMovingAvgMps!.value, 8.33);
      expect(b.mostElevationGainM!.rideId, 2);
      expect(b.mostElevationGainM!.value, 600);
      expect(b.longestDistanceM!.startedAtMs, ms(2026, 9, 1));
    });

    test('并列时保留更早的那次', () {
      final PersonalBests b = personalBests(<Ride>[
        ride(id: 1, startedAtMs: ms(2026, 9, 1)),
        ride(id: 2, startedAtMs: ms(2026, 9, 2)),
      ]);
      expect(b.longestDistanceM!.rideId, 1);
    });

    test('没有已结束骑行时四项全为 null', () {
      final PersonalBests b = personalBests(<Ride>[
        ride(id: 1, startedAtMs: ms(2026, 9, 1), status: RideStatus.recording, summary: null),
      ]);
      expect(b.longestDistanceM, isNull);
      expect(b.longestDurationS, isNull);
      expect(b.fastestMovingAvgMps, isNull);
      expect(b.mostElevationGainM, isNull);
    });

    test('跳过没有 id 或没有 summary 的骑行', () {
      final PersonalBests b = personalBests(<Ride>[
        const Ride(startedAtMs: 1000, status: RideStatus.finished, summary: null),
        Ride(id: 9, startedAtMs: 2000, status: RideStatus.finished, summary: null),
      ]);
      expect(b.longestDistanceM, isNull);
    });

    test('空输入返回全 null', () {
      final PersonalBests b = personalBests(<Ride>[]);
      expect(b.longestDistanceM, isNull);
      expect(b.mostElevationGainM, isNull);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
.fvm/flutter_sdk/bin/flutter test test/domain/analysis/trend_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写实现**

创建 `lib/domain/analysis/trend.dart`：

```dart
import '../models/ride.dart';
import '../models/ride_status.dart';
import '../models/ride_summary.dart';

/// 统计页的时间范围。见设计文档 10.4。
enum TrendRange { week, month, year }

/// 趋势折线上的一个桶。
class TrendBucket {
  const TrendBucket({
    required this.startMs,
    required this.endMs,
    required this.label,
    required this.distanceM,
    required this.durationS,
    required this.elevationGainM,
    required this.rideCount,
  });

  /// 桶的起点（含）。本地时间的当日/当月 00:00。
  final int startMs;

  /// 桶的终点（不含）。
  final int endMs;

  /// 日桶为 `MM-DD`，月桶为 `YYYY-MM`。
  final String label;

  final double distanceM;
  final int durationS;
  final double elevationGainM;
  final int rideCount;
}

/// 一个范围内的累计值与逐桶趋势。
class TrendSummary {
  const TrendSummary({
    required this.rangeStartMs,
    required this.rangeEndMs,
    required this.distanceM,
    required this.durationS,
    required this.elevationGainM,
    required this.rideCount,
    required this.buckets,
  });

  final int rangeStartMs;
  final int rangeEndMs;
  final double distanceM;
  final int durationS;
  final double elevationGainM;
  final int rideCount;
  final List<TrendBucket> buckets;
}

/// 个人最佳纪录。
class PersonalBest {
  const PersonalBest({
    required this.rideId,
    required this.startedAtMs,
    required this.value,
  });

  final int rideId;
  final int startedAtMs;
  final double value;
}

/// 四项个人最佳。没有对应数据时为 null。
class PersonalBests {
  const PersonalBests({
    this.longestDistanceM,
    this.longestDurationS,
    this.fastestMovingAvgMps,
    this.mostElevationGainM,
  });

  final PersonalBest? longestDistanceM;
  final PersonalBest? longestDurationS;
  final PersonalBest? fastestMovingAvgMps;
  final PersonalBest? mostElevationGainM;
}

/// 按日历范围聚合骑行。
///
/// 范围是**日历对齐**的：`week` 从本周一 00:00 起 7 天，`month` 从本月 1 日
/// 00:00 起当月天数天，`year` 从本年 1 月 1 日 00:00 起 12 个月。
/// 骑行按 `startedAtMs` 落桶，左闭右开。
///
/// 只统计 `status == finished` 且带汇总的骑行：未结束的骑行没有汇总指标，
/// 计进去会让累计值凭空变小。
TrendSummary buildTrend(
  List<Ride> rides, {
  required TrendRange range,
  required int nowMs,
}) {
  final DateTime now = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final List<_Span> spans = _spansFor(range, now);

  final List<double> distances = List<double>.filled(spans.length, 0);
  final List<int> durations = List<int>.filled(spans.length, 0);
  final List<double> gains = List<double>.filled(spans.length, 0);
  final List<int> counts = List<int>.filled(spans.length, 0);

  for (final Ride ride in rides) {
    if (ride.status != RideStatus.finished) continue;
    final RideSummary? summary = ride.summary;
    if (summary == null) continue;

    final int index = spans.indexWhere(
      (_Span s) => ride.startedAtMs >= s.startMs && ride.startedAtMs < s.endMs,
    );
    if (index < 0) continue;

    distances[index] += summary.distanceM;
    durations[index] += summary.durationS;
    gains[index] += summary.elevationGainM;
    counts[index] += 1;
  }

  final List<TrendBucket> buckets = <TrendBucket>[
    for (int i = 0; i < spans.length; i++)
      TrendBucket(
        startMs: spans[i].startMs,
        endMs: spans[i].endMs,
        label: spans[i].label,
        distanceM: distances[i],
        durationS: durations[i],
        elevationGainM: gains[i],
        rideCount: counts[i],
      ),
  ];

  double totalDistance = 0;
  int totalDuration = 0;
  double totalGain = 0;
  int totalCount = 0;
  for (int i = 0; i < spans.length; i++) {
    totalDistance += distances[i];
    totalDuration += durations[i];
    totalGain += gains[i];
    totalCount += counts[i];
  }

  return TrendSummary(
    rangeStartMs: spans.first.startMs,
    rangeEndMs: spans.last.endMs,
    distanceM: totalDistance,
    durationS: totalDuration,
    elevationGainM: totalGain,
    rideCount: totalCount,
    buckets: buckets,
  );
}

/// 四项个人最佳。并列时保留**更早**的那次（先到先得），便于稳定测试。
PersonalBests personalBests(List<Ride> rides) {
  PersonalBest? distance;
  PersonalBest? duration;
  PersonalBest? speed;
  PersonalBest? gain;

  for (final Ride ride in rides) {
    final int? id = ride.id;
    final RideSummary? summary = ride.summary;
    if (ride.status != RideStatus.finished) continue;
    if (id == null || summary == null) continue;

    PersonalBest? better(PersonalBest? current, double value) =>
        current == null || value > current.value
            ? PersonalBest(
                rideId: id,
                startedAtMs: ride.startedAtMs,
                value: value,
              )
            : current;

    distance = better(distance, summary.distanceM);
    duration = better(duration, summary.durationS.toDouble());
    speed = better(speed, summary.movingAvgSpeedMps);
    gain = better(gain, summary.elevationGainM);
  }

  return PersonalBests(
    longestDistanceM: distance,
    longestDurationS: duration,
    fastestMovingAvgMps: speed,
    mostElevationGainM: gain,
  );
}

/// 一个桶的时间跨度。
class _Span {
  const _Span({
    required this.startMs,
    required this.endMs,
    required this.label,
  });

  final int startMs;
  final int endMs;
  final String label;
}

List<_Span> _spansFor(TrendRange range, DateTime now) {
  switch (range) {
    case TrendRange.week:
      final DateTime monday =
          DateTime(now.year, now.month, now.day - (now.weekday - 1));
      return <_Span>[
        for (int i = 0; i < 7; i++)
          _daySpan(DateTime(monday.year, monday.month, monday.day + i)),
      ];
    case TrendRange.month:
      // DateTime(y, m + 1, 0).day 就是当月天数，跨年由 DateTime 自己归一化。
      final int daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      return <_Span>[
        for (int i = 0; i < daysInMonth; i++)
          _daySpan(DateTime(now.year, now.month, 1 + i)),
      ];
    case TrendRange.year:
      return <_Span>[
        for (int i = 0; i < 12; i++) _monthSpan(DateTime(now.year, 1 + i, 1)),
      ];
  }
}

_Span _daySpan(DateTime start) {
  final DateTime end = DateTime(start.year, start.month, start.day + 1);
  return _Span(
    startMs: start.millisecondsSinceEpoch,
    endMs: end.millisecondsSinceEpoch,
    label: '${_two(start.month)}-${_two(start.day)}',
  );
}

_Span _monthSpan(DateTime start) {
  final DateTime end = DateTime(start.year, start.month + 1, 1);
  return _Span(
    startMs: start.millisecondsSinceEpoch,
    endMs: end.millisecondsSinceEpoch,
    label: '${start.year}-${_two(start.month)}',
  );
}

String _two(int value) => value.toString().padLeft(2, '0');
```

- [ ] **Step 4: 运行测试确认通过**

```bash
.fvm/flutter_sdk/bin/flutter test test/domain/analysis/trend_test.dart
```

Expected: `All tests passed!`（18 个测试）

- [ ] **Step 5: 变异自证**

| 变异点 | 应被杀死 |
| --- | --- |
| `_spansFor` 的 `now.day - (now.weekday - 1)` 改成 `now.day` | week 首桶是本周一 / 骑行落在 startedAtMs 所属的那一天 |
| 落桶判定 `< s.endMs` 改成 `<= s.endMs` | 桶的右端点属于下一个桶 |
| 删掉 `ride.status != RideStatus.finished` 判断 | 未结束的骑行不计入 |
| `personalBests` 的 `>` 改成 `>=` | 并列时保留更早的那次 |
| `_monthSpan` 的 `now.month + 1` 改成 `now.month` | year 范围下按月份落桶 |

- [ ] **Step 6: 静态检查与提交**

```bash
.fvm/flutter_sdk/bin/flutter analyze lib test
```

Expected: `No issues found!`

```bash
git add lib/domain/analysis/trend.dart test/domain/analysis/trend_test.dart
git commit -m "feat: 添加周月年聚合与个人最佳"
```

---

## Task 4: data/db — DAO 扩展（日期范围查询、全量读写、删除）

Plan A 的 DAO 只覆盖记录链路需要的操作。本任务补齐事后分析需要的四类：

1. **统计页**要按时间范围取骑行 → `listFinishedBetween`
2. **备份**要把全部数据导出 → `TrackPointDao.listAll`、`RideDao.countFinished`
3. **恢复**要按原 id 写回并先清空 → `RideDao.insertWithId`、两个 `deleteAll`
4. **设置页**要能清除已配对的传感器 → `SettingsDao.remove`

**Files:**
- Modify: `lib/data/db/settings_dao.dart`
- Modify: `lib/data/db/ride_dao.dart`
- Modify: `lib/data/db/track_point_dao.dart`
- Test: `test/data/db/settings_dao_test.dart`（追加）
- Test: `test/data/db/ride_dao_test.dart`（追加）
- Test: `test/data/db/track_point_dao_test.dart`（追加）

- [ ] **Step 1: 写失败测试**

在 `test/data/db/settings_dao_test.dart` 末尾（`main()` 内）追加：

```dart
  test('remove 删掉键后读回 null', () async {
    final SettingsDao dao = SettingsDao(db);
    await dao.setString('hr_sensor_id', 'AA:BB');
    await dao.setString('weight_kg', '70');

    await dao.remove('hr_sensor_id');

    expect(await dao.getString('hr_sensor_id'), isNull);
    expect(await dao.getString('weight_kg'), '70');
  });

  test('remove 一个不存在的键不抛错', () async {
    await SettingsDao(db).remove('never_set');
    expect(await SettingsDao(db).getString('never_set'), isNull);
  });
```

在 `test/data/db/ride_dao_test.dart` 末尾（`main()` 内）追加：

```dart
  test('listFinishedBetween 只取区间内已完成的骑行，按开始时间正序', () async {
    await dao.insert(const Ride(startedAtMs: 1000, status: RideStatus.finished));
    await dao.insert(const Ride(startedAtMs: 2000, status: RideStatus.finished));
    await dao.insert(const Ride(startedAtMs: 3000, status: RideStatus.finished));
    await dao.insert(const Ride(startedAtMs: 2500, status: RideStatus.recording));

    final List<Ride> rides = await dao.listFinishedBetween(fromMs: 2000, toMs: 3000);
    expect(rides.map((Ride r) => r.startedAtMs).toList(), <int>[2000]);
  });

  test('listFinishedBetween 是左闭右开区间', () async {
    await dao.insert(const Ride(startedAtMs: 2000, status: RideStatus.finished));
    await dao.insert(const Ride(startedAtMs: 3000, status: RideStatus.finished));

    final List<Ride> rides = await dao.listFinishedBetween(fromMs: 2000, toMs: 3000);
    expect(rides.length, 1);
    expect(rides.first.startedAtMs, 2000);
  });

  test('countFinished 只数已完成的骑行', () async {
    await dao.insert(const Ride(startedAtMs: 1000, status: RideStatus.finished));
    await dao.insert(const Ride(startedAtMs: 2000, status: RideStatus.finished));
    await dao.insert(const Ride(startedAtMs: 3000, status: RideStatus.recording));

    expect(await dao.countFinished(), 2);
  });

  test('insertWithId 保留给定的 id，供备份恢复使用', () async {
    await dao.insertWithId(const Ride(
      id: 7,
      startedAtMs: 1000,
      status: RideStatus.finished,
      title: '通勤',
    ));

    final Ride ride = (await dao.findById(7))!;
    expect(ride.title, '通勤');
    expect(ride.startedAtMs, 1000);
  });

  test('insertWithId 能原样保留汇总列', () async {
    await dao.insertWithId(Ride(
      id: 3,
      startedAtMs: 1000,
      endedAtMs: 3601000,
      status: RideStatus.finished,
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
        avgCadence: 78,
        calories: 900,
        pointCount: 3400,
      ),
    ));

    final RideSummary s = (await dao.findById(3))!.summary!;
    expect(s.distanceM, 25000);
    expect(s.maxHr, 176);
    expect(s.calories, 900);
    expect(s.pointCount, 3400);
  });

  test('deleteAll 清空 rides 表', () async {
    await dao.insert(const Ride(startedAtMs: 1000, status: RideStatus.finished));
    await dao.deleteAll();
    expect(await dao.countFinished(), 0);
    expect(await dao.listFinished(), isEmpty);
  });
```

在 `test/data/db/track_point_dao_test.dart` 末尾（`main()` 内）追加：

```dart
  test('listAll 按 ride_id 再按 t_ms 正序返回全部点', () async {
    final int rideA = await RideDao(db).insert(
      const Ride(startedAtMs: 0, status: RideStatus.finished),
    );
    final int rideB = await RideDao(db).insert(
      const Ride(startedAtMs: 0, status: RideStatus.finished),
    );

    await dao.insertBatch(<TrackPoint>[
      TrackPoint(rideId: rideB, tMs: 100, lat: 1.0, lon: 1.0),
      TrackPoint(rideId: rideA, tMs: 300, lat: 2.0, lon: 2.0),
      TrackPoint(rideId: rideA, tMs: 100, lat: 3.0, lon: 3.0),
    ]);

    final List<TrackPoint> all = await dao.listAll();
    expect(all.length, 3);
    expect(all.map((TrackPoint p) => p.rideId).toList(), <int>[rideA, rideA, rideB]);
    expect(all[0].tMs, 100);
    expect(all[1].tMs, 300);
  });

  test('deleteAll 清空 track_points 表', () async {
    final int rideId = await RideDao(db).insert(
      const Ride(startedAtMs: 0, status: RideStatus.finished),
    );
    await dao.insertBatch(<TrackPoint>[
      TrackPoint(rideId: rideId, tMs: 0, lat: 1.0, lon: 1.0),
    ]);

    await dao.deleteAll();
    expect(await dao.listAll(), isEmpty);
  });
```

> 注意：`test/data/db/track_point_dao_test.dart` 若还没有 import `RideDao` / `Ride` / `RideStatus`，需要补上：
> `import 'package:cycling_app/data/db/ride_dao.dart';`、`import 'package:cycling_app/domain/models/ride.dart';`、`import 'package:cycling_app/domain/models/ride_status.dart';`

- [ ] **Step 2: 运行测试确认失败**

```bash
.fvm/flutter_sdk/bin/flutter test test/data/db
```

Expected: FAIL，报 `The method 'remove' isn't defined` / `listFinishedBetween` / `countFinished` / `insertWithId` / `deleteAll` / `listAll` 未定义。

- [ ] **Step 3: 写实现**

在 `lib/data/db/settings_dao.dart` 的 `setString` 之后加：

```dart
  /// 删除一个键。键不存在时静默返回。
  Future<void> remove(String key) async {
    await _db.delete('settings', where: 'key = ?', whereArgs: <Object?>[key]);
  }
```

在 `lib/data/db/ride_dao.dart` 的 `listFinished` 之后加：

```dart
  /// 指定时间区间内已完成的骑行，按开始时间正序。区间为左闭右开。
  ///
  /// 统计页按周/月/年取数用；正序是为了让调用方直接按顺序落桶。
  Future<List<Ride>> listFinishedBetween({
    required int fromMs,
    required int toMs,
  }) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'rides',
      where: "status = 'finished' AND started_at >= ? AND started_at < ?",
      whereArgs: <Object?>[fromMs, toMs],
      orderBy: 'started_at ASC',
    );
    return rows.map(Ride.fromDbMap).toList();
  }

  /// 已完成的骑行条数。备份的 manifest.json 里要写这个数字。
  Future<int> countFinished() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      "SELECT COUNT(*) AS c FROM rides WHERE status = 'finished'",
    );
    return (rows.first['c'] as num).toInt();
  }

  /// 带上 id 插入，供备份恢复还原原始 id。
  ///
  /// 与 [insert] 的区别是不剥掉 `id` 列，因此 `track_points.ride_id` 的外键
  /// 关系能原样重建。
  Future<void> insertWithId(Ride ride) async {
    await _db.insert('rides', ride.toDbMap());
  }

  /// 清空 rides 表。恢复备份前调用，语义是「替换成备份里的状态」。
  Future<void> deleteAll() async {
    await _db.delete('rides');
  }
```

在 `lib/data/db/track_point_dao.dart` 的 `deleteByRide` 之后加：

```dart
  /// 全部轨迹点，按 ride_id 再按 t_ms 正序。备份导出用。
  Future<List<TrackPoint>> listAll() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'track_points',
      orderBy: 'ride_id ASC, t_ms ASC',
    );
    return rows.map(TrackPoint.fromDbMap).toList();
  }

  /// 清空 track_points 表。恢复备份前调用。
  Future<void> deleteAll() async {
    await _db.delete('track_points');
  }
```

- [ ] **Step 4: 运行测试确认通过**

```bash
.fvm/flutter_sdk/bin/flutter test test/data/db
```

Expected: `All tests passed!`

- [ ] **Step 5: 变异自证**

| 变异点 | 应被杀死 |
| --- | --- |
| `listFinishedBetween` 的 `started_at >= ?` 改成 `>` | listFinishedBetween 是左闭右开区间 |
| `listFinishedBetween` 去掉 `status = 'finished'` 条件 | listFinishedBetween 只取区间内已完成的骑行 |
| `countFinished` 去掉 `WHERE status = 'finished'` | countFinished 只数已完成的骑行 |
| `insertWithId` 改成调用 `insert`（剥掉 id） | insertWithId 保留给定的 id |
| `listAll` 的 `orderBy` 改成 `t_ms ASC` | listAll 按 ride_id 再按 t_ms 正序返回全部点 |

- [ ] **Step 6: 静态检查与提交**

```bash
.fvm/flutter_sdk/bin/flutter analyze lib test
```

Expected: `No issues found!`

```bash
git add lib/data/db test/data/db
git commit -m "feat: 扩展 DAO 支持范围查询、全量读写与清空"
```

---

## Task 5: data — 传感器配对持久化与自动重连

设计文档 10.5 要求设置页有「传感器配对管理」；Plan A 的实施偏差记录里也留了这条缺口：Plan A 每次开始前手动连接，配对信息没有存下来。

本任务做三件事：

1. 把配对成功的传感器（id + 名字）持久化到 `settings` 表
2. 给 `BlePlatform` 补 `deviceById`，让「按 id 找回设备」不依赖一次扫描
3. 记录页开始记录时自动重连已配对的传感器

**配对只在真正连上之后才写入**：用户从列表里点了一个设备、但那个设备其实不提供标准 HRS，这种失败不该被记住。

**Files:**
- Create: `lib/data/sensor_pairing.dart`
- Modify: `lib/data/ble/ble_platform.dart`
- Modify: `lib/data/ble/ble_scanner.dart`
- Modify: `lib/app/providers.dart`
- Modify: `lib/features/record/record_controller.dart`
- Test: `test/data/sensor_pairing_test.dart`（新建）
- Test: `test/data/ble/ble_scanner_test.dart`（追加）
- Test: `test/features/record/record_controller_test.dart`（追加）

- [ ] **Step 1: 写失败测试**

创建 `test/data/sensor_pairing_test.dart`：

```dart
import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/settings_dao.dart';
import 'package:cycling_app/data/ble/sensor_monitor.dart';
import 'package:cycling_app/data/sensor_pairing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late SensorPairingRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = SensorPairingRepository(SettingsDao(db));
  });

  tearDown(() => db.close());

  test('没配对过时读回 null', () async {
    expect(await repo.load(SensorKind.heartRate), isNull);
    expect(await repo.load(SensorKind.cadence), isNull);
  });

  test('保存后可读回 id 与名字', () async {
    await repo.save(
      SensorKind.heartRate,
      const PairedSensor(id: 'AA:01', name: 'FIT 3'),
    );

    final PairedSensor? p = await repo.load(SensorKind.heartRate);
    expect(p!.id, 'AA:01');
    expect(p.name, 'FIT 3');
  });

  test('心率与踏频各自独立，互不覆盖', () async {
    await repo.save(
      SensorKind.heartRate,
      const PairedSensor(id: 'AA:01', name: 'FIT 3'),
    );
    await repo.save(
      SensorKind.cadence,
      const PairedSensor(id: 'BB:02', name: 'CADENCE'),
    );

    expect((await repo.load(SensorKind.heartRate))!.id, 'AA:01');
    expect((await repo.load(SensorKind.cadence))!.id, 'BB:02');
  });

  test('重复保存同一种传感器时覆盖旧值', () async {
    await repo.save(
      SensorKind.heartRate,
      const PairedSensor(id: 'AA:01', name: 'FIT 3'),
    );
    await repo.save(
      SensorKind.heartRate,
      const PairedSensor(id: 'AA:09', name: 'FIT 4'),
    );

    final PairedSensor p = (await repo.load(SensorKind.heartRate))!;
    expect(p.id, 'AA:09');
    expect(p.name, 'FIT 4');
  });

  test('clear 后读回 null，且不影响另一种传感器', () async {
    await repo.save(
      SensorKind.heartRate,
      const PairedSensor(id: 'AA:01', name: 'FIT 3'),
    );
    await repo.save(
      SensorKind.cadence,
      const PairedSensor(id: 'BB:02', name: 'CADENCE'),
    );

    await repo.clear(SensorKind.heartRate);

    expect(await repo.load(SensorKind.heartRate), isNull);
    expect((await repo.load(SensorKind.cadence))!.id, 'BB:02');
  });

  test('clear 一个没配对的传感器不抛错', () async {
    await repo.clear(SensorKind.cadence);
    expect(await repo.load(SensorKind.cadence), isNull);
  });

  test('只有 id 没有名字时也能读回，名字为空串', () async {
    await repo.save(SensorKind.cadence, const PairedSensor(id: 'BB:02', name: ''));

    final PairedSensor p = (await repo.load(SensorKind.cadence))!;
    expect(p.id, 'BB:02');
    expect(p.name, isEmpty);
  });

  test('id 为空串视为未配对', () async {
    await repo.save(SensorKind.heartRate, const PairedSensor(id: '', name: 'x'));
    expect(await repo.load(SensorKind.heartRate), isNull);
  });
}
```

在 `test/data/ble/ble_scanner_test.dart` 的 `FakeBlePlatform` 里补一个字段与实现，让已有的假平台跟上新接口：

```dart
  /// `deviceById` 的返回值表。
  final Map<String, BleDeviceHandle> devicesById = <String, BleDeviceHandle>{};

  @override
  Future<BleDeviceHandle?> deviceById(String id) async => devicesById[id];
```

并在文件末尾（`main()` 内）追加：

```dart
  group('deviceById', () {
    test('能按 id 找回设备句柄', () async {
      final FakeBlePlatform platform = FakeBlePlatform();
      final FakeScanDevice device = FakeScanDevice(id: 'AA:01', name: 'Fit 3');
      platform.devicesById['AA:01'] = device;

      final BleDeviceHandle? found = await BleScanner(platform: platform).deviceById('AA:01');
      expect(found, same(device));
    });

    test('id 不存在时返回 null', () async {
      final FakeBlePlatform platform = FakeBlePlatform();
      expect(await BleScanner(platform: platform).deviceById('AA:99'), isNull);
    });

    test('空 id 直接返回 null，不查平台', () async {
      final FakeBlePlatform platform = FakeBlePlatform();
      expect(await BleScanner(platform: platform).deviceById(''), isNull);
    });
  });
```

在 `test/features/record/record_controller_test.dart` 里：

**（a）** 在 `_FakeRideRepository` 里补一个字段，记录 `startRide` 收到的设备名：

```dart
  String? lastHrDeviceName;
  String? lastCadenceDeviceName;
```

并在 `startRide` 方法体开头补：

```dart
    lastHrDeviceName = hrDeviceName;
    lastCadenceDeviceName = cadenceDeviceName;
```

**（b）** 在 `_FakeBleDevice` 之后补两个假实现：

```dart
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
```

**（c）** 把 `makeContainer` 换成可注入版本（**保留原来的无参调用方式**，其余用例不用改）：

```dart
  /// 只替换 IO 边界的容器：假仓储、假定位、假时钟、假配对、可选假 BLE 平台。
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
        if (platform != null) blePlatformProvider.overrideWithValue(platform),
      ],
    );
  }
```

**（d）** 在 `main()` 末尾追加三条用例：

```dart
  testWidgets('start 时自动重连已配对的心率传感器，并把设备名写进骑行记录', (WidgetTester tester) async {
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
    expect(repo.lastHrDeviceName, 'FIT 3');
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
    expect(repo.lastHrDeviceName, isNull);
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
```

> **注意**：新增的 `sensorPairingProvider` override 是必需的。不加的话 `start()` 会去读 `sensorPairingProvider`，
> 它依赖 `databaseProvider`，而后者在测试里没有 override，会抛 `ProviderException`（riverpod 3 会把
> `UnimplementedError` 包一层），**所有已有用例都会红**。

- [ ] **Step 2: 运行测试确认失败**

```bash
.fvm/flutter_sdk/bin/flutter test test/data/sensor_pairing_test.dart test/data/ble/ble_scanner_test.dart test/features/record/record_controller_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`（`sensor_pairing.dart` 还没建）、`The method 'deviceById' isn't defined`、`Undefined name 'sensorPairingProvider'`。

- [ ] **Step 3: 写实现**

创建 `lib/data/sensor_pairing.dart`：

```dart
import 'ble/sensor_monitor.dart';
import 'db/settings_dao.dart';

/// 一个配对成功的传感器。
class PairedSensor {
  const PairedSensor({required this.id, required this.name});

  /// 平台侧设备标识（Android 是 MAC，iOS 是 UUID）。
  final String id;

  /// 配对时的设备名，用于界面展示。
  final String name;
}

/// 已配对传感器的持久化。见设计文档 10.5 的「传感器配对管理」。
///
/// 存 `settings` 表而不是 `rides` 表：这是「用户配置」，与某一次骑行无关。
class SensorPairingRepository {
  SensorPairingRepository(this._dao);

  final SettingsDao _dao;

  static const String _hrIdKey = 'hr_sensor_id';
  static const String _hrNameKey = 'hr_sensor_name';
  static const String _cadenceIdKey = 'cadence_sensor_id';
  static const String _cadenceNameKey = 'cadence_sensor_name';

  /// 读取已配对的传感器。没配对过、或存下来的 id 是空串时返回 null。
  Future<PairedSensor?> load(SensorKind kind) async {
    final String? id = await _dao.getString(_idKey(kind));
    if (id == null || id.isEmpty) return null;
    final String? name = await _dao.getString(_nameKey(kind));
    return PairedSensor(id: id, name: name ?? '');
  }

  Future<void> save(SensorKind kind, PairedSensor sensor) async {
    await _dao.setString(_idKey(kind), sensor.id);
    await _dao.setString(_nameKey(kind), sensor.name);
  }

  Future<void> clear(SensorKind kind) async {
    await _dao.remove(_idKey(kind));
    await _dao.remove(_nameKey(kind));
  }

  String _idKey(SensorKind kind) =>
      kind == SensorKind.heartRate ? _hrIdKey : _cadenceIdKey;

  String _nameKey(SensorKind kind) =>
      kind == SensorKind.heartRate ? _hrNameKey : _cadenceNameKey;
}
```

在 `lib/data/ble/ble_platform.dart` 的 `abstract class BlePlatform` 里，`stopScan` 之后加：

```dart
  /// 按平台侧 id 找回一个设备句柄，用于自动重连已配对的传感器。
  ///
  /// 找不到时返回 null。注意这里拿到的句柄没有广播信息，连接前也读不到
  /// 系统缓存名——因此配对时要把名字一起存下来。
  Future<BleDeviceHandle?> deviceById(String id);
```

在 `class FlutterBluePlusPlatform` 里加：

```dart
  @override
  Future<BleDeviceHandle?> deviceById(String id) async =>
      id.isEmpty ? null : FlutterBluePlusDevice(BluetoothDevice.fromId(id));
```

在 `lib/data/ble/ble_scanner.dart` 的 `isAdapterOn` 之后加：

```dart
  /// 按 id 找回设备句柄。空 id 直接返回 null，不查平台。
  Future<BleDeviceHandle?> deviceById(String id) =>
      id.isEmpty ? Future<BleDeviceHandle?>.value() : _platform.deviceById(id);
```

在 `lib/app/providers.dart` 里，把 `bleScannerProvider` 换成下面三行（并补 import `../data/ble/ble_platform.dart` 与 `../data/sensor_pairing.dart`）：

```dart
/// BLE 平台。抽成 provider 是为了让记录控制器的自动重连能在测试里注入假实现。
final Provider<BlePlatform> blePlatformProvider =
    Provider<BlePlatform>((Ref ref) => const FlutterBluePlusPlatform());

final Provider<BleScanner> bleScannerProvider =
    Provider<BleScanner>((Ref ref) => BleScanner(platform: ref.watch(blePlatformProvider)));

/// 已配对传感器的读写。设置页与记录控制器共用。
final Provider<SensorPairingRepository> sensorPairingProvider =
    Provider<SensorPairingRepository>(
  (Ref ref) => SensorPairingRepository(SettingsDao(ref.watch(databaseProvider))),
);
```

在 `lib/features/record/record_controller.dart` 里改三处（并补 import `../../data/ble/ble_platform.dart` 与 `../../data/sensor_pairing.dart`）：

**（1）** 在 `_cadenceMonitor` 声明下方补 getter 与常量：

```dart
  /// 自动重连的整体时间预算。
  ///
  /// 传感器不在身边时 `connect` 要等满 10 秒超时，不能让「开始骑行」卡那么久。
  /// 超时后记录照常开始，[SensorMonitor] 的退避重连会继续在后台尝试。
  static const Duration _kAutoConnectBudget = Duration(seconds: 3);

  SensorPairingRepository get _pairing => ref.read(sensorPairingProvider);

  BlePlatform get _blePlatform => ref.read(blePlatformProvider);
```

**（2）** 在 `start()` 里，把 `startRide` 那一段前面插一行 `await`：

```dart
    // 见设计文档 6.1：连接传感器属于 preparing 阶段，放在建记录之前，
    // 这样 rides.hr_device_name / cadence_device_name 才有值。
    await _autoConnectPairedSensors().timeout(_kAutoConnectBudget, onTimeout: () {});

    final Ride ride = await ref.read(rideRepositoryProvider).startRide(
          startedAtMs: _now(),
          hrDeviceName: _hrMonitor?.deviceName,
          cadenceDeviceName: _cadenceMonitor?.deviceName,
        );
```

**（3）** 在 `_onSensorConnection` 里补「连上就记住」，并新增两个方法：

```dart
  void _onSensorConnection(SensorKind kind, bool connected) {
    if (kind == SensorKind.heartRate) {
      _hrConnected = connected;
    } else {
      _cadenceConnected = connected;
    }
    // 只有真的连上了才记住：用户点错设备（那个设备不提供标准 HRS）时
    // 不该被写进配对，否则下次开记录会一直去连一个连不上的设备。
    if (connected) unawaited(_rememberSensor(kind));
    _publish();
  }

  Future<void> _rememberSensor(SensorKind kind) async {
    final SensorMonitor? monitor =
        kind == SensorKind.heartRate ? _hrMonitor : _cadenceMonitor;
    if (monitor == null) return;
    await _pairing.save(
      kind,
      PairedSensor(id: monitor.device.id, name: monitor.deviceName),
    );
  }

  /// 自动重连上次配对成功的传感器。见设计文档 10.5 与 6.1。
  ///
  /// 任何一步失败都直接跳过：传感器连不上不阻断开始记录（设计文档 6.1）。
  Future<void> _autoConnectPairedSensors() async {
    for (final SensorKind kind in SensorKind.values) {
      final PairedSensor? paired = await _pairing.load(kind);
      if (paired == null) continue;
      final BleDeviceHandle? device = await _blePlatform.deviceById(paired.id);
      if (device == null) continue;
      await connectSensor(kind, device);
    }
  }
```

- [ ] **Step 4: 运行测试确认通过**

```bash
.fvm/flutter_sdk/bin/flutter test test/data/sensor_pairing_test.dart test/data/ble/ble_scanner_test.dart test/features/record/record_controller_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: 跑全量测试确认没有回归**

```bash
.fvm/flutter_sdk/bin/flutter test
```

Expected: `All tests passed!`。
**特别注意 `test/app/providers_test.dart`**：它有一条断言「`locationServiceProvider` / `bleScannerProvider` 返回生产实现」，
`bleScannerProvider` 现在会 `ref.watch(blePlatformProvider)`，若那条断言检查的是实例相等，需要确认仍然成立。

- [ ] **Step 6: 变异自证**

| 变异点 | 应被杀死 |
| --- | --- |
| `SensorPairingRepository.load` 去掉 `id.isEmpty` 判断 | id 为空串视为未配对 |
| `save` 里心率与踏频用同一个 key | 心率与踏频各自独立 |
| `clear` 只删 id 不删 name | 没直接杀死点——**补一条用例**：clear 后重新 save 一个新名字，确认名字也换了（否则旧名字残留） |
| `_autoConnectPairedSensors` 去掉 `device == null` 判断 | 配对里的设备找不回来时照常开始记录 |
| `start()` 里删掉 `await _autoConnectPairedSensors()` | start 时自动重连已配对的心率传感器 |
| `_onSensorConnection` 里把 `if (connected)` 改成 `if (!connected)` | 连接传感器成功后记住设备 |

- [ ] **Step 7: 静态检查与提交**

```bash
.fvm/flutter_sdk/bin/flutter analyze lib test
```

Expected: `No issues found!`

```bash
git add lib/data lib/app/providers.dart lib/features/record/record_controller.dart test
git commit -m "feat: 持久化传感器配对并在开始记录时自动重连"
```

---

## Task 6: data/export — GPX 1.1 生成

设计文档 12：单次导出 GPX，**心率与踏频写入 Garmin `TrackPointExtension` 扩展（`gpxtpx:hr`、`gpxtpx:cad`）**，否则 Strava、码表读不到心率。

两条硬约束：

1. **只用 WGS-84 原始坐标**，不做 GCJ-02 转换——转换只服务地图显示（Task 1 的注释里已写明）。给第三方平台的必须是标准坐标。
2. **GPS 断点拆成多个 `<trkseg>`**，与设计文档 9.3 一致。否则第三方平台会画出一条横穿隧道的假直线。

**Files:**
- Create: `lib/data/export/gpx.dart`
- Create: `test/data/export/gpx_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/data/export/gpx_test.dart`：

```dart
import 'package:cycling_app/data/export/gpx.dart';
import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// 按 local name 取元素，避免在测试里跟命名空间前缀纠缠。
Iterable<XmlElement> named(XmlDocument doc, String local) =>
    doc.descendantElements.where((XmlElement e) => e.name.local == local);

const Ride _ride = Ride(
  id: 1,
  startedAtMs: 1758384000000, // 2025-09-21T00:00:00Z
  endedAtMs: 1758387600000,
  status: RideStatus.finished,
);

TrackPoint pt(
  int tMs, {
  double? lat = 31.0,
  double? lon = 121.0,
  double? alt,
  int? hr,
  int? cadence,
}) =>
    TrackPoint(
      rideId: 1,
      tMs: tMs,
      lat: lat,
      lon: lon,
      altitudeM: alt,
      hr: hr,
      cadence: cadence,
    );

void main() {
  group('GPX 结构与命名空间', () {
    test('输出是合法 XML，根元素是 gpx 且 version 为 1.1', () {
      final XmlDocument doc =
          XmlDocument.parse(buildGpx(ride: _ride, points: <TrackPoint>[pt(0)]));

      expect(doc.rootElement.name.local, 'gpx');
      expect(doc.rootElement.getAttribute('version'), '1.1');
      expect(doc.rootElement.getAttribute('creator'), kGpxCreator);
    });

    test('声明了 GPX 1.1 与 gpxtpx 两个命名空间', () {
      final XmlDocument doc =
          XmlDocument.parse(buildGpx(ride: _ride, points: <TrackPoint>[pt(0)]));

      expect(doc.rootElement.getAttribute('xmlns'), kGpxNamespace);
      expect(doc.rootElement.getAttribute('xmlns:gpxtpx'), kGpxTpxNamespace);
    });

    test('trk 带 type 为 cycling', () {
      final XmlDocument doc =
          XmlDocument.parse(buildGpx(ride: _ride, points: <TrackPoint>[pt(0)]));

      expect(named(doc, 'type').single.innerText, 'cycling');
    });
  });

  group('GPX 轨迹点', () {
    test('只输出有坐标的点', () {
      final XmlDocument doc = XmlDocument.parse(buildGpx(
        ride: _ride,
        points: <TrackPoint>[
          pt(0),
          const TrackPoint(rideId: 1, tMs: 1000, hr: 140), // 无坐标
          pt(2000),
        ],
      ));

      expect(named(doc, 'trkpt').length, 2);
    });

    test('经纬度写到小数点后 6 位', () {
      final XmlDocument doc = XmlDocument.parse(buildGpx(
        ride: _ride,
        points: <TrackPoint>[pt(0, lat: 31.230416, lon: 121.473701)],
      ));

      final XmlElement trkpt = named(doc, 'trkpt').single;
      expect(trkpt.getAttribute('lat'), '31.230416');
      expect(trkpt.getAttribute('lon'), '121.473701');
    });

    test('缺高程时不输出 ele 元素', () {
      final XmlDocument doc =
          XmlDocument.parse(buildGpx(ride: _ride, points: <TrackPoint>[pt(0)]));

      expect(named(doc, 'ele'), isEmpty);
    });

    test('有高程时输出 ele，保留两位小数', () {
      final XmlDocument doc = XmlDocument.parse(
        buildGpx(ride: _ride, points: <TrackPoint>[pt(0, alt: 12.3456)]),
      );

      expect(named(doc, 'ele').single.innerText, '12.35');
    });

    test('时间写成 UTC 的 ISO8601，带 Z 结尾', () {
      final XmlDocument doc = XmlDocument.parse(
        buildGpx(ride: _ride, points: <TrackPoint>[pt(1758384000000)]),
      );

      final String time = named(doc, 'time').last.innerText;
      expect(time, '2025-09-21T00:00:00.000Z');
      expect(time.endsWith('Z'), isTrue);
    });
  });

  group('GPX 传感器扩展', () {
    test('心率与踏频写进 gpxtpx 扩展', () {
      final XmlDocument doc = XmlDocument.parse(
        buildGpx(ride: _ride, points: <TrackPoint>[pt(0, hr: 142, cadence: 78)]),
      );

      expect(named(doc, 'TrackPointExtension').length, 1);
      expect(named(doc, 'hr').single.innerText, '142');
      expect(named(doc, 'cad').single.innerText, '78');
    });

    test('只有心率时不写 cad', () {
      final XmlDocument doc = XmlDocument.parse(
        buildGpx(ride: _ride, points: <TrackPoint>[pt(0, hr: 142)]),
      );

      expect(named(doc, 'hr').single.innerText, '142');
      expect(named(doc, 'cad'), isEmpty);
    });

    test('只有踏频时不写 hr', () {
      final XmlDocument doc = XmlDocument.parse(
        buildGpx(ride: _ride, points: <TrackPoint>[pt(0, cadence: 78)]),
      );

      expect(named(doc, 'cad').single.innerText, '78');
      expect(named(doc, 'hr'), isEmpty);
    });

    test('两者都没有时不输出 extensions 元素', () {
      final XmlDocument doc =
          XmlDocument.parse(buildGpx(ride: _ride, points: <TrackPoint>[pt(0)]));

      expect(named(doc, 'extensions'), isEmpty);
      expect(named(doc, 'TrackPointExtension'), isEmpty);
    });
  });

  group('GPX 断点分段', () {
    test('时间间隔超过 kGpsGapMs 时拆成两个 trkseg', () {
      final XmlDocument doc = XmlDocument.parse(buildGpx(
        ride: _ride,
        points: <TrackPoint>[
          pt(0),
          pt(1000),
          pt(1000 + kGpsGapMs + 1),
          pt(2000 + kGpsGapMs + 1),
        ],
      ));

      final List<XmlElement> segs = named(doc, 'trkseg').toList();
      expect(segs.length, 2);
      expect(named(segs[0], 'trkpt').length, 2);
      expect(named(segs[1], 'trkpt').length, 2);
    });

    test('恰好等于 kGpsGapMs 不拆段', () {
      final XmlDocument doc = XmlDocument.parse(buildGpx(
        ride: _ride,
        points: <TrackPoint>[pt(0), pt(kGpsGapMs)],
      ));

      expect(named(doc, 'trkseg').length, 1);
    });

    test('时间不前进时也拆段', () {
      final XmlDocument doc = XmlDocument.parse(buildGpx(
        ride: _ride,
        points: <TrackPoint>[pt(1000), pt(500)],
      ));

      expect(named(doc, 'trkseg').length, 2);
    });

    test('没有可用点时仍生成合法 GPX，只含一个空 trkseg', () {
      final XmlDocument doc = XmlDocument.parse(
        buildGpx(ride: _ride, points: const <TrackPoint>[]),
      );

      expect(doc.rootElement.name.local, 'gpx');
      expect(named(doc, 'trkseg').length, 1);
      expect(named(doc, 'trkpt'), isEmpty);
    });
  });

  group('GPX 名称', () {
    test('有标题时用标题', () {
      final XmlDocument doc = XmlDocument.parse(buildGpx(
        ride: const Ride(
          id: 1,
          startedAtMs: 1758384000000,
          status: RideStatus.finished,
          title: '周末环湖',
        ),
        points: <TrackPoint>[pt(0)],
      ));

      expect(named(doc, 'name').first.innerText, '周末环湖');
    });

    test('没有标题时用开始日期', () {
      final XmlDocument doc =
          XmlDocument.parse(buildGpx(ride: _ride, points: <TrackPoint>[pt(0)]));

      expect(named(doc, 'name').first.innerText, '骑行 2025-09-21');
    });

    test('标题里的特殊字符被正确转义', () {
      final String gpx = buildGpx(
        ride: const Ride(
          id: 1,
          startedAtMs: 1758384000000,
          status: RideStatus.finished,
          title: 'A & B <c>',
        ),
        points: <TrackPoint>[pt(0)],
      );

      // 不抛异常即说明转义正确；再确认原文没有裸露的裸 & 或 <。
      final XmlDocument doc = XmlDocument.parse(gpx);
      expect(named(doc, 'name').first.innerText, 'A & B <c>');
      expect(gpx.contains('A & B <c>'), isFalse);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
.fvm/flutter_sdk/bin/flutter test test/data/export/gpx_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写实现**

创建 `lib/data/export/gpx.dart`：

```dart
import 'package:xml/xml.dart';

import '../../domain/analysis/constants.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';

/// GPX 1.1 命名空间。
const String kGpxNamespace = 'http://www.topografix.com/GPX/1/1';

/// Garmin 轨迹点扩展命名空间。心率与踏频必须放在这里，第三方平台才认。
const String kGpxTpxNamespace =
    'http://www.garmin.com/xmlschemas/TrackPointExtension/v1';

/// GPX 文件里的 creator 标识。
const String kGpxCreator = 'cycling_app';

/// 生成 GPX 1.1 文本。见设计文档 12。
///
/// **坐标一律用落盘的 WGS-84 原始值**，不做 GCJ-02 转换：那个转换只服务地图
/// 显示（见 `domain/analysis/gcj02.dart`），导给 Strava 的必须是标准坐标。
///
/// 没有坐标的点（GPS 丢失时只有心率/踏频）不输出：`trkpt` 的 lat/lon 是必需
/// 属性。时间间隔超过 [kGpsGapMs] 或时间不前进处拆成新的 `trkseg`，
/// 否则第三方平台会画出一条横穿隧道的假直线（设计文档 9.3）。
String buildGpx({required Ride ride, required List<TrackPoint> points}) {
  final String name = _trackName(ride);
  final List<List<TrackPoint>> segments = _splitSegments(
    points.where((TrackPoint p) => p.hasPosition).toList(),
  );

  final XmlBuilder builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element(
    'gpx',
    attributes: <String, String>{
      'version': '1.1',
      'creator': kGpxCreator,
      'xmlns': kGpxNamespace,
      'xmlns:gpxtpx': kGpxTpxNamespace,
    },
    nest: () {
      builder.element('metadata', nest: () {
        builder.element('name', nest: name);
        builder.element('time', nest: _isoUtc(ride.startedAtMs));
      });

      builder.element('trk', nest: () {
        builder.element('name', nest: name);
        builder.element('type', nest: 'cycling');

        if (segments.isEmpty) {
          // 没有可用点时也留一个空 trkseg，保证结构一致、可被解析。
          builder.element('trkseg');
          return;
        }
        for (final List<TrackPoint> segment in segments) {
          builder.element('trkseg', nest: () {
            for (final TrackPoint p in segment) {
              _writeTrackPoint(builder, p);
            }
          });
        }
      });
    },
  );

  return builder.buildDocument().toXmlString(pretty: true);
}

void _writeTrackPoint(XmlBuilder builder, TrackPoint p) {
  builder.element(
    'trkpt',
    attributes: <String, String>{
      'lat': p.lat!.toStringAsFixed(6),
      'lon': p.lon!.toStringAsFixed(6),
    },
    nest: () {
      final double? altitude = p.altitudeM;
      if (altitude != null) {
        builder.element('ele', nest: altitude.toStringAsFixed(2));
      }
      builder.element('time', nest: _isoUtc(p.tMs));

      final int? hr = p.hr;
      final int? cadence = p.cadence;
      if (hr == null && cadence == null) return;

      builder.element('extensions', nest: () {
        builder.element('gpxtpx:TrackPointExtension', nest: () {
          if (hr != null) builder.element('gpxtpx:hr', nest: '$hr');
          if (cadence != null) builder.element('gpxtpx:cad', nest: '$cadence');
        });
      });
    },
  );
}

/// 按 GPS 断点把点拆成若干段。首点自成一段的开头。
List<List<TrackPoint>> _splitSegments(List<TrackPoint> located) {
  final List<List<TrackPoint>> segments = <List<TrackPoint>>[];
  List<TrackPoint>? current;
  int? prevTMs;

  for (final TrackPoint p in located) {
    final int? prev = prevTMs;
    final bool needNew = current == null ||
        prev == null ||
        p.tMs - prev <= 0 ||
        p.tMs - prev > kGpsGapMs;
    if (needNew) {
      current = <TrackPoint>[];
      segments.add(current);
    }
    current!.add(p);
    prevTMs = p.tMs;
  }

  return segments;
}

String _trackName(Ride ride) {
  final String title = ride.title?.trim() ?? '';
  if (title.isNotEmpty) return title;
  final DateTime start = DateTime.fromMillisecondsSinceEpoch(ride.startedAtMs);
  return '骑行 ${start.year}-${_two(start.month)}-${_two(start.day)}';
}

String _isoUtc(int epochMs) =>
    DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true).toIso8601String();

String _two(int value) => value.toString().padLeft(2, '0');
```

- [ ] **Step 4: 运行测试确认通过**

```bash
.fvm/flutter_sdk/bin/flutter test test/data/export/gpx_test.dart
```

Expected: `All tests passed!`（20 个测试）

- [ ] **Step 5: 变异自证**

| 变异点 | 应被杀死 |
| --- | --- |
| 断点判定 `> kGpsGapMs` 改成 `> kGpsGapMs * 100` | 时间间隔超过 kGpsGapMs 时拆成两个 trkseg |
| 断点判定去掉 `p.tMs - prev <= 0` | 时间不前进时也拆段 |
| `where((p) => p.hasPosition)` 去掉 | 只输出有坐标的点 |
| 心率/踏频写到顶层而不是 gpxtpx 扩展 | 心率与踏频写进 gpxtpx 扩展 |
| 时间用 `DateTime.fromMillisecondsSinceEpoch(tMs)`（本地时区） | 时间写成 UTC 的 ISO8601 |
| `_splitSegments` 里 `needNew` 永远 false | 时间间隔超过 kGpsGapMs 时拆成两个 trkseg |

- [ ] **Step 6: 静态检查与提交**

```bash
.fvm/flutter_sdk/bin/flutter analyze lib test
```

Expected: `No issues found!`

```bash
git add lib/data/export/gpx.dart test/data/export/gpx_test.dart
git commit -m "feat: 添加 GPX 1.1 导出生成"
```

---

## Task 7: data/export — 全量备份与恢复

设计文档 12：导出 ZIP 归档，内含 `manifest.json`（schema 版本、导出时间、记录条数）、`rides.json`、`track_points.jsonl`（每行一个 JSON 对象，数据量大时便于流式读写）。

**序列化直接复用 `Ride.toDbMap()` / `TrackPoint.toDbMap()`**：字段名与数据库列一一对应，不用再维护第二套映射，恢复时用现成的 `fromDbMap` 反解。

**版本策略**：当前只有 `kBackupSchemaVersion == 1`。恢复时**只接受版本号完全相等**的归档；版本更高则明确拒绝并说明原因（避免新版数据被旧版 App 静默损坏）；版本更低的情况在 v1 阶段不可能出现（没有比 1 更低的版本）。等真的出现 v2 时再补迁移分支——**现在不要写一个永远走不到的迁移函数**。

**Files:**
- Create: `lib/data/export/backup.dart`
- Modify: `lib/data/db/ride_dao.dart`（字段类型 `Database` → `DatabaseExecutor`）
- Modify: `lib/data/db/track_point_dao.dart`（同上）
- Create: `test/data/export/backup_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/data/export/backup_test.dart`：

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/ride_dao.dart';
import 'package:cycling_app/data/db/track_point_dao.dart';
import 'package:cycling_app/data/export/backup.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const Ride _finished = Ride(
  id: 1,
  startedAtMs: 1000,
  endedAtMs: 3601000,
  status: RideStatus.finished,
  title: '周末环湖',
  hrDeviceName: 'FIT 3',
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
    avgCadence: 78,
    calories: 900,
    pointCount: 3,
  ),
);

const List<TrackPoint> _points = <TrackPoint>[
  TrackPoint(id: 1, rideId: 1, tMs: 1000, lat: 31.0, lon: 121.0, altitudeM: 10, speedMps: 5, hr: 140, cadence: 80),
  TrackPoint(id: 2, rideId: 1, tMs: 2000, lat: 31.0001, lon: 121.0, hr: 145),
  TrackPoint(id: 3, rideId: 1, tMs: 3000), // GPS 丢失，只有传感器
];

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
  });

  tearDown(() => db.close());

  group('buildBackupArchive', () {
    test('归档里恰好有 manifest / rides / track_points 三个条目', () {
      final Uint8List bytes = buildBackupArchive(
        rides: const <Ride>[_finished],
        points: _points,
        exportedAtMs: 1758384000000,
      );

      final Archive archive = ZipDecoder().decodeBytes(bytes);
      expect(
        archive.files.map((ArchiveFile f) => f.name).toSet(),
        <String>{'manifest.json', 'rides.json', 'track_points.jsonl'},
      );
    });

    test('manifest 写出 schema 版本、导出时间与条数', () {
      final Uint8List bytes = buildBackupArchive(
        rides: const <Ride>[_finished],
        points: _points,
        exportedAtMs: 1758384000000,
      );

      final Archive archive = ZipDecoder().decodeBytes(bytes);
      final Map<String, Object?> manifest = jsonDecode(
        utf8.decode(archive.findFile('manifest.json')!.content),
      ) as Map<String, Object?>;

      expect(manifest['schema_version'], kBackupSchemaVersion);
      expect(manifest['exported_at'], 1758384000000);
      expect(manifest['ride_count'], 1);
      expect(manifest['point_count'], 3);
    });

    test('track_points.jsonl 每行一个 JSON 对象', () {
      final Uint8List bytes = buildBackupArchive(
        rides: const <Ride>[_finished],
        points: _points,
        exportedAtMs: 0,
      );

      final Archive archive = ZipDecoder().decodeBytes(bytes);
      final String text = utf8.decode(archive.findFile('track_points.jsonl')!.content);
      final List<String> lines = text.split('\n').where((String l) => l.isNotEmpty).toList();

      expect(lines.length, 3);
      for (final String line in lines) {
        expect(jsonDecode(line), isA<Map<String, Object?>>());
      }
    });
  });

  group('parseBackupArchive', () {
    test('打包再解包，骑行与轨迹点字段完全一致', () {
      final Uint8List bytes = buildBackupArchive(
        rides: const <Ride>[_finished],
        points: _points,
        exportedAtMs: 1758384000000,
      );

      final BackupPayload payload = parseBackupArchive(bytes);

      final Ride ride = payload.rides.single;
      expect(ride.id, 1);
      expect(ride.title, '周末环湖');
      expect(ride.hrDeviceName, 'FIT 3');
      expect(ride.summary!.distanceM, 25000);
      expect(ride.summary!.calories, 900);

      expect(payload.points.length, 3);
      expect(payload.points[0].lat, 31.0);
      expect(payload.points[0].hr, 140);
      expect(payload.points[2].hasPosition, isFalse);
    });

    test('manifest 内容被解析出来', () {
      final BackupPayload payload = parseBackupArchive(buildBackupArchive(
        rides: const <Ride>[_finished],
        points: _points,
        exportedAtMs: 1758384000000,
      ));

      expect(payload.manifest.schemaVersion, kBackupSchemaVersion);
      expect(payload.manifest.rideCount, 1);
      expect(payload.manifest.pointCount, 3);
      expect(payload.manifest.exportedAtMs, 1758384000000);
    });

    test('schema 版本更高时明确拒绝', () {
      final Uint8List bytes = buildBackupArchive(
        rides: const <Ride>[],
        points: const <TrackPoint>[],
        exportedAtMs: 0,
        schemaVersion: kBackupSchemaVersion + 1,
      );

      expect(
        () => parseBackupArchive(bytes),
        throwsA(isA<BackupVersionException>()),
      );
    });

    test('拒绝时异常里带上实际版本与期望版本', () {
      final Uint8List bytes = buildBackupArchive(
        rides: const <Ride>[],
        points: const <TrackPoint>[],
        exportedAtMs: 0,
        schemaVersion: 99,
      );

      try {
        parseBackupArchive(bytes);
        fail('应当抛 BackupVersionException');
      } on BackupVersionException catch (e) {
        expect(e.found, 99);
        expect(e.expected, kBackupSchemaVersion);
        expect(e.toString(), contains('99'));
      }
    });

    test('归档里没有 manifest.json 时抛格式异常', () {
      final Archive archive = Archive()
        ..add(ArchiveFile.string('rides.json', '[]'));
      final Uint8List bytes = Uint8List.fromList(ZipEncoder().encode(archive));

      expect(
        () => parseBackupArchive(bytes),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('空数据也能打包与解包', () {
      final BackupPayload payload = parseBackupArchive(buildBackupArchive(
        rides: const <Ride>[],
        points: const <TrackPoint>[],
        exportedAtMs: 0,
      ));

      expect(payload.rides, isEmpty);
      expect(payload.points, isEmpty);
    });
  });

  group('applyBackup', () {
    test('replaceExisting 为真时先清空再写入', () async {
      // 先塞一条「旧数据」，恢复后应当消失。
      await RideDao(db).insert(const Ride(
        id: null,
        startedAtMs: 999,
        status: RideStatus.finished,
        title: '旧数据',
      ));

      await applyBackup(
        parseBackupArchive(buildBackupArchive(
          rides: const <Ride>[_finished],
          points: _points,
          exportedAtMs: 0,
        )),
        db: db,
      );

      final List<Ride> all = await RideDao(db).listFinished();
      expect(all.length, 1);
      expect(all.single.title, '周末环湖');
      expect(all.single.id, 1);
    });

    test('replaceExisting 为假时保留已有数据', () async {
      await RideDao(db).insert(const Ride(
        startedAtMs: 999,
        status: RideStatus.finished,
        title: '旧数据',
      ));

      await applyBackup(
        parseBackupArchive(buildBackupArchive(
          rides: const <Ride>[_finished],
          points: _points,
          exportedAtMs: 0,
        )),
        db: db,
        replaceExisting: false,
      );

      expect((await RideDao(db).listFinished()).length, 2);
    });

    test('恢复后轨迹点挂回原来的 ride id', () async {
      await applyBackup(
        parseBackupArchive(buildBackupArchive(
          rides: const <Ride>[_finished],
          points: _points,
          exportedAtMs: 0,
        )),
        db: db,
      );

      final List<TrackPoint> points = await TrackPointDao(db).listByRide(1);
      expect(points.length, 3);
      expect(points[0].tMs, 1000);
      expect(points[2].hasPosition, isFalse);
    });

    test('恢复后再导出，内容与首次导出一致（幂等）', () async {
      final Uint8List first = buildBackupArchive(
        rides: const <Ride>[_finished],
        points: _points,
        exportedAtMs: 0,
      );
      await applyBackup(parseBackupArchive(first), db: db);

      final Uint8List second = buildBackupArchive(
        rides: await RideDao(db).listFinished(),
        points: await TrackPointDao(db).listAll(),
        exportedAtMs: 0,
      );

      final BackupPayload a = parseBackupArchive(first);
      final BackupPayload b = parseBackupArchive(second);
      expect(b.rides.single.toDbMap(), a.rides.single.toDbMap());
      expect(
        b.points.map((TrackPoint p) => p.toDbMap()).toList(),
        a.points.map((TrackPoint p) => p.toDbMap()).toList(),
      );
    });

    test('恢复失败时不留半份数据（事务）', () async {
      // 造一个 ride 指向不存在的 ride_id 的点：外键会拒绝，整个事务应回滚。
      await RideDao(db).insert(const Ride(
        startedAtMs: 999,
        status: RideStatus.finished,
        title: '旧数据',
      ));

      final BackupPayload broken = BackupPayload(
        manifest: const BackupManifest(
          schemaVersion: kBackupSchemaVersion,
          exportedAtMs: 0,
          rideCount: 1,
          pointCount: 1,
        ),
        rides: const <Ride>[_finished],
        points: const <TrackPoint>[
          TrackPoint(rideId: 424242, tMs: 1000, lat: 1.0, lon: 1.0),
        ],
      );

      await expectLater(
        applyBackup(broken, db: db, replaceExisting: false),
        throwsA(anything),
      );

      // 旧数据还在，说明事务回滚了。
      final List<Ride> all = await RideDao(db).listFinished();
      expect(all.single.title, '旧数据');
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
.fvm/flutter_sdk/bin/flutter test test/data/export/backup_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 把两个 DAO 的字段放宽到 `DatabaseExecutor`**

`applyBackup` 要在**一个事务里**写完，而 `RideDao` / `TrackPointDao` 现在的构造函数收的是 `Database`；
sqflite 的 `Transaction` 实现的是 `DatabaseExecutor` 而不是 `Database`（`sqflite_common/lib/sqlite_api.dart` 里
`abstract class Transaction implements DatabaseExecutor {}`），所以收窄成 `Database` 就没法传事务进去。

改法：把两个 DAO 的字段与构造函数参数类型从 `Database` 换成 `DatabaseExecutor`。
`Database` 是 `DatabaseExecutor` 的子类型，所以**所有现有调用点（含 `RideRepository`、所有测试）都不用改**。

`lib/data/db/ride_dao.dart`：

```dart
class RideDao {
  RideDao(this._db);

  final DatabaseExecutor _db;
```

`lib/data/db/track_point_dao.dart`：

```dart
class TrackPointDao {
  TrackPointDao(this._db);

  final DatabaseExecutor _db;
```

两个文件都需要 `import 'package:sqflite/sqflite.dart';`（已有，`DatabaseExecutor` 从同一个入口导出）。

- [ ] **Step 4: 写实现**

创建 `lib/data/export/backup.dart`：

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';
import '../db/ride_dao.dart';
import '../db/track_point_dao.dart';

/// 备份文件的 schema 版本。见设计文档 12。
const int kBackupSchemaVersion = 1;

const String _manifestName = 'manifest.json';
const String _ridesName = 'rides.json';
const String _pointsName = 'track_points.jsonl';

/// 归档里的 manifest.json。
class BackupManifest {
  const BackupManifest({
    required this.schemaVersion,
    required this.exportedAtMs,
    required this.rideCount,
    required this.pointCount,
  });

  final int schemaVersion;
  final int exportedAtMs;
  final int rideCount;
  final int pointCount;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema_version': schemaVersion,
        'exported_at': exportedAtMs,
        'ride_count': rideCount,
        'point_count': pointCount,
      };

  static BackupManifest fromJson(Map<String, Object?> json) => BackupManifest(
        schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 0,
        exportedAtMs: (json['exported_at'] as num?)?.toInt() ?? 0,
        rideCount: (json['ride_count'] as num?)?.toInt() ?? 0,
        pointCount: (json['point_count'] as num?)?.toInt() ?? 0,
      );
}

/// 一份解开的备份。
class BackupPayload {
  const BackupPayload({
    required this.manifest,
    required this.rides,
    required this.points,
  });

  final BackupManifest manifest;
  final List<Ride> rides;
  final List<TrackPoint> points;
}

/// 归档结构不对（缺条目、JSON 坏了）。
class BackupFormatException implements Exception {
  BackupFormatException(this.message);

  final String message;

  @override
  String toString() => '备份文件格式不正确：$message';
}

/// 归档的 schema 版本不被支持。
class BackupVersionException implements Exception {
  BackupVersionException({required this.found, required this.expected});

  final int found;
  final int expected;

  @override
  String toString() =>
      '备份文件的 schema 版本是 $found，本应用只支持 $expected。'
      '请升级 App 后再恢复，避免数据被静默损坏。';
}

/// 打包成 ZIP。见设计文档 12。
///
/// [schemaVersion] 只给测试用来造出「版本不匹配」的归档，正常调用不要传。
Uint8List buildBackupArchive({
  required List<Ride> rides,
  required List<TrackPoint> points,
  required int exportedAtMs,
  int schemaVersion = kBackupSchemaVersion,
}) {
  final BackupManifest manifest = BackupManifest(
    schemaVersion: schemaVersion,
    exportedAtMs: exportedAtMs,
    rideCount: rides.length,
    pointCount: points.length,
  );

  final Archive archive = Archive()
    ..add(ArchiveFile.string(_manifestName, jsonEncode(manifest.toJson())))
    ..add(ArchiveFile.string(
      _ridesName,
      jsonEncode(<Map<String, Object?>>[
        for (final Ride r in rides) r.toDbMap(),
      ]),
    ))
    ..add(ArchiveFile.string(
      _pointsName,
      points.map((TrackPoint p) => jsonEncode(p.toDbMap())).join('\n'),
    ));

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// 解开归档并校验版本。
///
/// 版本号必须**完全相等**：更高版本说明归档来自更新的 App，旧版代码不认识
/// 新增字段，写下去会静默丢数据，因此明确拒绝（设计文档 12）。
/// 目前只有 v1，不存在「更旧需要迁移」的情况——等真的出现 v2 再补迁移分支。
BackupPayload parseBackupArchive(Uint8List bytes) {
  final Archive archive = ZipDecoder().decodeBytes(bytes);

  final ArchiveFile? manifestFile = archive.findFile(_manifestName);
  if (manifestFile == null) {
    throw BackupFormatException('归档里没有 $_manifestName');
  }

  final BackupManifest manifest;
  try {
    manifest = BackupManifest.fromJson(
      jsonDecode(utf8.decode(manifestFile.content)) as Map<String, Object?>,
    );
  } catch (error) {
    throw BackupFormatException('$_manifestName 无法解析：$error');
  }

  if (manifest.schemaVersion != kBackupSchemaVersion) {
    throw BackupVersionException(
      found: manifest.schemaVersion,
      expected: kBackupSchemaVersion,
    );
  }

  return BackupPayload(
    manifest: manifest,
    rides: _decodeRides(archive),
    points: _decodePoints(archive),
  );
}

List<Ride> _decodeRides(Archive archive) {
  final ArchiveFile? file = archive.findFile(_ridesName);
  if (file == null) throw BackupFormatException('归档里没有 $_ridesName');
  try {
    final List<Object?> raw = jsonDecode(utf8.decode(file.content)) as List<Object?>;
    return <Ride>[
      for (final Object? row in raw)
        Ride.fromDbMap(row as Map<String, Object?>),
    ];
  } catch (error) {
    throw BackupFormatException('$_ridesName 无法解析：$error');
  }
}

List<TrackPoint> _decodePoints(Archive archive) {
  final ArchiveFile? file = archive.findFile(_pointsName);
  if (file == null) throw BackupFormatException('归档里没有 $_pointsName');
  try {
    final String text = utf8.decode(file.content);
    return <TrackPoint>[
      for (final String line in text.split('\n'))
        if (line.trim().isNotEmpty)
          TrackPoint.fromDbMap(jsonDecode(line) as Map<String, Object?>),
    ];
  } catch (error) {
    throw BackupFormatException('$_pointsName 无法解析：$error');
  }
}

/// 把备份写回数据库。
///
/// [replaceExisting] 为真时先清空两张表，语义是「把数据库恢复成备份那一刻的
/// 状态」——设置页调用前必须弹确认框告知用户会丢掉现有记录。
///
/// 整个过程在一个事务里：中途失败（例如外键不满足）时回滚，不会留下半份数据。
Future<void> applyBackup(
  BackupPayload payload, {
  required Database db,
  bool replaceExisting = true,
}) async {
  await db.transaction((Transaction txn) async {
    final RideDao rides = RideDao(txn);
    final TrackPointDao points = TrackPointDao(txn);

    if (replaceExisting) {
      // 先删点再删骑行：track_points.ride_id 有外键约束。
      await points.deleteAll();
      await rides.deleteAll();
    }

    for (final Ride ride in payload.rides) {
      await rides.insertWithId(ride);
    }
    await points.insertBatch(payload.points);
  });
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
.fvm/flutter_sdk/bin/flutter test test/data/export/backup_test.dart
```

Expected: `All tests passed!`（14 个测试）

- [ ] **Step 6: 跑全量测试确认 DAO 类型放宽没有破坏别的东西**

```bash
.fvm/flutter_sdk/bin/flutter test
```

Expected: `All tests passed!`

- [ ] **Step 7: 变异自证**

| 变异点 | 应被杀死 |
| --- | --- |
| `parseBackupArchive` 的版本校验改成 `>` | schema 版本更高时明确拒绝（相等判断） |
| 版本校验整个删掉 | 拒绝时异常里带上实际版本与期望版本 |
| `applyBackup` 里 `replaceExisting` 判断反过来 | replaceExisting 为真时先清空再写入 / 为假时保留已有数据 |
| 先删骑行再删点 | 恢复失败时不留半份数据（外键会先炸，或删不干净） |
| `applyBackup` 不用 `db.transaction` 包住 | 恢复失败时不留半份数据 |
| `_decodePoints` 去掉 `line.trim().isNotEmpty` | 空数据也能打包与解包（空文本会 split 出一个空串，`jsonDecode('')` 抛错） |

- [ ] **Step 8: 静态检查与提交**

```bash
.fvm/flutter_sdk/bin/flutter analyze lib test
```

Expected: `No issues found!`

```bash
git add lib/data/export/backup.dart lib/data/db test/data/export/backup_test.dart
git commit -m "feat: 添加全量备份打包与恢复"
```

---

## 关于页面层的一个架构决定（Task 8–13 都适用，实施时不要改）

设计文档 4 的技术栈里图表选了 `fl_chart`。**本计划对它的使用做了一处收窄**：

| 场景 | 用什么 | 理由 |
| --- | --- | --- |
| 详情页的速度 / 心率 / 踏频曲线 | **自绘 `CustomPaint`** | 设计文档 8.2 要求「速度曲线与地图轨迹共用同一套颜色映射，保证两个视图视觉一致」。`fl_chart` 的 `LineChartBarData` 只能给整条线一个颜色、或一个**按 x 位置**的渐变，做不出「按每一段的速度着色」。自绘可以直接复用 `segmentColorArgb`，与地图图层用的是同一个函数。 |
| 历史卡片的迷你速度曲线 | **自绘 `CustomPaint`** | 列表里每张卡片一个图表，自绘比建一堆 `LineChart` 便宜得多。 |
| 统计页的趋势折线 | **`fl_chart` 的 `LineChart`** | 那里不需要按值着色，标准折线 + 坐标轴正好是 `fl_chart` 的强项。 |

自绘的部分**渲染本身手动验证**（设计文档 13 已把「地图渲染」列为不自动化项），
但喂给画笔的**数据**（`buildCurve`、`buildRouteSegments`、`buildTrend`）全部有测试兜住。

---

## Task 8: features/detail — 详情页（汇总网格 + 三条曲线 + 心率区间条）

设计文档 10.3：详情页自上而下是 ① 着色地图轨迹 ② 汇总指标网格 ③ 速度曲线（着色）④ 心率曲线 + 心率区间分布条 ⑤ 踏频曲线 ⑥ 导出 GPX 按钮。

本任务做 ②③④⑤，以及页面骨架；① 与 ⑥ 由 Task 10 补上。

**Files:**
- Create: `lib/features/detail/detail_providers.dart`
- Create: `lib/features/detail/detail_page.dart`
- Create: `lib/features/detail/summary_grid.dart`
- Create: `lib/features/detail/curve_chart.dart`
- Create: `lib/features/detail/hr_zone_bar.dart`
- Modify: `lib/core/format.dart`（补 `formatDateTime`）
- Test: `test/core/format_test.dart`（追加）
- Create: `test/features/detail/detail_page_test.dart`

- [ ] **Step 1: 先给 format.dart 补日期格式化（含失败测试）**

在 `test/core/format_test.dart` 末尾（`main()` 内）追加：

```dart
  group('formatDateTime', () {
    test('按本地时区输出 yyyy-MM-dd HH:mm', () {
      final int ms = DateTime(2026, 9, 21, 8, 5).millisecondsSinceEpoch;
      expect(formatDateTime(ms), '2026-09-21 08:05');
    });

    test('个位数月日与时分都补零', () {
      final int ms = DateTime(2026, 1, 2, 3, 4).millisecondsSinceEpoch;
      expect(formatDateTime(ms), '2026-01-02 03:04');
    });

    test('午夜输出 00:00', () {
      final int ms = DateTime(2026, 12, 31).millisecondsSinceEpoch;
      expect(formatDateTime(ms), '2026-12-31 00:00');
    });
  });
```

运行确认失败：

```bash
.fvm/flutter_sdk/bin/flutter test test/core/format_test.dart
```

Expected: FAIL，报 `The function 'formatDateTime' isn't defined`。

在 `lib/core/format.dart` 末尾加：

```dart
/// 日期时间文本，形如 `2026-09-21 08:05`。用本地时区。
///
/// 不做「今年省略年份」的压缩：列表里跨年的记录混在一起时，省略年份会看不出
/// 是哪一年，得不偿失。
String formatDateTime(int epochMs) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
```

再跑一次确认通过：

```bash
.fvm/flutter_sdk/bin/flutter test test/core/format_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 2: 写详情页的失败测试**

创建 `test/features/detail/detail_page_test.dart`：

```dart
import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/features/detail/detail_page.dart';
import 'package:cycling_app/features/detail/detail_providers.dart';
import 'package:cycling_app/features/detail/curve_chart.dart';
import 'package:cycling_app/features/detail/hr_zone_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

const AppSettings _settings = AppSettings(
  maxHeartRate: 190,
  weightKg: 70,
  distanceUnit: DistanceUnit.kilometer,
  mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
);

Ride rideWith({RideSummary? summary}) => Ride(
      id: 1,
      startedAtMs: DateTime(2026, 9, 21, 8).millisecondsSinceEpoch,
      endedAtMs: DateTime(2026, 9, 21, 9).millisecondsSinceEpoch,
      status: RideStatus.finished,
      title: '晨骑',
      summary: summary ??
          const RideSummary(
            distanceM: 25300,
            durationS: 3600,
            movingS: 3400,
            avgSpeedMps: 7.03,
            movingAvgSpeedMps: 7.44,
            maxSpeedMps: 12.5,
            elevationGainM: 180,
            avgHr: 142,
            maxHr: 176,
            avgCadence: 78,
            calories: 900,
            pointCount: 4,
          ),
    );

/// 每秒一个点，速度与心率递增，用来产生可断言的曲线与区间分布。
List<TrackPoint> pointsWithHr() => <TrackPoint>[
      for (int i = 0; i < 4; i++)
        TrackPoint(
          rideId: 1,
          tMs: 1000 + i * 1000,
          lat: 31.0 + i * 0.0001,
          lon: 121.0,
          altitudeM: 10.0 + i,
          speedMps: 4.0 + i,
          hr: 100 + i * 20,
          cadence: 70 + i,
        ),
    ];

Widget wrap({
  required RideDetail detail,
  AppSettings settings = _settings,
}) =>
    ProviderScope(
      overrides: <Override>[
        rideDetailProvider(detail.ride.id!).overrideWith((Ref ref) => detail),
        appSettingsProvider.overrideWithValue(AsyncValue<AppSettings>.data(settings)),
      ],
      child: MaterialApp(home: DetailPage(rideId: detail.ride.id!)),
    );

void main() {
  testWidgets('显示汇总指标网格里的距离、时长与爬升', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      detail: RideDetail(ride: rideWith(), points: pointsWithHr()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('25.30 km'), findsOneWidget);
    expect(find.text('1:00:00'), findsOneWidget);
    expect(find.text('180 m'), findsOneWidget);
  });

  testWidgets('标题显示骑行标题与日期', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      detail: RideDetail(ride: rideWith(), points: pointsWithHr()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('晨骑'), findsOneWidget);
    expect(find.text('2026-09-21 08:00'), findsOneWidget);
  });

  testWidgets('三条曲线区块都渲染出来', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      detail: RideDetail(ride: rideWith(), points: pointsWithHr()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('速度'), findsOneWidget);
    expect(find.text('心率'), findsOneWidget);
    expect(find.text('踏频'), findsOneWidget);
    expect(find.byType(CurveChart), findsNWidgets(3));
  });

  testWidgets('没有心率数据时不渲染心率曲线与区间条', (WidgetTester tester) async {
    final List<TrackPoint> noHr = <TrackPoint>[
      for (final TrackPoint p in pointsWithHr())
        TrackPoint(
          rideId: p.rideId,
          tMs: p.tMs,
          lat: p.lat,
          lon: p.lon,
          speedMps: p.speedMps,
          cadence: p.cadence,
        ),
    ];

    await tester.pumpWidget(wrap(
      detail: RideDetail(ride: rideWith(), points: noHr),
    ));
    await tester.pumpAndSettle();

    expect(find.text('心率'), findsNothing);
    expect(find.byType(HrZoneBar), findsNothing);
    expect(find.text('速度'), findsOneWidget);
  });

  testWidgets('没有踏频数据时不渲染踏频曲线', (WidgetTester tester) async {
    final List<TrackPoint> noCadence = <TrackPoint>[
      for (final TrackPoint p in pointsWithHr())
        TrackPoint(
          rideId: p.rideId,
          tMs: p.tMs,
          lat: p.lat,
          lon: p.lon,
          speedMps: p.speedMps,
          hr: p.hr,
        ),
    ];

    await tester.pumpWidget(wrap(
      detail: RideDetail(ride: rideWith(), points: noCadence),
    ));
    await tester.pumpAndSettle();

    expect(find.text('踏频'), findsNothing);
    expect(find.text('心率'), findsOneWidget);
  });

  testWidgets('轨迹点为空时显示空数据提示且不崩溃', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      detail: RideDetail(ride: rideWith(), points: const <TrackPoint>[]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('这次骑行没有轨迹数据'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('心率区间条按区间标出时长占比', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      detail: RideDetail(ride: rideWith(), points: pointsWithHr()),
    ));
    await tester.pumpAndSettle();

    // 四个点共 3 秒：心率 120/140/160 分别落在 Z2/Z3/Z4（最大心率 190）。
    final HrZoneBar bar = tester.widget<HrZoneBar>(find.byType(HrZoneBar));
    expect(bar.breakdown.totalSeconds, 3.0);
    expect(bar.breakdown.ratioOf(2), closeTo(1 / 3, 1e-9));
    expect(bar.breakdown.ratioOf(3), closeTo(1 / 3, 1e-9));
    expect(bar.breakdown.ratioOf(4), closeTo(1 / 3, 1e-9));
    expect(bar.breakdown.ratioOf(1), 0);
    expect(bar.breakdown.ratioOf(5), 0);
  });

  testWidgets('汇总缺失（进行中的骑行）时显示提示而不是崩溃', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      detail: RideDetail(
        ride: Ride(id: 1, startedAtMs: 1000, status: RideStatus.finished),
        points: const <TrackPoint>[],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('这条记录还没有汇总指标'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 3: 运行测试确认失败**

```bash
.fvm/flutter_sdk/bin/flutter test test/features/detail/detail_page_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 4: 写实现**

创建 `lib/features/detail/detail_providers.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../app/providers.dart';
import '../../data/ride_repository.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';

/// 详情页需要的数据：骑行本身 + 它的全部轨迹点。
class RideDetail {
  const RideDetail({required this.ride, required this.points});

  final Ride ride;
  final List<TrackPoint> points;
}

/// 按 rideId 取详情。用 family 让每个详情页各自缓存。
final FutureProviderFamily<RideDetail, int> rideDetailProvider =
    FutureProvider.family<RideDetail, int>((Ref ref, int rideId) async {
  final RideRepository repo = ref.watch(rideRepositoryProvider);
  final Ride? ride = await repo.getRide(rideId);
  if (ride == null) {
    throw StateError('骑行记录不存在：$rideId');
  }
  return RideDetail(ride: ride, points: await repo.getPoints(rideId));
});
```

创建 `lib/features/detail/summary_grid.dart`：

```dart
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/models/ride.dart';

/// 汇总指标网格。见设计文档 10.3 的第 2 块。
class SummaryGrid extends StatelessWidget {
  const SummaryGrid({required this.ride, required this.unit, super.key});

  final Ride ride;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) {
    final RideSummary? s = ride.summary;
    if (s == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('这条记录还没有汇总指标'),
      );
    }

    final List<_Metric> metrics = <_Metric>[
      _Metric('距离', formatDistance(s.distanceM, unit)),
      _Metric('时长', formatDuration(s.durationS)),
      _Metric('移动时长', formatDuration(s.movingS)),
      _Metric('总均速', '${formatSpeedValue(s.avgSpeedMps, unit)} ${speedUnitLabel(unit)}'),
      _Metric('移动均速', '${formatSpeedValue(s.movingAvgSpeedMps, unit)} ${speedUnitLabel(unit)}'),
      if (s.maxSpeedMps != null)
        _Metric('最高速', '${formatSpeedValue(s.maxSpeedMps!, unit)} ${speedUnitLabel(unit)}'),
      _Metric('爬升', '${s.elevationGainM.round()} m'),
      if (s.avgHr != null) _Metric('平均心率', '${s.avgHr!.round()} bpm'),
      if (s.maxHr != null) _Metric('最高心率', '${s.maxHr} bpm'),
      if (s.avgCadence != null) _Metric('平均踏频', '${s.avgCadence!.round()} rpm'),
      if (s.calories != null) _Metric('卡路里', '${s.calories!.round()} kcal（参考）'),
      _Metric('轨迹点', '${s.pointCount}'),
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: <Widget>[
          for (final _Metric m in metrics)
            SizedBox(width: 104, child: _MetricTile(metric: m)),
        ],
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value);

  final String label;
  final String value;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(metric.label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            metric.value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: kAppAccent,
            ),
          ),
        ],
      );
}
```

> `RideSummary` 需要 import：在文件顶部补 `import '../../domain/models/ride_summary.dart';`。

创建 `lib/features/detail/curve_chart.dart`：

```dart
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/analysis/color_scale.dart';
import '../../domain/analysis/curve.dart';

/// 详情页的一条曲线。见设计文档 10.3 的第 3~5 块。
///
/// 自绘而不是用图表库：设计文档 8.2 要求速度曲线与地图轨迹共用同一套颜色映射，
/// 而 `fl_chart` 的折线只能整条一个颜色（或一个按 x 位置的渐变），
/// 做不出「按每一段的速度着色」。自绘可以直接复用 [segmentColorArgb]。
class CurveChart extends StatelessWidget {
  const CurveChart({
    required this.samples,
    required this.unitLabel,
    this.colorBySpeed = false,
    this.baseColorArgb = kAppAccentArgb,
    super.key,
  });

  final List<CurveSample> samples;

  /// y 轴单位，画在左上角。
  final String unitLabel;

  /// 为真时按每段平均速度着色（速度曲线用），否则用 [baseColorArgb]。
  final bool colorBySpeed;

  final int baseColorArgb;

  static const double chartHeight = 140;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: chartHeight,
      child: CustomPaint(
        size: Size.infinite,
        painter: _CurvePainter(
          samples: samples,
          colorBySpeed: colorBySpeed,
          baseColorArgb: baseColorArgb,
        ),
      ),
    );
  }
}

/// 主题强调色的 ARGB 整数形式，供画笔使用（画笔只认 int，不认 Color 常量表）。
const int kAppAccentArgb = 0xFF4CAF50;

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.samples,
    required this.colorBySpeed,
    required this.baseColorArgb,
  });

  final List<CurveSample> samples;
  final bool colorBySpeed;
  final int baseColorArgb;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    double maxY = 0;
    for (final CurveSample s in samples) {
      if (s.y > maxY) maxY = s.y;
    }
    if (maxY <= 0) maxY = 1;

    final double maxX = samples.last.xSeconds;
    if (maxX <= 0) return;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (int i = 1; i < samples.length; i++) {
      final CurveSample a = samples[i - 1];
      final CurveSample b = samples[i];
      // 断点两侧不连线：否则会画出一条横穿隧道或建筑物的假直线（设计文档 9.3）。
      if (a.segment != b.segment) continue;

      paint.color = Color(
        colorBySpeed ? segmentColorArgb(a.y, b.y) : baseColorArgb,
      );
      canvas.drawLine(
        Offset(
          a.xSeconds / maxX * size.width,
          size.height - a.y / maxY * size.height,
        ),
        Offset(
          b.xSeconds / maxX * size.width,
          size.height - b.y / maxY * size.height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      !identical(old.samples, samples) ||
      old.colorBySpeed != colorBySpeed ||
      old.baseColorArgb != baseColorArgb;
}
```

创建 `lib/features/detail/hr_zone_bar.dart`：

```dart
import 'package:flutter/material.dart';

import '../../domain/analysis/heart_rate.dart';

/// 心率区间分布条。见设计文档 10.3 的第 4 块与 8.2 的区间定义。
class HrZoneBar extends StatelessWidget {
  const HrZoneBar({required this.breakdown, super.key});

  final HrZoneBreakdown breakdown;

  /// 各区间在条上的颜色，由慢到快。
  static const List<Color> zoneColors = <Color>[
    Color(0xFF64B5F6),
    Color(0xFF4CAF50),
    Color(0xFFFFB300),
    Color(0xFFFB8C00),
    Color(0xFFB71C1C),
  ];

  @override
  Widget build(BuildContext context) {
    if (breakdown.totalSeconds <= 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('这次骑行没有心率数据'),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 14,
              child: Row(
                children: <Widget>[
                  for (final HrZone zone in kHrZones)
                    if (breakdown.ratioOf(zone.index) > 0)
                      Expanded(
                        flex: (breakdown.ratioOf(zone.index) * 1000).round(),
                        child: ColoredBox(color: zoneColors[zone.index - 1]),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: <Widget>[
              for (final HrZone zone in kHrZones)
                Text(
                  '${zone.label} ${(breakdown.ratioOf(zone.index) * 100).round()}%'
                  ' · ${breakdown.secondsByZone[zone.index]?.round() ?? 0}s',
                  style: TextStyle(
                    fontSize: 12,
                    color: zoneColors[zone.index - 1],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
```

创建 `lib/features/detail/detail_page.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/constants.dart';
import '../../domain/analysis/curve.dart';
import '../../domain/analysis/heart_rate.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';
import 'curve_chart.dart';
import 'detail_providers.dart';
import 'hr_zone_bar.dart';
import 'summary_grid.dart';

/// 单次骑行详情页。见设计文档 10.3。
///
/// 地图轨迹与导出 GPX 由 Task 10 补在本页上方与下方。
class DetailPage extends ConsumerWidget {
  const DetailPage({required this.rideId, super.key});

  final int rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RideDetail> detail = ref.watch(rideDetailProvider(rideId));
    final DistanceUnit unit =
        ref.watch(appSettingsProvider).valueOrNull?.distanceUnit ??
            DistanceUnit.kilometer;

    return Scaffold(
      appBar: AppBar(title: Text(detail.valueOrNull?.ride.title ?? '骑行详情')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            Center(child: Text('读取记录失败：$error')),
        data: (RideDetail data) => _DetailBody(detail: data, unit: unit),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.detail, required this.unit});

  final RideDetail detail;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Ride ride = detail.ride;
    final List<TrackPoint> points = detail.points;
    final int maxHeartRate =
        ref.watch(appSettingsProvider).valueOrNull?.maxHeartRate ??
            kDefaultMaxHeartRate;

    final List<CurveSample> speed =
        buildCurve(points, metric: CurveMetric.speed);
    final List<CurveSample> hr =
        buildCurve(points, metric: CurveMetric.heartRate);
    final List<CurveSample> cadence =
        buildCurve(points, metric: CurveMetric.cadence);

    return ListView(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            formatDateTime(ride.startedAtMs),
            style: const TextStyle(color: kAppSurface, fontSize: 13),
          ),
        ),
        SummaryGrid(ride: ride, unit: unit),
        if (points.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('这次骑行没有轨迹数据'),
          ),
        if (speed.length >= 2) ...<Widget>[
          const _SectionTitle('速度'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CurveChart(
              samples: speed,
              unitLabel: speedUnitLabel(unit),
              colorBySpeed: true,
            ),
          ),
        ],
        if (hr.length >= 2) ...<Widget>[
          const _SectionTitle('心率'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CurveChart(samples: hr, unitLabel: 'bpm'),
          ),
          const SizedBox(height: 12),
          HrZoneBar(breakdown: hrZoneBreakdown(points, maxHeartRate)),
        ],
        if (cadence.length >= 2) ...<Widget>[
          const _SectionTitle('踏频'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CurveChart(samples: cadence, unitLabel: 'rpm'),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      );
}
```

> `kDefaultMaxHeartRate` 来自 `lib/data/settings_repository.dart`，已经在 import 列表里。
> `kGpsGapMs` 在本文件用不到，若 `analyze` 报未使用导入就把 `constants.dart` 那行删掉。

- [ ] **Step 5: 运行测试确认通过**

```bash
.fvm/flutter_sdk/bin/flutter test test/features/detail/detail_page_test.dart test/core/format_test.dart
```

Expected: `All tests passed!`（8 + 23 个测试）

- [ ] **Step 6: 变异自证**

| 变异点 | 应被杀死 |
| --- | --- |
| `_DetailBody` 里 `speed.length >= 2` 改成 `>= 0`（永远渲染） | 轨迹点为空时显示空数据提示且不崩溃（空样本画不出线，但断言的是提示文本与 `CurveChart` 数量） |
| 心率区块的条件改成永远渲染 | 没有心率数据时不渲染心率曲线与区间条 |
| 踏频区块的条件改成永远渲染 | 没有踏频数据时不渲染踏频曲线 |
| `_CurvePainter` 里去掉 `a.segment != b.segment` 的跳过 | **没有直接杀死点——补一条用例**：`CurveChart` 的 painter 在跨 segment 时不产生线段（用 `shouldRepaint` + 一个暴露给测试的 `segmentCount` getter，或直接断言 `buildCurve` 的 segment 值并在注释里说明画笔依赖它） |
| `SummaryGrid` 里 `s == null` 时返回空而不是提示 | 汇总缺失时显示提示而不是崩溃 |
| `formatDateTime` 的 `padLeft(2, '0')` 去掉 | 个位数月日与时分都补零 |

- [ ] **Step 7: 静态检查与提交**

```bash
.fvm/flutter_sdk/bin/flutter analyze lib test
```

Expected: `No issues found!`

```bash
git add lib/core/format.dart lib/features/detail test/core/format_test.dart test/features/detail
git commit -m "feat: 添加骑行详情页的指标网格与曲线"
```

---

## Task 9: features/history — 历史列表页

设计文档 10.2：卡片列表，按时间倒序。每张卡显示日期、距离、时长、均速、爬升，以及一条**着色的迷你速度曲线缩略图**。

**Files:**
- Create: `lib/features/history/history_providers.dart`
- Create: `lib/features/history/history_page.dart`
- Create: `lib/features/history/mini_speed_curve.dart`
- Create: `lib/features/history/ride_card.dart`
- Create: `test/features/history/history_page_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/features/history/history_page_test.dart`：

```dart
import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/features/detail/detail_page.dart';
import 'package:cycling_app/features/detail/detail_providers.dart';
import 'package:cycling_app/features/history/history_page.dart';
import 'package:cycling_app/features/history/history_providers.dart';
import 'package:cycling_app/features/history/mini_speed_curve.dart';
import 'package:cycling_app/features/history/ride_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

const AppSettings _settings = AppSettings(
  maxHeartRate: 190,
  weightKg: 70,
  distanceUnit: DistanceUnit.kilometer,
  mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
);

const RideSummary _summary = RideSummary(
  distanceM: 25300,
  durationS: 3600,
  movingS: 3400,
  avgSpeedMps: 7.03,
  movingAvgSpeedMps: 7.44,
  maxSpeedMps: 12.5,
  elevationGainM: 180,
  pointCount: 4,
);

Ride ride(int id, {String? title, int? startedAtMs}) => Ride(
      id: id,
      startedAtMs: startedAtMs ?? DateTime(2026, 9, 21, 8).millisecondsSinceEpoch,
      endedAtMs: DateTime(2026, 9, 21, 9).millisecondsSinceEpoch,
      status: RideStatus.finished,
      title: title,
      summary: _summary,
    );

List<TrackPoint> points() => <TrackPoint>[
      for (int i = 0; i < 4; i++)
        TrackPoint(
          rideId: 1,
          tMs: 1000 + i * 1000,
          lat: 31.0 + i * 0.0001,
          lon: 121.0,
          speedMps: 4.0 + i,
        ),
    ];

Widget wrap({
  required List<Ride> rides,
  List<TrackPoint>? ridePoints,
  AppSettings settings = _settings,
}) =>
    ProviderScope(
      overrides: <Override>[
        historyRidesProvider.overrideWith((Ref ref) => rides),
        appSettingsProvider.overrideWithValue(AsyncValue<AppSettings>.data(settings)),
        for (final Ride r in rides)
          ridePointsProvider(r.id!).overrideWith(
            (Ref ref) => ridePoints ?? const <TrackPoint>[],
          ),
      ],
      child: const MaterialApp(home: HistoryPage()),
    );

void main() {
  testWidgets('没有记录时显示空态提示', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(rides: const <Ride>[]));
    await tester.pumpAndSettle();

    expect(find.text('还没有骑行记录'), findsOneWidget);
    expect(find.byType(RideCard), findsNothing);
  });

  testWidgets('每条记录一张卡片，按传入顺序渲染', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      rides: <Ride>[
        ride(2, title: '第二次', startedAtMs: DateTime(2026, 9, 22, 8).millisecondsSinceEpoch),
        ride(1, title: '第一次'),
      ],
      ridePoints: points(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(RideCard), findsNWidgets(2));
    expect(find.text('第二次'), findsOneWidget);
    expect(find.text('第一次'), findsOneWidget);
  });

  testWidgets('卡片显示日期、距离、时长、均速与爬升', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(rides: <Ride>[ride(1)], ridePoints: points()));
    await tester.pumpAndSettle();

    expect(find.text('2026-09-21 08:00'), findsOneWidget);
    expect(find.text('25.30 km'), findsOneWidget);
    expect(find.text('1:00:00'), findsOneWidget);
    expect(find.text('25.3 km/h'), findsOneWidget); // 7.03 m/s
    expect(find.text('180 m'), findsOneWidget);
  });

  testWidgets('卡片里渲染迷你速度曲线', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(rides: <Ride>[ride(1)], ridePoints: points()));
    await tester.pumpAndSettle();

    expect(find.byType(MiniSpeedCurve), findsOneWidget);
  });

  testWidgets('没有标题时用日期当标题', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(rides: <Ride>[ride(1)], ridePoints: points()));
    await tester.pumpAndSettle();

    expect(find.text('2026-09-21 08:00'), findsOneWidget);
  });

  testWidgets('英里单位下按英里显示距离', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      rides: <Ride>[ride(1)],
      ridePoints: points(),
      settings: const AppSettings(
        maxHeartRate: 190,
        weightKg: 70,
        distanceUnit: DistanceUnit.mile,
        mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('15.72 mi'), findsOneWidget); // 25300 m
  });

  testWidgets('点卡片进入详情页', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(rides: <Ride>[ride(1)], ridePoints: points()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(RideCard).first);
    await tester.pumpAndSettle();

    expect(find.byType(DetailPage), findsOneWidget);
    expect(find.text('骑行详情'), findsOneWidget);
  });

  testWidgets('没有汇总指标的记录不崩溃，卡片显示占位', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      rides: <Ride>[
        const Ride(id: 1, startedAtMs: 1000, status: RideStatus.finished),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(RideCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
.fvm/flutter_sdk/bin/flutter test test/features/history/history_page_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写实现**

创建 `lib/features/history/history_providers.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../app/providers.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';

/// 已完成的骑行，按开始时间倒序（排序由 `RideDao.listFinished` 保证）。
final FutureProvider<List<Ride>> historyRidesProvider =
    FutureProvider<List<Ride>>(
  (Ref ref) => ref.watch(rideRepositoryProvider).listFinished(),
);

/// 某次骑行的轨迹点，供卡片上的迷你曲线使用。
///
/// 用 family 而不是一次取全部点：列表是懒加载的，不可见的卡片不会触发查询，
/// 记录多起来之后不会一次把所有轨迹点读进内存。
final FutureProviderFamily<List<TrackPoint>, int> ridePointsProvider =
    FutureProvider.family<List<TrackPoint>, int>(
  (Ref ref, int rideId) => ref.watch(rideRepositoryProvider).getPoints(rideId),
);
```

创建 `lib/features/history/mini_speed_curve.dart`：

```dart
import 'package:flutter/material.dart';

import '../../domain/analysis/color_scale.dart';
import '../../domain/analysis/curve.dart';
import '../../domain/models/track_point.dart';

/// 卡片上的迷你速度曲线缩略图。见设计文档 10.2。
///
/// 用 [CustomPaint] 而不是图表库：列表里每张卡片一个图表，自绘便宜得多，
/// 而且能直接复用 [segmentColorArgb]，与详情页曲线、地图轨迹视觉一致。
class MiniSpeedCurve extends StatelessWidget {
  const MiniSpeedCurve({required this.points, super.key});

  final List<TrackPoint> points;

  static const double height = 32;

  /// 缩略图最多画这么多点，再多也看不出来。
  static const int maxSamples = 60;

  @override
  Widget build(BuildContext context) {
    final List<CurveSample> samples = buildCurve(
      points,
      metric: CurveMetric.speed,
      maxSamples: maxSamples,
    );
    if (samples.length < 2) return const SizedBox(height: height);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        size: Size.infinite,
        painter: _MiniSpeedPainter(samples),
      ),
    );
  }
}

class _MiniSpeedPainter extends CustomPainter {
  _MiniSpeedPainter(this.samples);

  final List<CurveSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    double maxY = 0;
    for (final CurveSample s in samples) {
      if (s.y > maxY) maxY = s.y;
    }
    if (maxY <= 0) return;

    final double maxX = samples.last.xSeconds;
    if (maxX <= 0) return;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (int i = 1; i < samples.length; i++) {
      final CurveSample a = samples[i - 1];
      final CurveSample b = samples[i];
      if (a.segment != b.segment) continue;

      paint.color = Color(segmentColorArgb(a.y, b.y));
      canvas.drawLine(
        Offset(a.xSeconds / maxX * size.width, size.height - a.y / maxY * size.height),
        Offset(b.xSeconds / maxX * size.width, size.height - b.y / maxY * size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniSpeedPainter old) => !identical(old.samples, samples);
}
```

创建 `lib/features/history/ride_card.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/ride_summary.dart';
import 'history_providers.dart';
import 'mini_speed_curve.dart';

/// 历史列表里的一张骑行卡片。见设计文档 10.2。
class RideCard extends ConsumerWidget {
  const RideCard({required this.ride, required this.unit, this.onTap, super.key});

  final Ride ride;
  final DistanceUnit unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RideSummary? s = ride.summary;

    return Card(
      color: kAppSurface,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      ride.title?.trim().isNotEmpty == true
                          ? ride.title!.trim()
                          : formatDateTime(ride.startedAtMs),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (ride.title?.trim().isNotEmpty == true)
                    Text(
                      formatDateTime(ride.startedAtMs),
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (s == null)
                const Text('这条记录还没有汇总指标', style: TextStyle(fontSize: 13))
              else ...<Widget>[
                Text(
                  formatDistance(s.distanceM, unit),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: kAppAccent,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: <Widget>[
                    Text(formatDuration(s.durationS), style: _metaStyle),
                    Text(
                      '${formatSpeedValue(s.movingAvgSpeedMps, unit)} ${speedUnitLabel(unit)}',
                      style: _metaStyle,
                    ),
                    Text('爬升 ${s.elevationGainM.round()} m', style: _metaStyle),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              _MiniCurve(rideId: ride.id),
            ],
          ),
        ),
      ),
    );
  }
}

const TextStyle _metaStyle = TextStyle(fontSize: 13, color: Colors.white70);

/// 迷你曲线单独拆一个 Consumer，让轨迹点的加载不影响卡片其余部分的重建。
class _MiniCurve extends ConsumerWidget {
  const _MiniCurve({required this.rideId});

  final int? rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int? id = rideId;
    if (id == null) return const SizedBox(height: MiniSpeedCurve.height);

    final AsyncValue<List<TrackPoint>> points = ref.watch(ridePointsProvider(id));
    return points.maybeWhen(
      data: (List<TrackPoint> list) => MiniSpeedCurve(points: list),
      orElse: () => const SizedBox(height: MiniSpeedCurve.height),
    );
  }
}
```

> 补 import：`import '../../domain/models/track_point.dart';`（`_MiniCurve` 用到 `TrackPoint`）。

创建 `lib/features/history/history_page.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/settings_repository.dart';
import '../../domain/models/ride.dart';
import '../detail/detail_page.dart';
import 'history_providers.dart';
import 'ride_card.dart';

/// 历史列表页。见设计文档 10.2。
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Ride>> rides = ref.watch(historyRidesProvider);
    final DistanceUnit unit =
        ref.watch(appSettingsProvider).valueOrNull?.distanceUnit ??
            DistanceUnit.kilometer;

    return Scaffold(
      appBar: AppBar(title: const Text('历史')),
      body: rides.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            Center(child: Text('读取记录失败：$error')),
        data: (List<Ride> list) {
          if (list.isEmpty) {
            return const Center(child: Text('还没有骑行记录'));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: list.length,
            itemBuilder: (BuildContext context, int index) {
              final Ride ride = list[index];
              final int? id = ride.id;
              return RideCard(
                ride: ride,
                unit: unit,
                onTap: id == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) => DetailPage(rideId: id),
                          ),
                        ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
.fvm/flutter_sdk/bin/flutter test test/features/history/history_page_test.dart
```

Expected: `All tests passed!`（8 个测试）

- [ ] **Step 5: 变异自证**

| 变异点 | 应被杀死 |
| --- | --- |
| 空列表时改成渲染空 `ListView` | 没有记录时显示空态提示 |
| `RideCard` 的 `onTap` 传 null | 点卡片进入详情页 |
| 距离用 `s.distanceM.toString()` | 卡片显示日期、距离、时长、均速与爬升 |
| 均速改用 `s.avgSpeedMps`（而不是移动均速） | 卡片显示…均速（7.44 m/s = 26.8 km/h，与 25.3 不同） |
| `_MiniCurve` 里 `rideId == null` 时直接 `watch(ridePointsProvider(null))` | 没有汇总指标的记录不崩溃（那条记录 id 是 1，不触发；**这条要自己判断是否真被杀死**，没杀死就说明缺用例，补一条 `id == null` 的卡片用例） |

- [ ] **Step 6: 静态检查与提交**

```bash
.fvm/flutter_sdk/bin/flutter analyze lib test
```

Expected: `No issues found!`

```bash
git add lib/features/history test/features/history
git commit -m "feat: 添加历史列表页与迷你速度曲线"
```

---

## Task 10: features/detail — 地图轨迹与导出 GPX

设计文档 10.3 的第 1 块与第 6 块。

地图用 `flutter_map` + 高德栅格瓦片（设计文档 9.1）。**这里有一个必须处理的坐标系问题**：高德是 GCJ-02，手机 GPS 是 WGS-84，直接叠加会偏移数百米——Task 1 的 `wgs84ToGcj02` 就是为这一步准备的。

**再一个必须处理的点**：地图折线要在两种情况下**断开**（Plan A 的实施偏差记录里列为「留给 Plan B 的已知缺口 2」）：

- 时间间隔 > `kGpsGapMs`（设计文档 9.3 的隧道/桥下）
- 隐含速度 > `kMaxPlausibleSpeedMps`（GPS 跳变）

**关于「按相邻两点平均速度着色」的一处工程取舍**：设计文档 9.2 的字面要求是每个点对一段颜色。但一小时骑行有 3000+ 个点，那就是 3000+ 条 `Polyline`，`flutter_map` 会卡。因此 `buildRouteSegments` 按 `maxVerticesPerSegment`（默认 24）把连续点分组成段，**每段一个颜色**（取该段平均速度）。断点一定会断开，不受分组影响。这个取舍在下面的实现注释里写明。

**Files:**
- Create: `lib/domain/analysis/route_segments.dart`
- Create: `lib/features/detail/route_map.dart`
- Create: `lib/features/detail/gpx_export.dart`
- Modify: `lib/features/detail/detail_page.dart`（把地图与导出按钮接进去）
- Create: `test/domain/analysis/route_segments_test.dart`
- Modify: `test/features/detail/detail_page_test.dart`（追加）

- [ ] **Step 1: 写 route_segments 的失败测试**

创建 `test/domain/analysis/route_segments_test.dart`：

```dart
import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/analysis/gcj02.dart';
import 'package:cycling_app/domain/analysis/route_segments.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPoint pt(
  int tMs, {
  double? lat = 31.0,
  double? lon = 121.0,
  double? speed,
}) =>
    TrackPoint(rideId: 1, tMs: tMs, lat: lat, lon: lon, speedMps: speed);

void main() {
  group('基本行为', () {
    test('空输入返回空列表', () {
      expect(buildRouteSegments(const <TrackPoint>[]), isEmpty);
    });

    test('单点构不成折线，返回空列表', () {
      expect(buildRouteSegments(<TrackPoint>[pt(0, speed: 5)]), isEmpty);
    });

    test('无坐标的点被跳过，不影响连线', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 5),
        const TrackPoint(rideId: 1, tMs: 500, hr: 140), // 无坐标
        pt(1000, lat: 31.0001, speed: 6),
      ]);

      expect(segs.length, 1);
      expect(segs.single.vertices.length, 2);
    });

    test('坐标经过 WGS-84 → GCJ-02 转换', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, lat: 39.90750, lon: 116.39123, speed: 5),
        pt(1000, lat: 39.90760, lon: 116.39133, speed: 6),
      ]);

      final ({double lat, double lon}) expected = wgs84ToGcj02(39.90750, 116.39123);
      expect(segs.single.vertices.first.lat, closeTo(expected.lat, 1e-9));
      expect(segs.single.vertices.first.lon, closeTo(expected.lon, 1e-9));
    });

    test('境外点不做转换', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, lat: 35.6762, lon: 139.6503, speed: 5),
        pt(1000, lat: 35.6763, lon: 139.6504, speed: 6),
      ]);

      expect(segs.single.vertices.first.lat, 35.6762);
      expect(segs.single.vertices.first.lon, 139.6503);
    });
  });

  group('断线规则', () {
    test('时间间隔超过 kGpsGapMs 时断开', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 5),
        pt(1000, lat: 31.0001, speed: 5),
        pt(1000 + kGpsGapMs + 1, lat: 31.0002, speed: 5),
        pt(2000 + kGpsGapMs + 1, lat: 31.0003, speed: 5),
      ]);

      expect(segs.length, 2);
      expect(segs[0].vertices.length, 2);
      expect(segs[1].vertices.length, 2);
    });

    test('恰好等于 kGpsGapMs 不断开', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 5),
        pt(kGpsGapMs, lat: 31.0001, speed: 5),
      ]);

      expect(segs.length, 1);
    });

    test('时间不前进时断开', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(1000, speed: 5),
        pt(500, lat: 31.0001, speed: 5),
      ]);

      expect(segs.length, 2);
    });

    test('隐含速度超过 kMaxPlausibleSpeedMps 时断开（GPS 跳变）', () {
      // 1 秒内跨 0.01 度纬度 ≈ 1113 米，远超 30 m/s。
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 5),
        pt(1000, lat: 31.01, speed: 5),
        pt(2000, lat: 31.0101, speed: 5),
      ]);

      // 第一对是跳变（断开），后一对可信。
      expect(segs.length, 2);
      expect(segs[0].vertices.length, 1);
      expect(segs[1].vertices.length, 2);
    });

    test('缺速度时不判跳变，按时间判定', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0),
        pt(1000, lat: 31.01), // 大跳但没速度
        pt(2000, lat: 31.0101),
      ]);

      expect(segs.length, 1);
    });
  });

  group('分组与着色', () {
    test('连续点被分成不超过 maxVerticesPerSegment 个顶点的段', () {
      final List<TrackPoint> points = <TrackPoint>[
        for (int i = 0; i < 100; i++)
          pt(i * 1000, lat: 31.0 + i * 0.0001, speed: 5),
      ];

      final List<RouteSegment> segs =
          buildRouteSegments(points, maxVerticesPerSegment: 10);

      for (final RouteSegment s in segs) {
        expect(s.vertices.length, lessThanOrEqualTo(10));
      }
      expect(segs.length, greaterThan(1));
    });

    test('相邻两段共享一个顶点，折线才连得上', () {
      final List<TrackPoint> points = <TrackPoint>[
        for (int i = 0; i < 30; i++)
          pt(i * 1000, lat: 31.0 + i * 0.0001, speed: 5),
      ];

      final List<RouteSegment> segs =
          buildRouteSegments(points, maxVerticesPerSegment: 10);

      expect(segs.length, greaterThan(1));
      for (int i = 1; i < segs.length; i++) {
        final RouteVertex prevLast = segs[i - 1].vertices.last;
        final RouteVertex curFirst = segs[i].vertices.first;
        expect(curFirst.lat, prevLast.lat);
        expect(curFirst.lon, prevLast.lon);
      }
    });

    test('快的那一段颜色与慢的那一段不同', () {
      final List<RouteSegment> slow = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 1),
        pt(1000, lat: 31.0001, speed: 1),
      ]);
      final List<RouteSegment> fast = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 14),
        pt(1000, lat: 31.0001, speed: 14),
      ]);

      expect(slow.single.colorArgb, isNot(fast.single.colorArgb));
    });

    test('没有速度时按 0 处理，不抛错', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0),
        pt(1000, lat: 31.0001),
      ]);

      expect(segs.single.colorArgb, isNotNull);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
.fvm/flutter_sdk/bin/flutter test test/domain/analysis/route_segments_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写 route_segments 实现**

创建 `lib/domain/analysis/route_segments.dart`：

```dart
import '../models/track_point.dart';
import 'color_scale.dart';
import 'constants.dart';
import 'gcj02.dart';
import 'geo.dart';

/// 地图折线上的一个顶点（已转成 GCJ-02）。
class RouteVertex {
  const RouteVertex(this.lat, this.lon);

  final double lat;
  final double lon;
}

/// 地图折线的一段：一组顶点 + 一个颜色。
class RouteSegment {
  const RouteSegment({required this.vertices, required this.colorArgb});

  final List<RouteVertex> vertices;

  /// 0xAARRGGBB。
  final int colorArgb;
}

/// 把轨迹点整理成地图可用的分段折线。见设计文档 9.2 与 9.3。
///
/// **坐标会转成 GCJ-02**：高德瓦片是 GCJ-02，直接用 WGS-84 画会偏移数百米。
/// 转换只发生在这里，落盘与 GPX 导出的仍是 WGS-84 原始坐标。
///
/// **两种情况下断开折线**，否则地图上会出现横穿隧道或建筑物的假直线：
/// - 时间间隔超过 [kGpsGapMs]（设计文档 9.3）
/// - 隐含速度超过 [kMaxPlausibleSpeedMps]（GPS 跳变）
///
/// [maxVerticesPerSegment] 是对设计文档 9.2「按相邻两点平均速度分段着色」的
/// 工程取舍：字面做法会为每个点对生成一条 `Polyline`，一小时骑行 3000+ 个点
/// 就是 3000+ 条，`flutter_map` 会卡。这里把连续点分组，每组一条 `Polyline`、
/// 一个颜色（取该组平均速度）。断点一定会断开，不受分组影响。
/// 相邻两段共享一个顶点，折线才连得上。
List<RouteSegment> buildRouteSegments(
  List<TrackPoint> points, {
  double maxSpeedMps = kColorScaleMaxSpeedMps,
  int maxVerticesPerSegment = 24,
}) {
  assert(maxVerticesPerSegment >= 2, '一段至少要两个顶点才画得出线');

  final List<TrackPoint> located =
      points.where((TrackPoint p) => p.hasPosition).toList();
  if (located.length < 2) return const <RouteSegment>[];

  final List<RouteSegment> segments = <RouteSegment>[];

  /// 当前正在攒的顶点。段与段之间靠「保留最后一个顶点」连起来。
  List<RouteVertex> current = <RouteVertex>[
    _vertex(located.first),
  ];
  final List<double> currentSpeeds = <double>[_speed(located.first)];

  for (int i = 1; i < located.length; i++) {
    final TrackPoint prev = located[i - 1];
    final TrackPoint cur = located[i];

    if (!_connectable(prev, cur)) {
      _flush(segments, current, currentSpeeds, maxSpeedMps);
      current = <RouteVertex>[_vertex(cur)];
      currentSpeeds
        ..clear()
        ..add(_speed(cur));
      continue;
    }

    if (current.length >= maxVerticesPerSegment) {
      _flush(segments, current, currentSpeeds, maxSpeedMps);
      // 新段从上一段的末点开始，保证折线在视觉上是连着的。
      current = <RouteVertex>[current.last];
      currentSpeeds
        ..clear()
        ..add(currentSpeeds.isEmpty ? _speed(prev) : _speed(prev));
    }

    current.add(_vertex(cur));
    currentSpeeds.add(_speed(cur));
  }

  _flush(segments, current, currentSpeeds, maxSpeedMps);
  return segments;
}

void _flush(
  List<RouteSegment> out,
  List<RouteVertex> vertices,
  List<double> speeds,
  double maxSpeedMps,
) {
  if (vertices.length < 2) return;
  double sum = 0;
  for (final double s in speeds) {
    sum += s;
  }
  final double average = speeds.isEmpty ? 0 : sum / speeds.length;
  out.add(RouteSegment(
    vertices: List<RouteVertex>.unmodifiable(vertices),
    colorArgb: speedColorArgb(average, maxSpeedMps: maxSpeedMps),
  ));
}

bool _connectable(TrackPoint a, TrackPoint b) {
  final int dt = b.tMs - a.tMs;
  if (dt <= 0 || dt > kGpsGapMs) return false;
  // 缺速度时判不出跳变，退回纯时间判定（与 splitMovingStationary 一致）。
  final double? speedA = a.speedMps;
  final double? speedB = b.speedMps;
  if (speedA == null || speedB == null) return true;
  return isTrustedSegment(a, b);
}

RouteVertex _vertex(TrackPoint p) {
  final ({double lat, double lon}) converted = wgs84ToGcj02(p.lat!, p.lon!);
  return RouteVertex(converted.lat, converted.lon);
}

double _speed(TrackPoint p) => p.speedMps ?? 0;
```

- [ ] **Step 4: 运行 route_segments 测试确认通过**

```bash
.fvm/flutter_sdk/bin/flutter test test/domain/analysis/route_segments_test.dart
```

Expected: `All tests passed!`（13 个测试）

- [ ] **Step 5: 写地图与导出实现**

创建 `lib/features/detail/route_map.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/analysis/route_segments.dart';

/// 详情页顶部的着色轨迹地图。见设计文档 9.1 / 9.2。
///
/// 渲染本身不做自动化测试（设计文档 13 把「地图渲染」列为手动验证项）；
/// 喂进来的 [segments] 由 `buildRouteSegments` 算好并已单测覆盖。
class RouteMap extends StatelessWidget {
  const RouteMap({
    required this.segments,
    required this.tileUrlTemplate,
    this.subdomains = const <String>[],
    this.height = 260,
    super.key,
  });

  final List<RouteSegment> segments;

  /// 瓦片源地址，来自设置（设计文档 9.1 的对冲措施：接口失效时可换源）。
  final String tileUrlTemplate;

  final List<String> subdomains;
  final double height;

  @override
  Widget build(BuildContext context) {
    final List<LatLng> all = <LatLng>[
      for (final RouteSegment s in segments)
        for (final RouteVertex v in s.vertices) LatLng(v.lat, v.lon),
    ];

    if (all.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('这次骑行没有可显示的轨迹')),
      );
    }

    return SizedBox(
      height: height,
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(all),
            padding: const EdgeInsets.all(24),
          ),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
          ),
        ),
        children: <Widget>[
          TileLayer(
            urlTemplate: tileUrlTemplate,
            subdomains: subdomains,
            userAgentPackageName: 'com.ling.cycling_app',
          ),
          PolylineLayer(
            polylines: <Polyline<Object>>[
              for (final RouteSegment s in segments)
                Polyline<Object>(
                  points: <LatLng>[
                    for (final RouteVertex v in s.vertices) LatLng(v.lat, v.lon),
                  ],
                  strokeWidth: 4,
                  color: Color(s.colorArgb),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
```

创建 `lib/features/detail/gpx_export.dart`：

```dart
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/export/gpx.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';

/// 把一次骑行导出成 GPX 文件并调起系统分享面板。见设计文档 12。
///
/// 生成逻辑（[buildGpx]）是纯函数，已单测覆盖；这里只做「写文件 + 分享」
/// 这两步 IO，因此不写自动化测试（测试环境没有分享通道）。
class GpxExporter {
  const GpxExporter();

  /// 返回生成的文件路径。分享被取消或失败时抛出的异常交给调用方处理。
  Future<String> exportAndShare({
    required Ride ride,
    required List<TrackPoint> points,
  }) async {
    final Directory dir = await getTemporaryDirectory();
    final String fileName = 'ride_${ride.id ?? 0}.gpx';
    final File file = File('${dir.path}/$fileName');
    await file.writeAsString(buildGpx(ride: ride, points: points));

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'application/gpx+xml')],
        subject: ride.title?.trim().isNotEmpty == true ? ride.title : fileName,
        text: '骑行轨迹 GPX',
      ),
    );
    return file.path;
  }
}
```

> `XFile` 从 `share_plus` 转出（它 re-export 了 `cross_file`）。若 `analyze` 报 `XFile` 未定义，
> 补 `import 'package:cross_file/cross_file.dart';`。

- [ ] **Step 6: 把地图与导出按钮接进详情页**

在 `test/features/detail/detail_page_test.dart` 里补 import 与两条用例：

```dart
import 'package:cycling_app/features/detail/route_map.dart';
```

```dart
  testWidgets('轨迹点有坐标时渲染地图区块', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      detail: RideDetail(ride: rideWith(), points: pointsWithHr()),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(RouteMap), findsOneWidget);
  });

  testWidgets('轨迹点没有坐标时不渲染地图，显示占位提示', (WidgetTester tester) async {
    final List<TrackPoint> noPosition = <TrackPoint>[
      for (int i = 0; i < 3; i++)
        TrackPoint(rideId: 1, tMs: 1000 + i * 1000, speedMps: 5, hr: 140),
    ];

    await tester.pumpWidget(wrap(
      detail: RideDetail(ride: rideWith(), points: noPosition),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(RouteMap), findsOneWidget);
    expect(find.text('这次骑行没有可显示的轨迹'), findsOneWidget);
  });
```

> `RouteMap` 在没有可显示轨迹时**仍然渲染自己**（内部显示占位提示），因此上面两条都断言
> `find.byType(RouteMap), findsOneWidget`。这是为了让地图区块的位置稳定，不让页面在有无轨迹之间跳动。
>
> **注意**：`RouteMap` 里的 `FlutterMap` 会去请求网络瓦片，widget 测试里没有网络会失败或卡住。
> 因此 `DetailPage` 只在**有可显示轨迹时**才构建 `RouteMap`，而测试里用的是 `pointsWithHr()`（有坐标）
> ——这条用例会真的去请求瓦片。**如果实测发现它超时或抛网络异常**，就把这条用例改成断言
> `find.byType(RouteMap)` 之前先 `tester.pumpWidget` 用一个注入了空 `segments` 的 `RouteMap`
> 单独测，并在报告里说明原因。**不要为了让它变绿而删掉整条用例。**

在 `lib/features/detail/detail_page.dart` 里改三处：

**（1）** 补 import：

```dart
import '../../domain/analysis/route_segments.dart';
import 'gpx_export.dart';
import 'route_map.dart';
```

**（2）** 在 `_DetailBody` 的 `ListView` 最前面（日期那一段之前）插入地图：

```dart
    final List<RouteSegment> route = buildRouteSegments(points);
    final String tileUrl = ref.watch(appSettingsProvider).valueOrNull?.mapTileUrlTemplate
        ?? kDefaultMapTileUrlTemplate;

    return ListView(
      children: <Widget>[
        RouteMap(
          segments: route,
          tileUrlTemplate: tileUrl,
          subdomains: kDefaultMapTileSubdomains,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            formatDateTime(ride.startedAtMs),
            style: const TextStyle(color: kAppSurface, fontSize: 13),
          ),
        ),
```

**（3）** 在 `ListView` 的 `const SizedBox(height: 32)` 之前插入导出按钮：

```dart
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: FilledButton.icon(
            onPressed: () => _exportGpx(context, ride, points),
            icon: const Icon(Icons.ios_share),
            label: const Text('导出 GPX'),
          ),
        ),
```

并在 `_DetailBody` 里加一个方法：

```dart
  /// 导出失败时给用户一句能看懂的话，而不是把异常栈糊在界面上。
  Future<void> _exportGpx(
    BuildContext context,
    Ride ride,
    List<TrackPoint> points,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await const GpxExporter().exportAndShare(ride: ride, points: points);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$error')));
    }
  }
```

- [ ] **Step 7: 运行测试确认通过**

```bash
.fvm/flutter_sdk/bin/flutter test test/domain/analysis/route_segments_test.dart test/features/detail/detail_page_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 8: 变异自证**

| 变异点 | 应被杀死 |
| --- | --- |
| `_connectable` 的 `dt > kGpsGapMs` 改成 `dt > kGpsGapMs * 100` | 时间间隔超过 kGpsGapMs 时断开 |
| `_connectable` 去掉 `dt <= 0` | 时间不前进时断开 |
| `_connectable` 直接 `return true`（不判跳变） | 隐含速度超过 kMaxPlausibleSpeedMps 时断开 |
| `_vertex` 不调 `wgs84ToGcj02` | 坐标经过 WGS-84 → GCJ-02 转换 |
| `_flush` 里 `vertices.length < 2` 改成 `< 1` | 单点构不成折线，返回空列表 |
| 分组时不保留共享顶点（新段从空开始） | 相邻两段共享一个顶点 |

- [ ] **Step 9: 静态检查与提交**

```bash
.fvm/flutter_sdk/bin/flutter analyze lib test
```

Expected: `No issues found!`

```bash
git add lib/domain/analysis/route_segments.dart lib/features/detail test/domain/analysis/route_segments_test.dart test/features/detail
git commit -m "feat: 添加地图轨迹图层与 GPX 导出入口"
```

---

## Task 11: features/stats — 长期统计页

设计文档 10.4：周 / 月 / 年范围切换 → 累计距离、时长、爬升 → 趋势折线 → 个人最佳纪录卡片。

**Files:**
- Create: `lib/features/stats/stats_providers.dart`
- Create: `lib/features/stats/stats_page.dart`
- Create: `lib/features/stats/trend_chart.dart`
- Create: `lib/features/stats/personal_bests_card.dart`
- Create: `test/features/stats/stats_page_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/features/stats/stats_page_test.dart`：

```dart
import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/features/stats/personal_bests_card.dart';
import 'package:cycling_app/features/stats/stats_page.dart';
import 'package:cycling_app/features/stats/stats_providers.dart';
import 'package:cycling_app/features/stats/trend_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

const AppSettings _settings = AppSettings(
  maxHeartRate: 190,
  weightKg: 70,
  distanceUnit: DistanceUnit.kilometer,
  mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
);

const RideSummary _summary = RideSummary(
  distanceM: 10000,
  durationS: 1800,
  movingS: 1700,
  avgSpeedMps: 5.56,
  movingAvgSpeedMps: 5.88,
  maxSpeedMps: 11.1,
  elevationGainM: 100,
  pointCount: 1800,
);

/// 固定「现在」：2026-09-24（周四）。
int get nowMs => DateTime(2026, 9, 24, 12).millisecondsSinceEpoch;

Ride ride(int id, int y, int m, int d, {double distanceM = 10000}) => Ride(
      id: id,
      startedAtMs: DateTime(y, m, d, 8).millisecondsSinceEpoch,
      endedAtMs: DateTime(y, m, d, 9).millisecondsSinceEpoch,
      status: RideStatus.finished,
      summary: RideSummary(
        distanceM: distanceM,
        durationS: 1800,
        movingS: 1700,
        avgSpeedMps: 5.56,
        movingAvgSpeedMps: 5.88,
        maxSpeedMps: 11.1,
        elevationGainM: 100,
        pointCount: 1800,
      ),
    );

Widget wrap({
  required List<Ride> rides,
  AppSettings settings = _settings,
}) =>
    ProviderScope(
      overrides: <Override>[
        finishedRidesProvider.overrideWith((Ref ref) => rides),
        nowProvider.overrideWithValue(() => nowMs),
        appSettingsProvider.overrideWithValue(AsyncValue<AppSettings>.data(settings)),
      ],
      child: const MaterialApp(home: StatsPage()),
    );

void main() {
  testWidgets('默认显示本周累计距离、时长与爬升', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(rides: <Ride>[
      ride(1, 2026, 9, 22),
      ride(2, 2026, 9, 24),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('20.00 km'), findsOneWidget);
    expect(find.text('1:00:00'), findsOneWidget);
    expect(find.text('200 m'), findsOneWidget);
  });

  testWidgets('范围外的骑行不计入累计', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(rides: <Ride>[
      ride(1, 2026, 9, 20), // 上周日
    ]));
    await tester.pumpAndSettle();

    expect(find.text('0 m'), findsOneWidget);
  });

  testWidgets('切到「年」后累计包含全年的骑行', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(rides: <Ride>[
      ride(1, 2026, 3, 15),
      ride(2, 2026, 9, 24),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('年'));
    await tester.pumpAndSettle();

    expect(find.text('20.00 km'), findsOneWidget);
  });

  testWidgets('切到「月」后累计包含整月的骑行', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(rides: <Ride>[
      ride(1, 2026, 9, 2),
      ride(2, 2026, 9, 24),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();

    expect(find.text('20.00 km'), findsOneWidget);
  });

  testWidgets('渲染趋势折线', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(rides: <Ride>[ride(1, 2026, 9, 22)]));
    await tester.pumpAndSettle();

    expect(find.byType(TrendChart), findsOneWidget);
    final TrendChart chart = tester.widget<TrendChart>(find.byType(TrendChart));
    expect(chart.trend.buckets.length, 7);
  });

  testWidgets('渲染个人最佳卡片，四项都显示', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(rides: <Ride>[
      ride(1, 2026, 9, 22, distanceM: 30000),
      ride(2, 2026, 9, 24, distanceM: 10000),
    ]));
    await tester.pumpAndSettle();

    expect(find.byType(PersonalBestsCard), findsOneWidget);
    final PersonalBestsCard card =
        tester.widget<PersonalBestsCard>(find.byType(PersonalBestsCard));
    expect(card.bests.longestDistanceM!.rideId, 1);
    expect(card.bests.longestDistanceM!.value, 30000);
  });

  testWidgets('个人最佳跨范围统计，不受周月年切换影响', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(rides: <Ride>[
      ride(1, 2026, 3, 15, distanceM: 40000),
      ride(2, 2026, 9, 24, distanceM: 10000),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();

    final PersonalBestsCard card =
        tester.widget<PersonalBestsCard>(find.byType(PersonalBestsCard));
    expect(card.bests.longestDistanceM!.value, 40000);
  });

  testWidgets('没有任何记录时不崩溃', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(rides: const <Ride>[]));
    await tester.pumpAndSettle();

    expect(find.text('0 m'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
.fvm/flutter_sdk/bin/flutter test test/features/stats/stats_page_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写实现**

创建 `lib/features/stats/stats_providers.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/ride.dart';

/// 全部已完成的骑行。统计页在内存里按范围聚合，不每次查库。
///
/// 个人记录量级（几百到几千条）下这完全够用；真到几万条再考虑下推到 SQL。
final FutureProvider<List<Ride>> finishedRidesProvider =
    FutureProvider<List<Ride>>(
  (Ref ref) => ref.watch(rideRepositoryProvider).listFinished(),
);

/// 当前选中的统计范围。见设计文档 10.4。
final StateProvider<TrendRange> trendRangeProvider =
    StateProvider<TrendRange>((Ref ref) => TrendRange.week);
```

> `TrendRange` 来自 `lib/domain/analysis/trend.dart`，需要在文件顶部补
> `import '../../domain/analysis/trend.dart';`；
> `StateProvider` 需要 `import 'package:flutter_riverpod/legacy.dart';`。

创建 `lib/features/stats/trend_chart.dart`：

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/analysis/trend.dart';

/// 趋势折线。见设计文档 10.4。
///
/// 这里用 `fl_chart`：不需要按值着色，标准折线 + 坐标轴正好是它的强项。
class TrendChart extends StatelessWidget {
  const TrendChart({required this.trend, super.key});

  final TrendSummary trend;

  static const double height = 180;

  @override
  Widget build(BuildContext context) {
    final List<FlSpot> spots = <FlSpot>[
      for (int i = 0; i < trend.buckets.length; i++)
        FlSpot(i.toDouble(), trend.buckets[i].distanceM / 1000),
    ];

    final double maxY = spots.fold(
      0,
      (double m, FlSpot s) => s.y > m ? s.y : m,
    );

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.2,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (double value, TitleMeta meta) =>
                    Text('${value.round()}', style: const TextStyle(fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final int index = value.round();
                  if (index < 0 || index >= trend.buckets.length) {
                    return const SizedBox.shrink();
                  }
                  // 桶多的时候标签会挤成一团，隔一个显示一个。
                  if (trend.buckets.length > 10 && index.isOdd) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    trend.buckets[index].label,
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
          ),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: kAppAccent,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: kAppAccent.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

> `withValues(alpha:)` 是 Flutter 3.27+ 的新 API（替代 `withOpacity`）。若 `analyze` 报未定义，
> 说明本机 SDK 更老，改用 `withOpacity(0.15)`。

创建 `lib/features/stats/personal_bests_card.dart`：

```dart
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/trend.dart';

/// 个人最佳纪录卡片。见设计文档 10.4。
///
/// **跨全部历史统计**，不受周/月/年范围切换影响：个人最佳的意义就是「历史最好」。
class PersonalBestsCard extends StatelessWidget {
  const PersonalBestsCard({required this.bests, required this.unit, super.key});

  final PersonalBests bests;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[
      if (bests.longestDistanceM != null)
        _row('最远距离', formatDistance(bests.longestDistanceM!.value, unit)),
      if (bests.longestDurationS != null)
        _row('最长时长', formatDuration(bests.longestDurationS!.value.round())),
      if (bests.fastestMovingAvgMps != null)
        _row(
          '最快移动均速',
          '${formatSpeedValue(bests.fastestMovingAvgMps!.value, unit)} '
              '${speedUnitLabel(unit)}',
        ),
      if (bests.mostElevationGainM != null)
        _row('最大爬升', '${bests.mostElevationGainM!.value.round()} m'),
    ];

    return Card(
      color: kAppSurface,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '个人最佳',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Text('还没有可统计的记录', style: TextStyle(fontSize: 13))
            else
              ...rows,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kAppAccent,
              ),
            ),
          ],
        ),
      );
}
```

创建 `lib/features/stats/stats_page.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/trend.dart';
import '../../domain/models/ride.dart';
import 'personal_bests_card.dart';
import 'stats_providers.dart';
import 'trend_chart.dart';

/// 长期统计页。见设计文档 10.4。
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Ride>> rides = ref.watch(finishedRidesProvider);
    final AppSettings? settings = ref.watch(appSettingsProvider).valueOrNull;
    final DistanceUnit unit = settings?.distanceUnit ?? DistanceUnit.kilometer;
    final TrendRange range = ref.watch(trendRangeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: rides.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            Center(child: Text('读取记录失败：$error')),
        data: (List<Ride> list) {
          final TrendSummary trend = buildTrend(
            list,
            range: range,
            nowMs: ref.read(nowProvider)(),
          );

          return ListView(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: SegmentedButton<TrendRange>(
                  segments: const <ButtonSegment<TrendRange>>[
                    ButtonSegment<TrendRange>(value: TrendRange.week, label: Text('周')),
                    ButtonSegment<TrendRange>(value: TrendRange.month, label: Text('月')),
                    ButtonSegment<TrendRange>(value: TrendRange.year, label: Text('年')),
                  ],
                  selected: <TrendRange>{range},
                  onSelectionChanged: (Set<TrendRange> selected) =>
                      ref.read(trendRangeProvider.notifier).state = selected.first,
                ),
              ),
              _Totals(trend: trend, unit: unit),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  '距离趋势（km）',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
                child: TrendChart(trend: trend),
              ),
              const SizedBox(height: 16),
              PersonalBestsCard(bests: personalBests(list), unit: unit),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}

/// 范围内的累计距离 / 时长 / 爬升 / 次数。
class _Totals extends StatelessWidget {
  const _Totals({required this.trend, required this.unit});

  final TrendSummary trend;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: <Widget>[
            _tile('距离', formatDistance(trend.distanceM, unit)),
            _tile('时长', formatDuration(trend.durationS)),
            _tile('爬升', '${trend.elevationGainM.round()} m'),
            _tile('次数', '${trend.rideCount}'),
          ],
        ),
      );

  Widget _tile(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: kAppAccent,
              ),
            ),
          ],
        ),
      );
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
.fvm/flutter_sdk/bin/flutter test test/features/stats/stats_page_test.dart
```

Expected: `All tests passed!`（8 个测试）

- [ ] **Step 5: 变异自证**

| 变异点 | 应被杀死 |
| --- | --- |
| `SegmentedButton` 的 `onSelectionChanged` 不改 state | 切到「年」后累计包含全年的骑行 |
| `_Totals` 里用 `trend.rideCount` 代替 `trend.distanceM` | 默认显示本周累计距离、时长与爬升 |
| `PersonalBestsCard` 改成用当前范围的 rides 算 | 个人最佳跨范围统计，不受周月年切换影响 |
| `TrendChart` 的 `maxX` 写死 0 | 渲染趋势折线（`chart.trend.buckets.length` 断言的是入参，杀不死；**补一条**：断言 `find.byType(LineChart)` 存在且 `LineChartData.lineBarsData.single.spots.length == buckets.length`） |
| 范围切换时 `buildTrend` 仍用 `TrendRange.week` | 切到「年」后累计包含全年的骑行 |

- [ ] **Step 6: 静态检查与提交**

```bash
.fvm/flutter_sdk/bin/flutter analyze lib test
```

Expected: `No issues found!`

```bash
git add lib/features/stats test/features/stats
git commit -m "feat: 添加长期统计页与个人最佳"
```

---

## Task 12: features/settings — 设置页（含备份与恢复）

设计文档 10.5：最大心率、体重、单位、传感器配对管理、地图瓦片源、全量备份与恢复。

**为了可测，数据与文件 IO 都从 provider 取**：

- `backupStoreProvider` → `BackupStore`（取全部数据 / 写回备份）
- `backupIoProvider` → `BackupIo`（导出归档 / 让用户选归档文件）

真实实现走 `path_provider` / `file_picker` / `share_plus`；widget 测试注入假实现，因此**不碰数据库也不碰文件系统**。

**Files:**
- Create: `lib/data/export/backup_store.dart`
- Create: `lib/data/export/backup_io.dart`
- Modify: `lib/app/providers.dart`（补两个 provider）
- Create: `lib/features/settings/settings_page.dart`
- Create: `lib/features/settings/backup_section.dart`
- Create: `test/features/settings/settings_page_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/features/settings/settings_page_test.dart`：

```dart
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/export/backup.dart';
import 'package:cycling_app/data/export/backup_io.dart';
import 'package:cycling_app/data/export/backup_store.dart';
import 'package:cycling_app/data/ble/sensor_monitor.dart';
import 'package:cycling_app/data/sensor_pairing.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

const AppSettings _settings = AppSettings(
  maxHeartRate: 190,
  weightKg: 70,
  distanceUnit: DistanceUnit.kilometer,
  mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
);

/// 内存版设置仓储：记录最后一次 save 的内容。
class _FakeSettingsRepository implements SettingsRepository {
  AppSettings saved = _settings;
  int saveCalls = 0;

  @override
  Future<AppSettings> load() async => saved;

  @override
  Future<void> save(AppSettings settings) async {
    saved = settings;
    saveCalls++;
  }
}

/// 内存版配对仓储。
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

/// 内存版备份数据源。
class _FakeBackupStore implements BackupStore {
  _FakeBackupStore({this.rides = const <Ride>[], this.points = const <TrackPoint>[]});

  List<Ride> rides;
  List<TrackPoint> points;
  BackupPayload? applied;
  bool? appliedReplaceExisting;

  @override
  Future<List<Ride>> listRides() async => rides;

  @override
  Future<List<TrackPoint>> listPoints() async => points;

  @override
  Future<void> apply(BackupPayload payload, {required bool replaceExisting}) async {
    applied = payload;
    appliedReplaceExisting = replaceExisting;
  }
}

/// 内存版文件 IO：导出只记录字节，选文件返回预设内容。
class _FakeBackupIo implements BackupIo {
  _FakeBackupIo({this.pickResult});

  Uint8List? pickResult;
  Uint8List? exported;
  String? exportedFileName;
  int exportCalls = 0;
  int pickCalls = 0;
  Object? exportError;

  @override
  Future<void> exportArchive(Uint8List bytes, {required String fileName}) async {
    exportCalls++;
    if (exportError != null) throw exportError!;
    exported = bytes;
    exportedFileName = fileName;
  }

  @override
  Future<Uint8List?> pickArchive() async {
    pickCalls++;
    return pickResult;
  }
}

Uint8List emptyArchive() => buildBackupArchive(
      rides: const <Ride>[],
      points: const <TrackPoint>[],
      exportedAtMs: 0,
    );

Uint8List wrongVersionArchive() => buildBackupArchive(
      rides: const <Ride>[],
      points: const <TrackPoint>[],
      exportedAtMs: 0,
      schemaVersion: kBackupSchemaVersion + 1,
    );

void main() {
  late _FakeSettingsRepository settings;
  late _FakeSensorPairing pairing;
  late _FakeBackupStore store;
  late _FakeBackupIo io;

  setUp(() {
    settings = _FakeSettingsRepository();
    pairing = _FakeSensorPairing();
    store = _FakeBackupStore(
      rides: const <Ride>[
        Ride(id: 1, startedAtMs: 1000, status: RideStatus.finished, title: '晨骑'),
      ],
    );
    io = _FakeBackupIo();
  });

  Widget wrap({AppSettings current = _settings}) => ProviderScope(
        overrides: <Override>[
          settingsRepositoryProvider.overrideWithValue(settings),
          sensorPairingProvider.overrideWithValue(pairing),
          backupStoreProvider.overrideWithValue(store),
          backupIoProvider.overrideWithValue(io),
          appSettingsProvider
              .overrideWithValue(AsyncValue<AppSettings>.data(current)),
        ],
        child: const MaterialApp(home: SettingsPage()),
      );

  testWidgets('显示当前设置值', (WidgetTester tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('190'), findsOneWidget);
    expect(find.text('70.0'), findsOneWidget);
    expect(find.text('公里'), findsOneWidget);
    expect(find.text(kDefaultMapTileUrlTemplate), findsOneWidget);
  });

  testWidgets('改最大心率后保存写回仓储', (WidgetTester tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('190'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '175');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(settings.saveCalls, 1);
    expect(settings.saved.maxHeartRate, 175);
  });

  testWidgets('越界的最大心率不保存，给出提示', (WidgetTester tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('190'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '999');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(settings.saveCalls, 0);
    expect(find.textContaining('最大心率'), findsWidgets);
  });

  testWidgets('没有配对传感器时显示未配对，并提供连接入口', (WidgetTester tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.textContaining('未配对'), findsNWidgets(2)); // 心率 + 踏频
  });

  testWidgets('已配对的传感器显示名字与解除按钮', (WidgetTester tester) async {
    pairing.stored[SensorKind.heartRate] =
        const PairedSensor(id: 'AA:01', name: 'FIT 3');

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.textContaining('FIT 3'), findsOneWidget);
    expect(find.text('解除'), findsOneWidget);
  });

  testWidgets('点解除后清掉配对并刷新界面', (WidgetTester tester) async {
    pairing.stored[SensorKind.heartRate] =
        const PairedSensor(id: 'AA:01', name: 'FIT 3');

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('解除'));
    await tester.pumpAndSettle();

    expect(pairing.stored.containsKey(SensorKind.heartRate), isFalse);
    expect(find.textContaining('FIT 3'), findsNothing);
  });

  testWidgets('点导出备份会把归档交给 IO 层', (WidgetTester tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('导出备份'));
    await tester.pumpAndSettle();

    expect(io.exportCalls, 1);
    expect(io.exported, isNotNull);
    expect(io.exportedFileName, endsWith('.zip'));
    // 归档能被解回来，说明内容是真的。
    final BackupPayload payload = parseBackupArchive(io.exported!);
    expect(payload.rides.single.title, '晨骑');
  });

  testWidgets('导出失败时显示提示而不是崩溃', (WidgetTester tester) async {
    io.exportError = StateError('磁盘满了');

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('导出备份'));
    await tester.pumpAndSettle();

    expect(find.textContaining('导出失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('用户取消选文件时不弹确认框也不写库', (WidgetTester tester) async {
    io.pickResult = null;

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复备份'));
    await tester.pumpAndSettle();

    expect(io.pickCalls, 1);
    expect(find.text('确认恢复？'), findsNothing);
    expect(store.applied, isNull);
  });

  testWidgets('归档版本不匹配时说明原因，且不写库', (WidgetTester tester) async {
    io.pickResult = wrongVersionArchive();

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复备份'));
    await tester.pumpAndSettle();

    expect(find.textContaining('schema 版本'), findsOneWidget);
    expect(find.text('确认恢复？'), findsNothing);
    expect(store.applied, isNull);
  });

  testWidgets('确认框里取消则不写库', (WidgetTester tester) async {
    io.pickResult = emptyArchive();

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复备份'));
    await tester.pumpAndSettle();

    expect(find.text('确认恢复？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(store.applied, isNull);
  });

  testWidgets('确认后按替换语义写回备份', (WidgetTester tester) async {
    io.pickResult = emptyArchive();

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(store.applied, isNotNull);
    expect(store.appliedReplaceExisting, isTrue);
    expect(find.textContaining('恢复完成'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
.fvm/flutter_sdk/bin/flutter test test/features/settings/settings_page_test.dart
```

Expected: FAIL，报 `Target of URI doesn't exist`。

- [ ] **Step 3: 写数据层与 provider**

创建 `lib/data/export/backup_store.dart`：

```dart
import 'package:sqflite/sqflite.dart';

import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';
import '../db/ride_dao.dart';
import '../db/track_point_dao.dart';
import 'backup.dart';

/// 备份数据的读写。抽成接口是为了让设置页的 widget 测试不必碰真实数据库。
abstract class BackupStore {
  /// 全部已完成的骑行。
  Future<List<Ride>> listRides();

  /// 全部轨迹点。
  Future<List<TrackPoint>> listPoints();

  /// 把备份写回数据库。
  Future<void> apply(BackupPayload payload, {required bool replaceExisting});
}

/// 生产实现：直接读写本地 SQLite。
class SqliteBackupStore implements BackupStore {
  SqliteBackupStore(this._db);

  final Database _db;

  @override
  Future<List<Ride>> listRides() => RideDao(_db).listFinished();

  @override
  Future<List<TrackPoint>> listPoints() => TrackPointDao(_db).listAll();

  @override
  Future<void> apply(
    BackupPayload payload, {
    required bool replaceExisting,
  }) =>
      applyBackup(payload, db: _db, replaceExisting: replaceExisting);
}
```

创建 `lib/data/export/backup_io.dart`：

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 备份文件的读写。抽成接口是为了让设置页的 widget 测试不必碰文件系统，
/// 也避免测试里去弹真实的系统分享面板与文件选择器。
abstract class BackupIo {
  /// 把归档交给系统分享面板。失败时抛异常，由调用方提示用户。
  Future<void> exportArchive(Uint8List bytes, {required String fileName});

  /// 让用户选一个归档文件并读出字节。用户取消时返回 null。
  Future<Uint8List?> pickArchive();
}

/// 生产实现：临时目录 + 系统分享 + 系统文件选择器。
class FileBackupIo implements BackupIo {
  const FileBackupIo();

  @override
  Future<void> exportArchive(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final Directory dir = await getTemporaryDirectory();
    final File file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'application/zip')],
        subject: fileName,
        text: '骑行记录备份',
      ),
    );
  }

  @override
  Future<Uint8List?> pickArchive() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final PlatformFile picked = result.files.first;
    final Uint8List? bytes = picked.bytes;
    if (bytes != null) return bytes;
    // 某些平台上 withData 拿不到内容，退回按路径读。
    final String? path = picked.path;
    if (path == null) return null;
    return File(path).readAsBytes();
  }
}
```

在 `lib/app/providers.dart` 里补（并 import `../data/export/backup_io.dart` 与 `../data/export/backup_store.dart`）：

```dart
/// 备份数据的读写。设置页用；抽成 provider 是为了让 widget 测试注入假实现。
final Provider<BackupStore> backupStoreProvider = Provider<BackupStore>(
  (Ref ref) => SqliteBackupStore(ref.watch(databaseProvider)),
);

/// 备份文件的读写（系统分享 / 文件选择器）。
final Provider<BackupIo> backupIoProvider =
    Provider<BackupIo>((Ref ref) => const FileBackupIo());
```

- [ ] **Step 4: 写设置页实现**

创建 `lib/features/settings/backup_section.dart`：

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/export/backup.dart';
import '../../data/export/backup_io.dart';
import '../../data/export/backup_store.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';

/// 备份与恢复区块。见设计文档 10.5 与 12。
class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('备份与恢复', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _export,
                child: const Text('导出备份'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _restore,
                child: const Text('恢复备份'),
              ),
            ),
          ],
        ),
        if (_message != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _message!,
            style: TextStyle(
              fontSize: 13,
              color: _isError ? Theme.of(context).colorScheme.error : null,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final BackupStore store = ref.read(backupStoreProvider);
      final List<Ride> rides = await store.listRides();
      final List<TrackPoint> points = await store.listPoints();
      final Uint8List bytes = buildBackupArchive(
        rides: rides,
        points: points,
        exportedAtMs: ref.read(nowProvider)(),
      );
      await ref.read(backupIoProvider).exportArchive(
            bytes,
            fileName: 'cycling_backup_${DateTime.now().millisecondsSinceEpoch}.zip',
          );
      _setMessage('已导出 ${rides.length} 条记录', isError: false);
    } catch (error) {
      _setMessage('导出失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final Uint8List? bytes = await ref.read(backupIoProvider).pickArchive();
      if (bytes == null) return; // 用户取消，什么都不做

      // 先解析再确认：版本不匹配时直接说明原因，不要先弹一个会被推翻的确认框。
      final BackupPayload payload = parseBackupArchive(bytes);

      if (!mounted) return;
      final bool ok = await _confirm(payload) ?? false;
      if (!ok) return;

      await ref.read(backupStoreProvider).apply(payload, replaceExisting: true);
      _setMessage(
        '恢复完成：${payload.rides.length} 条记录、${payload.points.length} 个轨迹点',
        isError: false,
      );
    } on BackupVersionException catch (error) {
      _setMessage('$error', isError: true);
    } on BackupFormatException catch (error) {
      _setMessage('$error', isError: true);
    } catch (error) {
      _setMessage('恢复失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(BackupPayload payload) => showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('确认恢复？'),
          content: Text(
            '将清空当前全部记录，替换成备份里的 '
            '${payload.rides.length} 条记录、${payload.points.length} 个轨迹点。'
            '这一步无法撤销。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('恢复'),
            ),
          ],
        ),
      );

  void _setMessage(String message, {required bool isError}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _isError = isError;
    });
  }
}
```

创建 `lib/features/settings/settings_page.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/ble/sensor_monitor.dart';
import '../../data/sensor_pairing.dart';
import '../../data/settings_repository.dart';
import 'backup_section.dart';

/// 设置页。见设计文档 10.5。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _maxHr;
  late final TextEditingController _weight;
  late final TextEditingController _tileUrl;

  DistanceUnit _unit = DistanceUnit.kilometer;
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _maxHr = TextEditingController();
    _weight = TextEditingController();
    _tileUrl = TextEditingController();
  }

  @override
  void dispose() {
    _maxHr.dispose();
    _weight.dispose();
    _tileUrl.dispose();
    super.dispose();
  }

  /// 只在第一次拿到设置时填进输入框，之后不覆盖用户正在输入的内容。
  void _fillOnce(AppSettings settings) {
    if (_loaded) return;
    _loaded = true;
    _maxHr.text = '${settings.maxHeartRate}';
    _weight.text = settings.weightKg.toStringAsFixed(1);
    _tileUrl.text = settings.mapTileUrlTemplate;
    _unit = settings.distanceUnit;
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings? settings = ref.watch(appSettingsProvider).valueOrNull;
    if (settings == null) {
      return const Scaffold(
        appBar: null,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    _fillOnce(settings);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('个人参数', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            controller: _maxHr,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '最大心率（bpm）',
              helperText: '用于心率区间划分，可参考 220 − 年龄',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '体重（kg）',
              helperText: '仅用于估算卡路里，结果仅供参考',
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<DistanceUnit>(
            segments: const <ButtonSegment<DistanceUnit>>[
              ButtonSegment<DistanceUnit>(
                value: DistanceUnit.kilometer,
                label: Text('公里'),
              ),
              ButtonSegment<DistanceUnit>(
                value: DistanceUnit.mile,
                label: Text('英里'),
              ),
            ],
            selected: <DistanceUnit>{_unit},
            onSelectionChanged: (Set<DistanceUnit> selected) =>
                setState(() => _unit = selected.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tileUrl,
            decoration: const InputDecoration(
              labelText: '地图瓦片源',
              helperText: '高德接口失效时可换成 OSM 或自建源，无需重新发版',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('保存')),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const Divider(height: 40),
          const _SensorSection(),
          const Divider(height: 40),
          const BackupSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final int? hr = int.tryParse(_maxHr.text.trim());
    final double? weight = double.tryParse(_weight.text.trim());
    final String tileUrl = _tileUrl.text.trim();

    if (hr == null ||
        hr < kMinPlausibleMaxHeartRate ||
        hr > kMaxPlausibleMaxHeartRate) {
      setState(() => _error =
          '最大心率需要是 $kMinPlausibleMaxHeartRate~$kMaxPlausibleMaxHeartRate 之间的整数');
      return;
    }
    if (weight == null || weight <= 0) {
      setState(() => _error = '体重需要是大于 0 的数字');
      return;
    }
    if (tileUrl.isEmpty) {
      setState(() => _error = '地图瓦片源不能为空');
      return;
    }

    setState(() => _error = null);
    await ref.read(settingsRepositoryProvider).save(AppSettings(
          maxHeartRate: hr,
          weightKg: weight,
          distanceUnit: _unit,
          mapTileUrlTemplate: tileUrl,
        ));
    ref.invalidate(appSettingsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('设置已保存')),
    );
  }
}

/// 传感器配对管理。见设计文档 10.5。
class _SensorSection extends ConsumerStatefulWidget {
  const _SensorSection();

  @override
  ConsumerState<_SensorSection> createState() => _SensorSectionState();
}

class _SensorSectionState extends ConsumerState<_SensorSection> {
  Map<SensorKind, PairedSensor?> _paired = <SensorKind, PairedSensor?>{};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final SensorPairingRepository repo = ref.read(sensorPairingProvider);
    final Map<SensorKind, PairedSensor?> result = <SensorKind, PairedSensor?>{};
    for (final SensorKind kind in SensorKind.values) {
      result[kind] = await repo.load(kind);
    }
    if (!mounted) return;
    setState(() {
      _paired = result;
      _loaded = true;
    });
  }

  Future<void> _clear(SensorKind kind) async {
    await ref.read(sensorPairingProvider).clear(kind);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('传感器配对', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
          '连接成功后会自动记住设备，下次开始记录时自动重连。',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
        const SizedBox(height: 12),
        if (!_loaded)
          const SizedBox(height: 24, child: CircularProgressIndicator(strokeWidth: 2))
        else ...<Widget>[
          _row('心率', SensorKind.heartRate),
          const SizedBox(height: 8),
          _row('踏频', SensorKind.cadence),
        ],
      ],
    );
  }

  Widget _row(String label, SensorKind kind) {
    final PairedSensor? paired = _paired[kind];
    return Row(
      children: <Widget>[
        SizedBox(width: 56, child: Text(label)),
        Expanded(
          child: Text(
            paired == null ? '未配对' : '${paired.name.isEmpty ? paired.id : paired.name}',
            style: TextStyle(
              fontSize: 13,
              color: paired == null ? Colors.white54 : kAppAccent,
            ),
          ),
        ),
        if (paired != null)
          TextButton(onPressed: () => _clear(kind), child: const Text('解除')),
      ],
    );
  }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
.fvm/flutter_sdk/bin/flutter test test/features/settings/settings_page_test.dart
```

Expected: `All tests passed!`（12 个测试）

- [ ] **Step 6: 变异自证**

| 变异点 | 应被杀死 |
| --- | --- |
| `_restore` 里先弹确认框再解析 | 归档版本不匹配时说明原因，且不写库 |
| `_restore` 里 `bytes == null` 时不 return | 用户取消选文件时不弹确认框也不写库 |
| `_confirm` 的 `?? false` 改成 `?? true` | 确认框里取消则不写库 |
| `apply(..., replaceExisting: true)` 改成 `false` | 确认后按替换语义写回备份 |
| `_save` 去掉最大心率范围校验 | 越界的最大心率不保存，给出提示 |
| `_SensorSection._clear` 不调 `_reload` | 点解除后清掉配对并刷新界面 |
| `_export` 不捕获异常 | 导出失败时显示提示而不是崩溃 |

- [ ] **Step 7: 静态检查与提交**

```bash
.fvm/flutter_sdk/bin/flutter analyze lib test
```

Expected: `No issues found!`

```bash
git add lib/data/export lib/app/providers.dart lib/features/settings test/features/settings
git commit -m "feat: 添加设置页与备份恢复"
```

---

## Task 13: 接线与收尾

把历史 / 统计 / 设置三个 tab 换成真实页面，删掉 Plan A 遗留的临时诊断页，跑全量测试。

**Files:**
- Modify: `lib/app/home_shell.dart`
- Modify: `test/app/home_shell_test.dart`
- Delete: `lib/features/settings/ble_probe_page.dart`

- [ ] **Step 1: 改 home_shell**

把 `lib/app/home_shell.dart` 的 `IndexedStack.children` 换成：

```dart
          children: const <Widget>[
            RecordPage(),
            HistoryPage(),
            StatsPage(),
            SettingsPage(),
          ],
```

补 import：

```dart
import '../features/history/history_page.dart';
import '../features/settings/settings_page.dart';
import '../features/stats/stats_page.dart';
```

`PlaceholderPage` **保留**：它仍然是 Task 19 引入的真实组件，Plan B 之后可能还有别的占位需求。若 `analyze` 报它未被使用，说明确实没有任何引用了，那就删掉它以及 `test/app/home_shell_test.dart` 里对它的断言，并在报告里写明。

- [ ] **Step 2: 删掉 Plan A 遗留的临时诊断页**

`lib/features/settings/ble_probe_page.dart` 是 Plan A Task 3 用来验证 Fit 3 心率广播的临时页面，现在已无任何引用（用 `grep -rn "ble_probe\|BleProbePage" lib test` 确认一次）。

```bash
git rm lib/features/settings/ble_probe_page.dart
```

若 grep 发现仍有引用，**先报告再决定**，不要直接删。

- [ ] **Step 3: 更新 home_shell 测试**

`test/app/home_shell_test.dart` 现在会构建三个真实页面，它们都要读数据库。按已有的模式处理：给测试的 `ProviderScope` 补上必要的 override（至少 `historyRidesProvider` / `finishedRidesProvider` / `appSettingsProvider` 与 `databaseProvider`），

**不要削弱它已有的断言**：

- tab 标签顺序 `['记录','历史','统计','设置']`
- `IndexedStack.index == NavigationBar.selectedIndex`
- 同一时刻只渲染当前 tab 的内容

- [ ] **Step 4: 跑全量测试**

```bash
.fvm/flutter_sdk/bin/flutter test
```

Expected: `All tests passed!`。
**基线是 Plan A 结束时的 254 个测试**；Plan B 新增的用例会让总数显著上升。报告实测总数。

- [ ] **Step 5: 静态检查**

```bash
.fvm/flutter_sdk/bin/flutter analyze lib test
```

Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add -A
git commit -m "feat: 接入历史、统计与设置页，移除临时 BLE 诊断页"
```

- [ ] **Step 7: 真机验证（需要你在真机上操作）**

自动化测试覆盖不到的三项（设计文档 13）：**真实 BLE 硬件、真实 GPS、地图渲染**。Plan A 的 Task 22 也还没做（当时没有真机）。请在真机上依次确认：

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 打开 App，切到「历史」 | 空态显示「还没有骑行记录」 |
| 2 | 记一次骑行并结束，回到「历史」 | 出现一张卡片，带迷你速度曲线；点进去看到地图轨迹、汇总网格、三条曲线、心率区间条 |
| 3 | 看详情页地图 | **轨迹贴合道路，不偏移**（这是 GCJ-02 转换是否生效的关键判据；偏移数百米说明转换没接上） |
| 4 | 进隧道或到桥下骑一段 | 地图上轨迹在断点处断开，不画假直线 |
| 5 | 点「导出 GPX」，用第三方 App 打开 | 轨迹、时间、心率都在；**位置与地图一致**（说明 GPX 用的是 WGS-84 而地图用的是 GCJ-02，两者各自正确） |
| 6 | 切到「统计」，切周/月/年 | 累计值随范围变化；趋势折线有数据；个人最佳不随范围变化 |
| 7 | 进「设置」，改最大心率与体重后保存 | 详情页的心率区间分布随新的最大心率变化 |
| 8 | 「设置」→ 连接一次心率传感器 → 返回 | 配对区显示设备名；下次开始记录时自动连上（记录页心率变亮） |
| 9 | 「设置」→ 导出备份 → 恢复备份 | 导出能调起分享；恢复前弹确认框，恢复后记录与之前一致 |
| 10 | 把地图瓦片源改成 OSM（`https://tile.openstreetmap.org/{z}/{x}/{y}.png`） | 地图能正常显示（验证设计文档 9.1 的对冲措施真的有效） |

把第 3、4、5 项的实测结论写进设计文档第 9 节，第 10 项写进第 9.1 节。

---

## 自审记录

写完后按 writing-plans 的要求做了一遍检查，结论如下。

### 规格覆盖

| 设计文档章节 | 落在哪个任务 |
| --- | --- |
| 9.1 地图实现路径（flutter_map + 高德瓦片、瓦片源可配置） | Task 10（`RouteMap` + `AppSettings.mapTileUrlTemplate`） |
| 9.2 轨迹着色 | Task 1（坐标转换）+ Task 10（`buildRouteSegments` 复用 `speedColorArgb`） |
| 9.3 GPS 断点 | Task 10（`_connectable`）+ Task 2（曲线断点）+ Task 6（GPX 分段） |
| 10.2 历史页 | Task 9 |
| 10.3 详情页 | Task 8（②③④⑤）+ Task 10（①⑥） |
| 10.4 统计页 | Task 3（聚合与个人最佳）+ Task 11（页面） |
| 10.5 设置页 | Task 12（全部五项）+ Task 5（传感器配对） |
| 12 单次导出 GPX | Task 6（生成）+ Task 10（入口） |
| 12 全量备份与恢复 | Task 7（打包与解析）+ Task 12（UI 与确认流程） |
| 8.2 心率区间（详情页展示） | Task 8（`HrZoneBar`，复用 Plan A 的 `hrZoneBreakdown`） |
| 11.2 备份恢复版本不匹配 | Task 7（`BackupVersionException`）+ Task 12（界面提示原因） |
| 13 测试策略 | 每个任务的失败测试 + 变异自证；地图/图表渲染与真实 BLE/GPS 由 Task 13 第 7 步手动验证 |
| Plan A 遗留缺口 1（坐标系偏移） | Task 1 + Task 10 |
| Plan A 遗留缺口 2（地图上的 GPS 跳变断线） | Task 10（`_connectable` 的跳变判定） |
| Plan A 遗留缺口 3（传感器配对持久化） | Task 5 |

未覆盖的部分仍不在范围（设计文档 2 的「明确不做」）：账号、云同步、社交、导航、功率计、Apple Health / 华为运动健康集成、多语言。

### 占位符扫描

全文没有 TBD / TODO / 「稍后实现」。每个代码步骤都给了可直接粘贴的完整代码与确切路径。
唯一标注「不写自动化测试」的是 `GpxExporter.exportAndShare` 与 `RouteMap` 的渲染——这两处是纯 IO 与纯渲染，
设计文档 13 已明确列为手动验证项，且它们依赖的纯函数（`buildGpx`、`buildRouteSegments`）都有测试。

### 类型一致性

逐个核对了跨任务引用的名字：

- `CurveMetric` / `CurveSample` / `buildCurve`（Task 2）↔ Task 8 的 `CurveChart`、Task 9 的 `MiniSpeedCurve`
- `TrendRange` / `TrendBucket` / `TrendSummary` / `PersonalBest(s)` / `buildTrend` / `personalBests`（Task 3）↔ Task 11 的 `StatsPage`、`TrendChart`、`PersonalBestsCard`、`stats_providers`
- `PairedSensor` / `SensorPairingRepository`（Task 5）↔ Task 12 的 `_SensorSection`
- `BlePlatform.deviceById`（Task 5）↔ `RecordController._autoConnectPairedSensors`
- `kBackupSchemaVersion` / `BackupManifest` / `BackupPayload` / `BackupFormatException` / `BackupVersionException` / `buildBackupArchive` / `parseBackupArchive` / `applyBackup`（Task 7）↔ Task 12 的 `BackupStore`、`BackupSection`
- `kGpxNamespace` / `kGpxTpxNamespace` / `kGpxCreator` / `buildGpx`（Task 6）↔ Task 10 的 `GpxExporter`
- `RouteVertex` / `RouteSegment` / `buildRouteSegments`（Task 10）↔ `RouteMap`
- `RideDetail` / `rideDetailProvider`（Task 8）↔ Task 9 的 `HistoryPage`（跳转）与 `detail_page_test`
- `ridePointsProvider`（Task 9）↔ `RideCard._MiniCurve`
- `formatDateTime`（Task 8 补进 `format.dart`）↔ Task 9 的 `RideCard`、Task 8 的 `DetailPage`
- `RideDao.listFinishedBetween` / `countFinished` / `insertWithId` / `deleteAll`、`TrackPointDao.listAll` / `deleteAll`、`SettingsDao.remove`（Task 4）↔ Task 5、Task 7
- `DatabaseExecutor` 放宽（Task 7）↔ `applyBackup` 的 `db.transaction`
- `blePlatformProvider` / `sensorPairingProvider` / `backupStoreProvider` / `backupIoProvider`（Task 5、12）↔ 各自的测试 override

### 执行方式

与 Plan A 一致，二选一：

1. **Subagent-Driven（推荐）**：每个任务派一个全新的 subagent 执行，任务之间我来审查。
2. **Inline Execution**：在当前会话里按批次执行，到检查点停下来给你确认。

两种方式都要用 `.fvm/flutter_sdk/bin/flutter`（本机没有全局 flutter/dart），且每个任务结束都要单独提交。

---

## 实施偏差记录（Task 1–13 完成后回写）

Plan B 已全部实施完毕（分支 `feature/plan-b`，13 个任务提交）。
全量 **432 个测试通过**，`flutter analyze lib test` 输出 `No issues found!`。

本节把实施中发现的偏差回写进来。实施时**没有默认计划书是对的**——下面第一类的偏差如果照抄，会直接编译失败、断言必红或测试挂死。

### 一、计划书代码/断言不可行（照抄会编译失败或断言必红）

| # | 任务 | 计划书原文 | 实际做法 | 证据 |
| --- | --- | --- | --- | --- |
| 1 | T1 | 把 `library;` 放在 `import` 之后 | `library;` 必须在**所有其他指令之前** | `dart analyze` 报 `library_directive_not_first` |
| 2 | T2 | — | 无实现偏差；但见第二类第 1、2 条（两个变异点原用例杀不死） | — |
| 3 | T6 | 测试辅助 `named(XmlDocument doc, String local)` | 参数类型改为 **`XmlNode`** | 有调用 `named(segs[0], 'trkpt')`，而 `segs[0]` 是 `XmlElement`，编译报 `The argument type 'XmlElement' can't be assigned to the parameter type 'XmlDocument'` |
| 4 | T6 | 断言 `pt(1758384000000)` 的时间是 `'2025-09-21T00:00:00.000Z'` | 改为 **`'2025-09-20T16:00:00.000Z'`** | `1758384000000ms` 对应的 UTC 是 `2025-09-20T16:00:00Z`。计划书把**本地时间**（UTC+8 的 09-21 00:00）当成了 UTC |
| 5 | T6 | `current!.add(p)` | 改为 `current.add(p)` | Dart 3 流分析已能证明非空，`!` 触发 `unnecessary_non_null_assertion`，`analyze` 不通过 |
| 6 | T7 | 「恢复失败时不留半份数据（事务）」用 `throwsA(anything)` | 收紧为断言 `DatabaseException` 且 message `contains('FOREIGN KEY')`，并把旧数据改成 `insertWithId(id: 100)` | **原用例是因为错误的原因通过的**：旧数据自增拿到 `id = 1`，与备份里 `_finished.id == 1` 撞主键（1555），根本走不到外键。实测外键本身有效（`PRAGMA foreign_keys => 1`；孤儿点插入抛 787） |
| 7 | T7 | 「replaceExisting 为假时保留已有数据」 | 旧数据改用 `insertWithId(id: 100)` | 同上，原写法必然撞主键而失败 |
| 8 | T8 | 日期文本用 `color: kAppSurface` | 改为 `Colors.white70` | `kAppSurface = 0xFF1E1E1E` 画在 `kAppBackground = 0xFF121212` 上，对比度约 1.08:1，几乎不可见 |
| 9 | T8 | import 列表含 `constants.dart` 与 `theme.dart` | 两个都删掉 | 修第 8 条后 `theme.dart` 变成未使用；`constants.dart` 本来就未使用。`analyze` 报 `unused_import` |
| 10 | T8 | `summary_grid.dart` 的 import 列表 | 补 `import '../../domain/models/ride_summary.dart';` | 它用了 `RideSummary` 类型，缺 import 编译不过 |
| 11 | T8/10/11/12 | `ref.watch(appSettingsProvider).valueOrNull` | 改为 **`.value`** | **riverpod 3.4.3 的 `AsyncValue` 没有 `valueOrNull`**（编译错误实证；`lib/` 里此前无任何地方用过它） |
| 12 | T8 | `HrZoneBar` 的 `Expanded(flex: (ratio * 1000).round())` | 改为 `math.max(1, (ratio * 1000).round())` | `flex: 0` 不触发断言，但该区间宽度为 **0.0px** 整段消失；占比极小时肉眼看不见 |
| 13 | T8 | `detail_page_test.dart` 的 `find.text(...)` | 新增 `pumpDetail` 把视口调到 1600 高 | 默认 800×600 下 `ListView` 懒构建，后面的区块不会被 build |
| 14 | T9 | 断言 `find.text('25.3 km/h')` | 改为 **`'26.8 km/h'`** | 卡片渲染的是 `movingAvgSpeedMps`（7.44 → 26.784 → `'26.8 km/h'`）。`'25.3 km/h'` 是 `avgSpeedMps` 的值 |
| 15 | T9 | 断言 `find.text('180 m')` | 改为 **`find.text('爬升 180 m')`** | 卡片渲染 `'爬升 ${...} m'`，`find.text` 是精确匹配 |
| 16 | T9 | 「点卡片进入详情页」只断言 `find.text('骑行详情')` | 额外 override `rideDetailProvider(1)` | 否则 `DetailPage` 会读 `databaseProvider`（未 override）→ `ProviderException` |
| 17 | T9 | `wrap` 里 `ridePointsProvider(r.id!)` | 加 `if (r.id != null)` 守卫 | id 为 null 的用例会在建 `ProviderScope` 时就抛 |
| 18 | T9 | 测试里 `ListView.builder` 直接断言 | 新增 `pumpHistory`（视口 `Size(800, 2400)`） | 同第 13 条 |
| 19 | T10 | 「时间不前进时断开」断言 `segs.length == 2` | 改为 **`expect(segs, isEmpty)`** + 补一条 4 点用例 | `_flush` 开头 `if (vertices.length < 2) return;` 会丢弃断开后只剩 1 个顶点的段 |
| 20 | T10 | 「GPS 跳变」断言 `segs.length == 2` / `segs[0].vertices.length == 1` | 改为 `segs.length == 1` / `segs.single.vertices.length == 2` + 补一条用例 | 同上，孤立顶点被 `_flush` 丢弃 |
| 21 | T10 | `_flush` 里 `..add(currentSpeeds.isEmpty ? _speed(prev) : _speed(prev))` | 简化为 `..add(_speed(prev))` | 三元两个分支相同，是笔误 |
| 22 | T10 | 注释称「`DetailPage` 只在有可显示轨迹时才构建 `RouteMap`」 | 按**无条件构建**实现（占位分支在 `RouteMap` 内部） | 计划书注释与它自己的代码片段及两条测试互相矛盾；无条件构建才能让两条测试都成立 |
| 23 | T11 | 断言 `find.text('0 m'), findsOneWidget` | 给 `_Totals` 四格加 `Key('totals-distance'/'totals-duration'/'totals-gain'/'totals-count')`，按 Key 读该格的值 | 距离为 0 时 `'0 m'`，爬升为 0 时也是 `'0 m'` → 实际找到 **2 个** widget，`findsOneWidget` 必失败。且 `findsNWidgets(2)` 仍分不清是哪一格 |
| 24 | T11 | 测试里声明了未使用的 `const RideSummary _summary` | 删掉 | `analyze` 报 `unused_element` |
| 25 | T11 | 测试里 `ListView` 直接断言 | 新增 `pumpStats`（视口 `Size(800, 2400)`） | 同第 13 条 |
| 26 | T12 | **`file_picker` 的 API 完全不符**：`FilePicker.platform.pickFiles(type:, allowedExtensions:, withData: true)` → `FilePickerResult?` → `result.files.first.bytes` | 改为 **`FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['zip'])` → `PlatformFile?` → `picked.readAsBytes()`** | `file_picker 13.1.0` 里 `FilePicker` 是 `abstract final class`，**没有 `.platform`、没有 `withData`**，`pickFiles` 是静态方法且返回 `Future<List<PlatformFile>>`；`PlatformFile` **没有 `bytes`**，只有 `name`/`uri`/`path`/`xFile`/`Future<Uint8List> readAsBytes()` |
| 27 | T12 | 测试里 `ListView` 直接断言 | 新增 `pumpSettings`（视口 `Size(800, 3200)`） | 设置页是最长的 `ListView`，同第 13 条 |
| 28 | T12 | `_confirm` 里 `'${payload.rides.length}'` 这类多余插值 | 去掉多余插值 | `analyze` 报 `unnecessary_string_interpolations` |
| 29 | T12 | `backup_section.dart` import `backup_io.dart` | 删掉 | 未显式引用 `BackupIo` 类型 → `unused_import` |

### 二、计划书测试盲区（已补用例，并做了变异自证）

每个任务都做了变异测试自证（把实现改坏 → 确认至少一个用例变红 → 改回）。
计划书共列了 **50 个变异点，其中 15 个在原用例下杀不死**，逐一补用例后全部杀死：

| # | 任务 | 原用例杀不死的变异 | 补的用例 |
| --- | --- | --- | --- |
| 1 | T2 | `dt <= 0` 改成 `dt < 0` | 「时间相同（dt 为 0）时也递增 segment」——原用例 dt=-500，两种写法都为真 |
| 2 | T2 | 速度曲线去掉滑动平均 | 「速度曲线对尖峰做滑动平均」——原用例断言 `curve[2].y ∈ [1,3]`，而**未平滑的原始值恰好也是 2.0** |
| 3 | T3 | 删掉 `buildTrend` 的 `status != finished` 判断 | 「带 summary 但未结束的骑行不计入」——原两条用例的 ride 都带 `summary: null`，被 summary 判空提前拦截，`status` 过滤从不生效 |
| 4 | T3 | 删掉 `personalBests` 的 `status != finished` 判断 | 同上（同类漏洞） |
| 5 | T4 | `listFinishedBetween` 的 `orderBy ASC` 改成 `DESC` | 「区间内多条时按开始时间正序」——原用例每个区间内最多 1 条，ASC/DESC 结果相同 |
| 6 | T5 | `clear` 只删 id 不删 name | 「clear 同时清掉 id 与名字，不留残值」——**用 `SettingsDao.getAll()` 直接盯存储**。计划书建议的「clear 后 save 新名字」杀不死（save 会同时覆写两个键） |
| 7 | T5 | `_autoConnectPairedSensors` 去掉 `device == null` 判断 | 计划书直接删 `if` 无法编译；改用 `(await deviceById(...))!` 等价表达 |
| 8 | T6 | `hasPosition` 改成 `p.lat != null` | 「只有纬度没有经度时同样跳过」 |
| 9 | T6 | 去掉 `title?.trim()` | 「标题只有空白时视为没有标题，回退到开始日期」 |
| 10 | T7 | 版本校验 `!=` 改成 `>` | 「schema 版本**更低**时同样拒绝」——`>` 会静默接受 v0 归档（`fromJson` 缺字段默认 0），是真风险 |
| 11 | T7 | 「先删骑行再删点」 | **等价变异体**：`ON DELETE CASCADE` 使顺序无关，连整行删掉 `points.deleteAll()` 都全绿。同一事务内中间态不可观测，无法构造杀死它的用例，不加无意义用例 |
| 12 | T8 | `_CurvePainter` 去掉 `a.segment != b.segment` 跳过 | 把分段跳过抽成公开纯函数 **`drawnCurveSegments`**（画笔与测试共用），再断言跨 segment 不画线 |
| 13 | T8 | `speed.length >= 2` 改成 `>= 0` | 「轨迹点为空时一个曲线区块都不渲染」——空样本画不出线也不抛异常，原用例只断言提示文本 |
| 14 | T9 | `_MiniCurve` 去掉 id 判空 | 「没有 id 的记录不查询轨迹点也不崩溃」——原「没有汇总指标」用例的 id=1，杀不死 |
| 15 | T9 | 迷你曲线不再跳过跨段 | 抽出 **`drawnMiniCurveSegments`** 后断言跨 segment 不连线 |
| 16 | T10 | `dt > kGpsGapMs` 改成 `*100` | 「缺速度时长间隔超过 kGpsGapMs 也断开」——带速度时 `isTrustedSegment` 里又查一遍间隔，把 `_connectable` 自己的判定掩盖了 |
| 17 | T10 | 去掉 `_connectable` 的 `dt <= 0` | 「时间倒流处断开，前后各成一段」（4 个**无速度**的点）——同理，带速度时 `isTrustedSegment` 会兜住 |
| 18 | T11 | `TrendChart` 的 `maxX` 写死 0 | 断言 `data.maxX == 6`（7 桶 → 0..6）。**计划书建议的 `lineBarsData.single.spots.length == buckets.length` 杀不死它**——`spots` 在构造 `LineChartData` 之前就算好了 |
| 19 | T12 | `_confirm` 的 `?? false` 改成 `?? true` | 「点确认框**外面**关掉不写库」——点「取消」走 `pop(false)`，`false ?? true` 仍是 `false`；只有遮罩关闭才返回 null |
| 20 | T12 | `bytes == null` 时不 return | 用 `backupSectionTexts()` 钉死备份区**全部**文本——原 3 条断言全过（空字节进 `parseBackupArchive` 抛 `BackupFormatException`，被专用 catch 接住，提示文本不含「失败」） |
| 21 | T12 | `_export` 漏掉 `points` / 漏掉 `rides`（新增变异） | 「导出的归档包含轨迹点」/「点导出备份会把归档交给 IO 层」 |

另有若干**区分力不足但未被计划书列出**的用例，也一并补强：T9 的「没有标题时用日期当标题」原本与「卡片显示日期…」断言重复（区分力为零），拆成「无标题只一行日期 / 有标题标题与日期各一行」两条；T11 的「切到年/月」补了切换**前**的前置断言，「个人最佳四项」补了四项标签+值断言（原名声称四项却只断言一项）；T13 补了「切三个 tab 各自渲染对应页面」。

### 三、计划书里的测试数量期望已过时（一律以实测为准）

| 位置 | 计划书写 | 实测 |
| --- | --- | --- |
| T1 Step 4 | 10 个 | 11 个 |
| T2 Step 4 | 14 个 | 12 个（补 2 后 14） |
| T3 Step 4 | 18 个 | 17 个（补 2 后 19） |
| T6 Step 4 | 20 个 | 19 个（补 2 后 21） |
| T7 Step 5 | 14 个 | 15 个 |
| T10 Step 4 | 13 个 | 16 个（补 1 后 17） |
| T11 Step 4 | 8 个 | 8 个（补 2 后 10） |
| T12 Step 5 | 12 个 | 12 个（补 2 后 14） |

### 四、实施中发现的新增约束（后续维护必须知道）

1. **riverpod 3.4.3 的 `AsyncValue` 没有 `valueOrNull`**，只有 `.value`。计划书里 4 处用过它。
2. **widget 测试里 `ListView` 会懒构建**：默认视口 800×600 只构建前一两屏。凡是断言页面下半部分的用例，都要先把 `tester.view.physicalSize` 调高（本计划最终用了 `Size(800, 2400)` / `Size(800, 3200)`）并 `addTearDown(tester.view.reset)`。Task 8/9/11/12 都踩过。
3. **`flutter_map` 的 `FlutterMap` 在 widget 测试里不会挂住**：`flutter_test` 的 `HttpOverrides` 把瓦片请求挡成 400，一张也画不出来，但图层会正常构建，`pumpAndSettle` 不超时。因此可以断言 `find.byType(FlutterMap)` 与 `find.byType(PolylineLayer)`。
4. **`SensorMonitor` 的 FakeAsync 挂死风险在 Task 5 后扩大了**：`RecordController.start()` 现在会 `await _autoConnectPairedSensors().timeout(...)`。在 FakeAsync 下若 `blePlatformProvider` 注入的是**真实** `FlutterBluePlusPlatform`，`connect()` 永不返回，而 `.timeout` 的定时器也是假的（不 pump 不触发）→ **`await start()` 会死锁 10 分钟**。
   因此 `record_controller_test.dart` 的 `makeContainer` 改为**默认注入一个空假平台**；`record_views_test.dart` 也必须补 `sensorPairingProvider` override。**后续任何在 widget 测试里驱动 `start()` 的地方，都必须给 `blePlatformProvider` 注入假实现。**
5. **`RideDao.deleteAll()` 会经 `ON DELETE CASCADE` 连带清空 `track_points`**，所以 `applyBackup` 里「先删点再删骑行」的顺序其实无关紧要（保留为防御性代码）。
6. **`TrackPointDao.listAll()` 的 `orderBy 'ride_id ASC, t_ms ASC'` 是冗余的**：schema 的 `idx_track_points_ride_t(ride_id, t_ms)` 已提供同样顺序，因此「去掉 `t_ms ASC`」是等价变异，无法被任何用例杀死。**若将来删掉那个索引，这条会变成真实缺陷。**
7. **`_trackName`（GPX 的默认名称）依赖本地时区**：它用 `DateTime.fromMillisecondsSinceEpoch`（本地）拼日期，而 `_isoUtc` 用 `isUtc: true`。测试断言 `'骑行 2025-09-21'` 依赖本机 UTC+8，**在 UTC 或 UTC-8 环境会变成 `2025-09-20`（跨时区 flaky）**。未改成宽松断言，仅记录。
8. **`_downsample` 里的 `identical` 去重是死代码**：守卫保证 `samples.length > maxSamples`，索引步长 `last/(maxSamples-1) > 1`，相邻 `round()` 结果必严格递增，该分支不可达。保留原样。
9. **`PlaceholderPage` 已删除**。四个 tab 都接入真实页面后它变成零引用；它是公开类，`unused_element` 只对私有成员生效，所以 `analyze` 不会报错——**但留着就是死代码**。用户决定删掉，已删（`home_shell.dart` 只剩 `HomeShell`）。
10. **`dart format` 的 tall style 重排**：编辑器的保存钩子会用新版 `dart format` 重排被触碰的文件，导致 diff 里混入无关的格式变化（例如 Task 5 改 `ble_platform.dart` 时）。仅格式，无行为变化，但会让 diff 变噪。**不要为此对抗格式化器。**
11. **`FileBackupIo` 没有自动化测试**：测试环境没有文件选择器与分享通道，只保证 `analyze` 通过。`pickArchive` 的真机行为（`readAsBytes()` 在 Android content URI 上是否可用）**未实测**，列入真机验证清单。
12. **`_restore` 的 `on BackupVersionException` 专用 catch 目前未被任何用例区分**：删掉它后通用 catch 仍会输出含「schema 版本」的文案，测试照样通过。不是计划书列出的变异点，未补用例。
13. **`finishedRidesProvider` 与 `historyRidesProvider` 查询完全相同**（都调 `listFinished()`），是两套独立缓存。若要统一可让后者复用前者，本计划未做（不在范围）。
14. **`trendRangeProvider` 是全局 `StateProvider`**，切页/重建不会重置范围（保持上次选择）。设计上合理，但如果期望「每次进统计页重置为周」，需要另行处理。

### 五、仍未完成的事

1. **Plan A 的 Task 22（端到端真机验证）尚未执行** —— 需要一部带 BLE 与 GPS 的真机。
2. **Plan B 的 Task 13 Step 7（真机验证清单，10 项）尚未执行** —— 同样需要真机。
   其中最关键的判据是：**详情页地图上的轨迹要贴合道路**（验证 GCJ-02 转换真的接上了）、**GPX 导出的位置要与地图一致**（验证「地图用 GCJ-02、GPX 用 WGS-84」两者各自正确）、以及**把瓦片源换成 OSM 后地图仍能显示**（验证设计文档 9.1 的对冲措施有效）。
3. **Fit 3 心率广播的验证**（设计文档第 14 节的两项风险，Plan A 的 Task 3 Step 4–6 与 Task 22 Step 7–8）也依赖真机。

### 六、真机模拟验证发现的缺陷与修复

Plan A Task 22 与 Plan B Task 13 Step 7 已在 OPPO R9s Plus（Android 7.1.1）上用模拟 GPS 执行，
结果与偏差记在设计文档第 14 节。其中**唯一的用户可见功能性缺陷**在此修复：

#### 缺陷：结算保存后历史/统计列表不刷新（已修复）

**现象**：结束骑行保存后切到历史页，列表仍是旧的（只有上一条记录）；杀进程重启后新记录立刻出现。

**根因**：`historyRidesProvider`、`finishedRidesProvider`、`ridePointsProvider`、`rideDetailProvider`
都是一次性取数的 `FutureProvider`，取过一次就缓存住，而**全项目没有任何地方让它们失效**
（全库只有 `settings_page.dart` 对 `appSettingsProvider` 做过 `invalidate`）。

**修复**：在装配层引入集中的失效信号，而不是在每个保存点逐个 `invalidate`——
结束、崩溃结算、改标题、删除、恢复备份都要刷新同一批列表，漏掉任何一处都会重新长出这个缺陷。

| 文件 | 改动 |
| --- | --- |
| `lib/app/providers.dart` | 新增 `RideDataRevision`（`Notifier<int>`）与 `rideDataRevisionProvider`，`markChanged()` 自增版本号；`rideRepositoryProvider` 传入 `onRideDataChanged: () => ...markChanged()` |
| `lib/data/ride_repository.dart` | 新增可选构造参数 `onRideDataChanged`，在 `finishRide` / `settleRide` / `updateTitle` / `deleteRide` 成功后调用 |
| `lib/features/history/history_providers.dart` | 两个 provider 各加 `ref.watch(rideDataRevisionProvider)` |
| `lib/features/stats/stats_providers.dart` | `finishedRidesProvider` 同上 |
| `lib/features/detail/detail_providers.dart` | `rideDetailProvider` 同上 |
| `lib/features/settings/backup_section.dart` | `apply` 之后手动 `markChanged()`（恢复走 `BackupStore`，不经过 `RideRepository`） |

**刻意不通知的路径**：`appendPoints` / `setStatus` 是记录中的追加写，不影响已完成列表；
若也通知，每 2 秒一次落盘都会让历史页与统计页重查一遍库。

**测试**（全量 **436 个测试通过**，`analyze` 无问题）：

- `test/data/ride_repository_test.dart`：新增 2 条——「结束、结算、改标题、删除各通知一次」（断言恰好 4 次）、
  「记录中的追加写不通知」（断言 0 次）。
- `test/app/providers_test.dart`：新增 2 条——「结束骑行后历史与统计列表自动刷新」、
  「删除骑行后历史列表自动刷新」。两条都先用 `container.listen` 把 provider **订阅住**
  （模拟页面一直挂着 watch），否则缓存可能因无人监听被回收，断言会退化成
  「反正每次都会重查」而失去区分力。
- **变异自证**：把两处 `ref.watch(rideDataRevisionProvider)` 去掉后，这两条用例都变红；改回后全绿。

**同时暴露的假仓储问题**：`record_controller_test.dart` 与 `record_views_test.dart` 里的
`_FakeRideRepository implements RideRepository` 因新增字段而编译失败，各补一个
`onRideDataChanged => null` 的 getter。

#### 缺陷：非 GCJ-02 瓦片源下轨迹偏约 310 m（已修复）

**现象**：把瓦片源换成 OSM 后，轨迹相对底图整体偏移（真机实测约 180 物理像素 ≈ 310 m）。

**根因**：`route_segments.dart` 的 `_vertex` **无条件**做 `wgs84ToGcj02`。设计文档 9.1 把「换源」
当作高德接口失效时的对冲措施，但 OSM、Carto 这类源本身就是 WGS-84，再转一次反而偏出去。

**修复**：坐标用哪套跟着瓦片源走。

| 文件 | 改动 |
| --- | --- |
| `lib/domain/analysis/gcj02.dart` | 新增 `isGcj02TileSource(urlTemplate)`：只取主机名判 `autonavi.com` / `amap.com` 及其子域 |
| `lib/domain/analysis/route_segments.dart` | `buildRouteSegments` 新增 `toGcj02`（默认 `true`，与默认瓦片源一致），透传给 `_vertex` |
| `lib/features/detail/detail_page.dart` | `buildRouteSegments(points, toGcj02: isGcj02TileSource(tileUrl))` |

判定**只看域名不看路径**：`https://example.org/autonavi.com` 这种把域名写进路径的地址不是高德源，
按子串判定会误判、轨迹白偏几百米。瓦片模板里的 `{s}`、`{x}` 不是合法 URL 字符，因此不用
`Uri.parse`，手工切出 `scheme://` 与第一个 `/` 之间的部分（并去掉 userinfo 与端口）。

#### 缺陷：统计页 Y 轴刻度重复（已修复）

**现象**：真机上周视图 Y 轴印成 `0 / 1 / 1 / 2 / 2`。

**根因**：`trend_chart.dart` 没给 `SideTitles.interval`，`fl_chart` 自己算出 0.5 的步长，
而标签用 `value.round()` 格式化，`0.5→1`、`1.5→2` 就出现了重复。

**修复**：显式给「好看」的 1/2/5 序列步长，并让轴顶落在步长序列上。

| 文件 | 改动 |
| --- | --- |
| `lib/features/stats/trend_chart.dart` | 新增 `niceAxisInterval(maxY)`（目标最多 4 条刻度）与 `axisLabel(value, interval)`（步长 < 1 时保留一位小数）；`axisMax` 向上补到步长的整数倍 |

补轴顶这一步是**第二次真机验证才发现的**：只加 `interval` 之后轴印成
`0.0 / 0.5 / 1.0 / 1.5 / 1.7`——末尾那个 `1.7` 是 `fl_chart` 在 `maxY` 处补的原始轴顶，
落在步长序列之外，看着仍像刻度算错了。

**测试**（全量 **453 个测试通过**）：

- `test/domain/analysis/gcj02_test.dart`：新增 6 条，含「域名只出现在路径里的第三方地址不算」
  与「`notautonavi.com` 不算」两条边界用例。
- `test/domain/analysis/route_segments_test.dart`：新增 3 条，含「`toGcj02` 两个取值的顶点不同」
  （否则「原样输出」那条在「永远不转换」的实现下也会绿）。
- `test/features/detail/detail_page_test.dart`：新增 2 条，直接读 `PolylineLayer` 收到的坐标，
  分别断言高德源转成 GCJ-02、OSM 源保持 WGS-84。
- `test/features/stats/stats_page_test.dart`：新增 4 条，含「刻度标签不重复」与「轴顶落在步长序列上」。
- **变异自证**：把 `detail_page.dart` 的 `toGcj02` 参数去掉、把 `trend_chart.dart` 的
  `interval: interval` 去掉后，**恰好**上述两条用例变红（`OSM 源：轨迹保持 WGS-84 原样`、
  `Y 轴刻度 刻度标签不重复`），改回即全绿。
- **真机复核**：重装 APK 后统计页 Y 轴印成 `0.0 / 0.5 / 1.0 / 1.5 / 2.0`，重复与越界刻度都消失。

#### 其余 2 项待处理

1. **爬升被异常跳变污染**：首个真实定位点 `altitude_m = 0.0` 跳到 mock 的 500 m 被计成 500 m 爬升。
   距离与速度有 `kMaxPlausibleSpeedMps` 兜底，爬升没有对应的异常值过滤。**未修**。
2. **`android/app/build.gradle.kts` 两处偏离计划**：`compileSdk` 36→37（`permission_handler_android` 13.x 要求）、
   `minSdk` 23→24（被 flutter 默认值改写）。**未处理**；`android/build/` 也未被 gitignore。

> 瓦片源修复**没有做真机端到端复核**：默认高德源这条路径由
> `detail_page_test.dart` 的「高德源：轨迹转成 GCJ-02」覆盖（与修复前行为一致），
> 而 OSM 侧在该环境下无法真机验证——`tile.openstreetmap.org` 被 DNS 污染解析到
> 31.13.112.4、100% 丢包（见第 14 节），底图根本加载不出来。
> 复核时设备上还压着另一个会话的安装弹窗，未去点击。


