import 'package:cycling_app/app/cover_gate.dart';
import 'package:cycling_app/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) => MaterialApp(
  theme: buildAppTheme(),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: child,
  ),
);

void main() {
  testWidgets('封面显示品牌、标语与本机声明，期间不构建主界面', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const CoverGate(child: Text('主界面'))));

    expect(find.text('行迹'), findsOneWidget);
    expect(find.text('X I N G J I'), findsOneWidget);
    expect(find.text('把一路山河，\n收进一册薄薄的记录。'), findsOneWidget);
    expect(find.text('运动记录 · 单次分析 · 长期趋势'), findsOneWidget);
    expect(find.text('无账号 · 无云端 · 数据仅存于本机'), findsOneWidget);
    expect(find.text('主界面'), findsNothing);

    final Material background = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(CoverGate),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(background.color, kPaper);

    // 封面是 home 的根，没有 Scaffold。少了 Material，文字会套上 MaterialApp
    // 的兜底样式，纸面上多出一条黄色双下划线。
    expect(
      DefaultTextStyle.of(tester.element(find.text('行迹'))).style.decoration,
      isNot(TextDecoration.underline),
    );
  });

  testWidgets('封面 1.2 秒后自动淡出并进入主界面', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const CoverGate(child: Text('主界面'))));

    await tester.pump(const Duration(milliseconds: 1199));
    expect(find.text('主界面'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('主界面'), findsOneWidget);
  });

  testWidgets('点击封面立即跳过', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const CoverGate(child: Text('主界面'))));

    await tester.tap(find.byType(CoverGate));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('主界面'), findsOneWidget);
  });

  testWidgets('减少动态效果时停留 600ms 且不淡出', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(const CoverGate(child: Text('主界面')), disableAnimations: true),
    );

    await tester.pump(const Duration(milliseconds: 599));
    expect(find.text('主界面'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('主界面'), findsOneWidget);
  });
}
