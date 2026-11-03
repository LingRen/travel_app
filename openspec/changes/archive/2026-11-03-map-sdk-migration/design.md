# Design: 地图底图迁移到高德原生 SDK

## Context

当前两张地图都由 `flutter_map` 渲染：

- 记录页 [live_route_map.dart](file:///Users/ling/code/travel_app/lib/features/record/live_route_map.dart) 铺满整页、不响应手势，靠 `MapController` 每拍把相机平移到最新点。
- 详情页 [route_map.dart](file:///Users/ling/code/travel_app/lib/features/detail/route_map.dart) 一次性按轨迹包围盒取景，允许拖动与缩放。
- 底图是高德栅格瓦片，地址存在设置里（`kDefaultMapTileUrlTemplate`），属于非官方接口。
- 纸色外观用两层 `ColorFiltered`：降饱和矩阵 + 纸色薄罩；轨迹、起点、箭头、断口、指北、比例尺都是 Flutter 图层。
- 坐标口径由 `isGcj02TileSource(tileUrl)` 决定：GCJ-02 源才把 WGS-84 轨迹转过去；落盘与 GPX 始终 WGS-84。
- 断点规则在 `signalGapKind` / `isMeaningfulGap`，与底图无关：10 秒以上才可能是缺口，10~30 秒且位移 ≥20 m 画虚线，超过 30 秒断开。换底图不会改变任何断点。

约束：

- 纯本地应用；无账号、无服务端。地图请求仍会联网，但记录数据不出本机。
- 仓库必须能在没有 Key 的环境构建、运行、跑测试；Key 不能进版本库。
- 现有 widget 测试不能启动 platform view，也不能访问网络。
- 记录页每秒都有新定位与相机移动；底图切换不能增加明显卡顿。
- 设计稿的纸色外观、轨迹描边、起终点、断口表达要保持。

## Goals / Non-Goals

### Goals

- 有 Key 时用高德原生地图 SDK 渲染底图，纸色由自定义地图样式提供。
- 无 Key 或显式指定时回落到现有 `flutter_map` 栅格实现，功能不缺失。
- 记录页的被动跟随、详情页的拖动缩放、断口与标记的视觉保持不变。
- 坐标口径不产生偏移：底图为 GCJ-02，落盘 / 统计 / GPX 仍为 WGS-84。
- 设置页不再暴露瓦片 URL；主题色选择保留。
- 地图 widget 在测试中可稳定运行（强制 legacy 后端）。

### Non-Goals

- 不接入路况、导航、POI 搜索、轨迹编辑。
- 不更换定位 SDK、不调整断点阈值。
- 不改数据库、备份 schema、GPX。
- 不实现离线地图包或瓦片缓存策略。

## Approaches Considered

### Approach A: 原生 SDK 作为唯一后端，删除 flutter_map

**Pros:**

- 代码路径唯一，依赖更少，视觉与行为只有一套。
- 没有回落分支需要维护。

**Cons:**

- 没有 Key 时应用无法显示地图，违背「仓库无 Key 也能运行」的既有约束。
- 测试无法构建 platform view；所有地图 widget 测试需要重写或删除。
- 一旦原生 SDK 出现回归，没有可切换的退路。

### Approach B: Key 驱动的双后端，legacy 回落（推荐）

**Pros:**

- 有 Key 用正式底图与样式；无 Key 自动回到现有实现，开发与测试不受影响。
- 原生 SDK 出问题时可以用 `MAP_BACKEND=legacy` 立即回退，不需要改代码。
- 现有轨迹几何、断点、标记的纯逻辑继续复用。

**Cons:**

- 两套地图体需要同时维护，`flutter_map` 短期无法移除。
- 两套渲染的视觉一致性需要真机比对。

### Approach C: 保留栅格瓦片，只换成自建 / OSM 源

**Pros:**

- 改动最小，不引入原生依赖与 Key。

**Cons:**

- 仍是栅格 + 客户端滤镜，无法使用原生样式；国内底图细节与可用性下降。
- 没有解决非官方瓦片接口的失效风险。

## Decision

**Chosen Approach:** B —— Key 驱动的双后端，legacy 回落。

**Rationale:**

- 用户要的是「更可靠的纸色底图」，不是「必须删掉 flutter_map」。双后端同时满足正式底图与无 Key 可运行两个硬约束。
- `LocationPlatform` 式的可替换结构在本项目已有先例；地图也按同样方式隔离平台差异，记录与详情只依赖一个「地图体」。
- 测试环境天然没有地图 Key，自动走 legacy，不需要大范围改测试夹具。

## Trade-offs

- 接受短期同时维护两套地图体：`flutter_map` 继续承载无 Key 与测试路径，等原生路径在真机稳定若干版本后再评估删除。
- 接受原生 SDK 的包体增量与平台配置成本，换取正式授权底图和样式能力。
- 原生 platform view 无法被 `ColorFiltered` 处理，因此纸色只能依赖自定义地图样式二进制；没有样式文件时外观会退回 SDK 默认样式，这是可接受的降级。
- 原生地图上的标记与轨迹优先用 Flutter 覆盖层绘制，以保住现有视觉与测试 Key；代价是需要自己做坐标到屏幕的投影。若 spike 证明投影与 SDK 相机存在可见漂移，再退回 SDK 原生标记。

## Technical Details

### Architecture

```text
record_page / detail_page
        |
        v
LiveRouteMap / RouteMap            (对外 widget 名称与参数不变)
        |
        +-- mapBackendProvider ----> MapBackend.amap   (有 Key)
        |                               |
        |                               +-- AmapBasemap (platform view, styleData)
        |                               +-- Flutter overlay: 轨迹 / 标记 / 断口 / 指北 / 比例尺
        |
        +--------------------------> MapBackend.legacy  (无 Key 或显式回退)
                                        |
                                        +-- 现有 flutter_map TileLayer + ColorFiltered
                                        +-- 现有 PolylineLayer / MarkerLayer

纯逻辑：buildRouteSegments / signalGapKind / wgs84ToGcj02 不变
```

### Key Components

- `lib/features/map/map_backend.dart`：`MapBackend` 枚举与选择规则。输入当前平台的 Key（`amapMapKeyFor(defaultTargetPlatform)`）、`MAP_BACKEND` 覆盖值，输出 `amap` / `legacy`。
- `lib/features/map/amap_basemap.dart`：封装 `AMapWidget` 初始化、隐私声明、样式二进制、相机读取与销毁；不向上暴露 SDK 类型。
- `lib/features/map/map_projection.dart`：按相机中心、缩放与视口把 GCJ-02 点换算为屏幕坐标，供 Flutter 覆盖层使用；纯函数，可单测。
- `LiveRouteMap` / `RouteMap`：拆出 `_LegacyBody` 与 `_AmapBody`，共享顶点、断口、标记数据；对页面保持现有构造参数与 `Key`。
- `SettingsRepository`：保留 `mapTileUrlTemplate` 字段读取（旧库兼容），但不再写入、不再暴露 UI；新增不落库的 `MapBackend` 选择完全由配置决定。
- `lib/config/app_config.dart`：新增 `kAmapMapKeyAndroid` / `kAmapMapKeyIos`、`amapMapKeyFor(platform)`、`kAmapMapStyleAsset`、`kMapBackendOverride`。
- `lib/features/privacy/`：首启隐私同意弹窗与本地持久化标记；地图 Key、隐私声明值只在同意后传给 SDK。

### Backend Selection

| 条件 | 结果 |
| --- | --- |
| `MAP_BACKEND=legacy` | legacy（最高优先级，用于排障与测试） |
| `MAP_BACKEND=amap` 且 Key 非空 | amap |
| `MAP_BACKEND=amap` 且 Key 为空 | legacy，并在 debug 日志输出一次原因 |
| 未设置 `MAP_BACKEND`、Key 非空 | amap |
| 未设置 `MAP_BACKEND`、Key 为空 | legacy |

- 选择在 provider 创建时计算一次，不随主题色或设置变化重建。
- 记录页与详情页共用同一个 `mapBackendProvider`，避免一页原生一页栅格。

### 坐标口径

- 存储、距离、爬升、GPX：WGS-84，完全不变。
- 底图与覆盖层：统一转 GCJ-02 后再投影。转换仍用 `wgs84ToGcj02`，判定不再依赖「URL 是不是高德域名」。
- 详情页 `gapEnds` / `bridgedGaps` 的转换下标沿用 `buildRouteSegments(toGcj02: true)` 的输出；legacy 后端保留原逻辑。
- 禁止在接入层转换落盘点：一旦把 GCJ-02 写进数据库，GPX 与历史统计会整体偏移。

### 相机与覆盖层

- 记录页：不接收手势；每次新点用 320 ms 补间把相机中心移到最新点。`_AmapBody` 调用 SDK 的相机移动，同时用同一个补间值驱动覆盖层重绘，保证底图与轨迹同步。
- 详情页：首帧按轨迹包围盒取景，允许拖动与缩放；`onCameraMove` 更新覆盖层投影。
- 覆盖层绘制轨迹折线、起点环、当前位置箭头、断口端点、虚线缺口、指北与比例尺；`Key('live-route-map')`、`Key('map-heading-arrow')` 等测试锚点保留。
- 朝向箭头继续按最短弧累计角度；原生后端不假设 SDK 的 Marker 旋转能力，箭头由 Flutter 旋转组件绘制。
- 比例尺由相机缩放与纬度计算，沿用 `_MapScaleBar` 的公式。
- 投影必须验证：取轨迹上若干已知点，比较覆盖层落点与底图道路交点；偏移超过 1 个逻辑像素即视为不通过（真机任务 1.1）。

### 纸色样式

- 高德开放平台的「自定义地图」导出目录里含 `style.data` 与 `style_extra.data` 两个二进制文件；插件只接受这两份二进制（`CustomStyleOptions.styleData` / `styleExtraData`），**不支持按 styleId 拉取**（2026-11-02 spike 结论）。
- 约定资源路径：`assets/amap/style.data`（必需）与 `assets/amap/style_extra.data`（可选）；实现用 `rootBundle` 读取字节后传给 `CustomStyleOptions`，读取失败时用 SDK 默认样式。
- 尚未提供二进制时，`pubspec.yaml` 不声明这两个资源，地图照常以默认样式运行；README 写明从高德控制台下载并放到 `assets/amap/`。
- 原生后端不再套 `ColorFiltered`；`kMapTileColorMatrix` 仅保留给 legacy。
- 未提供样式二进制时使用 SDK 默认样式，并在 README / 设置页底图状态行标注「样式未配置」；不得用客户端滤镜糊在 platform view 上（Android 上会被忽略）。
- 主题色只影响轨迹、标记与界面，不改变底图样式；四套主题共用同一份样式二进制。

### 隐私同意

- 高德 SDK 要求 `hasContains` / `hasShow` / `hasAgree` 全为 true，否则平台视图白屏。
- 首启展示一次隐私弹窗：说明底图请求会联网、记录数据仍只存本机，并给出高德隐私政策链接；用户点「同意」后写入本地标记并初始化 SDK。
- 未同意前不创建 `AMapWidget`，地图区域按 legacy 纸色占位；「不同意」保持 legacy，不阻断记录。
- 弹窗文案与链接集中在一个 widget，便于审查；设置页提供再次查看入口。

### Key 与配置

- Dart 侧：`AMAP_MAP_KEY_ANDROID` / `AMAP_MAP_KEY_IOS`（`String.fromEnvironment`，按运行平台选一个）与 `MAP_BACKEND` 覆盖值；样式改由资源文件提供，不再有 styleId 注入。
- Android：高德 Key 绑定「包名 + SHA1」。debug 与 release 使用不同签名，需要在高德控制台各建一个 Key，或使用同一个 Key 登记两组 SHA1。
- iOS：Key 绑定 Bundle ID；本次先只验证 Android，iOS 接入与配置推迟。
- 本地开发：`config/amap_map_key_android.txt` 与 `config/amap_map_key_ios.txt`（gitignored），示例文件入库；`tool/run_local.sh` 分别注入两个 dart-define（网页 Key 那份逻辑不变）。
- release 由 CI Secret 注入；没有 Secret 时自动走 legacy，不阻断构建。
- 隐私合规：见「隐私同意」一节，首启弹窗在本次变更内实现。


### 加载失败与降级

- 原生 SDK 初始化失败、Key 无效、配额用尽：地图区域显示纸色底 + 「地图暂时不可用」小字，记录与轨迹累计继续。
- 不自动在运行时切到 legacy：后端选择在启动时确定，运行中切换会导致两套相机状态互相污染；排障靠 `MAP_BACKEND=legacy` 重启。
- 无网络时底图可能空白，覆盖层轨迹仍可绘制；不弹阻断对话框。

### 测试

- 所有现有地图 widget 测试在无 Key 环境自动走 legacy，保留原断言。
- 新增纯测试：后端选择真值表、`map_projection` 往返、GCJ-02 转换在两条后端下结果一致。
- widget 测试显式 override `mapBackendProvider` 为 legacy，避免未来 CI 注入 Key 后误建 platform view。
- 原生渲染、样式、投影对齐、相机跟随列入真机手动验证。

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| 高德 Flutter 地图插件维护不活跃或 API 不完整 | 任务 1.1 先做 spike：初始化、样式、相机、销毁四项跑通再继续；不满足则停止并回报，不硬推 |
| Flutter 覆盖层与原生相机投影漂移 | 用固定地标比对；漂移超过 1 逻辑像素时改为 SDK 原生 Marker / Polyline，或缩小覆盖层职责 |
| Android 签名变更导致 Key 失效 | 高德控制台同时登记 debug 与 release SHA1；README 写明排查顺序 |
| 记录页 1 Hz 相机移动导致卡顿 / 发热 | 真机测 30 分钟；必要时降低补间帧率或直接 moveCamera（不加动画） |
| 自定义样式审核 / 生效延迟 | 提前申请；未生效时允许默认样式运行，不阻塞发版 |
| 无 Key 或 Key 失效时用户看到空白地图 | 自动 legacy 回落；原生失败显示明确小字说明，记录不中断 |
| 同时维护两套地图体导致视觉分叉 | 抽出共享几何与标记数据；真机截图对比两套后端 |
| 隐私合规遗漏（SDK 初始化前未声明） | 首启隐私弹窗统一处理；未同意前不创建 `AMapWidget`，初始化封装在 `amap_basemap.dart` 单点 |
| 测试环境被注入 Key 后尝试 platform view | 测试统一 override legacy 后端；后端选择有单测 |

## Spike 结论（2026-11-02，Android）

- 候选 `amap_flutter_map` 3.0.0 无法在当前 AGP 9 / Gradle 9 下构建（`jcenter`、旧 Gradle DSL、Dart `<3.0`），弃用。
- 采用 `amap_map` 1.0.15：Android SDK 21+、iOS 12.0+，使用 `mavenCentral`，`compileSdk 35`。它依赖的 `flutter_plugin_android_lifecycle` 新版本要求编译到 36，当前用 `dependency_overrides: flutter_plugin_android_lifecycle: 2.0.24` 解决，Debug APK 构建通过。
- OPPO R9s Plus（API 25）真机验证通过：`onMapCreated` 触发；合规声明三项为 true 后正常出图；默认样式、标注、marker 与折线均正常；`onCameraMoveEnd` 能读到 `CameraPosition`（target/zoom/bearing/tilt）；销毁后原生侧 `dispose` 正常，重建后 `mapId` 从 0 递增到 1。
- 样式只接受 `style.data` / `style_extra.data` 二进制，**不支持 styleId**；见「纸色样式」。
- 原生 `Marker` / `Polyline` 的 id 在 Dart 侧每次构造都会重新生成，覆盖物必须缓存实例并复用，否则每次 rebuild 都会触发 add/remove。
- iOS 本次不做真机验证：Xcode 设备构建需要签名团队，且用户明确暂不处理 iOS。

## Open Questions

- 从高德控制台导出的 `style.data` 何时提供：未提供前以 SDK 默认样式运行，不阻塞后续开发。
- iOS 接入与签名配置：本变更后续单独验证，不影响 Android 路径。
- 自定义样式的具体配色参数由视觉验收决定，本设计只定义「由样式二进制提供纸色」这一约束。
- 是否在后续变更中彻底移除 `flutter_map`：等原生路径稳定且无 Key 运行需求消失后再评估，本次不决定。
