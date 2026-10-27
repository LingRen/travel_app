# Tasks

## 1. 纸本令牌与主题迁移

- [x] 1.1 重写 `lib/app/theme.dart`：`AppPalette` 扩展为 `paper`、`sheet`、`ink`、`muted`、`hairline`、`accent`、`accentInk`、`warning`、`danger`，`ThemeData` 改为亮色纸本，补齐 3 / 18 两档圆角与衬线 / 无衬线 / 等宽字体栈。验证：`flutter test test/app/theme_test.dart` 通过，且页面可通过 `context.palette` 读取全部令牌。
- [x] 1.2 在 `lib/data/settings_repository.dart` 将 `ThemeAccent` 改为朱砂 / 青瓷 / 黛蓝 / 藤黄，默认朱砂；`fromDb` 实现 `mint→celadon`、`sky`/`violet→indigo`、`amber→gamboge`、未知值→`cinnabar`。验证：`test/data/settings_repository_test.dart` 覆盖四种旧值与未知值的映射。
- [x] 1.3 重写 `test/app/theme_test.dart` 的深色断言：改为亮色、纸底、墨字、四组 `accentInk` 对纸底 ≥4.5:1、数据色与安全色可区分、非文字标记 ≥3:1。验证：`flutter test test/app/theme_test.dart` 全绿。
- [x] 1.4 在 `lib/app/app.dart` 设置 `SystemUiOverlayStyle` 为透明状态栏 + 深色图标，并确认首帧背景为纸色。验证：`test/app/app_test.dart` 断言主题亮度与状态栏样式，冷启动无深色闪屏。

## 2. 外壳、封面与共享纸本组件

- [x] 2.1 新增 `lib/app/ui/page_header.dart`、`seal.dart`、`paper_button.dart`、`paper_sheet.dart`、`paper_nav_bar.dart`：页眉含疏排栏目、年月、衬线标题与右侧动作；面板贴底、上方圆角 18、全屏遮罩；导航栏 58 高、顶部发丝线、选中 `accentInk`。验证：新增 `test/app/paper_ui_test.dart`，断言页眉层级、面板圆角与导航点击区域 ≥44×44。
- [x] 2.2 新增 `lib/app/cover_gate.dart`：首帧后 1.2 秒自动退场，点击立即跳过，淡出 300ms；`MediaQuery.disableAnimations` 时停留 600ms 且不淡出。验证：新增 `test/app/cover_gate_test.dart` 用 `FakeAsync` 覆盖自动、点击、减少动态效果三条时序。
- [x] 2.3 将 `lib/app/app.dart` 的 `home` 改为 `CoverGate(child: RecoveryGate(child: HomeShell()))`，封面结束后才构建恢复提示。验证：`test/app/app_test.dart` 与 `test/app/recovery_gate_test.dart` 通过，未结束会话的提示出现在封面之后。
- [x] 2.4 在 `lib/app/home_shell.dart` 用 `PaperNavBar` 替换 `NavigationBar`，历史 tab 包一层 `Navigator`，外层接 `NavigatorPopHandler`；详情在历史 tab 内推入且底栏保持可见。验证：`test/app/home_shell_test.dart` 覆盖四 tab 切换、状态保留、详情推入与系统返回。
- [ ] 2.5 更新 `README.md` 的应用名、定位与概览段落为「行迹」、多运动与纸本主题，删除「骑行 App / 深色」的旧描述。验证：通读 README 无旧品牌与深色表述，命令与路径仍可执行。

## 3. 运动类型、选择与筛选

