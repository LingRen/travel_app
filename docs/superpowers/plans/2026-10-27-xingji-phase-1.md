# 行迹 UI 改造阶段一实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 完成 OpenSpec tasks 1–3，并在现有记录页与历史页做类型浮标、筛选入口的最小接入，让应用以纸本主题、封面、纸本导航与五种运动类型运行。

**架构：** 先替换主题令牌与 `ThemeAccent`，再建立 `lib/app/ui/` 共享组件与 `CoverGate`，接入 `HomeShell` 的纸本导航与历史 tab 内嵌导航，最后补类型模型、类型视觉、类型面板与筛选面板。记录页 HUD 与历史条目版式不在本阶段重做。

**技术栈：** Flutter 3.47 / Dart 3.13 / Riverpod 3 / flutter_test / sqflite_common_ffi。

---

## 文件结构

**修改**

- `lib/app/theme.dart`：纸本色板、双强调色、亮色 `ThemeData`、字体与圆角刻度。
- `lib/data/settings_repository.dart`：`ThemeAccent` 四色与旧值映射。
- `lib/app/app.dart`：主题、状态栏、`CoverGate` 包裹顺序。
- `lib/app/home_shell.dart`：`PaperNavBar`、历史 tab 内嵌 `Navigator`。
- `lib/domain/models/activity_type.dart`：新增 `mountaineering`。
- `lib/features/record/handlebar_view.dart`：用类型浮标替换 `SegmentedButton`。
- `lib/features/history/history_page.dart`：页眉与筛选入口最小接入。
- `lib/features/stats/stats_page.dart`：页眉与筛选入口最小接入。
- `README.md`、`docs/superpowers/specs/2026-09-21-cycling-app-design.md`：品牌、主题与类型描述同步。

**新增**

- `lib/app/ui/page_header.dart`、`seal.dart`、`paper_button.dart`、`paper_sheet.dart`、`paper_nav_bar.dart`
- `lib/app/cover_gate.dart`
- `lib/features/activity/activity_type_visuals.dart`、`activity_type_chip.dart`、`activity_type_sheet.dart`、`sport_filter_trigger.dart`、`sport_filter_sheet.dart`
- `test/app/paper_ui_test.dart`、`test/app/cover_gate_test.dart`
- `test/domain/models/activity_type_test.dart`
- `test/features/activity/activity_type_visuals_test.dart`、`activity_type_sheet_test.dart`、`sport_filter_sheet_test.dart`

---

## 任务 1：纸本令牌与主题迁移

**文件：**
- 修改：`lib/app/theme.dart`
- 修改：`lib/data/settings_repository.dart`
- 测试：`test/app/theme_test.dart`
- 测试：`test/data/settings_repository_test.dart`

- [ ] **步骤 1：写失败的主题测试**

把 `test/app/theme_test.dart` 改为断言亮色纸本、完整 `AppPalette`、四组文字安全色与默认朱砂：

```dart
test('主题是亮色纸本，页面背景为纸色', () {
  final ThemeData theme = buildAppTheme();
  expect(theme.brightness, Brightness.light);
  expect(theme.colorScheme.brightness, Brightness.light);
  expect(theme.scaffoldBackgroundColor, const Color(0xFFF5F0E5));
});

test('AppPalette 提供完整纸本令牌', () {
  final AppPalette p = buildAppTheme().extension<AppPalette>()!;
  expect(p.paper, const Color(0xFFF5F0E5));
  expect(p.sheet, const Color(0xFFFCF9F2));
  expect(p.ink, const Color(0xFF1D1B17));
  expect(p.muted, const Color(0xFF746D60));
  expect(p.hairline, const Color(0xFFD8CEBB));
  expect(p.accentInk, ThemeAccent.cinnabar.inkColor);
});

test('四组文字安全色对纸底不低于 4.5:1', () {
  for (final ThemeAccent accent in ThemeAccent.values) {
    expect(
      _contrastRatio(accent.inkColor, const Color(0xFFF5F0E5)),
      greaterThanOrEqualTo(4.5),
      reason: accent.label,
    );
  }
});

test('默认主题是朱砂', () {
  expect(buildAppTheme().colorScheme.primary, ThemeAccent.cinnabar.inkColor);
});
```

- [ ] **步骤 2：运行测试确认失败**

运行：`flutter test test/app/theme_test.dart`
预期：FAIL，`AppPalette` 没有 `paper` / `inkColor`，默认主题仍是天青。

