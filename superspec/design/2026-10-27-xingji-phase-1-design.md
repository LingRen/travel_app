# 行迹 UI 改造 · 阶段一实施设计

- 日期：2026-10-27
- 对应变更：`openspec/changes/xingji-ui-redesign/`
- 对应任务：tasks 1–3，外加记录页类型浮标与历史页筛选入口的最小接入
- 状态：已获用户批准，按方案 A 执行

## 背景

OpenSpec 的 `design.md` 已定稿纸本令牌、封面、四 tab 外壳、五种运动类型与筛选语义。本阶段不重新讨论产品设计，只确定第一阶段如何落地，保证后续记录、回顾、统计、设置四组页面能复用同一套边界。

现有界面仍是深色沥青主题，页面依赖 `AppBar`、`SegmentedButton`、`Card` 与 `NavigationBar`。工作区还有未提交的领域层修改，本阶段不得覆盖或回退这些修改。

## 目标

- 用一套纸本令牌替换深色主题，所有页面共享颜色、字体、间距、圆角与印章。
- 建立封面、纸本导航栏、页眉、底部面板与按钮五个共享边界。
- 新增「登山」类型，完成类型选择面板与历史 / 统计共用筛选面板。
- 阶段末可运行：封面 → 待机记录页 → 切换运动类型 → 历史页打开筛选面板。
- 主题、迁移、类型、面板、封面与导航都有对应测试。

## 非目标

- 不在本阶段重做记录页 HUD、地图滤镜、动作区与结算页。
- 不在本阶段重做历史条目、详情、统计与设置页的内容版式。
- 不改记录引擎、数据库 schema、GPX、备份或 BLE 协议。
- 不做深色模式、运行时字体下载或高德瓦片样式改造。
- 不把历史与统计的筛选状态合并成一个全局 provider。

## 方案

采用「令牌 + 共享组件先行」：

1. 先替换 `lib/app/theme.dart` 与 `ThemeAccent`，让旧页面在过渡期仍能编译运行。
2. 再建立 `lib/app/ui/` 下的共享组件与 `CoverGate`，接入 `HomeShell`。
3. 最后加类型模型、类型视觉、类型面板与筛选面板，并在现有记录页 / 历史页做最小接入。
4. 阶段末跑测试与截图，停止并报告偏差。

不采用「页面直改后抽组件」，因为颜色与页眉会重复实现，第二阶段必然返工。不采用「全量重写」，因为 diff 过大、测试同时红，无法按阶段验收。

## 架构与组件边界

### 令牌层

`lib/app/theme.dart`：

- `AppPalette`：`paper`、`sheet`、`ink`、`muted`、`hairline`、`accent`、`accentInk`、`warning`、`danger`。
- `ThemeAccent`：朱砂 / 青瓷 / 黛蓝 / 藤黄，每种提供 `color`（原始颜料）与 `inkColor`（文字安全色）。
- 唯一亮色 `ThemeData`；状态栏透明、深色图标。
- 字体栈：衬线标题、无衬线正文、等宽数据；数字启用 tabular figures。
- 间距 4 / 8 / 12 / 16 / 24 / 32；圆角 2 / 3 / 18。

### 共享组件

`lib/app/ui/`：

- `PageHeader`：疏排栏目、年月、衬线大标题、可选右侧动作。
- `Seal`：方形印章，实心 / 空心两种，圆角 3。
- `PaperButton`：纸本按钮，主按钮用 `accentInk` 填充 + 纸色字。
- `PaperSheet`：贴底面板，上方圆角 18，全屏遮罩，拖动条、标题、副题与关闭。
- `PaperNavBar`：58 高、顶部发丝线、图标 20、标签 10、选中 `accentInk`。

### 外壳

- `CoverGate` 包在 `RecoveryGate` 外层；封面结束后才构建恢复提示。
- `HomeShell` 用 `IndexedStack` + `PaperNavBar`；历史 tab 内嵌 `Navigator`。
- 详情页在历史 tab 的导航栈内推入，底栏保持可见；系统返回交给当前 tab 的导航器。

### 类型与筛选

- `ActivityType` 新增 `mountaineering`，保留 `walking`。
- `activity_type_visuals.dart` 用穷尽 `switch` 提供图标、印章字与说明。
- `ActivityTypeChip` / `ActivityTypeSheet` 写入 `recordController.selectActivityType` 与 `lastActivityType`。
- `SportFilterTrigger` / `SportFilterSheet` 由历史与统计各自持有 filter provider。
- 阶段一只在现有记录页加类型浮标、在历史页页眉加筛选入口；内容版式留给后续阶段。

## 数据流

- 主题：设置仓储读取 `accent_theme` → `ThemeAccent.fromDb` 映射 → `CyclingApp` 构建 `ThemeData` → `AppPalette` 整树重着色。
- 类型：待机页选择 → `recordController.selectActivityType` → 设置仓储 `saveLastActivityType` → 冷启动 `AppSettings.lastActivityType` 恢复。
- 筛选：面板选择 → 历史 / 统计各自的 filter provider → 对应页面重新查询；不写数据库。
- 导航：`HomeShell` 选中 tab → `IndexedStack` 保留状态；历史 tab 的 `Navigator` 推入详情。

## 错误处理

- 主题值损坏：`fromDb` 回退朱砂，不写回损坏值。
- 类型值损坏：`ActivityType.fromDb` 回退骑行。
- 封面：不阻断恢复流程；封面期间不开始记录、不修改会话。
- 面板：选择失败或页面销毁时不写状态；筛选面板只改内存 provider。
- 测试环境：`disableAnimations` 时封面不淡出，避免测试等待动画。

## 测试策略

- 纯逻辑：`test/app/theme_test.dart`、`test/data/settings_repository_test.dart`、`test/domain/models/activity_type_test.dart`。
- 组件：`test/app/paper_ui_test.dart`、`test/app/cover_gate_test.dart`、`test/app/home_shell_test.dart`、`test/features/activity/*_test.dart`。
- 集成：`test/app/app_test.dart` 验证封面 → 主界面 → 恢复提示顺序。
- 不做 golden；用关键布局断言与人工截图。
- 阶段门禁：`flutter analyze`、相关测试、全量 `flutter test`。

## 迁移与回滚

- 主题值只做读取映射，不写 SQL 迁移；旧版本读到新值会回退天青，不崩溃。
- 类型只新增枚举值；旧记录保持原类型。
- 共享组件是新增文件，旧页面可逐步接入。
- 回滚按组 revert：令牌 → 组件/外壳 → 类型/筛选。领域层修改不在本阶段提交范围内。

## 验收

- 390×844 与 360×640 下，封面、待机记录页、历史页页眉、类型面板、筛选面板无裁切、无重叠。
- 四组主题色的文字安全色对纸底 ≥4.5:1。
- 类型面板当前项有实心印章、对勾与「当前」；五种类型说明不含「步频 / 步数」。
- 历史与统计筛选互不影响；切换筛选不改变记录数量与汇总。
- 阶段末停止，报告完成项、未完成项与偏差，等确认后进入 tasks 4–5。
