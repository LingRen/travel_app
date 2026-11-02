# 多运动类型泛化设计文档（方案 C：通用 Workout 平台）

日期：2026-10-23
状态：待用户审阅

## 1. 背景与目标

当前 App 以**骑行**为唯一运动语义：领域模型（`Ride`/`RideSummary`/`RideStatus`）、记录引擎、历史/统计/详情页、传感器层全部围绕骑行设计。本次迭代将 App 泛化为**通用多运动记录平台**，在保留骑行全部能力的前提下，新增跑步 / 健走 / 徒步三种运动类型。

核心价值不变：把一次运动完整、准确地记下来，事后回答「这次练得怎么样」与「最近练得怎么样」。

## 2. 范围

### 做

- 新增运动类型：骑行（保留现状）、跑步、健走、徒步
- 领域模型全量泛化：`Ride` → `Workout`（类、表、DAO、Repository 全链路改名）
- 数据层 v3 迁移：`rides` 表改名 `workouts` + 新增 `activity_type` 列（默认 `cycling`）
- 记录引擎按类型开关功能：跑步/健走/徒步关闭功率估算、踏频采样、速度跨档提示
- 配速读数：跑步/健走/徒步主读数显示配速（min/km 或 min/mi），新增 `formatPace`
- 记录界面：未开始态主键上方类型 chip 行；读数面板与传感器灯按类型渲染
- 历史列表按类型筛选，卡片主读数按类型（骑行均速 / 跑步配速）
- 统计页按类型筛选，跑步类型隐藏功率行
- 详情页类型徽标，曲线按数据自动呈现
- 提示系统保留并适配：距离里程碑全类型通用，文案动词按类型替换，TTS 同步

### 明确不做

- 自动运动类型识别（用户显式选择）
- 跑步步频硬件传感器支持（本次不做步频读数）
- 游泳 / 划船 / 室内器械等更多类型
- 类型切换发生在骑行中（类型在开始时刻冻结落库）
- 多语言（仅中文）

## 3. 关键决策记录

| 决策点 | 结论 | 理由 |
| --- | --- | --- |
| 实现方案 | 方案 C：通用 Workout 平台（全量泛化） | 用户明确选择；一次到位，避免多次迭代重复改名 |
| 数据层迁移 | 全量重命名：`rides` 表 → `workouts`，类同步改名 | 用户确认；`RENAME` 是 SQLite 原子操作，不动轨迹点数据 |
| 运动类型 | 骑行 + 跑步 + 健走 + 徒步 | 用户确认；覆盖日常户外有氧运动 |
| 类型选择入口 | 记录界面未开始态主键上方 chip 行 | 用户确认；类型在开始那一刻冻结落库 |
| 主读数 | 跑步/健走/徒步显示配速，骑行保持速度 | 用户确认「配速优先」 |
| 传感器范围 | 跑步/健走/徒步只连心率，不连踏频/功率 | 用户确认「按推荐来」 |
| 提示系统 | 保留并适配（距离里程碑通用，文案动词按类型替换） | 用户确认 |
| 历史/统计 | 支持类型筛选；统计页跑步类型隐藏功率行 | 用户确认 |
| 记录引擎泛化 | 单一会话类按类型开关功能，不拆子类 | 改动集中、测试可复用 |
| 距离里程碑 | 每 1km / 每 10km 判据全类型不变 | YAGNI，不引入 500m 粒度 |

## 4. 技术栈

技术栈不变（Flutter / geolocator / flutter_blue_plus / sqflite / flutter_riverpod / fl_chart / flutter_map 等），本次为纯领域与界面层泛化，不引入新依赖。

## 5. 领域模型泛化

### 5.1 ActivityType 枚举

```dart
enum ActivityType {
  cycling('cycling', '骑行'),
  running('running', '跑步'),
  walking('walking', '健走'),
  hiking('hiking', '徒步');
}
```

- 语义归属：与 `DistanceUnit` 同层，落设置/数据层，带 `dbValue` 稳定标识，不依赖 UI；
- `fromDb(String?)` 未知值回退 `cycling`（与 `DistanceUnit.fromDb` 同款兜底）；
- 枚举附带**能力描述**，供界面与引擎按类型分派：

| 能力 | 骑行 | 跑步/健走/徒步 |
| --- | --- | --- |
| 距离 / 时长 / 速度 / 海拔 / 爬升 | ✓ | ✓ |
| 功率估算 | ✓ | ✗ |
| 踏频采样 | ✓ | ✗ |
| 心率 | ✓ | ✓ |
| 配速读数 | ✗ | ✓ |
| 速度跨档提示 | ✓ | ✗ |
| 距离里程碑提示 | ✓ | ✓ |
| 历史/统计功率呈现 | ✓ | 隐藏 |

### 5.2 Workout（原 Ride）

