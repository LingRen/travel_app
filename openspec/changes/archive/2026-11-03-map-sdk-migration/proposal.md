# Proposal

## Why

记录页与详情页的地图现在由 `flutter_map` 叠加高德栅格瓦片（`webrd0{s}.is.autonavi.com`）渲染。这条瓦片地址不是高德开放平台的正式接口，属于随时可能失效的灰色用法；纸色外观也只能在客户端对整层瓦片套 `ColorFiltered`，无法像原生地图样式那样精细控制配色。与此同时，设置页把「地图瓦片源」暴露为可编辑 URL，普通用户既看不懂也无从判断该填什么。

迁移到高德原生地图 SDK 后，底图有了正式的 Key 与样式授权，纸色舆图可以由服务端样式统一控制，地图手势、缩放与渲染也交给原生 SDK。需要提前说明：**这次迁移不会消除「记录断节」**。断节由定位采集空档与 `kGpsGapMs` / `kGapBridgeMaxMs` / `kGapBreakMinDistanceM` 判定，属于 provider 无关的记录逻辑；换底图只影响「底图是否可靠、是否像纸」，不影响一个定位点有没有被采到。

## What Changes

- 记录页实时地图与详情页地图改用高德原生地图 SDK（Android / iOS platform view），保留现有的轨迹、起终点、断口与朝向表达。
- 纸色外观改由高德自定义地图样式二进制（`style.data` / `style_extra.data`）实现；原生后端不再使用整层 `ColorFiltered`。
- 新增底图后端选择：配置了高德地图 Key 时使用原生 SDK；未配置 Key 时自动回落到现有 `flutter_map` 栅格实现，保证仓库在没有 Key 的环境下仍能构建、运行与跑测试。
- 新增 `AMAP_MAP_KEY_ANDROID` / `AMAP_MAP_KEY_IOS` 的 `--dart-define` 注入；Android 按包名 + SHA1（debug / release 各自绑定），iOS 按 Bundle ID 绑定。Key 不进入版本库。
- 首次使用原生地图前展示隐私同意弹窗，同意后才以完整合规声明初始化 SDK；拒绝时继续使用 legacy 底图。
- 设置页移除「地图瓦片源」可编辑行，改为只读「底图」说明（高德地图 / 未配置 Key 时的内置栅格底图）。保留主题色选择。
- 显示坐标口径不变：落盘、统计与 GPX 始终是 WGS-84；仅绘制到 GCJ-02 底图时做显示转换，轨迹不得整体偏移。
- **BREAKING**（仅对开发配置）：不再支持用户自定义瓦片 URL；已有 `map_tile_url` 设置值不再影响底图，升级后忽略。

## Capabilities

### New Capabilities

- `map-basemap`: 定义底图后端选择、Key 配置与缺失回落、纸色地图样式、加载失败降级、显示坐标口径与可测试性。

### Modified Capabilities

- `recording`: 实时地图改由底图后端渲染，纸色由地图样式实现；被动跟随、断点断开、起点 / 朝向 / 指北 / 比例尺的行为保持不变。
- `activity-review`: 详情地图改由底图后端渲染，起终点、断口端点、260dp / 45% 矮视口高度保持不变。
- `settings`: 「地图与外观」分组移除可编辑瓦片源，改为只读底图行。

## Impact

- 受影响的规格：`map-basemap`（新增）、`recording`、`activity-review`、`settings`。
- 受影响的代码：`lib/features/record/live_route_map.dart`、`lib/features/detail/route_map.dart`、`lib/features/record/handlebar_view.dart`、`lib/features/record/record_page.dart`、`lib/features/detail/detail_page.dart`、`lib/app/providers.dart`、`lib/data/settings_repository.dart`、`lib/features/settings/settings_page.dart`、`lib/config/app_config.dart`、`pubspec.yaml`、Android / iOS 原生配置。
- 依赖：新增高德官方 Flutter 地图插件（候选 `amap_flutter_map`，以 spike 结论为准）；`flutter_map` / `latlong2` 保留为无 Key 回落后端。
- 测试：现有地图相关 widget 测试改为强制 legacy 后端运行；新增后端选择、缺 Key 回落、设置底图行与坐标转换口径的测试。原生地图渲染仍需真机手动验证。
- 文档：`README.md` 的「地图瓦片源」章节改为「地图与 Key」；技术栈表更新。
- 外部配置：高德开放平台新建 Android / iOS 应用并绑定 debug、release 签名；申请自定义地图样式 ID。

## Non-Goals

- 不接入在线路况、导航、搜索或轨迹编辑。
- 不更换定位 SDK，不调整断点阈值与距离 / 爬升算法。
- 不改变落盘坐标系、GPX 或数据库结构。
- 不为地图新增账号、云同步或服务端代理。