- [ ] **步骤 3：重写 `theme.dart`**

核心签名：

```dart
const Color kPaper = Color(0xFFF5F0E5);
const Color kSheet = Color(0xFFFCF9F2);
const Color kInk = Color(0xFF1D1B17);
const Color kMutedInk = Color(0xFF746D60);
const Color kHairlineColor = Color(0xFFD8CEBB);

const String kSerifFamily = 'Noto Serif SC';
const List<String> kSerifFallback = <String>['Songti SC', 'Noto Serif CJK SC', 'serif'];
const String kSansFamily = 'Noto Sans SC';
const List<String> kSansFallback = <String>['PingFang SC', 'Noto Sans CJK SC', 'sans-serif'];
const String kMonoFamily = 'IBM Plex Mono';
const List<String> kMonoFallback = <String>['monospace'];

const double kRadiusSeal = 3;
const double kRadiusSheet = 18;

class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.paper,
    required this.sheet,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.accent,
    required this.accentInk,
    required this.warning,
    required this.danger,
  });
  // ... copyWith / lerp 覆盖全部字段
}

ThemeData buildAppTheme([ThemeAccent accent = ThemeAccent.cinnabar]) {
  final Color ink = accent.inkColor;
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: ink,
    brightness: Brightness.light,
  ).copyWith(
    primary: ink,
    onPrimary: kPaper,
    secondary: ink,
    onSecondary: kPaper,
    error: kAppDanger,
    onError: kPaper,
    surface: kSheet,
    onSurface: kInk,
    surfaceContainerHighest: const Color(0xFFEFE8DA),
    onSurfaceVariant: kMutedInk,
    outline: kHairlineColor,
    outlineVariant: kHairlineColor,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: kPaper,
    extensions: <ThemeExtension<dynamic>>[
      AppPalette(
        paper: kPaper,
        sheet: kSheet,
        ink: kInk,
        muted: kMutedInk,
        hairline: kHairlineColor,
        accent: accent.color,
        accentInk: ink,
        warning: kAppWarning,
        danger: kAppDanger,
      ),
    ],
    // textTheme / appBarTheme / buttons / input / dialog / bottomSheet 全部改纸本
  );
}
```

兼容旧代码：保留 `kAppBackground`、`kAppSurface`、`kAppTextPrimary` 等常量，值指向纸本令牌，避免阶段一大量页面同时编译失败。

- [ ] **步骤 4：改 `ThemeAccent` 与映射**

```dart
enum ThemeAccent {
  cinnabar('cinnabar', '朱砂', Color(0xFFB4452F), Color(0xFFB4452F)),
  celadon('celadon', '青瓷', Color(0xFF7C9A8B), Color(0xFF4F6E60)),
  indigo('indigo', '黛蓝', Color(0xFF3E5A6B), Color(0xFF3E5A6B)),
  gamboge('gamboge', '藤黄', Color(0xFFC5A25E), Color(0xFF7E5F27));

  const ThemeAccent(this.dbValue, this.label, this.color, this.inkColor);
  final String dbValue;
  final String label;
  final Color color;
  final Color inkColor;

  static ThemeAccent fromDb(String? value) {
    if (value == 'mint') return ThemeAccent.celadon;
    if (value == 'sky' || value == 'violet') return ThemeAccent.indigo;
    if (value == 'amber') return ThemeAccent.gamboge;
    return ThemeAccent.values.firstWhere(
      (ThemeAccent a) => a.dbValue == value,
      orElse: () => ThemeAccent.cinnabar,
    );
  }
}
```

`AppSettings.accent` 默认改为 `ThemeAccent.cinnabar`。

- [ ] **步骤 5：更新设置仓储测试**

把旧的「默认天青」「琥珀回退天青」改成：

```dart
test('首次读取的主题色是朱砂', () async {
  expect((await repo.load()).accent, ThemeAccent.cinnabar);
});

test('旧主题值映射到新颜料', () async {
  for (final (String raw, ThemeAccent want) in <(String, ThemeAccent)>[
    ('mint', ThemeAccent.celadon),
    ('sky', ThemeAccent.indigo),
    ('violet', ThemeAccent.indigo),
    ('amber', ThemeAccent.gamboge),
  ]) {
    await SettingsDao(db).setString('accent_theme', raw);
    expect((await repo.load()).accent, want);
  }
});

test('未知主题值回退朱砂', () async {
  await SettingsDao(db).setString('accent_theme', 'no-such-theme');
  expect((await repo.load()).accent, ThemeAccent.cinnabar);
});
```