```dart
class Workout {
  final int? id;
  final int startedAtMs;
  final int? endedAtMs;
  final WorkoutStatus status;
  final String? title;
  final ActivityType activityType;  // 新增，默认 cycling
  final WorkoutSummary? summary;
  final String? hrDeviceName;
  final String? cadenceDeviceName;
  final String? powerDeviceName;
}
```

- `WorkoutSummary`（原 `RideSummary`）字段不变；跑步记录 `avgCadence`/`avgPowerW` 自然为 null，曲线与详情自动缺省；
- `WorkoutStatus`（原 `RideStatus`）不变；
- `TrackPoint` **不改名、不改结构**：轨迹点本身通用，跑步/骑行共用经纬度 + 传感器采样。

### 5.3 改名范围

全链路改名，保持语义一致：

- 文件：`ride.dart` → `workout.dart`、`ride_summary.dart` → `workout_summary.dart`、`ride_status.dart` → `workout_status.dart`、`ride_dao.dart` → `workout_dao.dart`、`ride_repository.dart` → `workout_repository.dart`
- provider：`rideRepositoryProvider` → `workoutRepositoryProvider`、`finishedRidesProvider`/`historyRidesProvider` 接口签名增加类型筛选参数
- 测试文件同步改名（见第 10 节）

## 6. 数据层迁移（v2 → v3）

### 6.1 迁移内容

```sql
ALTER TABLE rides RENAME TO workouts;
ALTER TABLE workouts ADD COLUMN activity_type TEXT NOT NULL DEFAULT 'cycling';
```

- `kSchemaVersion` 2 → 3；
- `RENAME` 是原子操作，不动已有轨迹点数据；
- 旧记录 `activity_type` 自动补 `cycling`，历史语义不变；
- 建表语句同步更新为 `CREATE TABLE workouts (... activity_type TEXT NOT NULL DEFAULT 'cycling' ...)`；
- 迁移顺序：先 `RENAME`，后 `ADD COLUMN`（`DEFAULT 'cycling'` 使既有行回填）。

### 6.2 崩溃恢复

`resumeExisting` 从库中读取该记录的 `activity_type` 重建会话类型，**不做默认假设**——恢复的是哪次运动，会话就是哪种类型。

## 7. 记录引擎

### 7.1 泛化方式

`RecordingSession` 构造时接收 `activityType`，按类型开关功能，**不拆多个会话子类**：

| 功能点 | 骑行 | 跑步/健走/徒步 |
| --- | --- | --- |
| `_estimatePower()` | ✓ | 直接返回 null |
| `ingestCadence(rpm)` | 写入 | 忽略 |
| `ingestPower(watts)` | 写入 | 忽略 |
| 速度跨档提示（10km/h 整档） | ✓ | 关闭 |
| 距离里程碑提示（每 1km / 10km） | ✓ | ✓（文案适配） |
| `TrackPoint` 落盘 | lat/lon/hr/cadence/power | lat/lon/hr/cadence=null/power=null |

- 跑步的点同样写库，`TrackPoint` 格式不变 → 详情页曲线与结算逻辑**全部复用**；
- `RecordingSnapshot` 增加 `pace`（由 `currentSpeedMps` 换算）或保留 `currentSpeedMps` 由 UI 换算——实现时取**保留 speed 由 UI 层换算**，domain 不引入新字段（YAGNI）；
- `pause`/`resume`/`finish`/`tick` 行为全类型一致，无分支。

### 7.2 配速换算

`formatPace` 放 `core/format.dart`，与速度换算同层：

```dart
/// 由速度（m/s）换算配速。speedMps <= 0 时返回 '--'。
/// 公里模式返回 mm:ss/km，英里模式返回 mm:ss/mi。
String formatPace(double speedMps, DistanceUnit unit)
```

- 换算：`paceSecPerKm = 1000 / (speedMps * 60)` 秒每公里；
- 显示格式固定为 `5'30"`（分'秒"，秒数两位补齐），单位尾缀 ` /km` 或 ` /mi` 由调用方拼在读数外；测试锚点断言 `5'30"` 与 `--` 两种取值。

### 7.3 提示适配

- `RideCue` 文案动词按类型映射：骑行「已骑 X 公里」/ 跑步「已跑 X 公里」/ 健走「已走 X 公里」/ 徒步「已徒步 X 公里」；
- 距离里程碑判据不变（每 1km / 每 10km）；
- 速度跨档提示仅骑行启用；
- TTS（`RideCuePlayer`）接口不变，播报文案与横幅同源。

## 8. 记录界面

### 8.1 类型选择入口

- 未开始态（idle）主键上方一行类型 chip（骑行 / 跑步 / 健走 / 徒步）；
- 选中态记忆：`RecordController` 持有 `_selectedActivityType`，`reset()` 后保留上次选择，默认首次为 `cycling`；
- 开始记录时冻结：`start()` 传入选中类型落库，骑行中不可切换；
- 主键文案随类型变化：「开始骑行」/「开始跑步」/「开始健走」/「开始徒步」。

