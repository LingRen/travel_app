# 地图 SDK 迁移实施计划

> **For the agent:** REQUIRED SKILL: use `/opsx-apply` to implement this plan.

**Goal:** 在保留无 Key 可运行的前提下，把记录页与详情页底图切到高德原生地图 SDK，并用自定义样式呈现纸色外观。

**Architecture:** 对外仍暴露 `LiveRouteMap` / `RouteMap`，内部按 `mapBackendProvider` 选择 `amap` 或 `legacy`。原生后端只负责底图，轨迹与标记继续由 Flutter 覆盖层按相机投影绘制；GCJ-02 转换仍只在显示层发生。

**Tech Stack:** Flutter 3.47.4、`amap_flutter_map`（候选，以 Task 1 结论为准）、`flutter_map`（legacy 回落）、`flutter_riverpod`。

**Related Documents:**
- Design: `openspec/changes/map-sdk-migration/design.md`
- Specs: `openspec/changes/map-sdk-migration/specs/map-basemap/spec.md`、`specs/recording/spec.md`、`specs/activity-review/spec.md`、`specs/settings/spec.md`

---

## Task 1: 插件可行性 spike（先于编码）

**Spec Reference:** 无（技术前置，失败则停止本变更并回报）

**Files:**
- 临时改动：`pubspec.yaml`、`lib/main.dart`（spike 后还原或转为正式改动）
- 记录：`openspec/changes/map-sdk-migration/design.md` 的 Open Questions（结论回填）

### Step 1.1: 验证四项能力

在真机上验证：初始化与隐私声明、默认样式出图、相机移动与读取、页面销毁后释放无泄漏。

**Run:** `tool/run_local.sh -d <device> -t tool/spike_amap.dart`（Key 由脚本从本地配置注入）
**Expected:** 四项全部通过。任一项不通过则停止，不进入 Task 2。

### Step 1.2: 记录结论

把插件版本、最低平台版本、后台/样式限制写回 design 的 Open Questions，再开始编码。

---

## Task 2: 后端选择与配置

**Spec Reference:** `### Requirement: 底图后端按配置选择并可回退`、`### Requirement: Key 与样式配置不进入版本库`、`### Requirement: 地图后端可测试且对页面保持稳定接口`

**Files:**
- Create: `lib/features/map/map_backend.dart`
- Modify: `lib/config/app_config.dart`
- Create: `test/features/map/map_backend_test.dart`

### Step 2.1: 写失败测试（RED）

**Scenario:** `#### Scenario: 配置了 Key`、`#### Scenario: 没有 Key`、`#### Scenario: 强制回退`、`#### Scenario: 后端选择单测`

```dart
// WHEN 覆盖值 / Key / 默认值组合变化
// THEN 选择结果符合真值表
test('legacy override wins even with key', () {
  expect(
    resolveMapBackend(key: 'k', override: 'legacy'),
    MapBackend.legacy,
  );
});
```

**Run:** `fvm flutter test test/features/map/map_backend_test.dart`
**Expected:** FAIL —— `resolveMapBackend` 未定义

### Step 2.2: 实现最小代码（GREEN）

新增枚举与真值表函数；`app_config.dart` 增加 `kAmapMapKey`、`kAmapMapStyleId`、`kMapBackendOverride`；`providers.dart` 暴露 `mapBackendProvider`，测试可 override。

**Run:** 同上
**Expected:** PASS

### Step 2.3: 提交

```bash
git add lib/features/map/map_backend.dart lib/config/app_config.dart lib/app/providers.dart test/features/map/map_backend_test.dart
git commit -m "feat(map-basemap): add backend selection and key config"
```

---

## Task 3: 显示投影工具

**Spec Reference:** `### Requirement: 显示坐标统一转换且落盘保持 WGS-84`、`### Requirement: 地图后端可测试且对页面保持稳定接口`

**Files:**
- Create: `lib/features/map/map_projection.dart`
- Create: `test/features/map/map_projection_test.dart`
- Modify: `lib/features/record/live_route_map.dart`（抽出可复用投影）

### Step 3.1: 写失败测试（RED）