- [ ] **步骤 6：运行测试**

运行：`flutter test test/app/theme_test.dart test/data/settings_repository_test.dart`
预期：PASS。

- [ ] **步骤 7：Commit**

```bash
git add lib/app/theme.dart lib/data/settings_repository.dart test/app/theme_test.dart test/data/settings_repository_test.dart
git commit -m "feat: 纸本主题令牌与四色主题迁移"
```

---

## 任务 2：状态栏与首帧纸色

**文件：**
- 修改：`lib/app/app.dart`
- 测试：`test/app/app_test.dart`

- [ ] **步骤 1：写失败的 app 测试**

```dart
testWidgets('CyclingApp 以亮色纸本启动并设置深色状态栏图标', (WidgetTester tester) async {
  await pumpApp(tester);
  final MaterialApp app = tester.widget<MaterialApp>(find.byType(MaterialApp));
  expect(app.theme!.brightness, Brightness.light);
  expect(app.theme!.scaffoldBackgroundColor, const Color(0xFFF5F0E5));

  final AnnotatedRegion<SystemUiOverlayStyle> region =
      tester.widget(find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first);
  expect(region.value.statusBarIconBrightness, Brightness.dark);
  expect(region.value.statusBarColor, Colors.transparent);
});
```

- [ ] **步骤 2：运行确认失败**

运行：`flutter test test/app/app_test.dart`
预期：FAIL，找不到 `AnnotatedRegion<SystemUiOverlayStyle>`。

- [ ] **步骤 3：实现**

在 `CyclingApp.build` 的 `MaterialApp` 外包：

```dart
return AnnotatedRegion<SystemUiOverlayStyle>(
  value: const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: kPaper,
    systemNavigationBarIconBrightness: Brightness.dark,
  ),
  child: MaterialApp(
    title: '行迹',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(accent),
    home: const CoverGate(child: RecoveryGate(child: HomeShell())),
  ),
);
```

- [ ] **步骤 4：运行测试**

运行：`flutter test test/app/app_test.dart`
预期：PASS（封面任务完成前先允许 `CoverGate` 未实现而失败，任务 5 再一起通过；本步骤先只验证主题与状态栏）。

- [ ] **步骤 5：Commit**

```bash
git add lib/app/app.dart test/app/app_test.dart
git commit -m "feat: 纸本首帧与状态栏样式"
```

---

## 任务 3：共享纸本组件

**文件：**
- 新增：`lib/app/ui/page_header.dart`、`seal.dart`、`paper_button.dart`、`paper_sheet.dart`、`paper_nav_bar.dart`
- 测试：`test/app/paper_ui_test.dart`

- [ ] **步骤 1：写失败的组件测试**

```dart
testWidgets('PageHeader 渲染栏目、年月、标题与右侧动作', (WidgetTester tester) async {
  await tester.pumpWidget(_wrap(const PageHeader(
    eyebrow: '运 动 日 志',
    date: '二〇二六 · 十月',
    title: '行迹',
    trailing: Text('全部运动'),
  )));
  expect(find.text('运 动 日 志'), findsOneWidget);
  expect(find.text('二〇二六 · 十月'), findsOneWidget);
  expect(find.text('行迹'), findsOneWidget);
  expect(find.text('全部运动'), findsOneWidget);
});

testWidgets('PaperSheet 贴底且上方圆角 18', (WidgetTester tester) async {
  await tester.pumpWidget(_wrap(PaperSheet(child: Text('面板'))));
  final Container box = tester.widget<Container>(find.byKey(const Key('paper-sheet')));
  final BoxDecoration d = box.decoration! as BoxDecoration;
  expect((d.borderRadius! as BorderRadius).topLeft.x, 18);
  expect((d.borderRadius! as BorderRadius).bottomLeft.x, 0);
});

testWidgets('PaperNavBar 四个 tab 点击区域不小于 44', (WidgetTester tester) async {
  await tester.pumpWidget(_wrap(PaperNavBar(
    selectedIndex: 0,
    onSelected: (_) {},
    items: const <PaperNavItem>[
      PaperNavItem(icon: Icons.directions_bike, label: '记录'),
      PaperNavItem(icon: Icons.history, label: '历史'),
      PaperNavItem(icon: Icons.bar_chart, label: '统计'),
      PaperNavItem(icon: Icons.settings, label: '设置'),
    ],
  )));
  for (final String label in <String>['记录', '历史', '统计', '设置']) {
    expect(tester.getSize(find.text(label)).height, greaterThan(0));
    expect(tester.getSize(find.ancestor(
      of: find.text(label),
      matching: find.byType(InkWell),
    ).first).height, greaterThanOrEqualTo(44));
  }
});
```

