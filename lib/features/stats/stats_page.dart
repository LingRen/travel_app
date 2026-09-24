import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/trend.dart';
import '../../domain/models/ride.dart';
import 'personal_bests_card.dart';
import 'stats_providers.dart';
import 'trend_chart.dart';

/// 长期统计页。见设计文档 10.4。
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Ride>> rides = ref.watch(finishedRidesProvider);
    final DistanceUnit unit =
        ref.watch(appSettingsProvider).value?.distanceUnit ??
            DistanceUnit.kilometer;
    final TrendRange range = ref.watch(trendRangeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: rides.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            Center(child: Text('读取记录失败：$error')),
        data: (List<Ride> list) {
          final TrendSummary trend = buildTrend(
            list,
            range: range,
            nowMs: ref.read(nowProvider)(),
          );

          return ListView(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceL, kSpaceL, 0),
                child: SegmentedButton<TrendRange>(
                  segments: const <ButtonSegment<TrendRange>>[
                    ButtonSegment<TrendRange>(value: TrendRange.week, label: Text('周')),
                    ButtonSegment<TrendRange>(value: TrendRange.month, label: Text('月')),
                    ButtonSegment<TrendRange>(value: TrendRange.year, label: Text('年')),
                  ],
                  selected: <TrendRange>{range},
                  onSelectionChanged: (Set<TrendRange> selected) =>
                      ref.read(trendRangeProvider.notifier).state = selected.first,
                ),
              ),
              _Totals(trend: trend, unit: unit),
              const Divider(height: 1, indent: kSpaceL, endIndent: kSpaceL),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kSpaceL,
                  kSpaceL,
                  kSpaceL,
                  kSpaceS,
                ),
                child: Text(
                  '距离趋势（${distanceUnitLabel(unit)}）',
                  style: kSectionTextStyle,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(kSpaceS, kSpaceM, kSpaceL, 0),
                child: TrendChart(trend: trend, unit: unit),
              ),
              const SizedBox(height: kSpaceXl),
              PersonalBestsCard(bests: personalBests(list), unit: unit),
              const SizedBox(height: kSpaceXxl),
            ],
          );
        },
      ),
    );
  }
}

/// 范围内的累计距离 / 时长 / 爬升 / 次数 / 平均功率 / 最高功率。
///
/// 排成两列三行的读数矩阵，而不是一行的多格：读数里时长最长有七位字符
/// （`1:00:00`），一行四格在手机宽度下每格只剩七十来像素，等宽数字撑不住，
/// 只能截断。两列每格一百多像素，读数可以放到 26pt 和仪表同一档。
///
/// 这里刻意不上强调色——琥珀色留给「当前值」与「最佳值」，累计值是历史汇总，
/// 用主文本色就够；一屏全是橙色数字的话，强调色就不强调任何东西了。
class _Totals extends StatelessWidget {
  const _Totals({required this.trend, required this.unit});

  final TrendSummary trend;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          kSpaceL,
          kSpaceXl,
          kSpaceL,
          kSpaceL,
        ),
        child: Column(
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                _tile('totals-distance', '距离', formatDistance(trend.distanceM, unit)),
                const SizedBox(width: kSpaceXl),
                _tile('totals-duration', '时长', formatDuration(trend.durationS)),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: kSpaceM),
              child: Divider(height: 1),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                _tile('totals-gain', '爬升', formatElevation(trend.elevationGainM, unit)),
                const SizedBox(width: kSpaceXl),
                _tile('totals-count', '次数', '${trend.rideCount}'),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: kSpaceM),
              child: Divider(height: 1),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                // 没配功率计时两格都是 `—`，不摆 0 W：那会让人以为真的踩不出功率。
                _tile('totals-avg-power', '平均功率', formatPower(trend.avgPowerW)),
                const SizedBox(width: kSpaceXl),
                _tile(
                  'totals-max-power',
                  '最高功率',
                  formatPower(trend.maxPowerW?.toDouble()),
                ),
              ],
            ),
          ],
        ),
      );

  /// [key] 是给 widget 测试用的稳定锚点：距离与爬升都为 0 时两格渲染的都是
  /// `0 m`，没有键就只能断言「树里有几个 `0 m`」，区分不出是哪一格。
  /// 标签在前、读数在后这一顺序也被测试依赖（`totalsValue` 取第 2 个 Text）。
  Widget _tile(String key, String label, String value) => Expanded(
        key: Key(key),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: kLabelTextStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: kSpaceXs),
            Text(
              value,
              style: kMetricTextStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
}