**Scenario:** `#### Scenario: 高德底图上的轨迹`（投影部分）、`#### Scenario: widget 测试`

覆盖：中心点投影到视口中心、南北 / 东西方向正确、纬度变化影响比例、缩放变化影响米/像素。

**Run:** `fvm flutter test test/features/map/map_projection_test.dart`
**Expected:** FAIL

### Step 3.2: 实现（GREEN）

实现 Web Mercator 投影（GCJ-02 输入），提供 `toScreen(point, camera, size)` 与 `metersPerPixel`；沿用现有比例尺公式，避免两套口径。

**Run:** 同上
**Expected:** PASS

### Step 3.3: 提交

```bash
git add lib/features/map/map_projection.dart test/features/map/map_projection_test.dart
git commit -m "feat(map-basemap): add Web Mercator screen projection for overlays"
```

---

## Task 4: 记录页原生地图体

**Spec Reference:** `### Requirement: 地图采用纸色滤镜并保留轨迹辨识`、`### Requirement: 实时地图标出起点与朝向`、`### Requirement: 地图显示方向与比例参照`、`### Requirement: 地图加载失败时降级而不阻断记录`

**Files:**
- Create: `lib/features/map/amap_basemap.dart`
- Modify: `lib/features/record/live_route_map.dart`
- Modify: `lib/features/record/handlebar_view.dart`、`lib/features/record/record_page.dart`（如果参数需要后端）
- Test: `test/features/record/record_views_test.dart`、`test/features/map/amap_basemap_test.dart`（假实现 / 初始化失败分支）

### Step 4.1: 写失败 widget 测试（RED）

**Scenario:** `#### Scenario: 无 Key 回落`、`#### Scenario: 原生后端下的标记`（legacy 对照）、`#### Scenario: 原生后端跟随`（逻辑层）

现有 `live-route-map`、`map-heading-arrow`、`map-north`、`map-scale-bar` 断言保持不变，并显式 override `mapBackendProvider: MapBackend.legacy`。

**Run:** `fvm flutter test test/features/record/record_views_test.dart`
**Expected:** FAIL —— 新标记 / 选择逻辑缺失

### Step 4.2: 实现（GREEN）

- `LiveRouteMap` 拆成 `_LegacyBody` 与 `_AmapBody`；`_AmapBody` 用 `AMapWidget` + Flutter 覆盖层，保持 320 ms 相机跟随与朝向最短弧。
- `amap_basemap.dart` 单点完成隐私声明、初始化、样式二进制、销毁；失败时返回纸色占位与「地图暂时不可用」。
- 无 Key 路径完全沿用现有 `FlutterMap` 代码。

**Run:** 同上 + `fvm flutter analyze`
**Expected:** PASS，无告警

### Step 4.3: 提交

```bash
git add lib/features/map/amap_basemap.dart lib/features/record/live_route_map.dart test/features/record/record_views_test.dart
git commit -m "feat(map-basemap): render live map with native basemap and flutter overlays"
```

---

## Task 5: 详情页原生地图体

**Spec Reference:** `### Requirement: 详情页提供返回、类型与地图`、`### Requirement: 详情地图标出起点与终点`

**Files:**
- Modify: `lib/features/detail/route_map.dart`
- Modify: `lib/features/detail/detail_page.dart`（仅参数口径）
- Test: `test/features/detail/detail_page_test.dart`

### Step 5.1: 写失败测试（RED）

**Scenario:** `#### Scenario: 无 Key 回落`、`#### Scenario: 原生后端下的断口`

保持 `detail-map-color-filter`（legacy）、起终点、断口端点、260dp / 45% 高度断言；新增「短缺口虚线」在 legacy 下的表达断言。

**Run:** `fvm flutter test test/features/detail/detail_page_test.dart`
**Expected:** FAIL（原生分支尚未接入）

### Step 5.2: 实现（GREEN）

`RouteMap` 同样拆 `_LegacyBody` / `_AmapBody`；详情相机支持拖动缩放，`onCameraMove` 刷新覆盖层；起终点与断口沿用现有绘制组件。

**Run:** 同上
**Expected:** PASS

### Step 5.3: 提交