- [x] 3.1 在 `lib/domain/models/activity_type.dart` 新增 `mountaineering('mountaineering', '登山', usesPace: true)`，保留 `walking`；更新能力注释与 `fromDb` 回退。验证：新增 `test/domain/models/activity_type_test.dart` 覆盖五种类型、能力集与未知值回退骑行。
- [x] 3.2 新增 `lib/features/activity/activity_type_visuals.dart`，用穷尽 `switch` 提供图标、印章字与说明：骑行「速度 · 踏频 · 功率」，跑步 / 健走「配速 · 心率」，徒步「配速 · 海拔 · 心率」，登山「爬升 · 海拔 · 心率」。验证：`test/features/activity/activity_type_visuals_test.dart` 断言五种类型均有映射且文案不含「步频」「步数」。
- [x] 3.3 新增 `ActivityTypeChip` 与 `ActivityTypeSheet`，接入 `showPaperSheet`；当前项显示朱砂实心印章、对勾与「当前」，选择后调用 `recordController.selectActivityType`。验证：`test/features/activity/activity_type_sheet_test.dart` 覆盖打开、当前项标识与切换回调。
- [x] 3.4 在设置仓储保存 `lastActivityType`，冷启动待机页恢复；无值或损坏时回退骑行。验证：`test/data/settings_repository_test.dart` 覆盖持久化与回退，`test/features/record/record_views_test.dart` 断言待机页浮标与「开始登山」文案。
- [x] 3.5 新增 `SportFilterTrigger` 与 `SportFilterSheet`，历史与统计各用独立 filter provider，选项为全部运动 + 五种类型；筛选只改查看范围。验证：`test/features/activity/sport_filter_sheet_test.dart` 断言两页筛选互不影响，切换前后记录数量与汇总值不变。
- [ ] 3.6 更新 `docs/superpowers/specs/2026-09-21-cycling-app-design.md` 的运动类型、筛选与类型说明段落，改为五种类型与共用筛选面板。验证：文档内不再出现「四种类型」或「步频 / 步数」承诺。

## 4. 记录页

- [x] 4.1 将 `lib/features/record/handlebar_view.dart` 的两条 HUD 渐变改为纸色（顶部 0.94→0、底部 0.96→0），文字改墨色，移除深色投影，中间地图带保持原亮度。验证：`test/features/record/record_views_test.dart` 断言渐变颜色、文字颜色与地图带高度。
- [x] 4.2 重做待机态：类型浮标、日期时间、定位精度说明、四格读数与整宽「开始{类型}」；状态条不放动作键。验证：`test/features/record/record_views_test.dart` 覆盖定位已就绪与未就绪两种文案。
- [x] 4.3 记录中动作区改为「结束」1/3 靠左、「暂停 / 继续」2/3 靠右，结束先弹「结束本次{类型}？」确认。验证：`test/features/record/record_views_test.dart` 断言宽度比例、暂停切换与取消不改变状态。
- [x] 4.4 主读数与底部三格按类型分派：骑行显示速度 + 0–50 刻度 + 心率 / 踏频 / 功率；配速类型显示配速占位符 + 心率 / 海拔 / 爬升，不出现踏频与功率。验证：`test/features/record/record_views_test.dart` 覆盖骑行、跑步静止、登山三种布局。
- [x] 4.5 为 `live_route_map.dart` 的瓦片加降饱和暖色滤镜，轨迹用 `accentInk` + `#1D1B17CC` 描边，新增固定指北与比例尺，记录中 `InteractiveFlag.none`，GPS 中断 >10 秒断开。验证：`test/features/record/record_views_test.dart` 与 `test/domain/analysis/route_segments_test.dart` 通过。
- [x] 4.6 提示横幅浮在上下浮层之间，出现与收起不挤压读数；配速类型的整公里提示使用配速口径且不播报速度档。验证：`test/features/record/record_views_test.dart` 与 `test/domain/recording/cue_detector_test.dart` 覆盖布局不变与配速文案。
- [x] 4.7 新增结算页：显示「记录已保存」、距离、时长、写入历史说明与「完成」；完成后回到待机并保留上次类型。验证：`test/features/record/record_views_test.dart` 断言结算内容与完成后的待机态。
- [x] 4.8 定位权限、定位服务与连续写入失败的错误显示在动作区上方，附原因与下一步入口。验证：`test/features/record/record_views_test.dart` 覆盖权限被拒与服务关闭。
- [ ] 4.9 更新 `README.md` 的记录页段落为纸本 HUD、五类型、按类型主读数与筛选口径。验证：文档描述与 4.1–4.8 的实现一致，无旧「深色浮层」表述。

## 5. 历史与单次详情

