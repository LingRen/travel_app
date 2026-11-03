# Implementation Tasks for map-sdk-migration

## Status
- Total Tasks: 36
- Completed: 26
- In Progress: 0
- Pending: 10

---

## Phase 1: 可行性确认与后端选择

### Entry Gate
> 先读 `plan.md` Task 1-3 与 `specs/map-basemap/spec.md`，确认插件 spike 结论已回填 design。

### Tasks
- [x] 1.1 在 Android 真机验证候选插件初始化、隐私声明、默认样式、相机读取与销毁（iOS 暂缓）
  - Spec: 技术前置；失败则停止并回报，不进入 1.2
  - 结果：OPPO R9s Plus（API 25）通过；样式只支持二进制，不支持 styleId
- [x] 1.2 把插件版本、最低平台版本与限制回填 `design.md` Open Questions
- [x] 1.3 写 `test/features/map/map_backend_test.dart`，覆盖「配置了 Key / 没有 Key / 强制回退」
  - Spec: `### Requirement: 底图后端按配置选择并可回退` → 三个 Scenario
- [x] 1.4 新增 `lib/features/map/map_backend.dart` 的 `MapBackend` 与 `resolveMapBackend`
- [x] 1.5 在 `lib/config/app_config.dart` 增加平台 Key、`kAmapMapStyleAsset`、`kMapBackendOverride`
- [x] 1.6 在 `lib/app/providers.dart` 暴露 `mapBackendProvider`（可在测试 override）
- [x] 1.7 运行 `fvm flutter test test/features/map/map_backend_test.dart` 与 `fvm flutter analyze`
- [ ] 1.8 提交：`feat(map-basemap): add backend selection and key config`

### Exit Gate
> 更新本文件状态与完成表；运行 `openspec validate map-sdk-migration --type change --strict`；提交。

---

## Phase 2: 投影工具与记录页原生地图

### Entry Gate
> 读 `plan.md` Task 3-4、`specs/recording/spec.md`；确认 1.1 通过。

### Tasks
- [x] 2.1 写 `test/features/map/map_projection_test.dart`：中心点、方向、缩放与米/像素
  - Spec: `### Requirement: 显示坐标统一转换且落盘保持 WGS-84` → `#### Scenario: 高德底图上的轨迹`
- [x] 2.2 新增 `lib/features/map/map_projection.dart`，实现 Web Mercator 屏幕投影
- [x] 2.3 抽出 `LiveRouteMap` 现有比例尺与标记几何，供两套地图体复用
- [x] 2.4 写 `test/features/record/record_views_test.dart` 的后端 override 与标记断言
  - Spec: `### Requirement: 实时地图标出起点与朝向` → `#### Scenario: 原生后端下的标记`
- [x] 2.5 新增 `lib/features/map/amap_basemap.dart`：初始化、隐私声明、样式二进制、失败占位、销毁
- [x] 2.6 在 `LiveRouteMap` 拆出 `_LegacyBody` 与 `_AmapBody`，保持 320 ms 跟随与最短弧朝向
  - Spec: `### Requirement: 地图显示方向与比例参照` → `#### Scenario: 原生后端跟随`
- [x] 2.7 无 Key 路径确认仍走 legacy 且 `live-route-map` / `map-heading-arrow` 等 Key 可用
  - Spec: `### Requirement: 地图后端可测试且对页面保持稳定接口` → `#### Scenario: widget 测试`
- [x] 2.8 运行记录页 widget 测试与 `fvm flutter analyze`
- [x] 2.9 读取 `assets/amap/style.data` / `style_extra.data` 并传给 `CustomStyleOptions`，缺失时用默认样式
  - Spec: `### Requirement: 纸色底图由自定义地图样式二进制提供` → 两个 Scenario
- [x] 2.10 新增首启隐私同意弹窗：同意后持久化并初始化 SDK，拒绝时保持 legacy
  - Spec: `### Requirement: 地图 SDK 初始化前取得隐私同意` → 三个 Scenario