- [ ] **步骤 2：运行确认失败**

运行：`flutter test test/app/paper_ui_test.dart`
预期：FAIL，文件不存在。

- [ ] **步骤 3：实现组件**

`PageHeader` 结构：

```dart
class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.eyebrow,
    required this.date,
    required this.title,
    this.trailing,
    super.key,
  });
  final String eyebrow;
  final String date;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(kSpaceXl, kSpaceL, kSpaceXl, kSpaceL),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(eyebrow, style: kLabelTextStyle)),
          Text(date, style: kLabelTextStyle),
        ]),
        const SizedBox(height: kSpaceM),
        Row(children: <Widget>[
          Expanded(child: Text(title, style: kPageTitleTextStyle)),
          if (trailing != null) trailing!,
        ]),
      ],
    ),
  );
}
```

`Seal`：

```dart
class Seal extends StatelessWidget {
  const Seal({required this.label, this.filled = true, this.size = 40, super.key});
  final String label;
  final bool filled;
  final double size;
  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? p.accentInk : Colors.transparent,
        border: filled ? null : Border.all(color: p.hairline),
        borderRadius: BorderRadius.circular(kRadiusSeal),
      ),
      child: Text(label, style: TextStyle(
        fontFamily: kSerifFamily,
        fontSize: size * 0.45,
        color: filled ? p.paper : p.muted,
      )),
    );
  }
}
```

`PaperButton` 提供 `filled` 与 `ghost` 两种；`PaperSheet` 用 `Container(key: Key('paper-sheet'), decoration: BoxDecoration(color: p.sheet, borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusSheet))))`；`PaperNavBar` 用 `SafeArea(top: false)` + 58 高 `Row`，每项 `InkWell` 包 `SizedBox(height: 58)`。

- [ ] **步骤 4：运行测试**

运行：`flutter test test/app/paper_ui_test.dart`
预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add lib/app/ui test/app/paper_ui_test.dart
git commit -m "feat: 纸本页眉、印章、按钮、面板与导航组件"
```

---

## 任务 4：封面 CoverGate

**文件：**
- 新增：`lib/app/cover_gate.dart`
- 测试：`test/app/cover_gate_test.dart`

- [ ] **步骤 1：写失败的封面测试**

```dart
testWidgets('封面 1.2 秒后自动退场', (WidgetTester tester) async {
  await tester.pumpWidget(_wrap(const CoverGate(child: Text('主界面'))));
  expect(find.text('行迹'), findsOneWidget);
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('主界面'), findsOneWidget);
});

testWidgets('点击封面立即跳过', (WidgetTester tester) async {
  await tester.pumpWidget(_wrap(const CoverGate(child: Text('主界面'))));
  await tester.tap(find.byType(GestureDetector).first);
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('主界面'), findsOneWidget);
});

testWidgets('减少动态效果时 600ms 且不淡出', (WidgetTester tester) async {
  await tester.pumpWidget(_wrap(
    const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: CoverGate(child: Text('主界面')),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  expect(find.text('主界面'), findsOneWidget);
});
```

- [ ] **步骤 2：运行确认失败**

运行：`flutter test test/app/cover_gate_test.dart`
预期：FAIL，`cover_gate.dart` 不存在。

- [ ] **步骤 3：实现**

```dart
class CoverGate extends StatefulWidget {
  const CoverGate({required this.child, super.key});
  final Widget child;
  @override
  State<CoverGate> createState() => _CoverGateState();
}

class _CoverGateState extends State<CoverGate> {
  bool _done = false;
  Timer? _timer;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timer != null) return;
    _reduced = MediaQuery.of(context).disableAnimations;
    _timer = Timer(Duration(milliseconds: _reduced ? 600 : 1200), _finish);
  }

  void _finish() {
    _timer?.cancel();
    if (!mounted) return;
    setState(() => _done = true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: ColoredBox(
        color: context.palette.paper,
        child: AnimatedOpacity(
          opacity: 1,
          duration: Duration(milliseconds: _reduced ? 0 : 300),
          child: const _CoverBody(),
        ),
      ),
    );
  }
}
```

自动退场时先淡出再切换：用一个 `_fading` 状态，`_finish` 设 `_fading = true`，`AnimatedOpacity` 完成后 `setState(_done = true)`；减少动态效果直接 `_done = true`。`_CoverBody` 包含「行迹」「XINGJI」、标语、副题、本机声明与 `Seal(label: '迹')`。

- [ ] **步骤 4：运行测试**

运行：`flutter test test/app/cover_gate_test.dart`
预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add lib/app/cover_gate.dart test/app/cover_gate_test.dart
git commit -m "feat: 行迹冷启动封面与减少动态效果"
```

