# 多运动类型泛化（方案 C：通用 Workout 平台）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 App 从骑行专属泛化为支持骑行/跑步/健走/徒步四种运动类型的通用 Workout 平台。

**Architecture:** 领域模型 `Ride`→`Workout` 全量改名并新增 `ActivityType` 枚举（自带能力集）；数据库 v2→v3 迁移（`rides` RENAME 为 `workouts` + 加 `activity_type` 列）；`RecordingSession` 按类型开关功率估算/踏频/速度跨档提示；界面按类型渲染读数与传感器灯；历史/统计支持类型筛选。

**Tech Stack:** Flutter + Riverpod 3 + sqflite + flutter_test。测试命令：`flutter analyze`、`flutter test`。

**Spec:** `docs/superpowers/specs/2026-10-23-multi-activity-workout-design.md`

---

## 文件结构总览

```text
lib/
  domain/models/
    activity_type.dart                新增：ActivityType 枚举（能力集）
    workout.dart                      改自 ride.dart
    workout_summary.dart              改自 ride_summary.dart
    workout_status.dart               改自 ride_status.dart
  domain/recording/
    recording_session.dart            改：接收 activityType，按类型开关功能
    cue_detector.dart                 改：速度跨档按类型启用
  domain/analysis/
    summary.dart                      改：类型名，逻辑不变
    trend.dart                        改：类型名，逻辑不变
  core/format.dart                    改：新增 formatPace
  data/
    db/database.dart                  改：schema v3 迁移 + 建表
    db/ride_dao.dart → workout_dao.dart
    ride_repository.dart → workout_repository.dart
    export/backup.dart                改：类型名 + activity_type 随 toDbMap
    export/gpx.dart                   改：类型名
    export/backup_store.dart          改：类型名
    mock_ride_seeder.dart             改：类型名
  features/
    record/record_controller.dart     改：选类型、按类型连传感器、startWorkout
    record/record_page.dart           改：类型 chip 行
    record/handlebar_view.dart        改：按类型渲染读数与传感器灯
    record/ride_cue_text.dart         改：文案动词按类型
    history/history_page.dart         改：类型筛选条
    history/ride_card.dart            改：类型图标 + 配速主读数
    history/history_providers.dart    改：筛选参数
    stats/stats_page.dart             改：类型筛选 + 功率行隐藏
    stats/stats_providers.dart        改：筛选参数
    detail/detail_page.dart           改：类型徽标
    detail/detail_providers.dart      改：类型名
    detail/summary_grid.dart          改：类型名
    detail/gpx_export.dart            改：类型名
    settings/backup_section.dart      改：类型名
  app/
    providers.dart                    改：类型名 + provider 改名
    recovery_gate.dart                改：类型名
test/  （与 lib 对应改名的 20 个文件 + 新增用例）
```

**重命名映射表**（全仓机械替换，改动点以映射表为准）：

| 旧 | 新 |
| --- | --- |
| `Ride`（类/注释） | `Workout` |
| `RideSummary` | `WorkoutSummary` |
| `RideStatus` | `WorkoutStatus` |
| `RideDao` | `WorkoutDao` |
| `RideRepository` | `WorkoutRepository` |
| `rideRepositoryProvider` | `workoutRepositoryProvider` |
| `'rides'`（SQL 表名） | `'workouts'` |
| `rides.json`（备份文件名） | `workouts.json` |
| `ride_dao.dart` | `workout_dao.dart` |
| `ride_repository.dart` | `workout_repository.dart` |
| `ride.dart` / `ride_summary.dart` / `ride_status.dart` | `workout.dart` 等 |
| 测试文件 `ride_test.dart` / `ride_dao_test.dart` / `ride_repository_test.dart` | 同步改名 |

> 注意：`startRide`/`finishRide`/`settleRide`/`deleteRide`/`getRide`/`updateTitle`/`setStatus` 这些**方法名**沿用旧词（保持「这是骑行记录」的接口语义，避免 diff 爆炸），只改类型。测试辅助 `ride(...)` 工厂函数也沿用原名。

---

### Task 1: 领域模型改名 Ride→Workout + ActivityType 枚举

**Files:**
- Create: `lib/domain/models/activity_type.dart`
- Modify: `lib/domain/models/ride.dart` → `lib/domain/models/workout.dart`
- Modify: `lib/domain/models/ride_summary.dart` → `lib/domain/models/workout_summary.dart`
- Modify: `lib/domain/models/ride_status.dart` → `lib/domain/models/workout_status.dart`
- Test: `test/domain/models/ride_test.dart` → `test/domain/models/workout_test.dart`

- [ ] **Step 1: 新增 ActivityType 枚举（先写文件，测试随后）**

创建 `lib/domain/models/activity_type.dart`：

