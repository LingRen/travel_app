# 地图 SDK 迁移真机验证（2026-11-02）

## 目标

对 `map-sdk-migration` 变更做 Android 真机核对：确认高德原生底图在有 Key 时可用、无 Key / 错误 Key 时回落到内置栅格底图、覆盖层（轨迹 / 起终点 / 断口 / 指北 / 比例尺）与底图对齐、详情页可拖动缩放、30 分钟记录无明显性能退化。

**范围**：仅 Android（OPPO R9s Plus，`cb2e5863`）。iOS 按用户要求暂缓，不做构建与验证。

## 被测代码

| 位置 | 内容 |
| --- | --- |
| [map_backend.dart](file:///Users/ling/code/travel_app/lib/features/map/map_backend.dart) | 后端选择真值表：覆盖值 > Key > 默认 legacy |
| [amap_basemap.dart](file:///Users/ling/code/travel_app/lib/features/map/amap_basemap.dart) | 隐私声明、初始化、样式二进制、10 秒未出图回落、销毁 |
| [privacy_consent.dart](file:///Users/ling/code/travel_app/lib/features/privacy/privacy_consent.dart) | 首启隐私同意弹窗，拒绝后本会话不再弹 |
| [map_projection.dart](file:///Users/ling/code/travel_app/lib/features/map/map_projection.dart) | Web Mercator 屏幕投影与米/像素 |
| [live_route_map.dart](file:///Users/ling/code/travel_app/lib/features/record/live_route_map.dart) | 记录页 `_AmapBody`，320 ms 相机跟随 + 覆盖层 |
| [route_map.dart](file:///Users/ling/code/travel_app/lib/features/detail/route_map.dart) | 详情页 `_AmapBody`，手势相机 + 覆盖层 |
| [settings_page.dart](file:///Users/ling/code/travel_app/lib/features/settings/settings_page.dart) | 只读「底图」行 |

## 环境

- 设备：OPPO R9s Plus，Android 7.1.1（API 25），1080×1920 / density 480（360×640 dp）。
- adb：`~/Library/Android/sdk/platform-tools/adb`；截图统一落 `/tmp/map_sdk_*`。
- Key：`config/amap_map_key_android.txt`、`config/amap_key.txt` 已填（不进版本库）。
- **样式二进制缺失**：`assets/amap/style.data` 与 `style_extra.data` 不存在，`pubspec.yaml` 也未声明该目录。按实现这属于「提供了样式二进制」的反面分支，底图会使用 SDK 默认样式。因此本轮的「纸色样式」项只能验证**不崩溃 + 默认样式出图**，纸色外观需补样式文件后复验。
- 构建需关闭沙箱（sqlite3 native asset 下载 + Gradle 写 SDK 目录）。

## 安装与启动

```bash
# 有 Key
DRT=$(tr -d '[:space:]' < config/amap_map_key_android.txt)
WEB=$(tr -d '[:space:]' < config/amap_key.txt)
fvm flutter build apk --debug \
  --dart-define=AMAP_MAP_KEY_ANDROID="$DRT" \
  --dart-define=AMAP_WEB_KEY="$WEB"
adb install -r -t build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.ling.cycling_app/.MainActivity
adb exec-out screencap -p > /tmp/map_sdk_key_record.png
```

错误 Key / 无 Key 同理，分别把 `AMAP_MAP_KEY_ANDROID` 换成 `INVALID_KEY` 或去掉该参数。

## 验证清单

### 4.2 有 Key：记录页（30 分钟）
1. 首启弹出隐私同意说明，文案与链接可读；同意后底图出图。
2. 底图风格：无样式文件时使用 SDK 默认样式；不崩溃、无空白。
3. 相机跟随：开始记录后当前位置保持在屏幕中心，移动时无跳变。
4. 朝向箭头随航向旋转，走最短弧，不整圈倒转。
5. 起点标记随位置移动，比例尺数值与 web mercator 估算一致。
6. 断口（GPS 丢失 > 10 s）在轨迹上断开，不连线。
7. 30 分钟记录：掉帧与耗电与 legacy 后端无明显差异（`adb shell dumpsys gfxinfo` 帧耗时对比）。

### 4.3 无 Key / 错误 Key
1. 记录页与详情页显示内置栅格底图，轨迹与标记完整。
2. 错误 Key 时 10 秒内出现「地图暂时不可用」，记录继续累计距离。
3. 拒绝隐私说明后当次会话不重复弹窗，底图保持内置栅格。
4. 冷启动后如果之前同意过，不再弹窗且直接走原生底图。

### 4.4 坐标对齐
1. 同一路段分别用 `MAP_BACKEND=legacy` 与高德后端记录，把两张详情截图缩放对齐后叠加，轨迹整体偏移应在个位数像素。
2. 落盘坐标仍为 WGS-84（导出 GPX 抽查一个点与记录页精度一致）。

### 4.5 详情页
1. 双指缩放与拖动生效，覆盖层随相机同步刷新，无滞后或错位。
2. 起终点标记、短缺口虚线、断口端点绘制正确。
3. 矮视口（640 dp 高设备）地图保持约 45% 高度，不挤占下方汇总。

### 4.6 性能
1. 记录 30 分钟，`gfxinfo` 掉帧率与 legacy 对比。
2. 电量统计中地图进程耗电无明显上升。

## 结果（2026-11-02 室内执行）

| 项 | 结论 | 证据 |
| --- | --- | --- |
| 4.2 有 Key 记录页/详情页 | 通过（默认样式、相机跟随、断口） | `/tmp/map_sdk_record_key2.png`、`/tmp/oppo_follow_B.png`、`/tmp/gap_10_detail.png` |
| 4.3 无 Key / 错误 Key | 用户明确不处理，跳过 | — |
| 4.4 坐标对齐 | 间接通过，叠加对比待户外 | `/tmp/map_sdk_detail_drag.png` |
| 4.5 详情页交互 | 拖动、断口通过；缩放待验 | `/tmp/map_sdk_detail_drag.png`、`/tmp/gap_10_detail.png` |
| 4.6 性能 | 待户外 30 分钟 | — |

### 4.2 有 Key（有效 Key 构建）

- 首启隐私弹窗：通过。文案、政策入口、「暂不使用 / 同意」齐全，弹窗出现时底图保持 legacy，不阻塞页面（`/tmp/map_sdk_detail_amap.png`）。
- 同意后原生底图：通过。详情页出现高德底图、`高德地图` 标识与城市注记，轨迹、`起` / `终`、`北` 覆盖层同步绘制（`/tmp/map_sdk_detail_amap2.png`）。
- 记录页原生底图：通过。待机页拿到定位后即挂载高德平台视图（`AMapFlutter_AMapPlatformView onCreate` 日志，pid 21575），底图被纸色渐变压淡属设计效果；读数、指北、比例尺齐全（`/tmp/map_sdk_record_key2.png`）。
- 纸色样式：**按用户决定改用 SDK 默认样式**，不再要求 `assets/amap/style.data`。
- 相机跟随：通过。OPPO 上用 `com.ling.mockgps` 沿路线步进（30.654/104.072 → 104.0733，约 25.9 km/h），记录 50 秒累计 344 m、69 秒累计 481 m；日志里 `onCameraChangeFinish` 的 target 逐拍前进，截图中位置点始终在屏幕中心、轨迹留在身后、底图与覆盖层不漂移。
- 拖动：通过。底图平移后轨迹与终点标记保持相对位置，覆盖层与相机同步（`/tmp/map_sdk_detail_drag.png`）。
- 朝向箭头：方向正确、未验转向。记录页截图中箭头沿行进方向（正东）显示，模拟路线是直线，无法产生航向变化（`/tmp/gap_4_back.png`）。
- 断口：通过。记录中强停 `com.ling.mockgps` 制造 20 秒无定位后恢复，结束并保存；详情页出现 1 段短缺口，用虚线段连接，并标注「短缺口 1 段 · 虚线处未采集到定位」（`/tmp/gap_10_detail.png`）。
- 起终点：通过。详情页 `起` / `终` 标记与轨迹两端对齐，断口两端各自收口。
- 30 分钟与性能：未验。本次只跑到 6 分 31 秒，且 debug 包不足以判断掉帧与耗电，需要 profile/release 包 + 真实骑行。
- 冷启动再进详情：通过。已有同意记录时不再弹窗，直接使用原生底图（错误 Key 构建的同一会话验证，`amap_privacy_agreed=true`）。

### 4.3 无 Key / 错误 Key

用户决定不处理无 Key 相关项，本节跳过。自动化测试仍覆盖 legacy 分支的渲染与隐私拒绝路径。

### 4.4 坐标对齐

轨迹端点与 `起` / `终` 标记重合；拖动后仍重合（`/tmp/map_sdk_detail_drag.png`）。缺少同一路段 legacy / 原生两套截图的叠加对比，户外补验。

### 4.5 详情页交互

- 拖动：通过（见上）。
- 双指缩放：未验（adb 单点输入无法产生 pinch）。
- 断口与矮视口：未验。模拟数据无信号中断段；本机 360×640 dp 属于矮屏，地图高度按 45% 收缩后布局正常（截图中地图约 237 dp）。

### 4.6 性能

未验，需户外记录 30 分钟后对比 `gfxinfo`。

## 发现与待办

1. **已修复：点「同意」后可能残留第二个弹窗**。`ref.invalidate` 刷新期间 provider 仍带着上一次的 `false`，网关会再排一次弹窗，而原生底图已经挂载。修复方式：`_AmapPrivacyGateState` 增加 `_agreedThisSession`，点同意即切原生底图，不再依赖刷新时序（[privacy_consent.dart](file:///Users/ling/code/travel_app/lib/features/privacy/privacy_consent.dart)）。真机复验：重装后直接出原生底图，无弹窗。
2. **样式**：按用户决定使用高德 SDK 默认样式，`assets/amap/style.data` 不再是验收前置。仓库里现有的样式二进制加载逻辑保留（放了文件就生效）。
3. **无 Key / 错误 Key**：用户明确不在本轮处理，相关观察不再作为阻塞项。
4. 设备上遗留：16 条模拟记录（可重复生成覆盖），以及验证中产生的短记录，未清理。
