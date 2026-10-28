# Tasks

## 1. 地名与天气服务

- [x] 1.1 改造 `lib/data/geocode/place_service.dart`：`PlaceService.place()` 返回 `PlaceInfo`（城市 / 区县 / 街道 / 省份，含 `cityDistrict` / `full` / `short`），请求前 `wgs84ToGcj02`，5 秒超时、10 分钟网格缓存、无 Key / 失败 / 畸形响应返回 null。验证：`test/data/geocode/place_service_test.dart` 覆盖 GCJ-02 参数、空 Key、字段回退、非 200、超时、异常与缓存。
- [x] 1.2 改造 `lib/data/weather/weather_service.dart`：`WeatherService.currentWeather()` 返回 `WeatherNow`（温度 + WMO 天气码），映射中文描述，使用 WGS-84，6 秒超时、10 分钟网格缓存、失败返回 null。验证：`test/data/weather/weather_service_test.dart` 覆盖请求参数、温度取整、天气码映射、缺字段、非 200、畸形 JSON、超时、异常与缓存。

## 2. 配置与装配

- [x] 2.1 新增 `lib/config/app_config.dart` 的 `kAmapWebKey = String.fromEnvironment('AMAP_WEB_KEY')`；新增 `config/amap_key.example.txt` 与 `tool/run_local.sh`，并在 `.gitignore` 忽略 `config/amap_key.txt`。验证：`git status --ignored` 只显示真实 Key 被忽略，示例文件与脚本可提交。
- [x] 2.2 在 `lib/app/providers.dart` 增加共享 `http.Client`、`PlaceService`、`WeatherService` provider，客户端在 provider 销毁时关闭。验证：`fvm flutter analyze` 通过，记录页与控制器测试可 override 两个服务。
- [x] 2.3 在 `android/app/src/main/AndroidManifest.xml` 补 `android.permission.INTERNET`，保证 release 包能加载地图瓦片并查询地名 / 天气。验证：release manifest 合并后包含 INTERNET（debug / profile 原本已有）。

## 3. 待机状态与记录页接线

- [x] 3.1 更新 `lib/features/record/idle_conditions.dart`：`IdleConditions` 组合地名 / 温度与降级文案；`IdleConditionsController` 只在待机且有定位时请求，按约 1 km 网格去重，generation 丢弃在途响应，退出待机立即清空。验证：`test/features/record/idle_conditions_test.dart` 覆盖并行查询、降级、非待机不请求、网格去重、开始后丢弃与异常静默。
- [x] 3.2 在 `lib/features/record/record_page.dart` 监听 `RecordState` 并同步 `idleConditionsProvider`，把状态传给 `HandlebarView`。验证：`test/features/record/record_views_test.dart` 断言预热定位后查询一次、显示地名 / 气温，开始记录后收起。

## 4. 待机卡片界面

- [x] 4.1 在 `lib/features/record/handlebar_view.dart` 的 `_IdleCard` 增加 `Key('idle-place-weather')` 行，只在 `locationReady` 时渲染，单行居中、超长省略、墨色 `kFontMeta`；地名缺失显示「当前位置」，温度缺失省略。验证：`test/features/record/record_views_test.dart` 覆盖完整、无地名、无温度、两者都无、等待定位与记录中六种情况。
- [x] 4.2 确认 1.3 倍文字缩放下新行不溢出、不挤压地图带。验证：`test/app/text_scale_smoke_test.dart` 在 390×844 与 360×640 两个尺寸下覆盖待机地名 / 气温。

## 5. 记录捕获与落库

