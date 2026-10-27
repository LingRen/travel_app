import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/trend.dart';

/// Y 轴刻度步长：1 / 2 / 5 序列，最多 4 条刻度线。
double niceAxisInterval(double maxY) {
  const List<double> candidates = <double>[
    0.1,
    0.2,
    0.5,
    1,
    2,
    5,
    10,
    20,
    50,
    100,
    200,
    500,
    1000,
  ];
  for (final double candidate in candidates) {
    if (maxY / candidate <= 4) return candidate;
  }
  return 1000;
}

/// 刻度标签：一律保留一位小数。
String axisLabel(double value) => value.toStringAsFixed(1);

/// 底部日期轴的预留高度。日期竖排，年视图的 `2026-01` 也能放下。
const double kBottomAxisHeight = 52;

/// 距离趋势柱形图。见设计文档 10.4 / 12。
///
/// 柱色使用文字安全色 `accentInk`；顶部圆角 2；柱宽按桶数自适应。
/// 触摸提示保留日期桶与两位小数读数。
class TrendChart extends StatelessWidget {
  const TrendChart({required this.trend, required this.unit, super.key});

  final TrendSummary trend;
  final DistanceUnit unit;

  static const double height = 200;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final List<double> values = <double>[
      for (final TrendBucket bucket in trend.buckets)
        distanceInUnit(bucket.distanceM, unit),
    ];
    final double maxY = values.fold<double>(
      0,
      (double m, double v) => v > m ? v : m,
    );
    final double interval = niceAxisInterval(maxY <= 0 ? 1 : maxY * 1.2);
    final double axisMax =
        ((maxY <= 0 ? 1 : maxY * 1.2) / interval).ceil() * interval;

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // 图表左右各留 40dp 给纵轴；柱宽不超过绘图区的 60%，桶多时收到 4dp。
          final double plotWidth = (constraints.maxWidth - 40).clamp(80.0, 1e9);
          final double barWidth = (plotWidth / trend.buckets.length * 0.6)
              .clamp(4.0, 24.0);

          return BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              minY: 0,
              maxY: axisMax,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (double value) =>
                    FlLine(color: palette.hairline, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (BarChartGroupData _) => palette.sheet,
                  maxContentWidth: 220,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem:
                      (
                        BarChartGroupData group,
                        int groupIndex,
                        BarChartRodData rod,
                        int rodIndex,
                      ) {
                        final TrendBucket bucket = trend.buckets[group.x];
                        return BarTooltipItem(
                          bucket.label,
                          _tooltipLabelStyle(palette),
                          children: <TextSpan>[
                            TextSpan(
                              text:
                                  '  ${rod.toY.toStringAsFixed(2)} ${distanceUnitLabel(unit)}',
                              style: _tooltipValueStyle(palette),
                            ),
                          ],
                        );
                      },
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: interval,
                    getTitlesWidget: (double value, TitleMeta meta) =>
                        Text(axisLabel(value), style: _axisLabelStyle(palette)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: kBottomAxisHeight,
                    interval: 1,
                    getTitlesWidget: (double value, TitleMeta meta) {
                      final int index = value.round();
                      if (index < 0 || index >= trend.buckets.length) {
                        return const SizedBox.shrink();
                      }
                      return Center(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Text(
                            trend.buckets[index].label,
                            style: _bottomLabelStyle(palette),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: <BarChartGroupData>[
                for (int i = 0; i < trend.buckets.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: <BarChartRodData>[
                      BarChartRodData(
                        toY: values[i],
                        width: barWidth,
                        color: palette.accentInk,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(kRadiusLine),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

TextStyle _bottomLabelStyle(AppPalette palette) => TextStyle(
  fontFamily: kMonoFamily,
  fontFamilyFallback: kMonoFallback,
  fontSize: 9,
  color: palette.muted,
  fontFeatures: kTabularFigures,
);

TextStyle _axisLabelStyle(AppPalette palette) => TextStyle(
  fontFamily: kMonoFamily,
  fontFamilyFallback: kMonoFallback,
  fontSize: 10,
  color: palette.muted,
  fontFeatures: kTabularFigures,
);

TextStyle _tooltipLabelStyle(AppPalette palette) => TextStyle(
  fontFamily: kMonoFamily,
  fontFamilyFallback: kMonoFallback,
  fontSize: 10,
  color: palette.muted,
  fontFeatures: kTabularFigures,
);

TextStyle _tooltipValueStyle(AppPalette palette) => TextStyle(
  fontFamily: kMonoFamily,
  fontFamilyFallback: kMonoFallback,
  fontSize: 12,
  color: palette.ink,
  fontFeatures: kTabularFigures,
);