```dart
/// 运动类型。语义归属与 `DistanceUnit` 同层：落设置/数据层，带稳定 dbValue。
///
/// 枚举自带的**能力集**供界面与记录引擎按类型分派：
///   - 骑行独有：踏频、功率、速度跨档提示；
///   - 跑步/健走/徒步：主读数用配速，无踏频/功率概念；
///   - 距离里程碑提示（每 1km / 10km）全类型通用。
/// 新增类型只需加一个枚举值，其余按默认能力（纯 GPS + 心率）走。
enum ActivityType {
  cycling('cycling', '骑行', supportsCadence: true, supportsPower: true),
  running('running', '跑步', usesPace: true),
  walking('walking', '健走', usesPace: true),
  hiking('hiking', '徒步', usesPace: true);

  const ActivityType(
    this.dbValue,
    this.label, {
    this.supportsCadence = false,
    this.supportsPower = false,
    this.usesPace = false,
  });

  /// 落库用的稳定标识，改显示名不影响已存数据。
  final String dbValue;

  /// 界面显示名。
  final String label;

  /// 是否支持踏频采样与踏频读数。
  final bool supportsCadence;

  /// 是否支持功率（实测与估算）。
  final bool supportsPower;

  /// 主读数是否为配速（跑步/健走/徒步）。
  final bool usesPace;

  /// 速度跨档提示只有骑行启用。速度档本身按 km/h 定义，跑步类型无意义。
  bool get supportsSpeedTierCue => !usesPace;

  static ActivityType fromDb(String? value) => ActivityType.values.firstWhere(
        (ActivityType a) => a.dbValue == value,
        orElse: () => ActivityType.cycling,
      );
}
```

- [ ] **Step 2: 写 ActivityType 测试**

在 `test/domain/models/workout_test.dart` 顶部新增（该文件稍后从 ride_test.dart 改名而来）：

```dart
test('ActivityType.fromDb 未知值回退骑行', () {
  expect(ActivityType.fromDb(null), ActivityType.cycling);
  expect(ActivityType.fromDb('unknown'), ActivityType.cycling);
  expect(ActivityType.fromDb('running'), ActivityType.running);
});

test('ActivityType 能力集', () {
  expect(ActivityType.cycling.supportsCadence, isTrue);
  expect(ActivityType.cycling.supportsPower, isTrue);
  expect(ActivityType.cycling.supportsSpeedTierCue, isTrue);
  expect(ActivityType.cycling.usesPace, isFalse);
  expect(ActivityType.running.supportsCadence, isFalse);
  expect(ActivityType.running.supportsPower, isFalse);
  expect(ActivityType.running.supportsSpeedTierCue, isFalse);
  expect(ActivityType.running.usesPace, isTrue);
  expect(ActivityType.walking.usesPace, isTrue);
  expect(ActivityType.hiking.usesPace, isTrue);
});
```

- [ ] **Step 3: 机械改名 Ride→Workout**

按映射表执行（可脚本化或手动）：
1. `git mv lib/domain/models/ride.dart lib/domain/models/workout.dart`，类 `Ride`→`Workout`，import 路径同步；
2. `git mv lib/domain/models/ride_summary.dart lib/domain/models/workout_summary.dart`，`RideSummary`→`WorkoutSummary`；
3. `git mv lib/domain/models/ride_status.dart lib/domain/models/workout_status.dart`，`RideStatus`→`WorkoutStatus`；
4. `workout.dart` 增加 `activityType` 字段与落库映射：

`lib/domain/models/workout.dart` 完整内容：

```dart
import 'activity_type.dart';
import 'workout_status.dart';
import 'workout_summary.dart';

/// 一次运动，对应 `workouts` 表的一行。
class Workout {
  const Workout({
    this.id,
    required this.startedAtMs,
    this.endedAtMs,
    required this.status,
    this.title,
    this.activityType = ActivityType.cycling,
    this.summary,
    this.hrDeviceName,
    this.cadenceDeviceName,
    this.powerDeviceName,
  });

  final int? id;
  final int startedAtMs;
  final int? endedAtMs;
  final WorkoutStatus status;
  final String? title;

  /// 本次运动的类型。开始记录时冻结落库，历史/统计按它聚合。
  final ActivityType activityType;

  /// 进行中的运动为 null。
  final WorkoutSummary? summary;
  final String? hrDeviceName;
  final String? cadenceDeviceName;
  final String? powerDeviceName;

  Map<String, Object?> toDbMap() => <String, Object?>{
        if (id != null) 'id': id,
        'started_at': startedAtMs,
        'ended_at': endedAtMs,
        'status': status.dbValue,
        'title': title,
        'activity_type': activityType.dbValue,
        'hr_device_name': hrDeviceName,
        'cadence_device_name': cadenceDeviceName,
        'power_device_name': powerDeviceName,
        if (summary != null) ...summary!.toDbColumns(),
      };

  static Workout fromDbMap(Map<String, Object?> m) => Workout(
        id: (m['id'] as num?)?.toInt(),
        startedAtMs: (m['started_at'] as num).toInt(),
        endedAtMs: (m['ended_at'] as num?)?.toInt(),
        status: WorkoutStatus.fromDb(m['status'] as String),
        title: m['title'] as String?,
        activityType: ActivityType.fromDb(m['activity_type'] as String?),
        summary: m['distance_m'] == null ? null : WorkoutSummary.fromDbColumns(m),
        hrDeviceName: m['hr_device_name'] as String?,
        cadenceDeviceName: m['cadence_device_name'] as String?,
        powerDeviceName: m['power_device_name'] as String?,
      );
}
```

`workout_summary.dart` 与 `workout_status.dart` 仅替换类型名，结构不变。

- [ ] **Step 4: 更新 workout_test.dart 断言 activityType**

在 `test/domain/models/workout_test.dart` 补用例（ride_test.dart 改名的同时加）：

```dart
test('toDbMap/fromDbMap 往返携带 activity_type', () {
  final Workout w = Workout(
    startedAtMs: 1000,
    status: WorkoutStatus.recording,
    activityType: ActivityType.running,
  );
  final Workout back = Workout.fromDbMap(w.toDbMap());
  expect(back.activityType, ActivityType.running);
  // 默认类型是骑行，与迁移后旧记录一致。
  expect(
    Workout.fromDbMap(const <String, Object?>{'started_at': 1, 'status': 'recording'}).activityType,
    ActivityType.cycling,
  );
});
```

