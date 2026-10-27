# 行迹 XINGJI

个人自用的运动记录与分析 App：把一次运动完整、准确地记下来，并回答两个问题——**这次怎么样**（单次详情）和**最近怎么样**（长期趋势）。

支持骑行、跑步、健走、徒步、登山五种类型。不是社交产品，不是导航工具，不是训练平台；无账号、无服务端、无云同步，数据全部留在本机。

## 功能

- **五种运动类型**：骑行 / 跑步 / 健走 / 徒步 / 登山。骑行支持速度、踏频、功率与速度档提示；其余类型以配速、心率、海拔与爬升为主。不采集、不展示步频或步数。
- **记录界面**：记录 tab 落地就是全屏实时地图，读数与按钮以纸色渐变浮在地图上。待机页有类型浮标、日期时间、定位精度与整宽「开始{类型}」；记录中按动作频率分配宽度——「结束」1/3 靠左，「暂停 / 继续」2/3 靠右。顶部四格是距离 / 时长 / 海拔 / 爬升，底部按类型显示速度或配速、刻度尺与传感器读数。
- **运动中的提示**：每满 1km 报该公里成绩，每满 10km 报累计里程，骑行还会在速度跨档时提示。屏内横幅 + 中文语音同时走，熄屏放口袋里也听得到；配速类型按配速口径播报。
- **崩溃恢复**：启动时检测到未结束的会话，提示继续续写或结算保存。
- **封面与纸本主题**：冷启动封面 1.2 秒后淡出，可点击跳过；全站亮色纸本，朱砂 / 青瓷 / 黛蓝 / 藤黄四色颜料可选，点选即生效。
- **历史**：按最近有记录的月份分组，首屏只显示该月，底部「更早的记录」在内存展开；日志条目显示日期、星期、标题、出发时间、距离、四格读数与迷你曲线。
- **单次详情**：地图轨迹、两行三列汇总、按类型命名的速度 / 配速曲线、心率曲线与五区间分布；踏频 / 功率区块只在骑行且有数据时出现。不展示天气、地点名称或路线名。
- **长期统计**：周 / 月 / 年切换，三项主读数为总距离 / 总时长 / 总爬升，柱形距离趋势，01–04 编号的个人最佳；筛选只改变统计范围，不修改数据。
- **地图**：`flutter_map` + 高德栅格瓦片，瓦片降饱和并覆纸色薄罩；轨迹用主题文字色与墨色描边，带指北与比例尺。GPS 中断超过 10 秒断开轨迹；记录中地图不响应拖动与缩放。
- **数据导出**：单次导出 GPX 1.1（心率 / 踏频写入 Garmin `TrackPointExtension`）；全量备份为 ZIP，恢复前校验 schema 版本并显示上次备份时间。

## 技术栈

| 用途 | 选型 |
| --- | --- |
| 框架 | Flutter 3.47.4 / Dart 3.13.3（fvm 管理） |
| 定位 | `geolocator` |
| 蓝牙 | `flutter_blue_plus` |
| 本地存储 | `sqflite`（测试用 `sqflite_common_ffi` 内存库） |
| 状态管理 | `flutter_riverpod` |
| 图表 | `fl_chart`（柱形趋势） |
| 地图 | `flutter_map` + `latlong2` |
| 语音播报 | `flutter_tts`（中文，`zh-CN`） |
| 屏幕常亮 / 权限 | `wakelock_plus` / `permission_handler` |
| 导出与备份 | `share_plus`、`path_provider`、`file_picker`、`archive`、`xml` |

字体不打包中文字体，全部走平台回退链：标题衬线、正文无衬线、数据等宽 + tabular figures。主题色分「标记色 + 文字安全色」两层，小字与图标只用满足对比度的 `accentInk`。

## 目录结构

分层原则：**`domain/` 是纯逻辑层，不依赖 IO，可脱离 Flutter 单独测试**。这是整个设计可测试性的根基。

