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

/// 刻度标签：一律保留一位小数。
///
/// 轴上是距离，相邻两天的差距常常不到一公里，印成整数会把 3.2 和 3.8 都读成
/// 3。统一一位小数，读数和曲线才对得上（此前按步长定精度，真机上出现过
/// `0 / 1 / 2` 与 `0.0 / 0.5 / 1.0` 两种精度混着出现）。
String axisLabel(double value) => value.toStringAsFixed(1);

/// 底部日期轴的预留高度。
///
/// 日期竖排，预留高度要放得下最长的一个标签（年视图的 `2026-01` 七个字符，
/// 9pt 等宽下约 38px），上下各留几像素余量，免得末尾被裁掉。
const double kBottomAxisHeight = 52;

/// 趋势折线。见设计文档 10.4。
///
/// 这里用 `fl_chart`：不需要按值着色，标准折线 + 坐标轴正好是它的强项。
class TrendChart extends StatelessWidget {
  const TrendChart({required this.trend, required this.unit, super.key});

  final TrendSummary trend;
  final DistanceUnit unit;

  /// 连底部竖排日期轴一起的总高度。日期轴吃掉 48px，绘图区留一百五十来像素，
  /// 和改造前（180 减去 24 的行标签）相当。
  static const double height = 200;

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
          gridData: FlGridData(
            // 只画横线：竖线只会和柱/点的位置抢注意力，而横线是刻度尺本身，
            // 让人能对着左边的数读出某一天大概骑了多少。
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (double value) => const FlLine(
              color: kAppHairline,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          // 触摸读数：默认 tooltip 直接把 `touchedSpot.y.toString()` 印出来，是
          // `13.945678901234567` 这样一整串小数（真机验证看到的就是这个）。这里
          // 换成界面统一口径的两位小数，前面标出是哪个日期桶，后面带上单位。
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (LineBarSpot _) => kAppSurfaceRaised,
              // 年视图是 `2026-01` 加读数，比默认的 120 宽一些，免得换行。
              maxContentWidth: 220,
              getTooltipItems: (List<LineBarSpot> touchedSpots) =>
                  <LineTooltipItem>[
                for (final LineBarSpot spot in touchedSpots)
                  LineTooltipItem(
                    trend.buckets[spot.x.round()].label,
                    _tooltipLabelStyle,
                    children: <TextSpan>[
                      TextSpan(
                        text: '  ${spot.y.toStringAsFixed(2)} ${distanceUnitLabel(unit)}',
                        style: _tooltipValueStyle,
                      ),
                    ],
                  ),
              ],
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
                getTitlesWidget: (double value, TitleMeta meta) => Text(
                  axisLabel(value),
                  style: _axisLabelStyle,
                ),
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
                  // 每个桶的日期都列出来，不再隔几个跳一个：跳过之后剩下的
                  // 日期对不上自己关心的那天，等于没标。
                  //
                  // 横排放不下——月视图 30 个 `MM-DD`，每个三十来像素，手机
                  // 绘图区只有三百来像素，必然叠成一团（真机验证就是这个
                  // 现象）。转 90° 竖排后每个标签只占一个字符高的宽度，
                  // `Center` 让它落在预留高度中间，既居中又不会被裁掉。
                  return Center(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Text(
                        trend.buckets[index].label,
                        style: _bottomLabelStyle,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: spots,
              // 日桶之间直连，30 天就是一条折来折去的锯齿。这里允许插值成曲线，
              // 但禁止越过极值——否则没骑车的日子会被插到 0 以下，看着像负距离。
              isCurved: true,
              curveSmoothness: 0.25,
              preventCurveOverShooting: true,
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

/// 竖排日期：比纵轴刻度再小一档。月视图 30 个桶时相邻两天的间距在手机上只有
/// 十来像素，字号不降下来，竖排也会挨在一起。
const TextStyle _bottomLabelStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontSize: 9,
  color: kAppTextMuted,
  fontFeatures: kTabularFigures,
);

/// 轴刻度标签：等宽 tabular，随折线一起当刻度尺用。
const TextStyle _axisLabelStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontSize: 10,
  color: kAppTextMuted,
  fontFeatures: kTabularFigures,
);

/// 触摸提示框里的日期：小一档、用弱色，让读数当主角。
const TextStyle _tooltipLabelStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontSize: 10,
  color: kAppTextMuted,
  fontFeatures: kTabularFigures,
);

/// 触摸提示框里的读数：两位小数，等宽 tabular，手指拖动时数字宽度不跳。
const TextStyle _tooltipValueStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontSize: 12,
  color: kAppTextPrimary,
  fontFeatures: kTabularFigures,
);