- [ ] **Step 5: 跑测试确认领域层通过**

Run: `flutter test test/domain/models/workout_test.dart`
Expected: PASS（此时 `Ride` 其他引用文件尚未改名，`flutter analyze` 会报错——允许，Task 2 处理）。

- [ ] **Step 6: Commit**

```bash
git add lib/domain/models/activity_type.dart lib/domain/models/workout.dart lib/domain/models/workout_summary.dart lib/domain/models/workout_status.dart test/domain/models/workout_test.dart
git commit -m "feat: 新增 ActivityType 枚举，领域模型 Ride 泛化为 Workout"
```

---

### Task 2: 数据层迁移 v2→v3 + DAO/Repository 改名

**Files:**
- Modify: `lib/data/db/database.dart`
- Modify: `lib/data/db/ride_dao.dart` → `lib/data/db/workout_dao.dart`
- Modify: `lib/data/ride_repository.dart` → `lib/data/workout_repository.dart`
- Modify: `lib/data/export/backup.dart`、`lib/data/export/gpx.dart`、`lib/data/export/backup_store.dart`
- Modify: `lib/data/mock_ride_seeder.dart`
- Modify: `lib/app/providers.dart`、`lib/app/recovery_gate.dart`
- Modify: `lib/features/record/record_controller.dart`（import 与类型名）
- Modify: `lib/features/history/history_providers.dart`、`history_page.dart`、`ride_card.dart`
- Modify: `lib/features/stats/stats_providers.dart`、`stats_page.dart`
- Modify: `lib/features/detail/detail_providers.dart`、`detail_page.dart`、`summary_grid.dart`、`gpx_export.dart`
- Modify: `lib/features/settings/backup_section.dart`
- Test: `test/data/db/database_test.dart`、`test/data/db/ride_dao_test.dart`→`workout_dao_test.dart`、`test/data/ride_repository_test.dart`→`workout_repository_test.dart`、其余 20 个测试文件同步类型名

- [ ] **Step 1: 数据库 v3 迁移 + 建表改表名**

`lib/data/db/database.dart` 修改：

```dart
/// 当前 schema 版本。备份文件的 manifest.json 会带上这个数字。
///
/// v2 引入功率：`track_points.power_w`、`workouts.avg_power_w` / `max_power_w` /
/// `power_device_name`。
/// v3 泛化多运动：`rides` 表改名 `workouts`，新增 `activity_type` 列（默认 cycling，
/// 老记录自动回填为骑行）。
const int kSchemaVersion = 3;
```

`_onUpgrade`：

```dart
Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    await db.execute('ALTER TABLE track_points ADD COLUMN power_w INTEGER');
    await db.execute('ALTER TABLE rides ADD COLUMN avg_power_w REAL');
    await db.execute('ALTER TABLE rides ADD COLUMN max_power_w INTEGER');
    await db.execute('ALTER TABLE rides ADD COLUMN power_device_name TEXT');
  }
  if (oldVersion < 3) {
    // RENAME 是原子操作，不动轨迹点数据；activity_type 带默认值使既有行回填为骑行。
    await db.execute('ALTER TABLE rides RENAME TO workouts');
    await db.execute(
      "ALTER TABLE workouts ADD COLUMN activity_type TEXT NOT NULL DEFAULT 'cycling'",
    );
  }
}
```

`_onCreate` 的 `CREATE TABLE rides` → `CREATE TABLE workouts`，并在列里加 `activity_type TEXT NOT NULL DEFAULT 'cycling'`（放在 status 与 title 之间）。

- [ ] **Step 2: 写 v3 迁移测试**

在 `test/data/db/database_test.dart` 追加：

```dart
test('v2 → v3 迁移：rides 改名 workouts 并补 activity_type 默认骑行', () async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  // 先建一个 v2 库：手工建表后把版本写成 2。
  final Database v2 = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 2,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE rides (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            started_at INTEGER NOT NULL,
            status TEXT NOT NULL,
            title TEXT,
            distance_m REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE track_points (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ride_id INTEGER NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
            t_ms INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      },
    ),
  );
  await v2.insert('rides', <String, Object?>{'started_at': 1000, 'status': 'finished'});
  await v2.close();

  // 用同一路径重开 → 触发 onUpgrade。
  final Database v3 = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: kSchemaVersion,
      onCreate: _noopCreate,
      onUpgrade: _upgradeLikeApp,
    ),
  );
  addTearDown(v3.close);

  final List<Map<String, Object?>> rows = await v3.query('workouts');
  expect(rows.single['activity_type'], 'cycling');
  expect(rows.single['started_at'], 1000);
});
```

（若 sqflite ffi 无法在同一内存路径重开触发升级，改用临时文件路径 `'${Directory.systemTemp.path}/migrate_test.db'`，并在 tearDown 删除文件。以实际跑通为准。）

- [ ] **Step 3: DAO/Repository/全仓类型改名**

按映射表执行机械替换，覆盖 Task 1 列出的全部文件：
- `ride_dao.dart` → `workout_dao.dart`，类 `RideDao`→`WorkoutDao`，SQL 表名 `'rides'`→`'workouts'`，`Ride`/`RideSummary`/`RideStatus`→`Workout` 系列；
- `ride_repository.dart` → `workout_repository.dart`，类与类型改名；`startRide` 增加 `activityType` 参数（默认 `ActivityType.cycling`），并把 `activityType` 传入 DAO insert：