```text
lib/
  app/          应用外壳：封面、路由、纸本主题、依赖装配
  features/
    activity/   类型视觉、类型浮标/面板、历史与统计共用筛选
    record/     记录页、会话控制、实时地图与提示横幅
    history/    月份分组与日志条目
    detail/     详情页（地图轨迹 + 汇总 + 曲线）
    stats/      长期统计、柱形趋势、个人最佳
    settings/   设置、传感器配对、备份与恢复
  domain/       纯逻辑，无 IO 依赖
    models/     Workout, TrackPoint, WorkoutSummary, ActivityType 等
    analysis/   指标计算、心率区间、趋势聚合
    recording/  记录状态机、轨迹点过滤、落盘缓冲
  data/
    db/         SQLite 打开、迁移、DAO
    ble/        心率 / 踏频 / 功率订阅
    location/   定位采集
    export/     GPX 生成、备份打包
  core/         单位换算、格式化
```

## 环境准备

版本由 fvm 固定，`.fvmrc` 已提交：

```bash
fvm install          # 安装 .fvmrc 里指定的 Flutter
fvm flutter pub get
fvm flutter run      # 连接设备后运行
```

不装 fvm 时，直接用 3.47.4 版本的 `flutter` 命令亦可。

### Android 说明

`android/app/build.gradle.kts` 里 `compileSdk = 37`，因为 `permission_handler_android` 13.x 要求依赖方 `compileSdk >= 37`，而 `flutter.compileSdkVersion` 目前是 36。

release 签名从 `android/key.properties` 读取（该文件不进版本库，见 `android/.gitignore`）。本地没有这个文件时会退回 debug 密钥，`flutter run --release` 无需先配 keystore。

## 测试

```bash
fvm flutter analyze
fvm flutter test
```

测试集中在纯逻辑与组件边界上：`domain/analysis`（爬升滤波、最高速平滑、心率区间边界、Haversine 距离、GCJ-02、趋势聚合）、`domain/recording`（状态机、批量落盘）、`data/db`（内存库跑 DAO）、`features/*`（Widget 测试，注入假定位流、传感器流、设置与备份 IO）。

真实 BLE 硬件、真实 GPS、瓦片渲染与户外强光可读性不做自动化，需真机手动验证。

## 构建与发版

版本号由 git tag 驱动。推一个形如 `v1.2.3` 的 tag 即触发 [release.yml](.github/workflows/release.yml)：

1. 解析 tag 得到 `versionName` / `versionCode`（`versionCode = major*10000 + minor*100 + patch`，因此 minor 与 patch 必须小于 100）
2. `flutter analyze` + `flutter test` 门禁
3. 从 Secrets 解出 keystore 写入 `android/key.properties`（未配 Secrets 则用 debug 签名构建）
4. 构建 release APK，用 `aapt` / `apksigner` 核对产物里的版本号与签名证书
5. 发布 GitHub Release，附上 APK

```bash
git tag v1.0.0 && git push origin v1.0.0
```

tag 带后缀（如 `v1.0.0-rc1`）会发成 prerelease。

本地手搓指定版本：

```bash
fvm flutter build apk --release --build-name=1.0.0 --build-number=10000
```

发正式签名包需要先在 GitHub 仓库配置 4 个 Secrets：`KEYSTORE_BASE64`、`KEYSTORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD`。

## 地图瓦片源

默认走高德栅格瓦片（GCJ-02 坐标，无需申请 Key）。这是非官方接口，属于灰色地带，接口变更会失效——因此瓦片源地址是设置里的可配置项，失效时可切到 OSM 或自建源，无需改代码重新发版。

瓦片在客户端做降饱和与纸色薄罩；轨迹坐标跟随瓦片源：高德 / 腾讯这类 GCJ-02 源才把显示坐标转过去，OSM 这类 WGS-84 源保持原样，否则轨迹会整体偏移几百米。落盘与 GPX 导出始终是 WGS-84。

## 设计文档

- [纸本改版设计](openspec/changes/xingji-ui-redesign/design.md)
- [纸本改版任务清单](openspec/changes/xingji-ui-redesign/tasks.md)
- [旧版核心设计文档](docs/superpowers/specs/2026-09-21-cycling-app-design.md)
- [实施计划 · 核心](docs/superpowers/plans/2026-09-21-cycling-app-core.md)
- [实施计划 · 详情/历史/统计/设置/地图/导出](docs/superpowers/plans/2026-09-21-cycling-app-plan-b.md)
