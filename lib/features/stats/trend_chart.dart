import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/trend.dart';

/// Y 轴刻度步长。
///
/// 不给 `interval` 时 `fl_chart` 会自己算一个可能带小数的步长（maxY=2.4 时算
/// 出 0.5），而标签按整数四舍五入就印成 `0 / 1 / 1 / 2 / 2`——相邻刻度重复，
/// 真机验证时看到的就是这个。显式给一个「好看」的 1/2/5 序列步长，既不会有
/// 重复标签，也不会出现 `0.333` 这种读不出来的刻度。
///
/// 目标是最多 4 条刻度线；[maxY] 应当已经带上顶部留白。
double niceAxisInterval(double maxY) {
  const List<double> candidates = <double>[
    0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000,
  ];
  for (final double candidate in candidates) {
    if (maxY / candidate <= 4) return candidate;
  }
  return 1000;
}

/// 刻度标签。步长不足 1 时保留一位小数，否则印整数。
String axisLabel(double value, double interval) =>
    interval >= 1 ? '${value.round()}' : value.toStringAsFixed(1);

/// 趋势折线。见设计文档 10.4。
///
/// 这里用 `fl_chart`：不需要按值着色，标准折线 + 坐标轴正好是它的强项。
class TrendChart extends StatelessWidget {
  const TrendChart({required this.trend, required this.unit, super.key});

  final TrendSummary trend;
  final DistanceUnit unit;

  static const double height = 180;

  @override
  Widget build(BuildContext context) {
    // 纵轴跟着设置里的距离单位走，否则切到英里后列表看 mi、趋势图看 km，
    // 两处对不上。
    final List<FlSpot> spots = <FlSpot>[
      for (int i = 0; i < trend.buckets.length; i++)
        FlSpot(i.toDouble(), distanceInUnit(trend.buckets[i].distanceM, unit)),
    ];

    final double maxY = spots.fold(
      0,
      (double m, FlSpot s) => s.y > m ? s.y : m,
    );
    final double interval = niceAxisInterval(maxY <= 0 ? 1 : maxY * 1.2);
    // 轴顶取步长的整数倍：否则 fl_chart 会在 maxY 处补一个不在步长序列上的
    // 标签（实测 `0.0 / 0.5 / 1.0 / 1.5 / 1.7`），看着像刻度算错了。
    final double axisMax = ((maxY <= 0 ? 1 : maxY * 1.2) / interval).ceil() * interval;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: 0,
          maxY: axisMax,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: interval,
                getTitlesWidget: (double value, TitleMeta meta) => Text(
                  axisLabel(value, interval),
                  style: const TextStyle(fontSize: 10),
                ),
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
