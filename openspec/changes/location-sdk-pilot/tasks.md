# Implementation Tasks for location-sdk-pilot

## Status
- Total Tasks: 46
- Completed: 41
- In Progress: 0
- Pending: 5

---

## Phase 1: 可行性确认与坐标归一

### Entry Gate
> 先读 `plan.md` Task 1-2 与 `specs/location-acquisition/spec.md`；确认地图变更已提供原生 Key 配置。

### Tasks
- [x] 1.1 真机验证候选插件初始化、隐私声明、1 Hz 连续定位与 GCJ-02 字段
  - 结论：官方包 Dart 2 不可用，内置 `third_party/amap_flutter_location_plus` 3.1.2；15 秒 12 个回调，字段齐全，失败以 `errorCode` 事件混在同一条流
- [x] 1.2 真机验证 Android 锁屏 30 分钟与 iOS 后台能力，记录是否自带前台通知
  - 结论：插件无任何前台服务 / 通知 / `enableBackgroundLocation` API（仅 iOS 有 `allowsBackgroundLocationUpdates`）→ 后台锁屏需应用级前台服务；30 分钟锁屏验收随 Task 7 做。iOS 按约定不在本轮
- [x] 1.3 把插件版本、后台方案与通知 API 回填 `design.md` Open Questions
- [x] 1.4 写 `test/domain/analysis/gcj02_inverse_test.dart`：成都 / 北京 / 海岸线往返误差 ≤2 m
  - Spec: `### Requirement: 高德定位结果归一为 WGS-84` → `#### Scenario: 记录落盘`
- [x] 1.5 在 `lib/domain/analysis/gcj02.dart` 增加迭代 `gcj02ToWgs84`，不改现有正变换
- [x] 1.6 运行 GCJ 测试与 `fvm flutter analyze`
  - 结果：GCJ 测试 24 条全过；`flutter analyze` 无问题；全量 `flutter test` 870 条全过
- [x] 1.7 提交：`feat(location-acquisition): add gcj02 to wgs84 inverse conversion`
  - 提交：`de952e6`（GCJ 逆变换）、`865cd61`（内置插件）、`14b3d82`（阶段文档）

### Exit Gate
> 更新状态与完成表；提交；若 1.2 不通过，暂停后续编码并回报。

---

## Phase 2: 定位源选择与配置

### Entry Gate
> 读 `plan.md` Task 3 与 `specs/location-acquisition/spec.md` 的选择、回滚要求。

### Tasks
- [x] 2.1 写 `test/data/location/location_provider_test.dart`：默认、release 忽略调试键、缺 Key、回滚
  - Spec: `### Requirement: 定位源默认使用系统定位并可切换` → 三个 Scenario
- [x] 2.2 新增 `lib/data/location/location_provider.dart`：debug 存储 → env → system
- [x] 2.3 在 `lib/config/app_config.dart` 增加 `kLocationProviderOverride`
- [x] 2.4 在 `SettingsRepository` 增加仅 debug 读写的 `location_provider_debug`
  - 同步补 `settings_repository_test.dart` 的读写用例，以及设置页测试假实现的空实现
- [x] 2.5 修改 `locationServiceProvider` 按选择结果构造 `LocationService`
  - 选择结果已接入 provider；高德平台构造随 Task 4 接入，接入前仍用系统定位
- [x] 2.6 运行 provider 测试与 `fvm flutter analyze`
  - 结果：新增 4 组（选择器 / 设置仓储）用例全过；全量 `flutter test` 884 条全过；`flutter analyze` 无问题
  - 附带：`analysis_options.yaml` 排除 `third_party/**`，内置插件副本不参与本项目 lint
- [ ] 2.7 提交：`feat(location-acquisition): select location provider with debug override`

### Exit Gate
> 更新状态；确认 release 默认仍为 system；提交。

---

## Phase 3: 高德平台、精度门槛与调试开关

### Entry Gate
> 读 `plan.md` Task 4-5 与 `specs/recording/spec.md`、`specs/settings/spec.md`。

