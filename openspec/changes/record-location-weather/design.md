# Design

## Context

记录待机页已经会在首帧后预热一次定位（`RecordController.loadIdlePreview`），拿到 `LocationFix` 后显示精度与地图圆点，并在有地名 / 气温时显示一行出发信息。地点与天气既然已经在出发前查到，就应该随记录一起保存：否则开始记录后信息立刻消失，用户回看历史时只剩下一个时间点。

约束：

- 应用仍是纯本地：无账号、无云端、无同步；运动记录只存本机。
- 地名与天气是外部查询，失败不能阻塞开始记录，也不能伪造读数。
- 高德 Key 不能进入 git；仓库要能在没有 Key 时正常构建、运行与测试。
- 坐标只用于当次请求：不落库、不写日志、不进 GPX。落库的只有地名文字与天气文字。
- 旧记录没有捕获过地点 / 天气，升级后保持空白；不尝试回填。
- 现有 widget 测试不能碰真实网络。

## Goals / Non-Goals

**Goals:**

- 待机页在已定位时显示一行「城市 · 区县 · 气温」。
- 开始记录（以及恢复没有条件的旧会话）时，把当时的地点与天气异步写入这条记录。
- 历史条目在出发时间后显示区县；详情标题下显示完整地点与天气。
- 地点与天气各自独立降级，任何一边失败都不影响另一边，也不影响记录本身。
- 请求有超时与内存缓存，待机页重建不会反复打接口。
- 数据库与备份的升级对旧数据无损。
- Key 只存在于本地被忽略的文件与运行时 `--dart-define`。

**Non-Goals:**

- 不做天气预报、逐小时、天气图标。
- 不做地点搜索、路线命名、附近 POI。
- 不保存坐标、不保存高德 / Open-Meteo 原始响应。
- 不把地点或天气写进 GPX。
- 不做分钟级轮询、后台定位或位置变化监听。
- 不引入服务端代理或 Key 下发。

## Decisions

### 在开始记录时捕获，而不是在详情页重查

地点与天气代表「出发那一刻」的条件，必须在开始时捕获：

- `RecordController.start()` 在拿到 `rideId` 后把 `_conditionsPendingRideId` 设为该 id，并异步调用 `_captureConditions`。
- 优先使用待机页已有的 `quickPreviewFix()`；同一个 `previewFuture` 也交给地图预览，避免重复请求一次粗略定位。
- 粗略定位拿不到时，把机会留给第一个带坐标的真实定位点：`_onFix` 检查 `_conditionsPendingRideId`，命中后立即捕获并清空。
- `_conditionsPendingRideId` 保证只捕获一次；记录结束、控制器销毁或新会话开始时清空，迟到的响应不会写到错误的记录上。
- 捕获与写库全程不 `await` 在开始流程里，网络慢或失败不影响「开始」按钮。

恢复未结束会话时，如果记录既没有 `placeName` 也没有 `weatherTempC`（升级前开始的记录），同样补一次捕获；已有任一项的记录不重复查询。

### 数据模型与数据库

新增 `WorkoutConditions`，只持有四个可空字段：

- `placeName`：详情用完整地名，形如「成都市 · 龙泉驿区 · 桃花故里」。
- `placeShort`：历史用短地名，通常是区县，形如「龙泉驿区」。
- `weatherText`：中文天气描述，形如「晴」。
- `weatherTempC`：出发时气温（摄氏度，整数）。

`Workout` 增加对应四列与 `conditions` getter。数据库 schema 从 v3 升到 v4，用四条 `ALTER TABLE ... ADD COLUMN` 补列；旧记录的新列自然为 null，正好表示「那次没有捕获地点 / 天气」，不需要重写任何轨迹点。

`WorkoutDao.updateConditions` 只写入非 null 的列：地点与天气是两个独立请求，任何一边失败都不该把另一边已经写好的值擦掉。四项都为空时直接返回。`WorkoutRepository.updateConditions` 写入后触发 `onWorkoutDataChanged`，让记录已经结束时历史页与详情页也能在条件晚到时刷新。

备份 schema 从 v2 升到 v3。v2 归档缺这四列，`Workout.fromDbMap` 对缺失列返回 null，旧备份无需迁移即可恢复。

### 两个服务，两个坐标系

