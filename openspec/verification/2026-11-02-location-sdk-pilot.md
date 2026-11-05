# 定位源试点验证记录（location-sdk-pilot）

- 状态：**真机配对骑行进行中（0 / 3 组）**
- 设备：OPPO R9s Plus（`cb2e5863`，Android，1080×1920 / 480 dpi）；
  Redmi K40（`192.168.1.2:42315`，Android 13，1080×2320）
- 应用：行迹 1.0.1 debug 构建（`com.ling.cycling_app`）
- 定位源：系统定位（`geolocator`，默认）/ 高德定位（`amap_flutter_location_plus` 3.1.2，试点）
- 判定标准：见 `openspec/changes/location-sdk-pilot/specs/location-acquisition/spec.md` 的
  「试点结论以对照数据决定」；至少 3 组同设备同路线配对记录，全部达标才讨论切换默认值。

---

## 1. 链路验证（MockGps，2026-11-03）

MockGps（`com.ling.mockgps`，`appops allow android:mock_location`）以 1 Hz 注入匀速位移
（约 7.18 m/s、精度 4 m），用于先证明「两个定位源都能把点写进记录」。这不是试点结论，
只验证链路与落库口径。

| 记录 | 定位源 | 时长 | 距离 | 点数 | 最大空档 | ≥10 s 空档 | ≥30 s 断点 | 最大隐含速度 |
|---|---|---|---|---|---|---|---|---|
| workout 3 | 系统 | 2:30 | 1061.8 m | 149 | 1.1 s | 0 | 0 | 7.2 m/s |
| workout 9 | 高德（修复后） | 2:12 | 903.9 m | 126 | 2.0 s | 0 | 0 | 7.2 m/s |
| workout 10 | 高德（清洁构建） | 0:52 | 330.0 m | 47 | 2.0 s | 0 | 0 | 7.2 m/s |

- 三条记录的库内距离（`workouts.distance_m`）与按轨迹点重算的 Haversine 距离完全一致，
  说明「落盘 WGS-84 → 统计」口径统一。
- 三个记录的精度均为 4 m，50 m 门槛未丢弃任何点；高德事件带 `mock=true`，说明插件确实
  读到了模拟点。

### 修复前的高德空流（已解决）

修复前高德源三次记录 `point_count = 0`、距离 0 m，界面却显示「信号良好」。真机日志确认
根因是：待机页的一次定位与记录的连续定位共用同一个高德原生客户端，一次定位 3 秒超时后的
`stop()` 把刚启动的连续定位一起停掉；同时 `_lastFixMs == 0` 让信号状态一直显示良好。

修复内容：
- `lib/data/location/amap_location_platform.dart`：记录接管后一次定位不再 `stop` 共享客户端
  （`_continuousActive`）；连续定位改为先订阅事件再 `configure` / `start`。
- `lib/features/record/record_controller.dart`：记录中从未收到定位超过 10 秒判为「信号弱」。

回归：`flutter analyze` 无问题，全量 905 条测试通过；修复后 workout 9 / 10 如上表。

---

## 2. 真机配对骑行记录（待填）

每组用同一条路线、同一台设备、连续两天内完成；两次记录间隔尽量短，天气与交通状况相近。
每次只切换「设置 → 调试 → 定位源」，切换后从下一次开始记录生效。

### 比较方案（2026-11-05 确认）

- **基准**：系统定位（`geolocator`）。不做厂商侧融合 / 平滑，落盘原生 WGS-84，
  用作路线与距离的基准。
- **候选**：高德定位。优势是空档 / 断点（GPS + 网络 + 基站融合）；代价是非 GPS 点
  海拔缺省为 0，可能拉塌爬升。
- **指标分工**：
  - 空档 / 断点：看高德是否显著更少（这是它唯一明确的优势项）；
  - 距离、最大隐含速度、异常跳变、爬升：以系统源为准。
- **切换门槛**：高德空档 / 断点显著更少，且距离偏差 ≤ 2–3%、爬升不失真，才讨论
  切换默认值；否则保持 `system`。
- **坐标口径**：高德 GCJ-02 逆变换为 5 轮迭代、容差 `1e-7` 度（约 1 cm），不会给
  距离对照引入偏差；底图绘制两者都经 `wgs84ToGcj02`，显示口径一致。

| 组 | 日期 | 定位源 | 时长 | 距离 | 爬升 | 点数 | ≥10 s 空档 | >30 s 断点 | 最大隐含速度 | 耗电 | 异常跳变 / 备注 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | 系统 | | | | | | | | | |
| 1 | | 高德 | | | | | | | | | |
| 2 | | 系统 | | | | | | | | | |
| 2 | | 高德 | | | | | | | | | |
| 3 | | 系统 | | | | | | | | | |
| 3 | | 高德 | | | | | | | | | |

### 每次记录的操作

