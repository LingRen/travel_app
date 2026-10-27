import 'package:cycling_app/app/theme.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/analysis/trend.dart';
import 'package:cycling_app/domain/models/workout.dart';
import 'package:cycling_app/domain/models/workout_status.dart';
import 'package:cycling_app/domain/models/workout_summary.dart';
import 'package:cycling_app/features/stats/trend_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const int _nowMs = 1748822400000; // 2025-06-02 08:00 UTC，测试只关心本地桶数

Workout _ride(double distanceM) => Workout(
      id: 1,
      startedAtMs: _nowMs,
      endedAtMs: _nowMs + 3600000,
      status: WorkoutStatus.finished,
      summary: WorkoutSummary(
        distanceM: distanceM,
        durationS: 1800,
        movingS: 1700,
        avgSpeedMps: 3,
        movingAvgSpeedMps: 3,
        maxSpeedMps: 5,
        elevationGainM: 10,
        pointCount: 10,
      ),
    );

Future<BarChartData> _pump(
  WidgetTester tester,
  TrendSummary trend,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: SizedBox(
        width: 390,
        child: TrendChart(trend: trend, unit: DistanceUnit.kilometer),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return tester.widget<BarChart>(find.byType(BarChart)).data;
}

void main() {
  testWidgets('周 / 月 / 年视图的柱数与桶数一致', (WidgetTester tester) async {
    final Map<TrendRange, int> expected = <TrendRange, int>{
      TrendRange.week: 7,
      TrendRange.month: 30,
      TrendRange.year: 12,
    };
    for (final MapEntry<TrendRange, int> entry in expected.entries) {
      final TrendSummary trend = buildTrend(
        <Workout>[_ride(10000)],
        range: entry.key,
        nowMs: _nowMs,
      );
      final BarChartData data = await _pump(tester, trend);
      expect(
        data.barGroups.length,
        entry.value,
        reason: entry.key.name,
      );
      expect(data.barGroups.length, trend.buckets.length);
    }
  });

  testWidgets('柱色、顶部圆角与触摸提示', (WidgetTester tester) async {
    final TrendSummary trend = buildTrend(
      <Workout>[_ride(12500)],
      range: TrendRange.week,
      nowMs: _nowMs,
    );
    final BarChartData data = await _pump(tester, trend);

    final BarChartGroupData group = data.barGroups.firstWhere(
      (BarChartGroupData g) => g.barRods.single.toY > 0,
    );
    final BarChartRodData rod = group.barRods.single;
    final AppPalette palette = Theme.of(
      tester.element(find.byType(TrendChart)),
    ).extension<AppPalette>()!;
    expect(rod.color, palette.accentInk);
    expect(
      rod.borderRadius,
      const BorderRadius.vertical(top: Radius.circular(2)),
    );

    final BarTooltipItem tip = data.barTouchData.touchTooltipData
        .getTooltipItem(group, group.x, rod, 0)!;
    expect(tip.text, trend.buckets[group.x].label);
    expect(tip.children!.single.text!.trim(), '12.50 km');
  });
}
