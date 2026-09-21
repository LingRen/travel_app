import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/analysis/trend.dart';

/// 趋势折线。见设计文档 10.4。
///
/// 这里用 `fl_chart`：不需要按值着色，标准折线 + 坐标轴正好是它的强项。
class TrendChart extends StatelessWidget {
  const TrendChart({required this.trend, super.key});

  final TrendSummary trend;

  static const double height = 180;

  @override
  Widget build(BuildContext context) {
    final List<FlSpot> spots = <FlSpot>[
      for (int i = 0; i < trend.buckets.length; i++)
        FlSpot(i.toDouble(), trend.buckets[i].distanceM / 1000),
    ];

    final double maxY = spots.fold(
      0,
      (double m, FlSpot s) => s.y > m ? s.y : m,
    );

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.2,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (double value, TitleMeta meta) =>
                    Text('${value.round()}', style: const TextStyle(fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final int index = value.round();
                  if (index < 0 || index >= trend.buckets.length) {
                    return const SizedBox.shrink();
                  }
                  // 桶多的时候标签会挤成一团，隔一个显示一个。
                  if (trend.buckets.length > 10 && index.isOdd) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    trend.buckets[index].label,
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
          ),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: kAppAccent,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: kAppAccent.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