### Tasks
- [x] 3.1 写 `test/data/location/location_service_test.dart`：800 m 点被丢弃、8 m 点通过
  - Spec: `### Requirement: 差精度定位不进入记录` → `#### Scenario: 基站级定位`、`#### Scenario: 精度恢复`
  - 另补 50 m 边界与「只有差精度点时不输出」两条
- [x] 3.2 在 `lib/domain/analysis/constants.dart` 增加 `kMaxAcceptedAccuracyM = 50.0`
- [x] 3.3 在 `LocationService.fixes()` 共享出口应用精度过滤
  - 精度为空同样丢弃；被丢弃的点不落盘、不参与距离 / 爬升 / 速度、不刷新信号状态
- [x] 3.4 新增 `lib/data/location/amap_location_platform.dart`：初始化、流映射、逆变换、销毁
  - 插件收发抽成 `AmapLocationSdk`；生产适配器把单订阅事件流包成广播流，支持看门狗重建
- [x] 3.5 写 `test/data/location/amap_location_platform_test.dart`：字段映射（速度 -1、负朝向）与坐标口径
  - Spec: `### Requirement: 高德定位结果归一为 WGS-84` → `#### Scenario: 导出 GPX`
  - 覆盖：GCJ→WGS 往返 ≤ 2 m、errorCode 事件丢弃、缺精度 / 经纬度丢弃、locationTime 解析、订阅取消即 stop
- [x] 3.6 `quickPreviewFix` 高德失败时回退系统一次，不阻塞待机页
  - 实现位置：`AmapLocationPlatform.getCurrentPosition` 3 秒超时后回退系统定位
- [x] 3.7 写 `test/features/settings/settings_page_test.dart`：debug 出现定位源行、release 不出现
  - Spec: `### Requirement: 调试工具只在调试构建出现` → 两个 Scenario
  - release 由 `kDebugMode` 门控整个调试区；测试补切换写库与记录中禁用两条
- [x] 3.8 在设置页 `_DebugSection` 增加定位源行，记录中 / 暂停时不可点
  - Spec: `### Requirement: 定位源切换不改变记录状态语义` → `#### Scenario: 记录中禁止切换`
- [x] 3.9 写 `test/features/record/record_controller_test.dart`：切换取消旧流、看门狗重置
  - Spec: `### Requirement: 试点源保持后台持续记录与看门狗` → `#### Scenario: 定位回调假死`
  - 新增「结束取消旧流、重置后再开始重新订阅」；切换重建由 `providers_test` 覆盖；看门狗重建用例原已存在
- [x] 3.10 运行相关测试与 `fvm flutter analyze`
  - 结果：`flutter analyze` 无问题；全量 `flutter test` 899 条全过
- [x] 3.11 提交：`feat(location-acquisition): add amap platform and accuracy gate` 与 debug 开关提交
  - 提交：`4491f94`（50 m 精度门槛）、`404f163`（高德平台 + debug 开关）

### Exit Gate
> 更新状态；确认系统定位路径行为只受 50 m 门槛影响；提交。

---

## Phase 4: 后台持续、试点对照与文档

### Entry Gate
> 读 `plan.md` Task 6-8 与试点成功标准表。

### Tasks
- [x] 4.1 按 spike 结论接 Android 前台服务 / 高德后台模式与 iOS capability
  - Spec: `### Requirement: 试点源保持后台持续记录与看门狗` → `#### Scenario: 锁屏记录`
  - Android：新增 `RecordingForegroundService` + `MainActivity` 平台通道，高德连续定位期间启停；系统定位继续由 geolocator 前台服务负责
  - **iOS 按约定不做**（未接 capability，`allowsBackgroundLocationUpdates` 保持 false）
- [x] 4.2 确认暂停期间不重建、不判信号弱
  - Spec: `### Requirement: 定位源切换不改变记录状态语义` → `#### Scenario: 暂停期间无定位`
  - 发现并修复：`_isGpsWeak()` 原先只在 `_collectGpsCues` 里按阶段门控，`RecordState.gpsWeak` 在暂停 30 秒后仍变 true；现统一在 `_isGpsWeak()` 内按 `RecordingPhase.recording` 判定
