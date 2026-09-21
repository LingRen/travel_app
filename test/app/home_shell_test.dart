import 'package:cycling_app/app/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpShell(WidgetTester tester) =>
      tester.pumpWidget(const MaterialApp(home: HomeShell()));

  int stackIndex(WidgetTester tester) =>
      tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;

  int selectedIndex(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  List<String> tabLabels(WidgetTester tester) {
    final NavigationBar bar =
        tester.widget<NavigationBar>(find.byType(NavigationBar));
    return bar.destinations
        .map((Widget d) => (d as NavigationDestination).label)
        .toList();
  }

  testWidgets('底部四个 tab 顺序为 记录/历史/统计/设置（设计文档 10）', (WidgetTester tester) async {
    await pumpShell(tester);

    expect(tabLabels(tester), <String>['记录', '历史', '统计', '设置']);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
  });

  testWidgets('默认停在「记录」tab', (WidgetTester tester) async {
    await pumpShell(tester);

    expect(stackIndex(tester), 0);
    expect(selectedIndex(tester), 0);
  });

  testWidgets('点击底部 tab 切换页面', (WidgetTester tester) async {
    await pumpShell(tester);

    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('统计')),
    );
    await tester.pumpAndSettle();
    expect(stackIndex(tester), 2);
    expect(selectedIndex(tester), 2);
    expect(find.text('统计 页尚未实现'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('设置')),
    );
    await tester.pumpAndSettle();
    expect(stackIndex(tester), 3);

    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('历史')),
    );
    await tester.pumpAndSettle();
    expect(stackIndex(tester), 1);
  });

  testWidgets('同一时刻只渲染当前 tab 的占位页', (WidgetTester tester) async {
    await pumpShell(tester);

    expect(find.byType(PlaceholderPage), findsOneWidget);
    expect(find.text('记录 页尚未实现'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('历史')),
    );
    await tester.pumpAndSettle();

    expect(find.text('历史 页尚未实现'), findsOneWidget);
    expect(find.text('记录 页尚未实现'), findsNothing);
  });
}
