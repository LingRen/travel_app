# Spec Delta

## Purpose

定义记录页与详情页共用底图的后端选择、Key 配置、纸色样式、降级与坐标口径，让地图在无 Key 环境仍可运行，在有 Key 时使用高德原生 SDK。

## ADDED Requirements

### Requirement: 底图后端按配置选择并可回退

系统 SHALL 按配置在 `amap` 与 `legacy` 两种底图后端之间选择：显式覆盖值优先，其次按高德地图 Key 是否存在决定。无 Key 时 SHALL 使用 legacy（`flutter_map` 栅格瓦片），不得出现空白地图或启动失败。

#### Scenario: 配置了 Key

- **WHEN** 应用以非空 `AMAP_MAP_KEY_ANDROID` 或 `AMAP_MAP_KEY_IOS` 启动且未指定后端覆盖
- **THEN** 记录页与详情页使用高德原生地图渲染底图

#### Scenario: 没有 Key

- **WHEN** 应用未配置当前平台的地图 Key 启动
- **THEN** 两张地图回落到 legacy 栅格后端，轨迹、标记与断口照常显示

#### Scenario: 强制回退

- **WHEN** 启动参数指定 `MAP_BACKEND=legacy`
- **THEN** 即使存在 Key 也使用 legacy 后端，可用于排障

### Requirement: Key 与样式配置不进入版本库

高德地图 Key SHALL 只通过构建期 `--dart-define` 或原生侧本地配置注入，不得写入版本库、日志或界面。Android 与 iOS 的 Key SHALL 分开注入，按运行平台选择。仓库 SHALL 提供被忽略的本地 Key 文件示例与注入脚本。

#### Scenario: 本地开发注入

- **WHEN** 开发者存在对应平台的本地地图 Key 文件并运行本地启动脚本
- **THEN** 该平台 Key 被注入构建，仓库状态不显示真实 Key

#### Scenario: release 未配置 Key

- **WHEN** release 构建没有注入 Key
- **THEN** 构建成功并自动使用 legacy 后端，不因缺少 Key 失败

### Requirement: 纸色底图由自定义地图样式二进制提供

原生后端 SHALL 通过高德自定义地图样式二进制（`style.data` / `style_extra.data`）呈现纸色底图：降低饱和度、提高暖色，并弱化 POI 与路网对比。样式 SHALL 从打包资源读取并传给地图 SDK；插件不支持 styleId 时 SHALL NOT 伪造 styleId 配置。原生后端不得依赖客户端整层颜色矩阵；主题色变化不得重建或替换底图样式。

#### Scenario: 提供了样式二进制

- **WHEN** 应用把 `assets/amap/style.data` 打进包并加载地图
- **THEN** 底图呈现纸色风格，轨迹与界面主题色独立变化

#### Scenario: 未提供样式二进制

- **WHEN** 应用有 Key 但没有样式资源
- **THEN** 底图使用 SDK 默认样式，应用不崩溃、不把颜色滤镜套在原生地图上

### Requirement: 地图 SDK 初始化前取得隐私同意

应用 SHALL 在首次创建高德地图平台视图前展示隐私同意说明，说明底图请求会联网、记录数据仍只存本机，并给出高德隐私政策入口。只有用户同意后 SHALL 以 `hasContains` / `hasShow` / `hasAgree` 全为 true 初始化 SDK；未同意时 SHALL 继续使用 legacy 底图且不阻断记录。

#### Scenario: 首次启动

- **WHEN** 用户首次打开应用且未同意过隐私说明
- **THEN** 地图区域不创建高德平台视图，先展示隐私同意弹窗

#### Scenario: 同意后

- **WHEN** 用户点击同意
- **THEN** 同意状态本地持久化，后续启动直接按 Key 使用原生底图

#### Scenario: 拒绝

- **WHEN** 用户选择不同意
- **THEN** 应用继续以 legacy 纸色底图运行，记录功能可用，不出现白屏

### Requirement: 地图加载失败时降级而不阻断记录

地图 SDK 初始化失败、Key 无效或配额用尽时，系统 SHALL 在纸色底上显示中文「地图暂时不可用」说明，并保持记录、轨迹累计与详情其它内容可用。系统不得弹出阻断式对话框。

#### Scenario: Key 无效

- **WHEN** 高德 Key 绑定错误导致底图无法加载
- **THEN** 地图区域显示纸色底与「地图暂时不可用」，记录继续累计

#### Scenario: 无网络

- **WHEN** 设备离线且底图瓦片或原生地图无法下载
- **THEN** 已有轨迹覆盖层仍绘制，界面不崩溃

### Requirement: 显示坐标统一转换且落盘保持 WGS-84

底图与覆盖层使用 GCJ-02 时，系统 SHALL 在绘制前把 WGS-84 轨迹转换为 GCJ-02；转换 SHALL NOT 写入数据库、统计或 GPX。两种后端下轨迹与底图不得出现整体偏移。

#### Scenario: 高德底图上的轨迹

- **WHEN** 记录在高德原生底图上显示
- **THEN** 轨迹与底图道路对齐，不出现数百米的整体偏移

#### Scenario: 导出 GPX

- **WHEN** 用户从详情页导出 GPX 或恢复备份
- **THEN** 坐标仍为原始 WGS-84，与底图后端无关

### Requirement: 地图后端可测试且对页面保持稳定接口

地图 SHALL 以可注入的后端选择供 widget 测试强制使用 legacy，不得在测试环境创建 platform view。记录页与详情页对外的地图组件构造参数与关键测试标识 SHALL 保持稳定。

#### Scenario: widget 测试

- **WHEN** 测试环境没有地图 Key
- **THEN** 地图走 legacy 后端，现有 `live-route-map`、`detail-map-color-filter` 等标识仍可断言

#### Scenario: 后端选择单测

- **WHEN** 覆盖值、Key 存在性与默认值组合变化
- **THEN** 选择结果与设计中的真值表一致