- [x] 4.3 `fvm flutter analyze` 与 `fvm flutter test` 全通过
  - 结果：`flutter analyze` 无问题；全量 901 条测试通过；`flutter build apk --debug --target-platform android-arm64` 成功
- [ ] 4.4 同设备同路线系统 / 高德各 3 次配对骑行，记录空档、断点、距离、爬升、跳变、耗电
  - 口径（2026-11-05 确认）：系统源为基准、高德为候选；空档 / 断点看高德，距离 / 最大隐含速度 / 跳变 / 爬升以系统为准
  - K40 已切回系统定位，组 1 可直接开始
  - Spec: `### Requirement: 试点结论以对照数据决定` → 两个 Scenario
  - 2026-11-03 前置发现（已修复，见 Phase 5）：MockGps（`com.ling.mockgps`）下，系统源 2:30 落 149 点 / 1.06 km，而高德源三次记录 `point_count = 0`；修复后高德源 2:12 / 903.9 m / 126 点
- [ ] 4.5 结论写入 `openspec/verification/2026-11-02-location-sdk-pilot.md`
  - 文档已建：链路验证（MockGps，含修复前后对照）、配对记录表与统计口径、结论待 4.4 完成后填写
- [ ] 4.6 未达标则保持 `system` 默认并确认开关仅 debug；达标则记录「可讨论切换默认值」
  - 当前默认值保持 `system`；切换门槛见 verification 第 2 节「比较方案」
- [x] 4.7 更新 `README.md`：`LOCATION_PROVIDER`、debug 开关、试点结论、WGS-84 与回滚
  - 试点结论等 4.4/4.5 完成后补写
- [x] 4.8 提交：`docs(location-acquisition): document provider pilot and rollback`
  - 提交：`08ec722`（前台服务 + 暂停信号弱修复）、`623691c`（README / tasks）

### Exit Gate
> 更新完成表；执行 `/opsx-verify`，通过后再 `/opsx-archive`。

---

## Phase 5: 修复高德定位空流

### Entry Gate
> 读 `specs/location-acquisition/spec.md` 的「高德定位在启动前完成事件订阅」。
> 设备证据：`run-as` 拉库后查 `track_points`，系统源 ride 3 有 149 点（纬度 30.657、经度 105.06185→105.07295），高德源 ride 1 / 2 / 4 均 0 点。

### Tasks
- [x] 5.1 单测先复现：`test/data/location/amap_location_platform_test.dart` 断言「先订阅 events，再 configure / start」，取消时先 `stop` 再取消订阅；`getCurrentPosition` 同样先订阅后启动
  - Spec: `### Requirement: 高德定位在启动前完成事件订阅` → `#### Scenario: 一次定位回退`
  - 新增：「待机定位超时不会停掉连续定位」
- [x] 5.2 改 `lib/data/location/amap_location_platform.dart`：`positionStream` 先 `_sdk.events.listen(...)` 再 `configure` / `start`；`getCurrentPosition` 先取得事件流再启动，`finally` 里先 `stop` 再取消临时订阅
  - 真因（真机日志确认）：一次定位与连续定位共用同一个原生客户端；待机页的 3 秒超时 `stop()` 会把刚启动的连续定位一起停掉（11:37 日志：连续 `startLocation` 后 3 秒被 `stopLocation`）
  - 修法：`_continuousActive` 标记是否已被记录接管，接管后一次定位只回退系统、不 `stop`
  - 附带修正：首次订阅顺序（先 listen 后 configure/start），保证原生 EventChannel sink 已注册
- [x] 5.3 `lib/features/record/record_controller.dart`：记录中从未收到定位时，超过 10 秒判为信号弱（不再因 `_lastFixMs == 0` 恒显示「信号良好」）
  - 做法：`_startStreams()` 记录等待起点 `_fixWaitSinceMs`，`_onFix` 置 0；`_isGpsWeak()` 取 `_lastFixMs != 0 ? _lastFixMs : _fixWaitSinceMs`
  - Spec: `### Requirement: 高德定位在启动前完成事件订阅` → `#### Scenario: 定位流完全没有回调`
