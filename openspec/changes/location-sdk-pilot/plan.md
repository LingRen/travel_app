# 高德定位试点实施计划

> **For the agent:** REQUIRED SKILL: use `/opsx-apply` to implement this plan.

**Goal:** 在不改变默认定位源与记录逻辑的前提下，把高德定位接入 `LocationPlatform` 试点，并以真机对照数据决定是否转正。

**Architecture:** `LocationService` 继续只依赖 `LocationPlatform`；新增 `AmapLocationPlatform` 在出口把 GCJ-02 转成 WGS-84，并在共享出口统一应用 50 m 精度门槛。定位源由 debug 开关或 `LOCATION_PROVIDER` 选择，默认 `system`。

**Tech Stack:** Flutter 3.47.4、`geolocator`（默认 / 回滚）、`amap_flutter_location`（候选，以 Task 1 结论为准）、`flutter_riverpod`。

**Related Documents:**
- Design: `openspec/changes/location-sdk-pilot/design.md`
- Specs: `openspec/changes/location-sdk-pilot/specs/location-acquisition/spec.md`、`specs/recording/spec.md`、`specs/settings/spec.md`
- 依赖：`openspec/changes/map-sdk-migration`（共用原生 Key 与平台配置）

---

## Task 1: 插件与后台能力 spike（先于编码）

**Spec Reference:** `### Requirement: 试点源保持后台持续记录与看门狗`

**Files:**
- 临时改动：`pubspec.yaml`、`lib/data/location/location_service.dart`
- 记录：design 的 Open Questions（结论回填）

### Step 1.1: 验证四项能力

1. 初始化与隐私声明调用顺序；
2. 1 Hz 连续定位与 GCJ-02 输出字段；
3. Android 锁屏 30 分钟是否持续回调，是否自带后台通知；
4. iOS 后台定位 capability 与回调。

**Run:** `fvm flutter run --dart-define=LOCATION_PROVIDER=amap --dart-define=AMAP_MAP_KEY=<key>`
**Expected:** 四项通过。后台不通过则先评估应用级前台服务；仍不通过则停止任务 2 之后的编码，保留设计结论。

### Step 1.2: 记录结论

把插件版本、后台方案、通知 API 写回 design；决定是否需要新增原生前台服务任务。

---

## Task 2: GCJ-02 → WGS-84 逆变换

**Spec Reference:** `### Requirement: 高德定位结果归一为 WGS-84`

**Files:**
- Modify: `lib/domain/analysis/gcj02.dart`
- Create: `test/domain/analysis/gcj02_inverse_test.dart`

### Step 2.1: 写失败测试（RED）

**Scenario:** `#### Scenario: 记录落盘`、`#### Scenario: 导出 GPX`（坐标断言）

```dart
// WHEN 取成都、北京、海岸线附近的 GCJ-02 点
// THEN 逆变换回 WGS-84 后与原 WGS-84 往返误差 ≤2 m
test('gcj02ToWgs84 round-trips within 2 m', () { ... });
```

**Run:** `fvm flutter test test/domain/analysis/gcj02_inverse_test.dart`
**Expected:** FAIL —— `gcj02ToWgs84` 未定义

### Step 2.2: 实现（GREEN）

迭代逆变换（最多 5 次或 1e-7 度收敛），处理边界与非法值；不修改现有 `wgs84ToGcj02` 行为。

**Run:** 同上
**Expected:** PASS

### Step 2.3: 提交

```bash
git add lib/domain/analysis/gcj02.dart test/domain/analysis/gcj02_inverse_test.dart
git commit -m "feat(location-acquisition): add gcj02 to wgs84 inverse conversion"
```

---

## Task 3: 定位源选择与配置

**Spec Reference:** `### Requirement: 定位源默认使用系统定位并可切换`、`### Requirement: 试点失败可回滚且不改变记录语义`