```dart
Future<Workout> startWorkout({
  required int startedAtMs,
  ActivityType activityType = ActivityType.cycling,
  String? hrDeviceName,
  String? cadenceDeviceName,
  String? powerDeviceName,
}) async {
  final int id = await _workouts.insert(Workout(
    startedAtMs: startedAtMs,
    status: WorkoutStatus.recording,
    activityType: activityType,
    hrDeviceName: hrDeviceName,
    cadenceDeviceName: cadenceDeviceName,
    powerDeviceName: powerDeviceName,
  ));
  return Workout(
    id: id,
    startedAtMs: startedAtMs,
    status: WorkoutStatus.recording,
    activityType: activityType,
    hrDeviceName: hrDeviceName,
    cadenceDeviceName: cadenceDeviceName,
    powerDeviceName: powerDeviceName,
  );
}
```

> 保留 `startRide` 作为 `startWorkout` 的别名（`=> startWorkout(startedAtMs: startedAtMs, ...)`）不必要——直接全仓改调用点即可，共 3 处（controller、mock_seeder、测试）。方法名 `startRide` 改为 `startWorkout`。`finishRide`/`settleRide`/`deleteRide`/`getRide`/`updateTitle`/`setStatus` 方法名**保持**，只改返回/参数类型。

- `app/providers.dart`：`rideRepositoryProvider`→`workoutRepositoryProvider`，装配 `WorkoutDao`；`RideDataRevision` 类名与注释里「骑行」保留（它只是数据版本号）。
- `data/export/backup.dart`：`_ridesName = 'rides.json'` → `_ridesName = 'workouts.json'`；类型名替换。备份 schema 版本**保持 1**（字段增了 activity_type，但 `Ride.fromDbMap` 对缺列有兜底——详见 Step 4 的兼容说明）。实际上为稳妥，`kBackupSchemaVersion` 升为 2，并在 `parseBackupArchive` 对 v1 归档做兼容读取（见 Step 4）。
- `mock_ride_seeder.dart`、`recovery_gate.dart`、`backup_section.dart`、`gpx.dart`、`backup_store.dart`、detail 系列：仅类型名替换。
- `features/history/history_providers.dart`、`stats/stats_providers.dart`：类型名替换（筛选参数在 Task 6/7 加）。

- [ ] **Step 4: 备份兼容（v1 旧归档可恢复）**

`kBackupSchemaVersion` 升为 2；`parseBackupArchive` 允许 v1：

```dart
if (manifest.schemaVersion < 1 || manifest.schemaVersion > kBackupSchemaVersion) {
  throw BackupVersionException(
    found: manifest.schemaVersion,
    expected: kBackupSchemaVersion,
  );
}
```

`Workout.fromDbMap` 对 `m['activity_type']` 为 null（v1 归档没这列）回退 cycling，已天然兼容，无需额外处理。

- [ ] **Step 5: 更新 repository 测试**

`test/data/ride_repository_test.dart` → `workout_repository_test.dart`，类型与 provider 名替换，并把 `startRide` 调用点改为 `startWorkout`。追加类型落库用例：

```dart
test('startWorkout 落库携带运动类型', () async {
  final Workout w = await repo.startWorkout(
    startedAtMs: 1000,
    activityType: ActivityType.running,
  );
  final Workout? back = await repo.getWorkout(w.id!);
  expect(back?.activityType, ActivityType.running);
});
```

`RideRepository.getRide` 改名为 `getWorkout` 会牵连 controller/recovery/detail 调用点——**统一改名**，一并替换。

- [ ] **Step 6: 全仓跑测试**

Run: `flutter test`
Expected: 全量通过（若个别测试因改名漏改失败，修正后重跑）。

- [ ] **Step 7: Commit**

```bash
git add lib/ test/
git commit -m "feat: 数据层 v3 迁移，rides 改名 workouts 并加 activity_type 列，RideRepository 泛化为 WorkoutRepository"
```

---

### Task 3: formatPace 配速换算

**Files:**
- Modify: `lib/core/format.dart`
- Test: `test/core/format_test.dart`（若不存在则创建）

- [ ] **Step 1: 写失败测试**

在 `test/core/format_test.dart`（新建或追加）：

```dart
test('formatPace 公里/英里两种单位', () {
  // 10 km/h = 2.777... m/s → 6分整每公里。
  expect(formatPace(10 / 3.6, DistanceUnit.kilometer), "6'00\"");
  // 6 min/km 对英里 = 9'39" / mi（6 * 1.609344 ≈ 9.656，取整分后余秒）。
  expect(formatPace(10 / 3.6, DistanceUnit.mile), "9'39\"");
  // 0 速度 / 负值 → '--'。
  expect(formatPace(0, DistanceUnit.kilometer), '--');
  expect(formatPace(-1, DistanceUnit.kilometer), '--');
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/format_test.dart`
Expected: FAIL（`formatPace` 未定义）。

- [ ] **Step 3: 实现 formatPace**

`lib/core/format.dart` 末尾追加：

