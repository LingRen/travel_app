# Proposal

## Why

现有界面是深色沥青风格的工程化界面：Material 默认组件、AppBar、SegmentedButton、卡片与高饱和强调色，和已经完成的「行迹 XINGJI」纸本设计稿是两套语言。设计稿已经把品牌、版式、五种运动类型与筛选交互定稿，但代码仍停留在旧视觉与旧类型集合（骑行 / 跑步 / 健走 / 徒步），继续按页修补只会让两套语言长期并存。现在按设计稿做一次整体改造，把品牌、版式与多运动交互一次收口。

## What Changes

- **BREAKING** 移除深色沥青主题，改为唯一亮色「纸本」主题：纸色底、墨色字、发丝线、朱砂强调；不做深色模式。
- **BREAKING** 主题色选项由「薄荷 / 天青 / 紫罗兰」改为设计稿的四种中国颜料「朱砂 / 青瓷 / 黛蓝 / 藤黄」，默认朱砂；已存库的旧值按映射迁移，未知值回退朱砂。
- 建立品牌视觉系统：`行迹 / XINGJI` 字标、印章组件、衬线标题 + 无衬线正文 + 等宽数据的字体层级、间距与圆角刻度；应用显示名改为「行迹」。
- 新增冷启动封面页：品牌字标、标语「把一路山河，收进一册薄薄的记录。」、本机数据声明；可点击跳过，尊重减少动态效果设置。
- 重做四个主 tab 与单次详情：记录页（待机 / 进行中 / 暂停 / 结束）、历史、详情、统计、设置全部按设计稿改为纸本版式；页面改用页眉与细线分区，不再使用 Material AppBar 与卡片阴影。
- 记录页保留全屏地图 + 浮层读数，浮层由暗底白字改为纸色渐变 + 墨色字；底图叠加纸色滤镜，轨迹仍用主题色并加深色描边。
- 新增第五种运动类型「登山」；类型选择改为待机页 `骑行 ⌄` 浮标 + 底部面板，开始后锁定；已完成的记录保留原类型。
- 历史与统计改为 `全部运动 ⌄` 触发共用的运动筛选面板；筛选只改变查看范围，不修改数据。
- 按运动类型统一指标口径：骑行用速度与功率，跑步 / 徒步 / 登山用配速且不显示功率；个人最佳在配速类型下显示「最快配速」。
- 类型说明只写真实具备的能力，不承诺设计稿里尚未实现的「步频 / 步数」。
- 更新受影响的 widget 测试与主题门禁测试；补充封面、筛选面板与纸本主题的测试。

## Capabilities

### New Capabilities

- `brand-system`: 品牌字标、印章、纸墨色板、字体层级、间距与圆角刻度，以及亮色唯一主题与主题色迁移。
- `app-shell`: 冷启动封面页、底部四 tab 导航、页面外壳与状态栏样式。
- `activity-types`: 五种运动类型的能力集、类型选择与锁定、历史 / 统计筛选语义、按类型的指标口径。
- `recording`: 记录页在待机、记录中、暂停与结束后的布局、浮层可读性、地图呈现与动作区。
- `activity-review`: 历史列表与单次详情的内容层级、类型筛选入口、空态与按类型的读数呈现。
- `stats`: 统计页的范围切换、运动筛选、累计读数、趋势与个人最佳。
- `settings`: 设置页的分组结构、身体参数、传感器、地图与外观、数据与关于。

### Modified Capabilities

无。项目此前没有 OpenSpec 规格，本次为全部新增能力。

## Impact

- 主题与外壳：`lib/app/theme.dart`、`lib/app/app.dart`、`lib/app/home_shell.dart`、`lib/app/recovery_gate.dart`、`lib/main.dart`。
- 记录：`lib/features/record/*`（`handlebar_view.dart`、`record_page.dart`、`live_route_map.dart`、`ride_cue_banner.dart`、`device_picker_sheet.dart`）。
- 回顾：`lib/features/history/*`、`lib/features/detail/*`、`lib/features/stats/*`。
- 设置：`lib/features/settings/*`、`lib/data/settings_repository.dart`（主题色枚举与迁移）。
- 类型：`lib/domain/models/activity_type.dart`、`lib/domain/recording/cue_detector.dart`、`lib/domain/analysis/*` 中按类型分派的读数与文案。
- 平台：Android / iOS 应用显示名改为「行迹」；状态栏改为深色图标。
- 测试：`test/app/*`、`test/features/**` 中依赖深色主题、AppBar、SegmentedButton 文案与旧类型集合的断言。
- 依赖：不新增运行时依赖；不打包中文字体，使用平台衬线 / 无衬线 / 等宽回退链（设计稿字体为参考，见 design.md）。
- 文档：`README.md` 与 `docs/superpowers/specs/2026-09-21-cycling-app-design.md` 中关于深色主题、三种强调色与四种运动类型的描述需要同步。