---

## 任务 5：接入封面与恢复顺序

**文件：**
- 修改：`lib/app/app.dart`
- 测试：`test/app/app_test.dart`、`test/app/recovery_gate_test.dart`

- [ ] **步骤 1：更新 app 测试**

```dart
testWidgets('启动先显示封面，再进入四 tab 主界面', (WidgetTester tester) async {
  await tester.pumpWidget(...);
  expect(find.text('行迹'), findsOneWidget);
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pumpAndSettle();
  expect(find.byType(HomeShell), findsOneWidget);
  expect(find.byType(PaperNavBar), findsOneWidget);
});
```

恢复提示测试：先 pump 封面，再等 1.5 秒，最后断言「检测到未结束的骑行」出现。

- [ ] **步骤 2：运行确认失败**

运行：`flutter test test/app/app_test.dart test/app/recovery_gate_test.dart`
预期：FAIL，`CoverGate` 尚未接入。

- [ ] **步骤 3：接入**

`CyclingApp.home` 改为：

```dart
home: const CoverGate(child: RecoveryGate(child: HomeShell())),
```

- [ ] **步骤 4：运行测试**

运行：`flutter test test/app/app_test.dart test/app/recovery_gate_test.dart`
预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add lib/app/app.dart test/app/app_test.dart test/app/recovery_gate_test.dart
git commit -m "feat: 封面先于恢复提示进入主界面"
```

---

## 任务 6：纸本导航与历史 tab 内嵌导航

**文件：**
- 修改：`lib/app/home_shell.dart`
- 测试：`test/app/home_shell_test.dart`

- [ ] **步骤 1：更新测试**

把 `NavigationBar` 断言改为 `PaperNavBar`；增加：

```dart
testWidgets('详情在历史 tab 内推入且底栏保持可见', (WidgetTester tester) async {
  await pumpShell(tester);
  await tester.tap(tab('历史'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(WorkoutCard));
  await tester.pumpAndSettle();
  expect(find.byType(DetailPage), findsOneWidget);
  expect(find.byType(PaperNavBar), findsOneWidget);
  await tester.pageBack();
  await tester.pumpAndSettle();
  expect(find.byType(HistoryPage), findsOneWidget);
});
```

- [ ] **步骤 2：运行确认失败**

运行：`flutter test test/app/home_shell_test.dart`
预期：FAIL，仍是 `NavigationBar`，详情不在历史栈。

- [ ] **步骤 3：实现**

`HomeShell` 结构：

```dart
final GlobalKey<NavigatorState> _historyNavKey = GlobalKey<NavigatorState>();

Scaffold(
  body: IndexedStack(
    index: _index,
    children: <Widget>[
      const RecordPage(),
      NavigatorPopHandler(
        onPopWithResult: (_) => _historyNavKey.currentState?.maybePop(),
        child: Navigator(
          key: _historyNavKey,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const HistoryPage(),
          ),
        ),
      ),
      const StatsPage(),
      const SettingsPage(),
    ],
  ),
  bottomNavigationBar: PaperNavBar(
    selectedIndex: _index,
    onSelected: (int i) => setState(() => _index = i),
    items: const <PaperNavItem>[...],
  ),
)
```

`HistoryPage` 的卡片点击用 `Navigator.of(context).push(...)`，自然落到内嵌导航。

- [ ] **步骤 4：运行测试**

运行：`flutter test test/app/home_shell_test.dart`
预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add lib/app/home_shell.dart lib/features/history/history_page.dart test/app/home_shell_test.dart
git commit -m "feat: 纸本底部导航与历史内嵌详情导航"
```

