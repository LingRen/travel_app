# Tasks

## 1. 地名与天气服务

- [x] 1.1 新增 `lib/data/geocode/place_service.dart`：`PlaceService` 接口与高德实现，请求前 `wgs84ToGcj02`，解析「城市 · 区县」，5 秒超时、10 分钟网格缓存、无 Key / 失败 / 畸形响应返回 null。验证：`test/data/geocode/place_service_test.dart` 覆盖 GCJ-02 参数、空 Key、字段回退、非 200、超时、异常与缓存。
- [x] 1.2 新增 `lib/data/weather/weather_service.dart`：`WeatherService` 接口与 Open-Meteo 实现，使用 WGS-84，解析 `current.temperature_2m` 并四舍五入，6 秒超时、10 分钟网格缓存、失败返回 null。验证：`test/data/weather/weather_service_test.dart` 覆盖请求参数、解析、非 200、畸形 JSON、超时、异常与缓存。

## 2. 配置与装配

- [x] 2.1 新增 `lib/config/app_config.dart` 的 `kAmapWebKey = String.fromEnvironment('AMAP_WEB_KEY')`；新增 `config/amap_key.example.txt` 与 `tool/run_local.sh`，并在 `.gitignore` 忽略 `config/amap_key.txt`。验证：`git status --ignored` 只显示真实 Key 被忽略，示例文件与脚本可提交。
- [x] 2.2 在 `lib/app/providers.dart` 增加共享 `http.Client`、`PlaceService`、`WeatherService` provider，客户端在 provider 销毁时关闭。验证：`fvm flutter analyze` 通过，记录页测试可 override 两个服务。
- [x] 2.3 在 `android/app/src/main/AndroidManifest.xml` 补 `android.permission.INTERNET`，保证 release 包能加载地图瓦片并查询地名 / 天气。验证：release manifest 合并后包含 INTERNET（debug / profile 原本已有）。

## 3. 待机状态与记录页接线

- [x] 3.1 新增 `lib/features/record/idle_conditions.dart`：`IdleConditions` 组合地名 / 温度与降级文案；`IdleConditionsController` 只在待机且有定位时请求，按约 1 km 网格去重，generation 丢弃在途响应，退出待机立即清空。验证：`test/features/record/idle_conditions_test.dart` 覆盖并行查询、降级、非待机不请求、网格去重、开始后丢弃与异常静默。
- [x] 3.2 在 `lib/features/record/record_page.dart` 监听 `RecordState` 并同步 `idleConditionsProvider`，把状态传给 `HandlebarView`。验证：`test/features/record/record_views_test.dart` 断言预热定位后查询一次、显示地名 / 气温，开始记录后收起。

## 4. 待机卡片界面

- [x] 4.1 在 `lib/features/record/handlebar_view.dart` 的 `_IdleCard` 增加 `Key('idle-place-weather')` 行，只在 `locationReady` 时渲染，单行居中、超长省略、墨色 `kFontMeta`；地名缺失显示「当前位置」，温度缺失省略。验证：`test/features/record/record_views_test.dart` 覆盖完整、无地名、无温度、两者都无、等待定位与记录中六种情况。
- [x] 4.2 确认 1.3 倍文字缩放下新行不溢出、不挤压地图带。验证：`test/app/text_scale_smoke_test.dart` 在 390×844 与 360×640 两个尺寸下覆盖待机地名 / 气温。

## 5. 文案、文档与平台说明

- [x] 5.1 设置页关于区改为「记录仅存本机」，补「位置名称与天气查询会联网，坐标不落库。」。验证：`test/features/settings/settings_page_test.dart` 断言新文案，并继续断言无账号 / 云同步 / 社交入口。
- [x] 5.2 更新 `README.md`：记录页特性、技术栈、目录结构、Key 配置与联网 / 隐私说明。验证：README 命令可执行，描述与实现一致。
- [x] 5.3 新增本 OpenSpec 变更（proposal / design / specs / tasks），记录坐标不落库、静默降级与 Key 管理决策。验证：`openspec validate "record-location-weather" --type change --strict` 通过。

## 6. 全量验证与交付

- [x] 6.1 `fvm flutter analyze` 无告警。验证：命令输出 `No issues found!`。
- [x] 6.2 `fvm flutter test` 全部通过。验证：输出 `All tests passed!`，包含新增服务、状态、widget 与 1.3 倍缩放用例。
- [x] 6.3 在真机 / 模拟器上生成待机页截图，确认地名、温度与卡片排版。验证：iPhone 17 Pro 模拟器截图显示「成都市 · 武侯区 · 20°C」，开始记录后该行消失由 widget 测试覆盖。
- [x] 6.4 只暂存本特性相关文件并提交，保留工作区既有未提交修改。验证：`git status` 中用户原有修改仍未暂存，提交内容不含 `config/amap_key.txt` 或真实 Key。
