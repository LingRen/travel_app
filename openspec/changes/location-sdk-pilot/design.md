# Design: 高德定位 SDK 试点

## Context

记录链路已经把平台差异收在 [location_service.dart](file:///Users/ling/code/travel_app/lib/data/location/location_service.dart)：

- `LocationService` 只依赖 `LocationPlatform`（`positionStream` / `getCurrentPosition` / 权限 / 服务开关），生产实现是 `GeolocatorLocationPlatform`。
- Android 用 `AndroidSettings` 的 `foregroundNotificationConfig` 起前台服务，1 Hz、`distanceFilter: 0`；iOS 用 `bestForNavigation`、`allowBackgroundLocationUpdates`、关闭自动暂停。
- 待机页 `quickPreviewFix()` 走中精度一次性请求，Android 强制系统 `LocationManager`。
- 会话侧每拍判定「信号弱」，超过 10 秒没有新点即进入弱信号；定位流 15 秒无回调会重建订阅（`_kFixStallRestartMs`）。
- 断点与距离规则（`kGpsGapMs=10s`、`kGapBridgeMaxMs=30s`、`kGapBreakMinDistanceM=20m`、`maxPlausibleSpeed`）在 domain 层，与 provider 无关。
- 目前没有通用精度门槛：只有起点落位要求 ≤30 m；差精度点仍会进入会话，可能被当成位移抖动。

高德定位 SDK 的输出是 GCJ-02，且带自己的后台定位与隐私合规要求。试点的目标不是「换掉 geolocator」，而是用同一套会话逻辑验证它是否能减少可联网补齐的空档，并用预先定义的数据决定是否转正。

## Goals / Non-Goals

### Goals

- 在 `LocationPlatform` 后接入高德定位，默认关闭，可通过配置或 debug 开关启用。
- 高德结果在接入层归一为 WGS-84，落盘 / 统计 / GPX 与历史数据完全不变。
- 精度差的点不进入会话；门槛与断点判定分离，不改变 10 / 30 秒阈值。
- 保留 Android 前台服务与 15 秒看门狗；锁屏 30 分钟可持续记录。
- 定义可量化的试点成功标准、对照方法与一键回滚。
- 未配置 Key、初始化失败或权限拒绝时回落到系统定位或明确报错，不崩溃。

### Non-Goals

- 不在本次删除 `geolocator`、不切换 release 默认值。
- 不改断点阈值、距离 / 爬升滤波、抽稀、GPX 结构。
- 不回填、重算或迁移历史轨迹。
- 不做地图匹配、路径吸附、室内定位、蓝牙信标。
- 不把高德定位用于待机页地名 / 天气之外的其它用途。

## Approaches Considered

### Approach A: 直接替换 geolocator

**Pros:**

- 代码路径唯一，长期维护成本低。
- 所有平台都走同一套高德配置。

**Cons:**

- 后台锁屏、权限、耗电尚未验证就切断退路。
- 一旦国内 SDK 在海外或无网络场景表现更差，没有回滚开关。
- 历史与新数据的口径切换风险集中。

### Approach B: 双流并行，取长补短

（geolocator 与高德同时订阅，按精度或时间合并。）

**Pros:**

- 理论上两边都差时仍有一个源。

**Cons:**

- 两条流同时工作，耗电成倍；重复点、时间戳不同步、坐标系不同，需要复杂的去重与仲裁。
- 会话层要接收「两个来源」概念，超出试点范围。

### Approach C: Provider 可插拔，默认系统，高德试点（推荐）

**Pros:**

- 复用现有 `LocationPlatform`，会话、状态机、断点逻辑零改动。
- 一个开关即可回滚；失败只影响启用者。
- 便于同机 A/B，把结论写成可验证数据。

**Cons:**

- 短期保留两个 provider 与两套平台配置。
- 调试开关与生产默认值需要清楚隔离。

## Decision

**Chosen Approach:** C —— Provider 可插拔，默认系统，高德试点。

**Rationale:**

- 现有抽象正好是为这种替换准备的；试点只应新增一个实现与选择逻辑，不应重写记录链路。
- 成功标准需要对照实验，开关式接入比直接替换更容易得到可比较的数据。
- 后台持续定位是记录类应用的硬需求；在真机验证通过前，不能让高德成为唯一路径。

## Trade-offs

- 接受两个 provider 的维护成本，换取可回滚与真机对照。
- 接受 GCJ-02 → WGS-84 逆变换的 1~2 m 近似误差；这远小于记录本身的定位误差，且能保证 GPX 与历史口径统一。
- 接受精度门槛会在极差环境下把点判为无效，从而让断点更早出现；这是「宁可不画，也不画假轨迹」的取舍，与现有断点原则一致。
- 接受 debug 切换需要重启记录会话才完全干净；运行中切换时先停旧流、再起新流，并重置看门狗。

## Technical Details

### Architecture

```text
RecordController
     |
     v
LocationService ---- LocationPlatform ---- GeolocatorLocationPlatform (default)
     |                       |
     |                       +------------- AmapLocationPlatform (pilot)
     |                                       |
     |                                       +-- GCJ-02 -> WGS-84
     |                                       +-- 精度门槛 50 m
     |
     +--> quickPreviewFix()  （试点源同样提供，失败回退系统一次）
     |
     v
RecordingSession / domain 断点规则（不改）
```

### Provider 选择

- `lib/config/app_config.dart` 新增：
  - `kLocationProviderOverride = String.fromEnvironment('LOCATION_PROVIDER')`，取值 `system` / `amap`，默认空。
- 选择顺序：
  1. debug 构建且本地调试设置为 `amap` / `system` → 用它；
  2. 否则用 `LOCATION_PROVIDER`；
  3. 否则 `system`。
- debug 开关落在 settings 表 `location_provider_debug`，只在 `kDebugMode` 读写；release 忽略该键，避免用户误开未验收的路径。
- `locationServiceProvider` 按选择结果构造 `LocationService(platform: ...)`；切换后 invalidate provider，记录页在下次开始 / 恢复时使用新源。
- 高德 Key 复用地图原生 Key（`AMAP_MAP_KEY`）。Key 为空时 `amap` 选择无效，回落到 `system` 并在 debug 日志说明原因。

### 高德定位接入

- 候选插件 `amap_flutter_location`，以 spike API 为准；封装在 `lib/data/location/amap_location_platform.dart`，不把 SDK 类型泄漏到 `LocationService` 之上。
- 初始化前调用插件要求的隐私展示 / 同意接口；未初始化成功时 `positionStream` 返回空流并记录错误，由 `checkReadiness` 给出可读原因。
- 选项：
  - 连续定位（非单次），间隔 1 秒；
  - 高精度优先，允许 GPS + WiFi + 基站融合；
  - 不逆地理编码（省流量与耗时）；
  - 关闭传感器辅助定位，避免静止时方向 / 速度噪声；
  - 超时与失败交给流错误与看门狗，不阻塞开始。
- `quickPreviewFix`：优先高德一次定位（3 秒超时），失败时退回现有系统 `quickPreviewFix`，待机页不因试点源不可用而一直空白。

### 坐标归一

- 高德返回 GCJ-02；新增 `gcj02ToWgs84(lat, lon)` 的迭代逆变换（初值取 GCJ 点，反复把 WGS→GCJ 的差值减回去，最多 5 次或 1e-7 度收敛）。
- 只在 `AmapLocationPlatform` 出口转换一次；`LocationService` 之上、`RecordingSession`、数据库、GPX 全部是 WGS-84。
- 起点、粗略定位、断点位移都使用归一后的坐标，避免与历史 / 地图底图口径混用。
- 单测覆盖成都、北京、海岸线附近的往返误差 ≤2 m，且不产生 NaN / 越界。

### 精度门槛

- 新增 `kMaxAcceptedAccuracyM = 50.0`：`accuracyM` 为空或大于该值的点不进入会话（仍可用于待机页粗略显示，但不落盘、不参与距离）。
- 门槛放在 `LocationService.fixes()` 的共享出口，对两个 provider 一致生效，保证 A/B 的条件相同；这是本变更对系统定位的唯一行为变化，预期只滤掉原本会造成假跳变的基站级点。
- 不把「被拒点」当作一个定位空档：会话仍以「多久没收到可信点」判定信号弱；因此弱信号区可能更早进入断点，这是可接受的保守行为。
- 起点精度门槛（30 m）与落盘门槛（50 m）保持独立，不合并。

### 后台与看门狗

- Android 前台服务：试点源不能复用 `geolocator` 的 `foregroundNotificationConfig`。spike 先确认高德插件是否提供后台定位 + 通知；不提供则在应用侧补一个最小前台服务（通知文案沿用「运动记录中 / 正在记录轨迹与心率」），只负责保活，定位仍由高德 SDK 提供。
- iOS：开启 Background Location capability，`allowsBackgroundLocationUpdates` 由插件选项或原生配置保证；锁屏后仍须持续回调。
- 15 秒看门狗保留：超时重建订阅。对高德实现，重建等价于销毁并重新创建定位客户端；连续重建不得泄漏监听。
- 暂停期间不重建、不判信号弱（沿用现有逻辑）。

### 试点成功标准

同一台设备、同一条 10~20 km 城市路线，各跑 3 次系统 / 高德配对（同一天、相近时段），数据从落盘轨迹回放计算：

| 指标 | 通过标准 |
| --- | --- |
| ≥10 秒定位空档数量 | 高德 ≤ 系统的 70%（可联网补齐的城区路段） |
| >30 秒断点数量 | 不增加；隧道等真无信号场景允许相同 |
| 总距离偏差 | 与系统配对记录的偏差 ≤2% |
| 累计爬升偏差 | ≤5%（同一套滤波参数） |
| 异常跳变 | 不出现隐含速度 >30 m/s 的段，不出现横穿建筑的假直线 |
| 锁屏续航 | 连续锁屏 30 分钟不断流；看门狗重建 ≤2 次/小时 |
| 耗电 | 每小时耗电不超过系统源的 +15% |

任一条不达标 → 保持 `system` 默认，记录结论；不删除实现，开关保留但 release 不可用。

### 测试

- 纯单测：provider 选择优先级、无 Key 回落、GCJ 逆变换误差、精度门槛、`toLocationFix` 字段映射（速度 -1、朝向负值）。
- `LocationService` 单测沿用假 `LocationPlatform`；新增高德平台的假实现，验证流被正确包装与错误时为空。
- `RecordController` 测试：切换 provider 后旧流被取消、看门狗重置、暂停期间不重建。
- 设置页 widget 测试：debug 构建出现「定位源」行，release 不出现。
- 真机：按成功标准跑配对路线，把结果写入 `openspec/verification/`；自动化不替代真实 GPS 对照。

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| 高德 Flutter 定位插件不支持后台持续定位 | spike 先行；不支持则补应用级前台服务，仍不满足就停止转正，保留 `geolocator` |
| GCJ-02 逆变换误差或边界 bug | 迭代逆变换 + 多城市单测；误差 >2 m 不启用 |
| 精度门槛让弱信号区断点变多 | 50 m 阈值先真机对照；若明显变差，调高阈值或只对高德生效并记录理由 |
| 两套 provider 同时初始化导致耗电 | 切换时显式 stop + dispose；debug 开关限定在待机状态可用，记录中禁用 |
| 隐私合规（定位 SDK 收集设备 / 网络信息） | 初始化前声明；README 与商店描述补充定位数据来源；必要时补隐私弹窗 |
| Key 绑定错误导致定位静默失败 | 启动时 debug 日志输出 provider 与 Key 是否存在；失败回落系统并提示 |
| 后台保活改动影响现有 geolocator 前台服务 | 前台服务只在 amap 试点启用；system 路径保持原配置不变 |
| 试点结论样本不足 | 至少 3 组配对；不足则延长试点，不提前切换默认值 |

## Spike 结论（2026-11-03，OPPO `cb2e5863`）

### 插件选型

- 官方 `amap_flutter_location` 最高版本 3.0.0，`environment.sdk` 是 `>=2.12.0 <3.0.0`，
  Dart 3 下 Pub 直接拒绝解析，不可用。
- 采用同一 API 的 Dart 3 分支 `amap_flutter_location_plus` 3.1.2，内置到
  `third_party/amap_flutter_location_plus`。上游发布于 2021 年，无法适配 Gradle 9 /
  AGP 9：需要把 `jcenter()` 换成 `mavenCentral()`、compileSdk 31→37、minSdk 16→21，
  并去掉用于解析 AGP 3.5.1 的 buildscript classpath（改动说明写在它的 build.gradle 头部）。
- 定位 SDK 依赖用 `compileOnly 'com.amap.api:location:5.6.0'`：宿主工程已经通过
  `amap_map` 的 `3dmap-location-search:10.1.200_loc6.4.9` 在运行时带上 loc 6.4.9，
  再打包一份会类冲突。真机验证通过，说明 5.6.0 编译、6.4.9 运行是兼容的。

### 初始化与隐私声明

调用顺序可用：`setApiKey(androidKey, iosKey)` → `updatePrivacyShow(true, true)` →
`updatePrivacyAgree(true)` → `setLocationOption(...)` → `startLocation()`。未注入 Key 时
不发定位请求，接入层按设计回落到系统定位。

### 连续定位与字段口径

- `locationInterval: 1000`、`needAddress: false`、`locationMode: Hight_Accuracy` 下，
  真机 15 秒收到 12 个回调，节奏约 1 Hz（首两个点因热启动略早）。
- 回调字段：`latitude` / `longitude` / `accuracy` / `altitude` / `bearing` / `speed` /
  `locationTime` / `locationType` 齐全；`needAddress=false` 时地址类字段为空串。
- **失败同样走这条流**：实测插入了 `{errorCode: 19, errorInfo: ...}` 的「无坐标事件」。
  接入层必须先判断 `errorCode` 再映射，否则会把它当成一个空坐标点。

### Android 后台能力

- 插件源码里没有任何前台服务 / 通知 / `enableBackgroundLocation` 的入口，
  `allowsBackgroundLocationUpdates` 只对 iOS 生效。
- 因此锁屏记录必须由应用侧补一个最小前台服务（宿主已经声明
  `FOREGROUND_SERVICE_LOCATION` 与 `ACCESS_BACKGROUND_LOCATION`），即
  Task 6 的「应用级前台服务」分支，而不是插件自带能力。
- 30 分钟锁屏验收依赖这个前台服务，放到 Task 7 真机试点里做；本轮 spike 不做长时空跑。

### 坐标系

- 本次真机被 `com.ling.mockgps` 的模拟定位源接管，AMap 返回的点与注入点一致，
  **无法据此确认 GCJ-02 偏移**。真实 GPS 下的口径对照（系统定位 vs 高德，同点位
  偏差应有数百米）列入 Task 7 的配对骑行，先用逆变换归一，再以 GPX 对照确认。
- iOS 按当前约定不在本轮验证范围。

## Open Questions

- 已解决：插件后台能力——插件不带后台通知，需应用级前台服务（见上）。
- 已解决：Key 共用——spike 用地图 Android Key（`AMAP_MAP_KEY_ANDROID`）成功拿到定位回调。
- 未决：精度门槛是否最终对两个 provider 都保留，取决于试点数据；当前设计按共享出口实现，
  便于统一比较。

