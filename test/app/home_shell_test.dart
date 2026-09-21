import 'package:cycling_app/app/home_shell.dart';
import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/features/record/record_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override 在 riverpod 3 里只从 misc 入口导出。
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

const AppSettings _testSettings = AppSettings(
  maxHeartRate: kDefaultMaxHeartRate,
  weightKg: kDefaultWeightKg,
  distanceUnit: DistanceUnit.kilometer,
  mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
);

void main() {
  /// 「记录」tab 现在是真实的 [RecordPage]，只需要设置 provider 就够渲染，
  /// 不需要真的连数据库。
  Future<void> pumpShell(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appSettingsProvider.overrideWithValue(
              const AsyncValue<AppSettings>.data(_testSettings),
            ),
          ],
          child: const MaterialApp(home: HomeShell()),
        ),
      );

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

  testWidgets('同一时刻只渲染当前 tab 的内容', (WidgetTester tester) async {
    await pumpShell(tester);

    // 记录 tab 是真实页面，另外三个 tab 都是占位页且处于 offstage。
    expect(find.byType(RecordPage), findsOneWidget);
    expect(find.text('开始骑行'), findsOneWidget);
    expect(find.byType(PlaceholderPage), findsNothing);
    expect(find.text('历史 页尚未实现'), findsNothing);

    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('历史')),
    );
    await tester.pumpAndSettle();

    expect(find.text('历史 页尚未实现'), findsOneWidget);
    expect(find.byType(RecordPage), findsNothing);
    expect(find.text('开始骑行'), findsNothing);
  });
}
