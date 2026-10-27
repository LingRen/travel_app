import 'package:cycling_app/app/theme.dart';
import 'package:cycling_app/domain/models/activity_type.dart';
import 'package:cycling_app/features/activity/activity_type_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    );

void main() {
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

  testWidgets('类型面板不承诺步频步数', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const ActivityTypeSheet(
      current: ActivityType.running,
      onSelected: _ignore,
    )));

    expect(find.textContaining('步频'), findsNothing);
    expect(find.textContaining('步数'), findsNothing);
    expect(find.text('配速 · 心率'), findsWidgets);
  });
}

void _ignore(ActivityType _) {}