- `AmapPlaceService`：高德要求 GCJ-02，GPS 与落盘轨迹是 WGS-84，因此请求前调用 `wgs84ToGcj02`。解析 `addressComponent` 的 `city` / `district` / `township` / `province`，返回 `PlaceInfo`：
  - `cityDistrict`：待机页用「城市 · 区县」。
  - `full`：详情用「城市 · 区县 · 街道/乡镇」。
  - `short`：历史用短地名，优先区县，其次城市、省份、街道。
  - 空字段与相邻重复项会被去掉；全部为空时服务返回 null。
- `OpenMeteoWeatherService`：使用原始 WGS-84，查询 `current=temperature_2m,weather_code&temperature_unit=celsius`，返回 `WeatherNow`（温度四舍五入到整数 + WMO 天气码）。天气码映射成中文描述（晴、多云、小雨、雷阵雨等）；未知码返回 null，界面只显示温度。

两个服务都返回 `Future<T?>`，网络异常、超时、非 200、畸形 JSON、字段缺失一律返回 null，不向界面抛错。

### 超时与缓存

- 高德 5 秒、Open-Meteo 6 秒。
- 两个服务各自维护 10 分钟内存缓存，键为约 1 km 网格。
- 待机控制器再按网格去重一次，避免同一位置反复调用服务。
- 不做定时刷新：待机页的位置来自一次预热定位，用户通常几秒内就出发；10 分钟缓存足够覆盖页面重建与短暂切后台。

### 界面位置与降级

待机页：`_IdleCard` 在「定位已就绪」下方显示一行 `Key('idle-place-weather')`，格式「城市 · 区县 · 气温」。地名缺失回退「当前位置」，温度缺失只显示地名。`IdleConditions` 不把「当前位置」写进状态，避免把降级文案误当成查询结果。开始记录、结束或定位丢失后整行收起；generation 保证在途响应不会写回。

历史：`WorkoutCard` 的出发时间行拼上 `placeShort`，例如「06:42 出发 · 龙泉驿区」。没有短地名时只显示「06:42 出发」，不加分隔符。

详情：标题与日期下方新增一行地点 / 天气：

- 左侧地点图标 + `placeName`（缺失时退回 `placeShort`），单行省略。
- 右侧 `weatherText weatherTempC°C`，例如「晴 18°C」；只有温度时显示「18°C」，只有描述时显示描述。
- 地点与天气都缺失时整行不渲染，不保留空白占位。
- 旧记录没有这些字段，因此不会出现伪造的地点或天气。

### Key 注入

`kAmapWebKey = String.fromEnvironment('AMAP_WEB_KEY')`。本地开发：

```bash
cp config/amap_key.example.txt config/amap_key.txt
# 填入高德 Web 服务 Key
tool/run_local.sh
```

`config/amap_key.txt` 被 `.gitignore` 忽略；`tool/run_local.sh` 读取后以 `--dart-define` 传给 `fvm flutter run`。没有 Key 时 `AmapPlaceService` 在发请求前就返回 null，待机页显示「当前位置」，气温不受影响；记录仍可保存天气。

### 平台联网

Android 主 manifest 补 `INTERNET`。debug / profile 的 manifest 原本就有这一条，但 release 包必须显式声明，否则地图瓦片、高德与 Open-Meteo 都无法访问。iOS 使用 HTTPS，不需要改 ATS。

## Risks / Trade-offs

- **高德配额与接口变更**：免费配额有限，接口也可能调整。缓存与网格去重压低调用量；失败时静默降级，不影响记录主流程。
- **外部依赖的隐私观感**：查询会把坐标发给高德与 Open-Meteo。设置页与 README 明确写出「查询会联网，不额外保存坐标」；不引入账号、设备标识或历史位置上传。
- **Key 泄露**：Key 只存在于本地文件与运行时环境，不进入 git、不写日志。发布包若需要地名，需要在构建时注入；没有 Key 的包仍可正常使用。
- **地点粒度与隐私**：详情显示到街道 / 乡镇，历史只显示区县。落库的是文字而不是坐标，仍比保存原始定位更克制；如果用户分享截图，地名会随截图暴露，这是设计稿明确要求的取舍。
- **旧记录空白**：升级前的记录没有地点 / 天气，历史与详情保持原样。不回填是因为无法可靠还原当时的位置与天气，宁可缺失也不伪造。
- **网络延迟**：条件可能比记录晚几秒落库。记录结束得很快时，`updateConditions` 仍会触发刷新信号，历史与详情能在条件到达后更新。

## Migration

数据库 v3 → v4：四条 `ADD COLUMN`，旧记录四列为 null。备份 v2 → v3：读取旧归档时缺列按 null 处理。旧记录的地点 / 天气不回填，界面按「没有数据」省略。