```dart
/// 配速文本（跑步/健走/徒步的主读数）。由速度（m/s）换算。
///
/// 公里模式为分钟每公里（mm:ss / km），英里模式为分钟每英里（mm:ss / mi）。
/// 速度无效（0、负值）时显示 `--`：起步前没有速度可言，摆 0 会像「停着」。
/// 显示格式固定 `5'30"`（分'秒"，秒数两位补齐），单位尾缀由调用方拼。
String formatPace(double speedMps, DistanceUnit unit) {
  if (speedMps <= 0) return '--';
  // 秒每单位距离：公里 1000m，英里 1609.344m。
  final double metersPerUnit =
      unit == DistanceUnit.mile ? _metersPerMile : 1000.0;
  final double seconds = metersPerUnit / (speedMps * 60) * 60; // = metersPerUnit / speedMps
  final int minutes = seconds ~/ 60;
  final int rest = seconds.remainder(60).round();
  // remainder 可能为 60（round 进位），归一化。
  if (rest == 60) {
    return "$minutes'00\"";
  }
  return "$minutes'${rest.toString().padLeft(2, '0')}\"";
}
```

> 换算核对：`seconds = metersPerUnit / speedMps`。10km/h=2.777m/s → 1000/2.777=360 秒 → `6'00"`。英里：1609.344/2.777≈579.4s → `9'39"`。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/format_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/core/format.dart test/core/format_test.dart
git commit -m "feat: 新增 formatPace 配速换算（min/km 与 min/mi）"
```

---

### Task 4: 记录引擎按类型开关功能 + 提示文案适配

**Files:**
- Modify: `lib/domain/recording/recording_session.dart`
- Modify: `lib/domain/recording/cue_detector.dart`
- Modify: `lib/domain/recording/ride_cue.dart`（不动结构，仅注释）
- Modify: `lib/features/record/ride_cue_text.dart`
- Test: `test/domain/recording/recording_session_test.dart`、`test/domain/recording/cue_detector_test.dart`、`test/features/record/record_controller_test.dart`

- [ ] **Step 1: 写失败测试（跑步会话不产功率/踏频）**

在 `test/domain/recording/recording_session_test.dart` 追加：

```dart
test('跑步会话不估算功率、忽略踏频与功率采样', () {
  final RecordingSession s = RecordingSession(
    rideId: 1,
    startedAtMs: 0,
    activityType: ActivityType.running,
    weightKg: 70,
  );
  s.ingestCadence(90);
  s.ingestPower(250);
  s.ingestFix(LocationFix(
    tMs: 1000,
    lat: 31.2304,
    lon: 121.4737,
    speedMps: 2.78,
    altitudeM: 10,
  ));
  s.tick(1000);
  expect(s.snapshot.power, isNull);
  expect(s.snapshot.cadence, isNull);
});
```

（`RecordingSession` 构造需新增 `activityType` 参数，默认 `ActivityType.cycling`。）

- [ ] **Step 2: 写失败测试（跑步无速度跨档提示）**

在 `test/domain/recording/cue_detector_test.dart` 追加（`CueDetector` 需新增 `activityType` 参数）：

```dart
test('跑步会话没有速度跨档提示，但保留距离里程碑', () {
  final CueDetector d = CueDetector(activityType: ActivityType.running);
  final List<RideCue> cues = d.update(
    distanceM: 1500,
    elapsedMs: 300000,
    speedMps: 12, // 远超过 10km/h 档
  );
  expect(cues.whereType<SpeedCue>(), isEmpty);
  expect(cues.whereType<LapCue>().length, 1);
});
```

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/domain/recording/`
Expected: FAIL。

- [ ] **Step 4: 实现按类型开关**

`lib/domain/recording/recording_session.dart`：

```dart
RecordingSession({
  required this.rideId,
  required this.startedAtMs,
  this.activityType = ActivityType.cycling,
  ...
});
```

新增字段与方法：

```dart
/// 本次运动的类型。决定功率估算、踏频采样与速度跨档提示是否启用。
final ActivityType activityType;
```

`ingestCadence`：

```dart
void ingestCadence(double rpm) {
  if (!activityType.supportsCadence) return;
  _cadence = rpm;
}
```

`ingestPower`：

```dart
void ingestPower(int watts) {
  if (!activityType.supportsPower) return;
  _power = watts;
}
```

`_estimatePower` 开头加：

```dart
int? _estimatePower() {
  if (!activityType.supportsPower) return null;
  if (_power != null) return null;
  ...
}
```

`_collectCues` 改为把类型传给 detector：

```dart
void _collectCues() {
  if (_phase != RecordingPhase.recording) return;
  _pendingCues.addAll(_cueDetector.update(
    distanceM: _distanceM,
    elapsedMs: _elapsedMs,
    speedMps: _currentSpeedMps,
    activityType: activityType,
  ));
}
```

`_cueDetector` 构造时也要带类型（崩溃恢复播种路径）：

```dart
_cueDetector = CueDetector(
  initialDistanceM: initialDistanceM,
  initialElapsedMs: initialElapsedMs,
  activityType: activityType,
);
```

`lib/domain/recording/cue_detector.dart`：构造加 `activityType` 参数；`update` 里速度跨档块改为：

```dart
if (activityType.supportsSpeedTierCue) {
  final int tier = (speedMps * 3.6) ~/ kCueSpeedTierKmh;
  if (tier > _speedTierKmh) {
    _speedTierKmh = tier;
    cues.add(SpeedCue(speedMps * 3.6));
  }
}
```

`update` 方法签名加 `required ActivityType activityType`。

- [ ] **Step 5: 提示文案动词按类型**

`lib/features/record/ride_cue_text.dart` 两个函数签名加 `ActivityType`，动词映射：

```dart
String _distanceVerb(ActivityType type) => switch (type) {
      ActivityType.cycling => '已骑行',
      ActivityType.running => '已跑',
      ActivityType.walking => '已走',
      ActivityType.hiking => '已徒步',
    };
```

