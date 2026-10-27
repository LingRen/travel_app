import 'package:cycling_app/app/theme.dart';
import 'package:cycling_app/domain/models/activity_type.dart';
import 'package:cycling_app/features/activity/sport_filter_sheet.dart';
import 'package:cycling_app/features/history/history_providers.dart';
import 'package:cycling_app/features/stats/stats_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('筛选面板列出全部运动与五种类型', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(SportFilterSheet(
      current: null,
      onSelected: (_) {},
    )));

    expect(find.text('筛选运动类型'), findsOneWidget);
    expect(find.text('全部运动'), findsOneWidget);
    for (final ActivityType type in ActivityType.values) {
      expect(find.text(type.label), findsOneWidget);
    }
    expect(find.text('当前'), findsOneWidget);
  });

  testWidgets('选择类型后回调并关闭面板', (WidgetTester tester) async {
    ActivityType? picked;
    await tester.pumpWidget(_wrap(SportFilterSheet(
      current: null,
      onSelected: (ActivityType? t) => picked = t,
    )));

    await tester.tap(find.byKey(const Key('sport-filter-mountaineering')));
    expect(picked, ActivityType.mountaineering);
  });

  test('历史与统计筛选状态互不影响', () {
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(historyFilterProvider.notifier).state = ActivityType.running;
    expect(c.read(statsFilterProvider), isNull);
    c.read(statsFilterProvider.notifier).state = ActivityType.hiking;
    expect(c.read(historyFilterProvider), ActivityType.running);
  });
}