- [x] 5.1 新增 `lib/domain/models/workout_conditions.dart`：四个可空字段、`placeLabel` / `weatherLabel` 组合文案；`Workout` 增加 `placeName` / `placeShort` / `weatherText` / `weatherTempC`、`conditions` getter 与 DB 映射。验证：`test/domain/models/workout_test.dart` 覆盖往返与旧记录缺列按 null 读取。
- [x] 5.2 `lib/data/db/database.dart` 升到 schema v4，迁移补四列；`WorkoutDao.updateConditions` 只写非 null 列，避免地点与天气互相擦除；`WorkoutRepository.updateConditions` 写入后触发 `onWorkoutDataChanged`。验证：`test/data/db/database_test.dart` 覆盖 v3 → v4 旧记录新列为 null；`test/data/db/workout_dao_test.dart` 覆盖写入、部分更新与全空不写；`test/data/workout_repository_test.dart` 覆盖刷新信号。
- [x] 5.3 `RecordController.start()` 在创建记录后异步捕获条件：优先待机页 `previewFix`，没有则等第一个带坐标的真实定位点；`_conditionsPendingRideId` 保证只写一次，失败静默，不阻塞开始。验证：`test/features/record/record_controller_test.dart` 覆盖粗略定位、首个真实点、两边失败不写、开始时无定位。
- [x] 5.4 `RecordController.resumeExisting()` 对既无地点也无天气的未结束记录补捕获一次；已有任一项的记录不重复查询。验证：`test/features/record/record_controller_test.dart` 覆盖升级前会话与已有条件会话。

## 6. 历史与详情

- [x] 6.1 `lib/features/history/ride_card.dart` 在出发时间后拼 `placeShort`，没有地点时只显示出发时间。验证：`test/features/history/history_page_test.dart` 覆盖「08:00 出发 · 龙泉驿区」与旧记录「08:00 出发」。
- [x] 6.2 `lib/features/detail/detail_page.dart` 在标题下新增地点 / 天气行：地点用完整地名，天气用「描述 温度°C」，缺失部分省略，两项都无时整行不渲染。验证：`test/features/detail/detail_page_test.dart` 覆盖完整、只有天气、旧记录不渲染。

## 7. 备份、文案与文档

- [x] 7.1 `lib/data/export/backup.dart` 备份 schema 升到 v3；v2 归档缺四列时按 null 读取。验证：`test/data/export/backup_test.dart` 覆盖新列往返与 v2 旧归档恢复。
- [x] 7.2 设置页关于区改为「记录仅存本机」，补「地点与天气随记录保存在本机；查询会联网，不额外保存坐标。」。验证：`test/features/settings/settings_page_test.dart` 断言新文案，并继续断言无账号 / 云同步 / 社交入口。
- [x] 7.3 更新 `README.md` 与 `docs/`：地点 / 天气随记录保存、历史与详情展示、旧记录空白、坐标不落库、备份 schema v3。验证：描述与实现一致，命令可执行。
- [x] 7.4 更新本 OpenSpec 变更的 proposal / design / specs / tasks，使文档不再声称地点 / 天气不进入数据库、历史或详情。验证：`openspec validate "record-location-weather" --type change --strict` 通过（输出 `Change 'record-location-weather' is valid`）。

## 8. 全量验证与交付

- [x] 8.1 `fvm flutter analyze` 无告警。验证：命令输出 `No issues found!`。
- [x] 8.2 `fvm flutter test` 全部通过。验证：输出 `All tests passed!`，包含新增服务、模型、迁移、备份、控制器、历史与详情用例。
- [x] 8.3 在模拟器 / OPPO 上开始一条新记录，确认历史副题出现区县、详情出现地点与天气；确认旧记录保持空白。验证：OPPO R9s Plus 新记录历史显示「17:19 出发 · 武侯区」，详情显示「成都市 · 武侯区 · 浆洗街街道 / 阴 20°C」，旧记录仍只显示出发时间。
- [x] 8.4 只暂存本特性相关文件并提交，保留工作区既有 13 个未提交修改；未获指示不 push。验证：提交只含本特性 33 个文件；`git status` 中用户原有 13 个修改仍未暂存；提交内容不含 `config/amap_key.txt` 或真实 Key。