- [x] 5.1 重做 `lib/features/history/history_page.dart` 页眉：「运 动 日 志」「二〇二六 · 十月」「行迹」、记录总数、本月摘要与「全部运动 ⌄」。验证：`test/features/history/history_page_test.dart` 断言页眉文本与筛选入口。
- [x] 5.2 历史按最近有记录的月份分组，首屏只渲染该月，底部「更早的记录 · N 次」在内存展开；筛选变化重置展开。验证：`test/features/history/history_page_test.dart` 覆盖有更早记录、无更早记录与筛选后重置。
- [x] 5.3 重做 `lib/features/history/ride_card.dart` 为日志条目：日期星期、标题 / 时间、出发时间、右上距离、四列次级读数与迷你曲线，条目间用发丝线。验证：`test/features/history/history_page_test.dart` 断言骑行显示均速与功率、跑步显示配速且功率列留空。
- [x] 5.4 历史空态按当前筛选显示「还没有{类型}记录」或「还没有运动记录」，并提供「查看全部运动」。验证：`test/features/history/history_page_test.dart` 覆盖登山筛选无结果。
- [x] 5.5 详情页接入历史 tab 的嵌套导航：顶部返回 + 「{类型}详情」、地图、标题与日期时间，底部导航保持可见。验证：`test/features/detail/detail_page_test.dart` 与 `test/app/home_shell_test.dart` 覆盖返回、tab 切换后保留详情栈。
- [x] 5.6 详情汇总改为两行三列六项读数，功率仅骑行显示，非骑行以海拔替代。验证：`test/features/detail/detail_page_test.dart` 覆盖骑行、徒步、登山三种汇总。
- [x] 5.7 详情曲线按类型命名：骑行「速度」，配速类型「配速」；心率区间条保留；踏频 / 功率区块只在骑行且有数据时出现。验证：`test/features/detail/detail_page_test.dart` 断言跑步与登山不出现踏频 / 功率及下滑提示。
- [x] 5.8 详情不展示天气、地点名称或路线名，无数据时不保留占位。验证：`test/features/detail/detail_page_test.dart` 断言无天气 / 地点文案与空白占位。
- [x] 5.9 详情地图竖屏 260dp、矮视口 45% 高度；信号中断段数与总时长显示在地图下方；GPX 导出入口与失败提示保留。验证：`test/features/detail/detail_page_test.dart` 覆盖横屏高度、中断摘要与导出失败。
- [ ] 5.10 更新 `README.md` 的历史、详情与 GPX 段落，改为月份分组、纸本条目与按类型读数。验证：文档描述与 5.1–5.9 一致，无「卡片列表」旧描述。

## 6. 统计

- [ ] 6.1 重做 `lib/features/stats/stats_page.dart` 页眉：「长 期 统 计」「二〇二六 · 十月」「里程」、记录总数、按月摘要与「全部运动 ⌄」；筛选无记录时显示空态与「查看全部运动」。验证：`test/features/stats/stats_page_test.dart` 断言页眉、筛选与空态。
- [ ] 6.2 周 / 月 / 年切换只更新累计与趋势，个人最佳始终基于当前筛选的全部历史。验证：`test/features/stats/stats_page_test.dart` 断言切到年后累计变化而最佳不变。
- [ ] 6.3 累计读数改为距离、时长、爬升三项主指标；功率次级行仅在骑行或全部运动且存在功率记录时出现。验证：`test/features/stats/stats_page_test.dart` 覆盖全部、跑步、空范围三种情况。
- [ ] 6.4 将 `lib/features/stats/trend_chart.dart` 从折线改为柱形：柱色 `accentInk`、顶部圆角 2、1/2/5 纵轴最多四档、横轴日期竖排、点按显示日期与距离。验证：`test/features/stats/trend_chart_test.dart` 覆盖月 / 周 / 年桶数与点按提示。
- [ ] 6.5 个人最佳改为 01–04 编号（最远距离、最快均速 / 最快配速、单次爬升、单次时长），功率最佳按适用性追加；配速类型用 `formatPace`。验证：`test/features/stats/stats_page_test.dart` 覆盖骑行、跑步与无记录。
- [ ] 6.6 统计页底部显示「统计口径 · 剔除停车空档」与「本机计算」，不出现云端或同步文案。验证：`test/features/stats/stats_page_test.dart` 断言页脚文本。
- [ ] 6.7 更新 `README.md` 的长期统计段落，改为三项主读数、柱形趋势、类型化个人最佳。验证：文档描述与 6.1–6.6 一致。