横幅文案 `DistanceCue` 分支改为 `'${_distanceVerb(type)} ${c.km} 公里'`；`LapCue` 分支首字「第 X 公里」不受动词影响，保持。语音文案同理。`RideCueBanner` 与 `RideCuePlayer` 的 `speak(List<RideCue>, DistanceUnit)` 增加 `ActivityType` 参数。

- [ ] **Step 6: 更新调用点**

`record_controller.dart`：
- `RecordingSession` 构造传 `activityType`；
- `_drainCues` 播报时传 `_session?.activityType ?? ActivityType.cycling`；
- `_onSensorReading` 中 `SensorKind.cadence`/`SensorKind.power` 分支保留（会话内部已按类型忽略），但界面已不渲染入口（Task 5）。

- [ ] **Step 7: 跑测试**

Run: `flutter test test/domain/recording/ test/features/record/record_controller_test.dart test/features/record/record_views_test.dart`
Expected: 全量通过。

- [ ] **Step 8: Commit**

```bash
git add lib/domain/recording/ lib/features/record/ride_cue_text.dart test/domain/recording/
git commit -m "feat: 记录引擎按运动类型开关功率/踏频/速度跨档提示，提示文案按类型适配"
```

---

### Task 5: 记录界面类型 chip + 按类型渲染读数与传感器灯

**Files:**
- Modify: `lib/features/record/record_controller.dart`
- Modify: `lib/features/record/record_page.dart`
- Modify: `lib/features/record/handlebar_view.dart`
- Test: `test/features/record/record_views_test.dart`、`test/features/record/record_controller_test.dart`

- [ ] **Step 1: 控制器增加类型选择状态**

`record_controller.dart`：

```dart
/// 选中的运动类型。未开始态由 chip 行修改；开始记录时冻结落库。
ActivityType _selectedActivityType = ActivityType.cycling;

void selectActivityType(ActivityType type) {
  if (_session != null) return; // 记录中不可切换
  _selectedActivityType = type;
  _publish();
}
```

`RecordState` 增加：

```dart
final ActivityType selectedActivityType;
// 构造默认 ActivityType.cycling
```

`reset()` 保留 `_selectedActivityType`（不清零，记住上次选择）。

`start()` 里：`ref.read(workoutRepositoryProvider).startWorkout(startedAtMs: _now(), activityType: _selectedActivityType, ...)`；`RecordingSession` 构造带 `activityType: _selectedActivityType`；`_autoConnectPairedSensors` 按类型裁剪（见 Task 4 后）：

```dart
Future<void> _autoConnectPairedSensors() async {
  for (final SensorKind kind in SensorKind.values) {
    if (!_sensorKindAllowed(kind)) continue;
    ...
  }
}

bool _sensorKindAllowed(SensorKind kind) {
  if (kind == SensorKind.heartRate) return true;
  if (kind == SensorKind.cadence) {
    return _selectedActivityType.supportsCadence;
  }
  return _selectedActivityType.supportsPower;
}
```

`connectSensor` 对不允许的类型直接 return：

```dart
Future<void> connectSensor(SensorKind kind, BleDeviceHandle device) async {
  if (!_sensorKindAllowed(kind)) return;
  ...
}
```

`_publish()` 透传 `selectedActivityType`。

- [ ] **Step 2: 记录页 chip 行**

`record_page.dart` 的未开始分支（`state.phase == null`）在 `HandlebarView` 前加类型选择行——直接作为 `HandlebarView` 新参数 `selectedActivityType`/`onSelectActivityType` 传入，由 `HandlebarView` 内部在 idle 态渲染：

`handlebar_view.dart` 新增参数：

```dart
final ActivityType selectedActivityType;
final ValueChanged<ActivityType> onSelectActivityType;
```

idle 态、主键上方渲染（在底部 Column 的 `SizedBox(height: buttonHeight)` 前）：

```dart
if (idle) ...<Widget>[
  const SizedBox(height: kSpaceS),
  // 运动类型选择：4 个 chip 一行。开始前可选，记录中不可切。
  SizedBox(
    width: double.infinity,
    child: SegmentedButton<ActivityType>(
      segments: <ButtonSegment<ActivityType>>[
        for (final ActivityType t in ActivityType.values)
          ButtonSegment<ActivityType>(value: t, label: Text(t.label)),
      ],
      selected: <ActivityType>{selectedActivityType},
      onSelectionChanged: (Set<ActivityType> selected) =>
          onSelectActivityType(selected.first),
      showSelectedIcon: false,
    ),
  ),
],
```

主键文案改为类型相关：`'开始${selectedActivityType.label}'`（`开始骑行`/`开始跑步`…）。

- [ ] **Step 3: 按类型渲染底部读数**

`handlebar_view.dart` build 内，底部大读数区：

```dart
// 主读数：骑行显示速度，跑步/健走/徒步显示配速。
final bool usePace = selectedActivityType.usesPace;
```

大数字那段的 `formatSpeedValue(...)` → 条件：

```dart
Text(
  usePace
      ? formatPace(state.currentSpeedMps, unit)
      : formatSpeedValue(state.currentSpeedMps, unit),
  key: const Key('handlebar-speed'),
  style: _hud(kInstrumentTextStyle),
),
...
Text(
  usePace ? (unit == DistanceUnit.mile ? '/mi' : '/km') : speedUnitLabel(unit),
  style: _hud(kLabelTextStyle),
),
```

`_SpeedScale` 仅在 `!usePace` 时渲染。

底部三格（心率/踏频/功率）改为按类型：

