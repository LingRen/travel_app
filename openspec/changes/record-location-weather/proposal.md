# Proposal

## Why

记录待机页现在只显示日期时间与定位精度，用户出发前看不到自己在哪、天气如何。设计稿曾画过位置与天气，但上一轮纸本改版把它明确列为非目标，所以一直没有数据链路。现在补上这一小块出发信息：只在待机页看一眼，不进入记录、历史或详情，也不改变「数据只存本机」的定位。

## What Changes

- 记录待机页在拿到定位后显示「城市 · 区县 · 气温」，例如「成都市 · 武侯区 · 18°C」；开始记录后立即收起。
- 地名走高德开放平台「Web 服务」逆地理编码，请求前把 WGS-84 转成 GCJ-02；气温走免 Key 的 Open-Meteo，使用原始 WGS-84。
- 两个请求独立、超时分别为 5s / 6s，结果在内存中按约 1 km 网格缓存 10 分钟；不做分钟级轮询。
- 网络失败、超时、无 Key 时静默降级：地名回退「当前位置」，温度整段省略，不显示假数据或错误弹窗。
- 高德 Key 不进入版本库：放在被忽略的 `config/amap_key.txt`，由 `tool/run_local.sh` 以 `--dart-define=AMAP_WEB_KEY` 注入；直接 `fvm flutter run` 时地名回退，气温仍可用。
- Android 主 manifest 补 `INTERNET` 权限，保证 release 包能加载地图瓦片并查询地名 / 天气；iOS 走 HTTPS，不改 ATS。
- 设置页关于区把「数据仅存本机」改为「记录仅存本机」，并补一行「位置名称与天气查询会联网，坐标不落库」。
- 坐标只用于当次请求，不写数据库、不写日志、不进 GPX；历史与详情仍不展示地点或天气。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `recording`: 待机页新增位置名称与气温，并明确只在待机时出现、记录中收起、失败时降级。
- `settings`: 关于区改为「记录仅存本机」，并声明位置 / 天气查询会联网且坐标不落库。

## Impact

- 数据层：新增 `lib/data/geocode/place_service.dart`、`lib/data/weather/weather_service.dart`、`lib/config/app_config.dart`。
- 状态与界面：新增 `lib/features/record/idle_conditions.dart`；修改 `lib/app/providers.dart`、`lib/features/record/record_page.dart`、`lib/features/record/handlebar_view.dart`。
- 配置与平台：新增 `config/amap_key.example.txt`、`tool/run_local.sh`，`.gitignore` 忽略真实 Key；修改 `android/app/src/main/AndroidManifest.xml`。
- 文案与文档：修改 `lib/features/settings/settings_page.dart`、`README.md`。
- 测试：新增 `test/data/geocode/place_service_test.dart`、`test/data/weather/weather_service_test.dart`、`test/features/record/idle_conditions_test.dart`；扩展 `test/features/record/record_views_test.dart`、`test/app/text_scale_smoke_test.dart`、`test/features/settings/settings_page_test.dart`。