## 7. 设置与平台

- [ ] 7.1 重做 `lib/features/settings/settings_page.dart` 页眉与五个分组：身体、传感器、地图与外观、数据、关于；分组用发丝线与疏排小标题，不使用卡片。验证：`test/features/settings/settings_page_test.dart` 断言分组顺序与页眉。
- [ ] 7.2 身体参数改为「标签 + 当前值」行 + 底部编辑面板：最大心率 100–230 整数校验、体重与瓦片源校验、确认后立即保存、取消不改变；距离单位行内切换。验证：`test/features/settings/settings_page_test.dart` 覆盖合法保存、非法输入不关闭与单位即时生效。
- [ ] 7.3 传感器三行显示设备名与已连接 / 未连接；未连接行打开设备面板，已连接行提供断开并回到未连接。验证：`test/features/settings/settings_page_test.dart` 覆盖心率已连接、踏频未连接与断开。
- [ ] 7.4 地图与外观分组提供瓦片源行与四颗主题色点，色点带名称、当前项对勾与「当前 {颜料}」，点击立即保存并整树重着色。验证：`test/features/settings/settings_page_test.dart` 覆盖选择青瓷、重启后保持与不依赖保存按钮。
- [ ] 7.5 数据分组保留导出备份、恢复确认与中文错误提示，显示上次备份时间（如有）。验证：`test/features/settings/settings_page_test.dart` 与 `test/data/export/backup_test.dart` 覆盖导出、确认恢复与失败提示。
- [ ] 7.6 关于分组显示「行迹 XINGJI · 1.0.0」与「数据仅存本机」，不出现账号、云同步或社交入口；调试工具只在 `kDebugMode` 显示。验证：`test/features/settings/settings_page_test.dart` 断言关于文本与 release 下无调试分组。
- [ ] 7.7 将 Android `android/app/src/main/AndroidManifest.xml` 的 `android:label` 与 iOS `ios/Runner/Info.plist` 的 `CFBundleDisplayName` 改为「行迹」，并确认状态栏深色图标。验证：`grep` 两个平台配置得到「行迹」，真机冷启动标题与状态栏符合纸本主题。
- [ ] 7.8 更新 `README.md` 的设置、主题色与平台段落，以及旧设计文档的主题 / 强调色段落，改为纸本唯一主题与四色颜料。验证：文档中不再出现深色主题、薄荷 / 天青 / 紫罗兰三色描述。

## 8. 集成验收

- [ ] 8.1 运行 `flutter analyze` 与 `dart format --output=none --set-exit-if-changed lib test`，确认无新增告警与格式差异；同时检查 `git status`，确认未覆盖工作区已有的领域层未提交改动。
- [ ] 8.2 运行 `flutter test` 全量通过，重点确认 `test/app/**`、`test/features/**` 中旧深色主题、AppBar、SegmentedButton 与旧文案断言已全部更新。
- [ ] 8.3 在 390×844 与 360×640 两种逻辑尺寸、系统文字缩放 1.3 下逐页截图，对照 `design/exports/` 检查封面、记录待机 / 进行中、历史、详情、统计、设置与两个面板无裁切、无重叠、地图带 ≥120dp。
- [ ] 8.4 用旧版本数据库（含 `mint` / `sky` / `amber` 主题值与 `walking` 记录）走一次升级启动，确认主题映射、健走记录展示与新类型选择正常，记录数量与汇总不变。
- [ ] 8.5 真机户外强光下确认记录页速度 / 距离读数与 HUD 对比度；若不足，只调整纸色渐变不透明度与瓦片滤镜参数，不改交互与规格。

## Workflow follow-up

- 按项目评审要求完成 review 后归档本 change，并验证归档结果。