**Files:**
- Create: `lib/data/location/location_provider.dart`
- Modify: `lib/config/app_config.dart`、`lib/app/providers.dart`、`lib/data/settings_repository.dart`
- Create: `test/data/location/location_provider_test.dart`

### Step 3.1: 写失败测试（RED）

**Scenario:** `#### Scenario: 默认启动`、`#### Scenario: release 忽略调试开关`、`#### Scenario: 高德 Key 缺失`、`#### Scenario: 回滚`

```dart
// WHEN debug 开关 = amap 但处于 release
// THEN 选择 system
test('release ignores persisted debug provider', () { ... });
```

**Run:** `fvm flutter test test/data/location/location_provider_test.dart`
**Expected:** FAIL

### Step 3.2: 实现（GREEN）

选择顺序：debug 存储值 → `LOCATION_PROVIDER` → `system`；Key 为空时回落；release 不读取 debug 键。`locationServiceProvider` 根据结果构造 `LocationService`。

**Run:** 同上
**Expected:** PASS

### Step 3.3: 提交

```bash
git add lib/data/location/location_provider.dart lib/config/app_config.dart lib/app/providers.dart lib/data/settings_repository.dart test/data/location/location_provider_test.dart
git commit -m "feat(location-acquisition): select location provider with debug override"
```

---

## Task 4: 高德定位平台与精度门槛

**Spec Reference:** `### Requirement: 差精度定位不进入记录`、`### Requirement: 高德定位结果归一为 WGS-84`

**Files:**
- Create: `lib/data/location/amap_location_platform.dart`
- Modify: `lib/data/location/location_service.dart`
- Modify: `lib/domain/analysis/constants.dart`
- Test: `test/data/location/location_service_test.dart`、`test/data/location/amap_location_platform_test.dart`

### Step 4.1: 写失败测试（RED）

**Scenario:** `#### Scenario: 基站级定位`、`#### Scenario: 精度恢复`、`#### Scenario: 记录落盘`

用假 `LocationPlatform` 依次送 800 m、8 m 精度点，断言 `fixes()` 只输出后者；断言高德点出口坐标已转 WGS-84。

**Run:** `fvm flutter test test/data/location/location_service_test.dart test/data/location/amap_location_platform_test.dart`
**Expected:** FAIL

### Step 4.2: 实现（GREEN）

新增 `kMaxAcceptedAccuracyM = 50.0`；在 `LocationService.fixes()` 共享出口过滤；新增 `AmapLocationPlatform`，映射字段并做逆变换，`quickPreviewFix` 失败时回退系统一次。

**Run:** 同上
**Expected:** PASS

### Step 4.3: 提交

```bash
git add lib/data/location/amap_location_platform.dart lib/data/location/location_service.dart lib/domain/analysis/constants.dart test/data/location
git commit -m "feat(location-acquisition): add amap platform and accuracy gate"
```

---

## Task 5: Debug 定位源开关

**Spec Reference:** `### Requirement: 定位源默认使用系统定位并可切换`、`### Requirement: 调试工具只在调试构建出现`、`### Requirement: 定位源切换不改变记录状态语义`

**Files:**
- Modify: `lib/features/settings/settings_page.dart`（`_DebugSection`）
- Modify: `lib/features/record/record_controller.dart`（记录中只读判定）
- Test: `test/features/settings/settings_page_test.dart`、`test/features/record/record_controller_test.dart`

### Step 5.1: 写失败测试（RED）

**Scenario:** `#### Scenario: 调试构建切换定位源`、`#### Scenario: 发布构建`、`#### Scenario: 记录中不可切换`、`#### Scenario: 切换后开始记录`

断言 debug 出现 `settings-location-provider`、release 不出现、记录中行不可点；切换后 `locationServiceProvider` 失效且旧流被取消。

**Run:** `fvm flutter test test/features/settings/settings_page_test.dart test/features/record/record_controller_test.dart`
**Expected:** FAIL