1. 设置 → 调试 → 定位源，选本轮要测的源（记录中该按钮不可点）。
2. 记录 tab → 开始{类型}，按平时习惯骑行，途中至少经过一段树荫或楼间（城市峡谷）。
3. 结束并保存；记下开始 / 结束电量（可用系统电池页，或记录前后 `dumpsys battery | grep level`）。
4. 每组两次都完成后，用下面口径出数。

### 统计口径

- **≥10 s 空档**：相邻两个落盘点的时间差 ≥ 10 s 的次数；**>30 s 断点**同口径取 ≥ 30 s。
- **最大隐含速度**：相邻点距离 / 时间差的最大值；超过 30 m/s 视为异常跳变。
- **距离 / 爬升**：直接取 `workouts.distance_m` 与汇总里的爬升，与轨迹点重算值对照。
- **耗电**：记录期间电量百分比下降，按时长折算成 %/小时。

拉库出数（debug 构建可 `run-as`）：

```bash
adb -s cb2e5863 shell "run-as com.ling.cycling_app cat databases/cycling_app.db" > /tmp/cycling.db
sqlite3 -header -column /tmp/cycling.db \
  "SELECT id, datetime(started_at/1000,'unixepoch','localtime') t, distance_m, duration_s, point_count
   FROM workouts ORDER BY id DESC LIMIT 6;"
```

空档与跳变用脚本按 `track_points(ride_id, t_ms, lat, lon)` 相邻点计算，方法与第 1 节表格相同。

---

## 3. K40 后台闪退修复（2026-11-05）

用户报告 Redmi K40（`M2012K11AC` / alioth，Android 13，targetSdk 36）实测闪退。取证与结论如下。

### 崩溃证据

```bash
adb -s 192.168.1.2:42315 shell "dumpsys dropbox --print data_app_crash"
```

2026-11-05 共 3 条，均为 `RecordingForegroundService` 触发的
`ForegroundServiceDidNotStartInTimeException: Context.startForegroundService() did not then
call Service.startForeground()`：

| 时间 | Foreground | Crash 类型 | 服务 |
|---|---|---|---|
| 08:32:20 | Yes | EXCEPTION | `RecordingForegroundService` |
| 08:56:41 | Yes | EXCEPTION | `RecordingForegroundService` |
| 13:14:31 | No | EXCEPTION | `RecordingForegroundService` |

同缓冲区的 `data_app_wtf` 给出直接原因：

```
Background started FGS: Disallowed [... uidState: LAST; code:DENIED; startForegroundCount:0]
```

### 根因

记录期看门狗（`_restartStalledFixStream`）的重建时序是「取消旧订阅 → 立刻重新订阅」。
原实现把前台服务的生命周期绑在订阅上：

1. 旧订阅 `onCancel` → `stopService`；
2. 立刻重订阅 → `startForegroundService`。

熄屏骑行时重建发生在应用处于后台（`uidState: LAST`），Android 12+ / MIUI 拒绝后台启动
前台服务，服务没进前台，系统在超时后把异常抛到应用主线程，进程被判定崩溃。

### 修复内容

- `lib/data/location/amap_location_platform.dart`
  - 新增活跃订阅计数：记录期只拉起一次前台服务；
  - 全部退订后延迟 2 秒回收，重建订阅会取消回收定时器，因此不再产生
    `stopService` + `startForegroundService` 抖动。
- `android/app/src/main/kotlin/com/ling/cycling_app/MainActivity.kt`
  - `start` 调用包 try/catch，后台被拒时返回平台错误，异常不再落到主线程。
- `android/app/src/main/kotlin/com/ling/cycling_app/RecordingForegroundService.kt`
  - `onStartCommand` 内 `startForeground` 失败时 `stopSelf()`，主动撤掉这次启动，
    避免系统超时判定。

### 回归结果

- 单测：新增「看门狗重建订阅只拉起一次、不提前回收」「前台服务启动失败时定位流照常工作」；
  `fvm flutter analyze` 无问题，全量 907 条测试通过。
- K40 真机（19:03 开始，高德源）：
  - 19:04:02 最后一个定位点（连续流已产生落盘点）；
  - 19:04:05 切后台 + `settings put secure location_mode 0` 制造断流，看门狗约 19:04:17
    在后台重建订阅；
  - 19:05:36 检查：进程存活（pid 不变）、`RecordingForegroundService` 仍
    `isForeground=true`、日志无 `Disallowed` / `ForegroundServiceDidNotStart`、
    `exit-info` 无新增崩溃；
  - 19:06 结束后 3 秒内服务已回收，仅剩 geolocator 的常驻服务。
- 构建注意：`flutter build apk --debug` 必须带
  `--dart-define=AMAP_MAP_KEY_ANDROID=...`，否则定位源会静默回落到系统源，
  容易把「没走高德」误判成高德问题。

---

## 4. 结论（待 3 组配对完成后填写）

- 空档 / 断点：待定
- 距离与爬升偏差：待定
- 跳变：待定
- 锁屏断流与耗电：待定
- 默认值决策：**当前仍保持系统定位**；达标才记录「可讨论切换默认值」