- [x] 5.4 补 `test/features/record/record_controller_test.dart`：开始 11 秒无定位 → `gpsWeak = true`；首个点到达后恢复为 false
- [x] 5.5 `fvm flutter analyze` 与 `fvm flutter test` 全通过
  - 结果：`flutter analyze` 无问题；全量 905 条测试通过
- [x] 5.6 构建 debug APK 装机复测：MockGps 下高德源记录 2 分钟，`track_points.point_count > 0` 且距离非 0
  - 结果（OPPO `cb2e5863`，MockGps `mock=true`、1 Hz、精度 4 m）：修复前 workout 7 / 8 `point_count = 0`；修复后 workout 9 为 2:12 / 903.9 m / 126 点，清洁构建 workout 10 为 0:52 / 330.0 m / 47 点；日志确认连续定位回调未被预览超时打断
  - 遗留：MockGps 只验证链路，4.4 仍需户外真机对照
- [ ] 5.7 更新 tasks 状态并提交（需用户同意）

### Exit Gate
> 高德源在 MockGps 下能落点、能累计距离；系统源行为不变；4.4 的真机对照仍需用户在户外完成。

---

## Phase 6: 修复 K40（Android 13）后台闪退

### Entry Gate
> 用户在 Redmi K40（`192.168.1.2:42315`，Android 13 / targetSdk 36）实测报告闪退。
> 证据：`dumpsys dropbox --print data_app_crash` 三条 `ForegroundServiceDidNotStartInTimeException`
> （2026-11-05 08:32、08:56、13:14，均为 `RecordingForegroundService`），
> 以及 `data_app_wtf` 的 `Background started FGS: Disallowed [uidState: LAST; code:DENIED]`。

### Tasks
- [x] 6.1 单测先复现：看门狗重建订阅不得重复拉起 / 提前回收前台服务；前台服务启动失败时定位流照常工作
  - Spec: `### Requirement: 试点源保持后台持续记录与看门狗` → `#### Scenario: 后台重建订阅不重启前台服务`、`#### Scenario: 后台启动前台服务被拒绝`
- [x] 6.2 改 `lib/data/location/amap_location_platform.dart`：活跃订阅计数 + 记录期只拉起一次 + 全部退订后 2 秒延迟回收
  - 真因：`_restartStalledFixStream` 是「取消旧订阅 → 立刻重订阅」，原实现在 cancel 里无条件 `stop` 前台服务、重订阅又 `start`；熄屏骑行时重建发生在后台，Android 12+ / MIUI 拒绝后台启动前台服务，随后系统抛 `ForegroundServiceDidNotStartInTimeException` 杀进程
- [x] 6.3 原生兜底：`MainActivity` 捕获启动异常并返回平台错误；`RecordingForegroundService.onStartCommand` 失败时 `stopSelf()`，避免系统超时判定
- [x] 6.4 `fvm flutter analyze` 与 `fvm flutter test` 全通过
  - 结果：`flutter analyze` 无问题；全量 907 条测试通过
- [x] 6.5 K40 真机复测：高德源开始记录 → 切后台 + 关闭系统定位制造断流 → 等 90 秒
  - 结果：进程存活（pid 不变），`RecordingForegroundService` 仍 `isForeground=true`，日志无 `Disallowed` / `ForegroundServiceDidNotStart`；`exit-info` 无新增崩溃；结束后服务按延迟回收
- [x] 6.6 更新 verification 文档的崩溃小节与复现步骤

### Exit Gate
> 后台断流下不再闪退；高德源记录、落点、服务回收均正常；4.4 户外对照仍需用户完成。

---

## Completion Tracking

| Phase | Tasks | Completed | Status |
|-------|-------|-----------|--------|
| Phase 1 | 7 | 7 | COMPLETE |
| Phase 2 | 7 | 6 | IN_PROGRESS |
| Phase 3 | 11 | 11 | COMPLETE |
| Phase 4 | 8 | 5 | IN_PROGRESS |
| Phase 5 | 7 | 6 | IN_PROGRESS |
| Phase 6 | 6 | 6 | COMPLETE |
| **Total** | **46** | **41** | **89%** |

**Status values:** `PENDING` → `IN_PROGRESS` → `COMPLETE`