### Step 5.2: 实现（GREEN）

debug 分组增加定位源行，仅待机可点；保存后 invalidate `locationServiceProvider`；切换时先 `dispose` 旧订阅再起新流，并重置看门狗计时。

**Run:** 同上
**Expected:** PASS

### Step 5.3: 提交

```bash
git add lib/features/settings/settings_page.dart lib/features/record/record_controller.dart test/features/settings/settings_page_test.dart test/features/record/record_controller_test.dart
git commit -m "feat(location-acquisition): add debug-only location provider switch"
```

---

## Task 6: 后台持续记录与看门狗

**Spec Reference:** `### Requirement: 试点源保持后台持续记录与看门狗`、`### Requirement: 定位源切换不改变记录状态语义`

**Files:**
- Modify: Android：`android/app/src/main/AndroidManifest.xml`、按 spike 结论新增前台服务 Kotlin 文件或配置插件后台模式
- Modify: iOS：`ios/Runner/Info.plist`、Xcode capability
- Modify: `lib/data/location/amap_location_platform.dart`、`lib/features/record/record_controller.dart`
- Test: `test/features/record/record_controller_test.dart`（看门狗 / 暂停分支）

### Step 6.1: 写失败测试（RED）

**Scenario:** `#### Scenario: 锁屏记录`（手动）、`#### Scenario: 定位回调假死`、`#### Scenario: 暂停期间无定位`

用假时钟与假流断言 15 秒无回调触发重建、暂停期间不重建。

**Run:** `fvm flutter test test/features/record/record_controller_test.dart`
**Expected:** FAIL（新 provider 的重建路径尚未接通）

### Step 6.2: 实现（GREEN）

按 spike 结论接后台方案；高德流的重建实现为销毁并重新创建客户端；保持「运动记录中 / 正在记录轨迹与心率」通知文案；暂停期间不重建。

**Run:** 同上 + `fvm flutter analyze`
**Expected:** PASS

### Step 6.3: 提交

```bash
git add android ios lib/data/location/amap_location_platform.dart lib/features/record/record_controller.dart test/features/record/record_controller_test.dart
git commit -m "feat(location-acquisition): keep background recording with amap provider"
```

---

## Task 7: 真机试点对照

**Spec Reference:** `### Requirement: 试点结论以对照数据决定`、`### Requirement: 试点失败可回滚且不改变记录语义`

**Files:**
- Create: `openspec/verification/2026-11-02-location-sdk-pilot.md`

### Step 7.1: 自动化回归

**Run:** `fvm flutter analyze && fvm flutter test`
**Expected:** `No issues found!`、`All tests passed!`

### Step 7.2: 配对骑行

同设备、同路线，系统 / 高德各 3 次，至少 10 km；记录空档数、断点数、距离、爬升、异常跳变、锁屏断流、耗电。

**Expected:** 全部满足设计第「试点成功标准」表；不足 3 组不判通过。

### Step 7.3: 结论与回滚

达标：在验证文档写明可讨论切换默认值；未达标：保持 `system` 默认并把开关限制在 debug。任何情况下都确认切回 `system` 无需数据迁移。

### Step 7.4: 记录并提交

```bash
git add openspec/verification/2026-11-02-location-sdk-pilot.md
git commit -m "docs(location-acquisition): record pilot comparison results"
```

---

## Task 8: 文档与收尾

**Spec Reference:** `### Requirement: 定位源默认使用系统定位并可切换`、`### Requirement: 高德定位结果归一为 WGS-84`

**Files:**
- Modify: `README.md`

### Step 8.1: 更新 README

补充：`LOCATION_PROVIDER` 用法、debug 开关、试点状态（未达标/达标）、GPX 仍为 WGS-84、回滚方式、隐私说明。

### Step 8.2: 提交

```bash
git add README.md
git commit -m "docs(location-acquisition): document location provider pilot and rollback"
```