---

## 任务 7：登山类型与类型视觉

**文件：**
- 修改：`lib/domain/models/activity_type.dart`
- 新增：`lib/features/activity/activity_type_visuals.dart`
- 测试：`test/domain/models/activity_type_test.dart`
- 测试：`test/features/activity/activity_type_visuals_test.dart`

- [ ] **步骤 1：写失败的类型测试**

```dart
test('五种类型与稳定标识', () {
  expect(ActivityType.values.map((ActivityType t) => t.dbValue), <String>[
    'cycling', 'running', 'walking', 'hiking', 'mountaineering',
  ]);
  expect(ActivityType.mountaineering.label, '登山');
  expect(ActivityType.mountaineering.usesPace, isTrue);
  expect(ActivityType.mountaineering.supportsPower, isFalse);
});

test('未知类型回退骑行', () {
  expect(ActivityType.fromDb('swimming'), ActivityType.cycling);
});
```

视觉测试：

```dart
test('五种类型都有说明且不承诺步频步数', () {
  for (final ActivityType type in ActivityType.values) {
    final String desc = activityTypeDescription(type);
    expect(desc, isNotEmpty);
    expect(desc.contains('步频'), isFalse);
    expect(desc.contains('步数'), isFalse);
  }
  expect(activityTypeDescription(ActivityType.cycling), '速度 · 踏频 · 功率');
  expect(activityTypeDescription(ActivityType.mountaineering), '爬升 · 海拔 · 心率');
});
```

- [ ] **步骤 2：运行确认失败**

运行：`flutter test test/domain/models/activity_type_test.dart test/features/activity/activity_type_visuals_test.dart`
预期：FAIL，没有 `mountaineering` 与视觉文件。

- [ ] **步骤 3：实现**

```dart
enum ActivityType {
  cycling('cycling', '骑行', supportsCadence: true, supportsPower: true),
  running('running', '跑步', usesPace: true),
  walking('walking', '健走', usesPace: true),
  hiking('hiking', '徒步', usesPace: true),
  mountaineering('mountaineering', '登山', usesPace: true);
  // ... 构造与字段不变
}
```

`activity_type_visuals.dart`：

```dart
IconData activityTypeIcon(ActivityType type) => switch (type) {
  ActivityType.cycling => Icons.directions_bike,
  ActivityType.running => Icons.directions_run,
  ActivityType.walking => Icons.directions_walk,
  ActivityType.hiking => Icons.hiking,
  ActivityType.mountaineering => Icons.terrain,
};

String activityTypeSeal(ActivityType type) => switch (type) {
  ActivityType.cycling => '骑',
  ActivityType.running => '跑',
  ActivityType.walking => '走',
  ActivityType.hiking => '徒',
  ActivityType.mountaineering => '登',
};

String activityTypeDescription(ActivityType type) => switch (type) {
  ActivityType.cycling => '速度 · 踏频 · 功率',
  ActivityType.running || ActivityType.walking => '配速 · 心率',
  ActivityType.hiking => '配速 · 海拔 · 心率',
  ActivityType.mountaineering => '爬升 · 海拔 · 心率',
};
```

- [ ] **步骤 4：运行测试**

