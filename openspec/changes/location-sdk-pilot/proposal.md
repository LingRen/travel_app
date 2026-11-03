# Proposal

## Why

记录中最影响回看体验的是定位空档：楼群、高架、树荫下系统 GPS 偶尔十几秒不给点，轨迹被画成断口或虚线。`geolocator` 只能拿到系统定位结果，在网络与基站可用时也无法主动融合 WiFi / 基站位置。高德定位 SDK 在国内做 GPS、WiFi、基站融合，理论上可以在这些「可联网补齐」的空档里补出点。

但这件事必须试点验证，不能直接替换：高德定位返回 GCJ-02、锁屏后台持续定位、耗电、精度门槛与现有断点逻辑的相互作用都还没有实测数据；而现有 `LocationPlatform` 抽象已经允许在不改会话逻辑的前提下接入第二个 provider。因此本变更只做「可开关的试点」，用预先定义的成功标准决定是否转正。

同样需要明确：高德定位补的是网络可解算的空档，**隧道、地下通道这类完全没有信号的场景仍然会断**；真值缺失时不得伪造轨迹。

## What Changes

- 在现有 `LocationPlatform` 抽象后新增高德定位实现（候选 `amap_flutter_location`，以 spike 结论为准），默认仍使用 `geolocator`。
- 新增 `LOCATION_PROVIDER=system|amap` 的 `--dart-define` 开关；release 默认 `system`，debug 构建在设置页「调试」分组提供运行时切换，便于同机 A/B。
- 高德定位返回 GCJ-02，接入时逆变换为 WGS-84（迭代近似，误差约 1~2 m）；落盘、统计、GPX 与既有记录继续使用 WGS-84，历史数据不改动。
- 引入精度门槛：精度差于阈值的定位点不进入记录会话，避免把基站级误差当成轨迹抖动。阈值与空档判定保持独立，`kGpsGapMs` / `kGapBridgeMaxMs` / `kGapBreakMinDistanceM` 不调整。
- 保留 Android 前台服务与 15 秒定位流看门狗；后台锁屏持续定位方案由 spike 决定（高德 SDK 自带后台模式或应用级前台服务），不满足则试点不转正。
- 定位源与配置纳入隐私合规：初始化前完成高德 SDK 要求的隐私声明调用；Key 复用地图原生 Key（见 `map-sdk-migration`），不进入版本库。
- 预置试点成功标准、对照方法与回滚方式，达到标准才考虑把默认值切到 `amap`。
- 明确不做：不删除 `geolocator`、不改断点阈值、不回填历史轨迹、不做轨迹后处理插值。

## Capabilities

### New Capabilities

- `location-acquisition`: 定义定位 provider 的选择与回滚、GCJ-02 → WGS-84 归一、精度门槛、后台与看门狗约束、试点成功标准与验证方法。

### Modified Capabilities

- `recording`: 记录状态增加「定位源」与试点开关；「信号弱 / 定位已恢复」判定继续基于真实点时间，不因 provider 改变；开始前权限校验与前台服务行为保持。
- `settings`: 「调试」分组新增定位源切换（仅 debug），release 不出现；关于区补充定位数据来源说明。

## Impact

- 受影响的规格：`location-acquisition`（新增）、`recording`、`settings`。
- 受影响的代码：`lib/data/location/location_service.dart`（新增 `AmapLocationPlatform` 与 provider 选择）、`lib/config/app_config.dart`、`lib/app/providers.dart`、`lib/features/record/record_controller.dart`（看门狗与状态）、`lib/features/record/handlebar_view.dart`（定位状态文案）、`lib/features/settings/settings_page.dart`（debug 开关）、Android / iOS 原生配置。
- 依赖：新增高德官方 Flutter 定位插件（候选 `amap_flutter_location`）；保留 `geolocator` 作为默认与回滚路径。
- 外部配置：高德 Android / iOS Key（与地图共用）绑定包名 + SHA1 / Bundle ID；确认定位 SDK 的后台定位与隐私合规要求。
- 测试：provider 选择、GCJ-02 逆变换、精度门槛、看门狗重建、无 Key 回落与 debug 开关的单元 / widget 测试；真实轨迹对照必须真机手动完成，并记录到 `openspec/verification/`。
- 文档：`README.md` 增加定位源开关、试点结论与回滚说明。

## Non-Goals

- 不在本变更内删除 `geolocator` 或改变默认定位源。
- 不修改断点阈值、距离 / 爬升滤波、轨迹抽稀与 GPX 结构。
- 不为历史记录回填或重新计算轨迹。
- 不做室内定位、蓝牙信标、地图匹配或路径吸附。
