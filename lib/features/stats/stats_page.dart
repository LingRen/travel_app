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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  '距离趋势（${distanceUnitLabel(unit)}）',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
                child: TrendChart(trend: trend, unit: unit),
              ),
              const SizedBox(height: 16),
              PersonalBestsCard(bests: personalBests(list), unit: unit),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}

/// 范围内的累计距离 / 时长 / 爬升 / 次数。
class _Totals extends StatelessWidget {
  const _Totals({required this.trend, required this.unit});

  final TrendSummary trend;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: <Widget>[
            _tile('totals-distance', '距离', formatDistance(trend.distanceM, unit)),
            _tile('totals-duration', '时长', formatDuration(trend.durationS)),
            _tile('totals-gain', '爬升', formatElevation(trend.elevationGainM, unit)),
            _tile('totals-count', '次数', '${trend.rideCount}'),
          ],
        ),
      );

  /// [key] 是给 widget 测试用的稳定锚点：距离与爬升都为 0 时两格渲染的都是
  /// `0 m`，没有键就只能断言「树里有几个 `0 m`」，区分不出是哪一格。
  Widget _tile(String key, String label, String value) => Expanded(
        key: Key(key),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: kAppAccent,
              ),
            ),
          ],
        ),
      );
}
