# Proposal

## Why

记录待机页现在会在出发前显示位置与气温，但这份信息只活在内存里：开始记录后立刻消失，历史列表只有「HH:mm 出发」，单次详情也只有标题与时间。用户回看一次骑行时，往往记不起那天在哪里、天气如何。设计稿也把地点与天气画进了历史条目和详情标题区。

## What Changes

- 开始记录时把当时的地点与天气随记录保存到本机；恢复旧会话时若记录还没有这些字段，也补一次捕获。
- 地点优先使用待机页已有的粗略定位，拿不到时用第一个真实定位点；天气与地点并行查询，都不阻塞开始记录。
- 详情页在标题下显示「城市 · 区县 · 街道/乡镇」与「晴 18°C」；历史条目在出发时间后显示具体地点（优先街道/乡镇，旧记录退回区县），例如「06:42 出发 · 桃花故里」。
- 数据库 `workouts` 表新增 `place_name` / `place_short` / `weather_text` / `weather_temp_c`，schema 升到 v4；备份 schema 升到 v3，旧备份缺列按 null 读取。
- 任一项查询失败、没有 Key、没有定位或响应缺字段时静默降级：地点或天气各自缺失时省略对应部分，两项都没有时整行不渲染，不伪造占位。
- 旧记录没有捕获过地点 / 天气，保持空白；不回填地点，因为无法可靠还原当时的位置与天气。
- 设置页文案改为「地点与天气随记录保存在本机；查询会联网，不额外保存坐标。」
- 坐标仍只用于当次请求，不写数据库、不写日志、不进 GPX；落库的只有地名与天气文字。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `recording`: 待机页继续显示位置与气温；开始 / 恢复记录时异步捕获并落库，失败时静默降级。
- `activity-review`: 历史条目在出发时间后显示具体地点（优先街道/乡镇，旧记录退回区县）；详情标题下显示地点与天气，缺失时整行省略。
- `settings`: 关于区说明地点与天气随记录保存在本机，查询会联网但不额外保存坐标。

## Impact

- 数据层：`lib/domain/models/workout.dart`、新增 `lib/domain/models/workout_conditions.dart`、`lib/data/db/database.dart`（v4 迁移）、`lib/data/db/workout_dao.dart`、`lib/data/workout_repository.dart`、`lib/data/export/backup.dart`（v3）。
- 服务层：`lib/data/geocode/place_service.dart` 返回 `PlaceInfo`；`lib/data/weather/weather_service.dart` 返回 `WeatherNow` 并映射 WMO 天气码。
- 状态与界面：`lib/features/record/record_controller.dart`、`lib/features/record/idle_conditions.dart`、`lib/features/history/ride_card.dart`、`lib/features/detail/detail_page.dart`、`lib/features/settings/settings_page.dart`。
- 文案与文档：`README.md`、本变更的 proposal / design / specs / tasks。
- 测试：扩展地点 / 天气服务、记录控制器、DAO、Repository、备份、数据库迁移、历史与详情 widget 测试。
