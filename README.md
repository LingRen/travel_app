# cycling_app

个人自用的骑行记录与分析 App。核心价值是把一次骑行完整、准确地记下来，并在事后回答两个问题：**这次骑得怎么样**（单次详情）和**我最近骑得怎么样**（长期趋势）。

不是社交产品，不是导航工具，不是训练平台。无账号、无服务端，数据全部留在本机。

## 功能

- **骑行记录**：手机 GPS 轨迹 + 蓝牙心率（标准 HRS）+ 蓝牙踏频（标准 CSC）+ 蓝牙功率计。传感器连不上不阻断开始记录，对应曲线留空，功率按速度与坡度估算。
- **骑行界面**：记录 tab 落地就是它，没有单独的准备页。大字号深色高对比主指标、速度刻度尺、指标条 + 实时轨迹缩略图；底部动作区按动作频率分宽——未开始是整宽「开始」，记录中是「结束」占 1/3 靠左、「暂停 / 继续」占 2/3 靠右。亮屏常亮，按电源键熄屏后采集照常。没连上的心率 / 踏频 / 功率可点那一格就地重连。
- **崩溃恢复**：启动时检测到未结束的会话（`status` 为 `recording` / `paused`），提示继续续写或结算保存。
- **单次分析**：汇总指标、速度曲线、心率曲线 + 五区间分布、踏频曲线、爬升与卡路里估算。
- **长期统计**：周 / 月 / 年累计、趋势折线、个人最佳。
- **地图轨迹**：`flutter_map` + 高德栅格瓦片，轨迹与速度曲线共用同一套速度 → 颜色映射。GPS 中断超过 10 秒不连线，避免画出横穿隧道的假直线。
- **数据导出**：单次导出 GPX 1.1（心率/踏频写入 Garmin `TrackPointExtension`，Strava 等平台可读）；全量备份为 ZIP，恢复前校验 schema 版本。

## 技术栈

| 用途 | 选型 |
| --- | --- |
| 框架 | Flutter 3.47.4 / Dart 3.13.3（fvm 管理） |
| 定位 | `geolocator` |
| 蓝牙 | `flutter_blue_plus` |
| 本地存储 | `sqflite`（测试用 `sqflite_common_ffi` 内存库） |
| 状态管理 | `flutter_riverpod` |
| 图表 | `fl_chart` |
| 地图 | `flutter_map` + `latlong2` |
| 屏幕常亮 / 权限 | `wakelock_plus` / `permission_handler` |
| 导出与备份 | `share_plus`、`path_provider`、`file_picker`、`archive`、`xml` |

## 目录结构

分层原则：**`domain/` 是纯逻辑层，不依赖 IO，可脱离 Flutter 单独测试**。这是整个设计可测试性的根基。

```text
lib/
  app/          应用外壳：路由、主题、依赖装配
  features/
    record/     记录页与会话控制
    history/    骑行列表
    detail/     详情页（地图轨迹 + 曲线图）
    stats/      长期统计与趋势
    settings/   设置、传感器配对、导出备份
  domain/       纯逻辑，无 IO 依赖
    models/     Ride, TrackPoint, RideSummary 等
    analysis/   指标计算、心率区间、速度→颜色映射、趋势聚合
    recording/  记录状态机、轨迹点过滤、落盘缓冲
  data/
    db/         SQLite 打开、迁移、DAO
    ble/        心率与踏频订阅
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

测试集中在纯逻辑上：`domain/analysis`（爬升滤波、最高速平滑、心率区间边界、Haversine 距离、GCJ-02 转换）、`domain/recording`（状态机、批量落盘）、`data/db`（内存库跑 DAO）、`features/*`（Widget 测试，注入假的定位流与传感器流）。

真实 BLE 硬件、真实 GPS、地图渲染这三项不做自动化，手动验证。

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

轨迹坐标会跟随瓦片源：高德/腾讯这类 GCJ-02 源才把显示坐标转过去，OSM 这类 WGS-84 源保持原样，否则轨迹会整体偏移几百米。落盘与 GPX 导出始终是 WGS-84。

## 设计文档

- [设计文档](docs/superpowers/specs/2026-09-21-cycling-app-design.md)
- [实施计划 · 核心](docs/superpowers/plans/2026-09-21-cycling-app-core.md)
- [实施计划 · 详情/历史/统计/设置/地图/导出](docs/superpowers/plans/2026-09-21-cycling-app-plan-b.md)