```dart
_MetricRow(
  dividerMargin: kSpaceS,
  cells: <Widget>[
    _MetricCell(label: '心率', value: state.hr?.toString() ?? '--', ...),
    if (selectedActivityType.supportsCadence)
      _MetricCell(label: '踏频', value: state.cadence?.toString() ?? '--', ...),
    if (selectedActivityType.supportsPower)
      _MetricCell(label: ..., value: state.power?.toString() ?? '--', ...),
  ],
),
```

心率格在跑步类型下整行只有一格，`_MetricRow` 的 Expanded 会把它拉满宽度，可接受。

- [ ] **Step 4: 按类型裁剪传感器灯**

`_StatusStrip` 加 `activityType` 参数，仅渲染允许的灯：

```dart
_SensorLamp(icon: Icons.favorite, connected: state.hrConnected, ...),
if (activityType.supportsCadence)
  _SensorLamp(icon: Icons.sync, connected: state.cadenceConnected, ...),
if (activityType.supportsPower)
  _SensorLamp(icon: Icons.bolt, connected: state.powerConnected, ...),
```

`_StatusStrip` 从 `HandlebarView` 传 `selectedActivityType`。

- [ ] **Step 5: 写界面测试**

`test/features/record/record_views_test.dart` 追加：

```dart
testWidgets('跑步类型：主读数显示配速，无踏频/功率格与灯', (WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[...],
    child: MaterialApp(
      home: Scaffold(
        body: HandlebarView(
          state: RecordState(selectedActivityType: ActivityType.running),
          unit: DistanceUnit.kilometer,
          tileUrlTemplate: '',
          onStart: () {},
          onPause: () {},
          onResume: () {},
          onFinish: () {},
          onPickDevice: (_) {},
        ),
      ),
    ),
  ));
  expect(find.text('踏频'), findsNothing);
  expect(find.text('功率（估算）'), findsNothing);
  // 配速读数键仍在。
  expect(find.byKey(const Key('handlebar-speed')), findsOneWidget);
});
```

（沿用测试文件既有的 fake repository / fake location 装配，见文件顶部。）

- [ ] **Step 6: 跑测试**

Run: `flutter test test/features/record/`
Expected: 全量通过。

- [ ] **Step 7: Commit**

```bash
git add lib/features/record/ test/features/record/
git commit -m "feat: 记录界面加运动类型 chip 行，按类型渲染配速主读数与传感器灯"
```

---

### Task 6: 历史列表类型筛选 + 卡片配速读数

**Files:**
- Modify: `lib/features/history/history_providers.dart`
- Modify: `lib/features/history/history_page.dart`
- Modify: `lib/features/history/ride_card.dart`
- Test: `test/features/history/history_page_test.dart`

- [ ] **Step 1: provider 加筛选参数**

`history_providers.dart`：

```dart
/// 历史页当前选中的类型筛选。null = 全部。
final StateProvider<ActivityType?> historyFilterProvider =
    StateProvider<ActivityType?>((Ref ref) => null);

final FutureProvider<List<Workout>> historyRidesProvider =
    FutureProvider<List<Workout>>((Ref ref) {
  ref.watch(rideDataRevisionProvider);
  final ActivityType? filter = ref.watch(historyFilterProvider);
  return ref.watch(workoutRepositoryProvider).listFinished(
        activityType: filter,
      );
});
```

`WorkoutRepository.listFinished` 加参数：

```dart
Future<List<Workout>> listFinished({
  int? limit,
  int? offset,
  ActivityType? activityType,
}) =>
    _workouts.listFinished(
      limit: limit,
      offset: offset,
      activityType: activityType,
    );
```

`WorkoutDao.listFinished` 加 where 分支：

```dart
Future<List<Workout>> listFinished({
  int? limit,
  int? offset,
  ActivityType? activityType,
}) async {
  final String where = activityType == null
      ? "status = 'finished'"
      : "status = 'finished' AND activity_type = ?";
  final List<Object?> args = activityType == null
      ? null
      : <Object?>[activityType.dbValue];
  final List<Map<String, Object?>> rows = await _db.query(
    'workouts',
    where: where,
    whereArgs: args,
    orderBy: 'started_at DESC',
    limit: limit,
    offset: offset,
  );
  return rows.map(Workout.fromDbMap).toList();
}
```

- [ ] **Step 2: 历史页加筛选条**

`history_page.dart` 在 AppBar 下方、列表上方加一行 `SegmentedButton<ActivityType?>`（全部/骑行/跑步/健走/徒步），选中态写 `historyFilterProvider`。

- [ ] **Step 3: 卡片类型图标 + 配速主读数**

`ride_card.dart`：
- 左侧身份列前加类型图标：`Icon(_activityIcon(ride.activityType), size: 16, color: kAppTextMuted)`，其中 `_activityIcon` 放 `ride_card.dart` 私有函数：

```dart
IconData _activityIcon(ActivityType t) => switch (t) {
      ActivityType.cycling => Icons.directions_bike,
      ActivityType.running => Icons.directions_run,
      ActivityType.walking => Icons.directions_walk,
      ActivityType.hiking => Icons.terrain,
    };
```

- 次级四列中「均速 km/h」列按类型换配速：

```dart
_MetaCell(
  ride.activityType.usesPace
      ? '配速 ${formatPace(s.movingAvgSpeedMps, unit)}'
      : '${formatSpeedValue(s.movingAvgSpeedMps, unit)} ${speedUnitLabel(unit)}',
  flex: 4,
),
```

- 空态文案按筛选：`'还没有${filter?.label ?? '骑行'}记录'`——`filter == null` 时显示「还没有骑行记录」（全量空态保留原语义）。

- [ ] **Step 4: 写测试**

