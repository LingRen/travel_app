import 'package:cycling_app/app/theme.dart';
import 'package:cycling_app/app/ui/page_header.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/app/ui/paper_button.dart';
import 'package:cycling_app/app/ui/paper_nav_bar.dart';
import 'package:cycling_app/app/ui/paper_sheet.dart';
import 'package:cycling_app/app/ui/seal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('PageHeader 渲染栏目、年月、标题、摘要与右侧动作', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        const PageHeader(
          eyebrow: '运 动 日 志',
          date: '二〇二六 · 十月',
          title: '行迹',
          subtitle: '本月 4 次 · 102.0 km · 4 小时 31 分',
          trailing: Text('共 42 次'),
          subtitleTrailing: Text('全部运动 ⌄'),
        ),
      ),
    );

    expect(find.text('运 动 日 志'), findsOneWidget);
    expect(find.text('二〇二六 · 十月'), findsOneWidget);
    expect(find.text('行迹'), findsOneWidget);
    expect(find.text('本月 4 次 · 102.0 km · 4 小时 31 分'), findsOneWidget);
    expect(find.text('共 42 次'), findsOneWidget);
    expect(find.text('全部运动 ⌄'), findsOneWidget);

    final Text title = tester.widget<Text>(find.text('行迹'));
    expect(title.style!.fontFamily, kSerifFamily);
  });

  testWidgets('PaperSheet 贴底且上方圆角 18、下方直角', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PaperSheet(
              title: '运动类型',
              subtitle: '选择本次记录的运动 · 开始后锁定',
              onClose: () {},
              child: const Text('面板'),
            ),
          ),
        ),
      ),
    );

    final Container sheet = tester.widget<Container>(
      find.byKey(const Key('paper-sheet')),
    );
    final BoxDecoration decoration = sheet.decoration! as BoxDecoration;
    final BorderRadius radius = decoration.borderRadius! as BorderRadius;
    expect(radius.topLeft.x, kRadiusSheet);
    expect(radius.topRight.x, kRadiusSheet);
    expect(radius.bottomLeft.x, 0);
    expect(radius.bottomRight.x, 0);
    expect(find.text('运动类型'), findsOneWidget);
    expect(find.text('选择本次记录的运动 · 开始后锁定'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
  });

  testWidgets('PaperNavBar 四个 tab 点击区域不小于 44', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        PaperNavBar(
          selectedIndex: 0,
          onSelected: (_) {},
          items: const <PaperNavItem>[
            PaperNavItem(icon: Icons.route, label: '记录'),
            PaperNavItem(icon: Icons.menu_book_outlined, label: '历史'),
            PaperNavItem(icon: Icons.trending_up, label: '统计'),
            PaperNavItem(icon: Icons.tune, label: '设置'),
          ],
        ),
      ),
    );

    for (final String label in <String>['记录', '历史', '统计', '设置']) {
      final Finder inkWell = find
          .ancestor(of: find.text(label), matching: find.byType(InkWell))
          .first;
      final Size size = tester.getSize(inkWell);
      expect(size.height, greaterThanOrEqualTo(44), reason: label);
      expect(size.width, greaterThanOrEqualTo(44), reason: label);
    }

    final Text selected = tester.widget<Text>(find.text('记录'));
    final Text unselected = tester.widget<Text>(find.text('历史'));
    expect(selected.style!.color, ThemeAccent.cinnabar.inkColor);
    expect(unselected.style!.color, kMutedInk);
  });

  testWidgets('PaperNavBar 点击回调带上下标', (WidgetTester tester) async {
    int? picked;
    await tester.pumpWidget(
      _wrap(
        PaperNavBar(
          selectedIndex: 0,
          onSelected: (int i) => picked = i,
          items: const <PaperNavItem>[
            PaperNavItem(icon: Icons.route, label: '记录'),
            PaperNavItem(icon: Icons.menu_book_outlined, label: '历史'),
          ],
        ),
      ),
    );

    await tester.tap(find.text('历史'));
    expect(picked, 1);
  });

  testWidgets('Seal 实心用颜料底纸色字，空心用发丝线框', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        const Row(
          children: <Widget>[
            Seal(label: '骑', filled: true),
            Seal(label: '跑', filled: false),
          ],
        ),
      ),
    );

    final Container filled = tester.widget<Container>(
      find.descendant(
        of: find.byType(Seal).first,
        matching: find.byType(Container),
      ),
    );
    final BoxDecoration filledDecoration = filled.decoration! as BoxDecoration;
    expect(filledDecoration.color, ThemeAccent.cinnabar.inkColor);

    final Container hollow = tester.widget<Container>(
      find.descendant(
        of: find.byType(Seal).last,
        matching: find.byType(Container),
      ),
    );
    final BoxDecoration hollowDecoration = hollow.decoration! as BoxDecoration;
    expect(hollowDecoration.border, isNotNull);

    final Text filledText = tester.widget<Text>(find.text('骑'));
    final Text hollowText = tester.widget<Text>(find.text('跑'));
    expect(filledText.style!.color, kPaper);
    expect(hollowText.style!.color, ThemeAccent.cinnabar.inkColor);
  });

  testWidgets('PaperButton 高度 52，点击触发回调', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(
      _wrap(PaperButton(label: '开始骑行', onPressed: () => taps++)),
    );

    expect(tester.getSize(find.byType(PaperButton)).height, 52);
    await tester.tap(find.text('开始骑行'));
    expect(taps, 1);
  });
}
