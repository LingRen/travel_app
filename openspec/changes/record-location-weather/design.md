# Design

## Context

记录待机页已经会在首帧后预热一次定位（`RecordController.loadIdlePreview`），拿到 `LocationFix` 后显示精度与地图圆点。位置名称与气温是同一时刻的附加信息，适合挂在这个已有信号上，而不是新开一条定位流。

约束：

- 应用仍是纯本地：无账号、无云端、无同步；运动记录只存本机。
- 地名与天气是外部查询，失败不能阻塞开始记录，也不能伪造读数。
- 高德 Key 不能进入 git；仓库要能在没有 Key 时正常构建、运行与测试。
- 历史、详情、数据库与 GPX 不因这个特性增加字段。
- 现有 widget 测试不能碰真实网络。

## Goals / Non-Goals

**Goals:**

- 待机页在已定位时显示一行「城市 · 区县 · 气温」。
- 地名与气温各自独立降级，任何一边失败都不影响另一边。
- 开始记录、结束或定位丢失后立即收起，在途响应不得写回。
- 请求有超时与内存缓存，待机页重建不会反复打接口。
- Key 只存在于本地被忽略的文件与运行时 `--dart-define`。

**Non-Goals:**

- 不做天气预报、逐小时、天气图标或天气描述。
- 不做地点搜索、路线命名、附近 POI。
- 不把位置名称或天气写进数据库、GPX、历史、详情或备份。
- 不做分钟级轮询、后台定位或位置变化监听。
- 不引入服务端代理或 Key 下发。

## Decisions

### 独立的状态与控制器

新增 `IdleConditionsController`（`Notifier<IdleConditions>`），由 `RecordPage` 在 `RecordState` 变化时调用：

```dart
update(idle: !state.isActive && !state.isFinished, fix: state.previewFix)
```

`IdleConditions` 只持有 `place` 与 `temperatureC`。界面按 `place ?? '当前位置'` 与可选的 `temperatureC°C` 组合，因此：

- 有地名有温度：`成都市 · 武侯区 · 18°C`
- 有地名无温度：`成都市 · 武侯区`
- 无地名有温度：`当前位置 · 18°C`
- 都没有：`当前位置`

不把「当前位置」写进状态，避免把降级文案误当成查询结果。

### generation 丢弃在途响应

每次位置网格变化或退出待机，`_generation` 自增。异步结果回来时先比对 generation，再写状态。这样开始记录后即使请求刚好返回，也不会把地名 / 温度重新写回界面。

位置按 `lat/lon` 保留两位小数（约 1 km）去重：同一街区内的微小定位变化不重复请求；换街区时先清空旧值，避免短暂显示上一个地点。

### 两个服务，两个坐标系

- `AmapPlaceService`：高德要求 GCJ-02，GPS 与落盘轨迹是 WGS-84，因此请求前调用 `wgs84ToGcj02`。只取 `addressComponent` 的 `city` / `district`，拼成「城市 · 区县」；高德把空字段返回成空数组，统一按空字符串处理。城市为空时退回区县、省份、街道。
- `OpenMeteoWeatherService`：使用原始 WGS-84，查询 `current=temperature_2m&temperature_unit=celsius`，把 `20.2` 四舍五入成 `20`。

两个服务都返回 `Future<T?>`，网络异常、超时、非 200、畸形 JSON、字段缺失一律返回 null，不向界面抛错。

### 超时与缓存

- 高德 5 秒、Open-Meteo 6 秒。
- 两个服务各自维护 10 分钟内存缓存，键为约 1 km 网格。
- 控制器再按网格去重一次，避免同一位置反复调用服务。
- 不做定时刷新：待机页的位置来自一次预热定位，用户通常几秒内就出发；10 分钟缓存足够覆盖页面重建与短暂切后台。

### Key 注入

`kAmapWebKey = String.fromEnvironment('AMAP_WEB_KEY')`。本地开发：

```bash
cp config/amap_key.example.txt config/amap_key.txt
# 填入高德 Web 服务 Key
tool/run_local.sh
```

`config/amap_key.txt` 被 `.gitignore` 忽略；`tool/run_local.sh` 读取后以 `--dart-define` 传给 `fvm flutter run`。没有 Key 时 `AmapPlaceService` 在发请求前就返回 null，待机页显示「当前位置」，气温不受影响。

### 界面位置

`_IdleCard` 在标题「定位已就绪」下方加一行 `Key('idle-place-weather')`，单行居中、超长省略，字号 `kFontMeta`、墨色。它只在 `locationReady` 时渲染；`locationReady` 来自 `previewFix?.hasPosition`。记录中整张待机卡片本来就不渲染，因此开始后自然收起。

待机卡片外层已有 `FittedBox(scaleDown)`，1.3 倍文字缩放时整张卡片等比缩小，不挤压地图带。

### 平台联网

Android 主 manifest 补 `INTERNET`。debug / profile 的 manifest 原本就有这一条，但 release 包必须显式声明，否则地图瓦片、高德与 Open-Meteo 都无法访问。iOS 使用 HTTPS，不需要改 ATS。

## Risks / Trade-offs

- **高德配额与接口变更**：免费配额有限，接口也可能调整。缓存与网格去重压低调用量；失败时静默降级，不影响记录主流程。
- **外部依赖的隐私观感**：查询会把坐标发给高德与 Open-Meteo。设置页与 README 明确写出「会联网，坐标不落库」；不引入账号、设备标识或历史位置上传。
- **Key 泄露**：Key 只存在于本地文件与运行时环境，不进入 git、不写日志。发布包若需要地名，需要在构建时注入；没有 Key 的包仍可正常使用。
- **位置名称粒度**：只显示城市与区县，不显示街道或 POI，降低隐私敏感度，也避免高德返回格式差异带来的不稳定。
- **网络延迟**：请求失败或超时最多让这一行晚几秒出现或永远不出现，不阻塞「开始」按钮。

## Migration

无数据库迁移。旧版本没有位置 / 天气字段，升级后待机页直接按新逻辑查询；历史记录保持原样。