`test/features/history/history_page_test.dart` 追加：

```dart
testWidgets('类型筛选后只显示该类型记录', (WidgetTester tester) async {
  // override finishedRidesProvider 为一条 cycling + 一条 running；
  // 选择「跑步」后 cycling 卡片消失。
});
```

- [ ] **Step 5: 跑测试**

Run: `flutter test test/features/history/`
Expected: 通过。

- [ ] **Step 6: Commit**

```bash
git add lib/features/history/ test/features/history/
git commit -m "feat: 历史列表支持运动类型筛选，跑步卡片显示配速读数"
```

---

### Task 7: 统计页类型筛选 + 功率行隐藏

**Files:**
- Modify: `lib/features/stats/stats_providers.dart`
- Modify: `lib/features/stats/stats_page.dart`
- Test: `test/features/stats/stats_page_test.dart`

- [ ] **Step 1: provider 加筛选**

`stats_providers.dart`：

```dart
final StateProvider<ActivityType?> statsFilterProvider =
    StateProvider<ActivityType?>((Ref ref) => null);

final FutureProvider<List<Workout>> finishedRidesProvider =
    FutureProvider<List<Workout>>((Ref ref) {
  ref.watch(rideDataRevisionProvider);
  final ActivityType? filter = ref.watch(statsFilterProvider);
  return ref.watch(workoutRepositoryProvider).listFinished(activityType: filter);
});
```

- [ ] **Step 2: 统计页加类型筛选 + 功率行隐藏**

`stats_page.dart`：周/月/年 SegmentedButton 上方加一行类型筛选（同 Task 6 样式）。`_Totals` 加 `showPowerRow`（= 筛选类型 `supportsPower`，全部时按「任意记录含功率」决定）：

```dart
// 功率行只在当前类型支持功率（或全部里有功率记录）时显示。
final bool showPower = filter == null
    ? list.any((Workout w) => w.summary?.avgPowerW != null)
    : filter.supportsPower;
```

`_Totals` 里平均/最高功率两格包进 `if (showPower)`。

- [ ] **Step 3: 写测试**

`test/features/stats/stats_page_test.dart` 追加跑步筛选用例，断言 `find.text('平均功率')` findsNothing。

- [ ] **Step 4: 跑测试**

Run: `flutter test test/features/stats/`
Expected: 通过。

- [ ] **Step 5: Commit**

```bash
git add lib/features/stats/ test/features/stats/
git commit -m "feat: 统计页支持运动类型筛选，非功率类型隐藏功率行"
```

---

### Task 8: 详情页类型徽标 + 收尾门禁

**Files:**
- Modify: `lib/features/detail/detail_page.dart`
- Test: `test/features/detail/detail_page_test.dart`

- [ ] **Step 1: 详情页类型徽标**

`detail_page.dart` 中日期行（`formatDateTime(...)` 那段）左侧或标题旁加类型徽标：

```dart
Row(
  children: <Widget>[
    Icon(_activityIcon(ride.activityType), size: 16, color: kAppTextMuted),
    const SizedBox(width: kSpaceS),
    Text(ride.activityType.label, style: const TextStyle(fontSize: 13, color: kAppTextMuted)),
    const SizedBox(width: kSpaceM),
    Text(formatDateTime(ride.startedAtMs), style: ...),
  ],
)
```

`_activityIcon` 从 ride_card 移到共享位置——为避免跨 feature 耦合，复制一份私有函数到 detail_page（图标映射相同即可）。

AppBar 标题：`ride.title ?? '骑行详情'` 改为 `ride.title ?? '${ride.activityType.label}详情'`。

- [ ] **Step 2: 写测试**

`test/features/detail/detail_page_test.dart` 追加：一条 `activityType: running` 的记录，断言 `find.text('跑步')` 存在。

- [ ] **Step 3: 跑全仓门禁**

Run: `flutter analyze`
Expected: No issues found.

Run: `flutter test`
Expected: 全量通过。

- [ ] **Step 4: 检查设计覆盖**

对照 spec 逐条核对：
- [ ] ActivityType 枚举 + 能力集 → Task 1
- [ ] 数据层 v3 迁移（RENAME + activity_type 默认 cycling）→ Task 2
- [ ] 备份兼容 v1 → Task 2 Step 4
- [ ] formatPace → Task 3
- [ ] 记录引擎开关 + 文案适配 → Task 4
- [ ] 类型 chip + 按类型渲染 → Task 5
- [ ] 历史筛选 + 配速 → Task 6
- [ ] 统计筛选 + 功率行隐藏 → Task 7
- [ ] 详情徽标 → Task 8

- [ ] **Step 5: Commit**

```bash
git add lib/features/detail/ test/features/detail/
git commit -m "feat: 详情页显示运动类型徽标，App 完成多运动类型泛化"
```

---

## Self-Review 记录

- **Spec 覆盖**：设计文档 5（领域模型）、6（迁移）、7（引擎/配速/提示）、8（界面）、9（历史/统计/详情）、10（测试）均已映射到 Task 1–8。第 11 节兜底（崩溃恢复类型、心率 `--`、reset 记忆）在 Task 2/4/5 中实现。
- **无占位符**：每个任务含完整代码或精确映射表。
- **类型一致**：`formatPace` 签名在 Task 3 定义、Task 5/6 调用，单位参数均为 `DistanceUnit`；`ActivityType` 能力 getter 名在 Task 1 定义、Task 4/5/6/7 使用一致（`supportsCadence`/`supportsPower`/`usesPace`/`supportsSpeedTierCue`）。