### 8.2 读数面板按类型渲染

`HandlebarView` 底部读数区按 `activityType` 分派：

- **骑行**：现状不动——速度大读数、速度刻度尺、心率/踏频/功率三格；
- **跑步/健走/徒步**：
  - 主读数替换为配速（`formatPace`）；
  - 去掉踏频/功率格，只留心率格（无步频硬件支持）；
  - 顶部四格（距离/时长/海拔/爬升）全类型保留。

### 8.3 传感器灯按类型裁剪

- `_StatusStrip` 三盏灯（心率/踏频/功率）：骑行三盏全亮（现状）；跑步/健走/徒步**只留心率灯**；
- `SensorKind` 枚举不动，但 `RecordController.start()` 按类型决定自动连接哪些已配对传感器（跑步只连心率）；`connectSensor` 对非骑行类型的踏频/功率请求直接忽略（兜底防御）；
- `SensorPairingRepository` 配对记录不变：切回骑行仍能自动连踏频/功率。

### 8.4 提示横幅

`RideCueBanner` 按类型走第 7.3 节适配文案，无其他改动。

## 9. 历史 / 统计 / 详情页

### 9.1 历史列表

- 顶部加类型筛选条（全部 / 骑行 / 跑步 / 健走 / 徒步），`historyRidesProvider` 接受筛选参数；
- `RideCard` 加类型图标；
- 主读数：骑行显示均速 `km/h`（现状）；跑步/健走/徒步显示**配速** `mm:ss`；
- 次级四列中「均速 km/h」列按类型换为「配速」（跑步类）；
- 空态文案按筛选：「还没有骑行记录」/「还没有跑步记录」/「还没有健走记录」/「还没有徒步记录」。

### 9.2 统计页

- 顶部加类型筛选（`finishedRidesProvider` 接受筛选），`buildTrend`/`personalBests` 只统计当前类型记录；
- 累计功率两格（平均/最高功率）：跑步/健走/徒步类型**整行隐藏**；
- 其余（距离/时长/爬升/次数）全类型保留。

### 9.3 详情页

- 模型泛化后自动适配，`DetailPage` 走 `Workout`/`WorkoutSummary`/`TrackPoint`；
- 标题下方加类型徽标（「骑行」/「跑步」等）；
- 曲线区：骑行四曲线现状不动；跑步/健走/徒步只有速度 + 心率两曲线（踏频/功率数据 null，现有逻辑自动不画）。

## 10. 测试与门禁

### 10.1 测试策略

| 层 | 策略 |
| --- | --- |
| 领域模型 | 现有 `Ride`→`Workout` 用例改名迁移；新增 `ActivityType.fromDb` 回退、`Workout` 带类型落库/读取用例 |
| 记录引擎 | 新增「跑步会话不估算功率、忽略踏频、速度跨档提示关闭、距离里程碑保留」用例；骑行用例全量保留（回归） |
| 格式层 | `formatPace` 边界：0 速度 → `--`、min/km、min/mi |
| 界面 | 类型 chip 选择、主键文案随类型、跑步界面无踏频/功率格与灯、历史类型筛选、统计功率行隐藏、详情类型徽标 |
| 数据层 | v2→v3 迁移用例：RENAME + activity_type 默认 cycling；旧库升级后旧记录类型为 cycling |

### 10.2 门禁

- 保持现状：`flutter analyze` + 全部单元测试通过；
- 不新增独立门禁——类型能力差异由第 10.1 用例守住。

## 11. 兜底与错误处理

- 跑步类型未接心率带：心率格显示 `--`（现状逻辑），不阻断记录；
- 类型选择为运行时纯 UI 状态，`reset()` 后保留上次选择；
- 崩溃恢复从库读类型，不做默认假设（见 6.2）；
- 统计/历史筛选在无对应类型记录时空态文案明确（见 9.1）。

## 12. 改动文件清单（预估）

| 层 | 文件 |
| --- | --- |
| 数据层 | `database.dart`（v3 迁移）、`ride_dao.dart`→`workout_dao.dart`、`ride_repository.dart`→`workout_repository.dart`、`track_point_dao.dart`（表名引用） |
| 领域层 | `ride.dart`→`workout.dart`、`ride_summary.dart`→`workout_summary.dart`、`ride_status.dart`→`workout_status.dart`、新增 `activity_type` 模型、`recording_session.dart`、`cue_detector.dart`、`ride_cue.dart` |
| 格式层 | `core/format.dart`（新增 `formatPace`） |
| 界面 | `record_page.dart`、`handlebar_view.dart`、`record_controller.dart`、`history_page.dart`、`ride_card.dart`、`stats_page.dart`、`detail_page.dart` |
| 测试 | 全量改名 + 新增类型差异用例（详见第 10.1 节） |