```bash
git add lib/features/detail/route_map.dart lib/features/detail/detail_page.dart test/features/detail/detail_page_test.dart
git commit -m "feat(map-basemap): render detail map with selectable basemap backend"
```

---

## Task 6: 设置页移除瓦片源

**Spec Reference:** `### Requirement: 地图与外观分组显示底图状态与主题色`、`### Requirement: 设置项不暴露开发用的地图地址`

**Files:**
- Modify: `lib/features/settings/settings_page.dart:75-81,157-182`
- Modify: `test/features/settings/settings_page_test.dart`

### Step 6.1: 写失败测试（RED）

**Scenario:** `#### Scenario: 配置了地图 Key`、`#### Scenario: 没有地图 Key`、`#### Scenario: 选择青瓷`、`#### Scenario: 发布构建浏览设置`

断言 `settings-tile` 消失、`settings-basemap` 显示「高德地图」或「内置栅格底图」、无 URL 输入、主题色仍可保存。

**Run:** `fvm flutter test test/features/settings/settings_page_test.dart`
**Expected:** FAIL

### Step 6.2: 实现（GREEN）

移除 `_editTileUrl` 与 URL 校验；新增只读 `_SettingsRow`；`AppSettings.mapTileUrlTemplate` 保留读取以兼容旧库，但不再写入与显示。

**Run:** 同上
**Expected:** PASS

### Step 6.3: 提交

```bash
git add lib/features/settings/settings_page.dart test/features/settings/settings_page_test.dart
git commit -m "feat(settings): replace editable tile source with read-only basemap row"
```

---

## Task 7: 本地 Key、README 与发版配置

**Spec Reference:** `### Requirement: Key 与样式配置不进入版本库`

**Files:**
- Create: `config/amap_map_key.example.txt`
- Modify: `.gitignore`、`tool/run_local.sh`
- Modify: `README.md`（「地图瓦片源」章节 → 「地图与 Key」，技术栈与地图描述）
- Modify: `.github/workflows/release.yml`（如存在 release 构建注入位）

### Step 7.1: 写验证清单

确认：示例文件可提交、真实文件被忽略、run_local 在缺文件时不注入、release 缺 Key 仍构建成功。

**Run:** `git status --ignored`、`fvm flutter build apk --release --build-number=10000`
**Expected:** 真实 Key 被忽略；release 构建成功并回落 legacy

### Step 7.2: 实现文档与脚本

更新 README：有 Key 时高德原生底图、无 Key 时内置栅格；删除「用户可换瓦片源」的承诺；补充 Android SHA1 / iOS Bundle ID 绑定与排障。

### Step 7.3: 提交

```bash
git add config/amap_map_key.example.txt .gitignore tool/run_local.sh README.md
git commit -m "docs(map-basemap): document native map key setup and fallback"
```

---

## Task 8: 真机验证与回归

**Spec Reference:** `### Requirement: 纸色底图由地图样式提供`、`### Requirement: 地图加载失败时降级而不阻断记录`、`### Requirement: 显示坐标统一转换且落盘保持 WGS-84`

**Files:**
- Create: `openspec/verification/2026-11-02-map-sdk-migration.md`

### Step 8.1: 自动化回归

**Run:** `fvm flutter analyze && fvm flutter test`
**Expected:** `No issues found!`、`All tests passed!`

### Step 8.2: 真机清单

1. 有 Key：记录 30 分钟，确认纸色样式、相机跟随、箭头、起点、断口；截图与设计稿比对。
2. 详情页：拖动缩放、起终点、短缺口虚线、断口端点、矮视口 45% 高度。
3. 坐标对齐：同一路段与 legacy 截图叠加比对，确认无整体偏移。
4. 无 Key / 错误 Key：两张地图、记录与详情均可用，出现「地图暂时不可用」而非崩溃。
5. 性能：记录 30 分钟，观察掉帧与耗电，确认无明显退化。

### Step 8.3: 记录结论并提交

把真机结果写入验证文档；未通过项回到对应任务修复，不勾选完成。

```bash
git add openspec/verification/2026-11-02-map-sdk-migration.md
git commit -m "docs(map-basemap): record device verification"
```