- [ ] 2.11 提交：`feat(map-basemap): render live map with native basemap and flutter overlays`

### Exit Gate
> 更新状态；确认无 Key 与有 Key（真机）两条路径都可用；提交。

---

## Phase 3: 详情页、设置页与配置

### Entry Gate
> 读 `plan.md` Task 5-7 与 `specs/activity-review/spec.md`、`specs/settings/spec.md`。

### Tasks
- [x] 3.1 写 `test/features/detail/detail_page_test.dart`：legacy 回落、起终点、断口、矮视口
  - Spec: `### Requirement: 详情地图标出起点与终点` → 三个 Scenario
- [x] 3.2 在 `RouteMap` 拆出 `_LegacyBody` / `_AmapBody`，接入 `onCameraMove` 刷新覆盖层
- [x] 3.3 写 `test/features/settings/settings_page_test.dart`：底图只读行、无 URL 输入、主题色仍可用
  - Spec: `### Requirement: 地图与外观分组显示底图状态与主题色` → 三个 Scenario
- [x] 3.4 修改 `settings_page.dart`：移除 `settings-tile` 与 `_editTileUrl`，新增 `settings-basemap`
- [x] 3.5 保留 `mapTileUrlTemplate` 读取兼容旧库，停止写入与显示
- [x] 3.6 新增平台 Key 本地文件示例、`.gitignore` 规则、`tool/run_local.sh` 分别注入
  - Spec: `### Requirement: Key 与样式配置不进入版本库` → `#### Scenario: 本地开发注入`
- [x] 3.7 更新 `README.md` 地图章节、技术栈与无 Key 说明
- [x] 3.8 运行设置页 / 详情页测试与 `fvm flutter analyze`
- [ ] 3.9 提交：`feat(settings): replace editable tile source with read-only basemap row` 与 `docs(map-basemap): document native map key setup and fallback`

### Exit Gate
> 更新状态；确认 release 缺 Key 仍构建成功；提交。

---

## Phase 4: 真机验证与收尾

### Entry Gate
> 读 `plan.md` Task 8 与 `specs/map-basemap/spec.md` 的降级、样式、坐标要求。

### Tasks
- [x] 4.1 `fvm flutter analyze` 与 `fvm flutter test` 全通过
  - 结果：`No issues found!`；865 条测试全部通过
- [ ] 4.2 真机有 Key：记录 30 分钟，确认纸色样式、跟随、箭头、起点、断口
  - Spec: `### Requirement: 纸色底图由自定义地图样式二进制提供` → `#### Scenario: 提供了样式二进制`
- [ ] 4.3 真机无 Key / 错误 Key：两页地图可用或显示「地图暂时不可用」，记录不断
  - Spec: `### Requirement: 地图加载失败时降级而不阻断记录` → 两个 Scenario
- [ ] 4.4 与 legacy 截图叠加，确认轨迹无整体偏移
  - Spec: `### Requirement: 显示坐标统一转换且落盘保持 WGS-84` → `#### Scenario: 高德底图上的轨迹`
- [ ] 4.5 详情页拖动缩放、断口、矮视口验证
- [ ] 4.6 记录 30 分钟观察掉帧与耗电，确认无显著退化
- [ ] 4.7 把结果写入 `openspec/verification/2026-11-02-map-sdk-migration.md`
- [ ] 4.8 提交：`docs(map-basemap): record device verification`

### Exit Gate
> 更新完成表；执行 `/opsx-verify`，通过后再 `/opsx-archive`。

---

## Completion Tracking

| Phase | Tasks | Completed | Status |
|-------|-------|-----------|--------|
| Phase 1 | 8 | 7 | IN_PROGRESS |
| Phase 2 | 11 | 10 | IN_PROGRESS |
| Phase 3 | 9 | 8 | IN_PROGRESS |
| Phase 4 | 8 | 1 | IN_PROGRESS |
| **Total** | **36** | **26** | **72%** |

**Status values:** `PENDING` → `IN_PROGRESS` → `COMPLETE`