运行：`flutter test test/domain/models/activity_type_test.dart test/features/activity/activity_type_visuals_test.dart`
预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add lib/domain/models/activity_type.dart lib/features/activity/activity_type_visuals.dart test/domain/models/activity_type_test.dart test/features/activity/activity_type_visuals_test.dart
git commit -m "feat: 新增登山类型与类型视觉说明"
```

---

## 任务 8：类型浮标与类型面板

**文件：**
- 新增：`lib/features/activity/activity_type_chip.dart`
- 新增：`lib/features/activity/activity_type_sheet.dart`
- 测试：`test/features/activity/activity_type_sheet_test.dart`

- [ ] **步骤 1：写失败的面板测试**

```dart
testWidgets('类型面板列出五种类型并标出当前项', (WidgetTester tester) async {
  ActivityType? picked;
  await tester.pumpWidget(_wrap(ActivityTypeSheet(
    current: ActivityType.cycling,
    onSelected: (ActivityType t) => picked = t,
  )));
  expect(find.text('选择运动'), findsOneWidget);
  for (final ActivityType type in ActivityType.values) {
    expect(find.text(type.label), findsOneWidget);
  }
  expect(find.text('当前'), findsOneWidget);
  await tester.tap(find.text('登山'));
  expect(picked, ActivityType.mountaineering);
});
```

- [ ] **步骤 2：运行确认失败**

运行：`flutter test test/features/activity/activity_type_sheet_test.dart`
预期：FAIL，文件不存在。

- [ ] **步骤 3：实现**

`ActivityTypeChip`：

```dart
class ActivityTypeChip extends StatelessWidget {
  const ActivityTypeChip({
    required this.type,
    required this.onTap,
    super.key,
  });
  final ActivityType type;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(kRadiusButton),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: kSpaceM, vertical: kSpaceS),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(activityTypeIcon(type), size: 18, color: context.palette.accentInk),
        const SizedBox(width: kSpaceS),
        Text(type.label, style: kBodyTextStyle),
        const SizedBox(width: kSpaceXs),
        Icon(Icons.expand_more, size: 18, color: context.palette.muted),
      ]),
    ),
  );
}
```

`ActivityTypeSheet` 用 `PaperSheet`，每行 `Seal(label: activityTypeSeal(type), filled: current == type)` + 类型名 + 说明 + 当前项「当前」+ 对勾。点击调用 `onSelected` 并 `Navigator.pop`。

- [ ] **步骤 4：运行测试**

运行：`flutter test test/features/activity/activity_type_sheet_test.dart`
预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add lib/features/activity/activity_type_chip.dart lib/features/activity/activity_type_sheet.dart test/features/activity/activity_type_sheet_test.dart
git commit -m "feat: 纸本运动类型浮标与选择面板"
```

---

## 任务 9：记录页接入类型浮标

**文件：**
- 修改：`lib/features/record/handlebar_view.dart`
- 测试：`test/features/record/record_views_test.dart`

- [ ] **步骤 1：更新记录页测试**

```dart
testWidgets('待机页显示类型浮标并可打开面板', (WidgetTester tester) async {
  await pumpHandlebar(tester, state: const RecordState());
  expect(find.text('骑行'), findsOneWidget);
  await tester.tap(find.text('骑行'));
  await tester.pumpAndSettle();
  expect(find.text('选择运动'), findsOneWidget);
  expect(find.text('登山'), findsOneWidget);
});
```

- [ ] **步骤 2：运行确认失败**

运行：`flutter test test/features/record/record_views_test.dart`
预期：FAIL，仍是 `SegmentedButton`，没有「选择运动」。

- [ ] **步骤 3：实现**

把 `handlebar_view.dart` 中的 `SegmentedButton<ActivityType>` 替换为：

```dart
ActivityTypeChip(
  type: selectedActivityType,
  onTap: () => showPaperSheet<void>(
    context: context,
    builder: (_) => ActivityTypeSheet(
      current: selectedActivityType,
      onSelected: onSelectActivityType,
    ),
  ),
),
```

记录中 / 暂停时不渲染这个 chip（当前代码只在未开始态渲染，保留该条件）。

- [ ] **步骤 4：运行测试**

运行：`flutter test test/features/record/record_views_test.dart`
预期：PASS（旧断言同步改为新 chip）。

- [ ] **步骤 5：Commit**

```bash
git add lib/features/record/handlebar_view.dart test/features/record/record_views_test.dart
git commit -m "feat: 记录待机页接入纸本类型浮标"
```

---

## 任务 10：共用筛选面板与历史 / 统计最小接入

**文件：**
- 新增：`lib/features/activity/sport_filter_trigger.dart`
- 新增：`lib/features/activity/sport_filter_sheet.dart`
- 修改：`lib/features/history/history_page.dart`
- 修改：`lib/features/stats/stats_page.dart`
- 测试：`test/features/activity/sport_filter_sheet_test.dart`
- 测试：`test/features/history/history_page_test.dart`
- 测试：`test/features/stats/stats_page_test.dart`

- [ ] **步骤 1：写失败的筛选测试**

```dart
testWidgets('筛选面板列出全部运动与五种类型', (WidgetTester tester) async {
  await tester.pumpWidget(_wrap(SportFilterSheet(
    current: null,
    onSelected: (_) {},
  )));
  expect(find.text('筛选运动'), findsOneWidget);
  expect(find.text('全部运动'), findsOneWidget);
  for (final ActivityType type in ActivityType.values) {
    expect(find.text(type.label), findsOneWidget);
  }
});

test('历史与统计筛选状态互不影响', () {
  final ProviderContainer c = ProviderContainer();
  addTearDown(c.dispose);
  c.read(historyFilterProvider.notifier).state = ActivityType.running;
  expect(c.read(statsFilterProvider), isNull);
  c.read(statsFilterProvider.notifier).state = ActivityType.hiking;
  expect(c.read(historyFilterProvider), ActivityType.running);
});
```

- [ ] **步骤 2：运行确认失败**

运行：`flutter test test/features/activity/sport_filter_sheet_test.dart`
预期：FAIL，文件不存在。

- [ ] **步骤 3：实现**

`SportFilterTrigger` 是「全部运动 ⌄」文本按钮；`SportFilterSheet` 用 `PaperSheet`，第一行「全部运动」，其后五种类型，当前项带对勾与「当前」。选择后 `Navigator.pop` 并回调。

历史页与统计页在现有 `Scaffold` 顶部插入 `PageHeader`（保留旧 AppBar 或暂时移除，阶段一以页眉替换 AppBar），`trailing` 为 `SportFilterTrigger`。筛选 provider 已独立，无需合并。

- [ ] **步骤 4：运行测试**

运行：`flutter test test/features/activity/sport_filter_sheet_test.dart test/features/history/history_page_test.dart test/features/stats/stats_page_test.dart`
预期：PASS（旧断言同步改为页眉文本）。

- [ ] **步骤 5：Commit**

```bash
git add lib/features/activity lib/features/history/history_page.dart lib/features/stats/stats_page.dart test/features/activity test/features/history test/features/stats
git commit -m "feat: 历史与统计共用纸本筛选面板"
```

---

## 任务 11：文档同步

**文件：**
- 修改：`README.md`
- 修改：`docs/superpowers/specs/2026-09-21-cycling-app-design.md`

- [ ] **步骤 1：更新 README**

把标题与定位改为「行迹 XINGJI」、个人自用运动记录、纸本主题、五种运动类型；记录页段落改为纸本 HUD 与类型浮标；历史 / 统计段落说明筛选面板。保留安装、测试、目录结构等可执行命令。

- [ ] **步骤 2：更新旧设计文档**

把运动类型、筛选、主题色段落改为五种类型、共用筛选面板、纸本唯一主题与四色颜料。删除「深色主题」「薄荷 / 天青 / 紫罗兰」与「步频 / 步数」承诺。

- [ ] **步骤 3：验证**

运行：

```bash
rg -n "深色|沥青|薄荷|天青|紫罗兰|四种类型|步频|步数" README.md docs/superpowers/specs/2026-09-21-cycling-app-design.md
```

预期：只允许出现解释历史迁移的句子，不得有面向用户的旧描述。

- [ ] **步骤 4：Commit**

```bash
git add README.md docs/superpowers/specs/2026-09-21-cycling-app-design.md
git commit -m "docs: 同步行迹品牌、纸本主题与五种运动类型"
```

---

## 任务 12：阶段一验收

**文件：**
- 不新增文件；修复测试与格式问题。

- [ ] **步骤 1：静态分析**

运行：`flutter analyze`
预期：No issues found。

- [ ] **步骤 2：格式检查**

运行：`dart format --output=none --set-exit-if-changed lib test`
预期：退出码 0。

- [ ] **步骤 3：相关测试**

运行：

```bash
flutter test test/app test/domain/models/activity_type_test.dart test/features/activity test/features/record/record_views_test.dart test/features/history/history_page_test.dart test/features/stats/stats_page_test.dart
```

预期：全部 PASS。

- [ ] **步骤 4：全量测试**

运行：`flutter test`
预期：全部 PASS；若旧页面测试仍断言深色主题或 `NavigationBar`，在本步骤一并修正。

- [ ] **步骤 5：截图**

在 390×844 与 360×640、文字缩放 1.3 下截取：封面、待机记录页、类型面板、历史页页眉、筛选面板。对照 `design/exports/` 检查无裁切、无重叠。把截图保存到 `.screenshots/xingji-phase-1/`。

- [ ] **步骤 6：Commit**

```bash
git add -A
git commit -m "test: 阶段一纸本主题与类型筛选验收"
```

- [ ] **步骤 7：停止并报告**

报告完成项、未完成项、与设计稿的偏差；等用户确认后再进入 tasks 4–5。
