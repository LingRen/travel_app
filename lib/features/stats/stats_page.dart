import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/ui/page_header.dart';
import '../../app/ui/paper_sheet.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/trend.dart';
import '../../domain/models/activity_type.dart';
import '../../domain/models/workout.dart';
import '../activity/sport_filter_sheet.dart';
import '../activity/sport_filter_trigger.dart';
import 'personal_bests_card.dart';
import 'stats_providers.dart';
import 'trend_chart.dart';

/// 长期统计页。见设计文档 10.4。
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Workout>> rides = ref.watch(finishedRidesProvider);
    final DistanceUnit unit =
        ref.watch(appSettingsProvider).value?.distanceUnit ??
        DistanceUnit.kilometer;
    final TrendRange range = ref.watch(trendRangeProvider);
    final ActivityType? filter = ref.watch(statsFilterProvider);
    final DateTime now = DateTime.fromMillisecondsSinceEpoch(
      ref.read(nowProvider)(),
    );

    return Scaffold(
      body: rides.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            Center(child: Text('读取记录失败：$error')),
        data: (List<Workout> list) {
          final TrendSummary trend = buildTrend(
            list,
            range: range,
            nowMs: ref.read(nowProvider)(),
          );
          final bool hasPower = list.any(
            (Workout ride) => ride.summary?.avgPowerW != null,
          );
          final bool showPowerRow =
              (filter == null || filter.supportsPower) && hasPower;

          return ListView(
            children: <Widget>[
              PageHeader(
                eyebrow: '长 期 统 计',
                date: formatChineseYearMonth(now),
                title: '里程',
                trailing: Text('共 ${list.length} 次', style: kLabelTextStyle),
                subtitle:
                    '按${_rangeName(range)}归拢 · '
                    '${_rangePeriodLabel(range)} ${trend.rideCount} 次',
                subtitleTrailing: SportFilterTrigger(
                  current: filter,
                  onTap: () => showPaperSheet<void>(
                    context: context,
                    builder: (_) => SportFilterSheet(
                      current: filter,
                      onSelected: (ActivityType? type) =>
                          ref.read(statsFilterProvider.notifier).state = type,
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: context.palette.hairline),
              _RangeTabs(
                range: range,
                unitLabel: distanceUnitLabel(unit),
                onChanged: (TrendRange value) =>
                    ref.read(trendRangeProvider.notifier).state = value,
              ),
              if (list.isEmpty)
                _EmptyStats(filter: filter)
              else ...<Widget>[
                _Totals(trend: trend, unit: unit, showPowerRow: showPowerRow),
                Divider(
                  height: 1,
                  indent: kSpaceL,
                  endIndent: kSpaceL,
                  color: context.palette.hairline,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kSpaceL,
                    kSpaceL,
                    kSpaceL,
                    kSpaceS,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '距 离 · 按${_chartBucketName(range)}',
                          style: kSectionTextStyle.copyWith(
                            fontFamily: kSerifFamily,
                            fontFamilyFallback: kSerifFallback,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          '${formatChineseYearMonth(now)} · '
                          '${trend.buckets.length} ${_bucketUnit(range)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: kLabelTextStyle.copyWith(
                            color: context.palette.muted,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kSpaceS,
                    kSpaceM,
                    kSpaceL,
                    0,
                  ),
                  child: TrendChart(trend: trend, unit: unit),
                ),
                const SizedBox(height: kSpaceXl),
                PersonalBestsCard(
                  bests: personalBests(list),
                  unit: unit,
                  rides: list,
                  filter: filter,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kSpaceL,
                    kSpaceXl,
                    kSpaceL,
                    kSpaceXxl,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '统计口径 · 剔除停车空档',
                          style: kLabelTextStyle.copyWith(
                            color: context.palette.muted,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      Text(
                        '本机计算',
                        style: kLabelTextStyle.copyWith(
                          color: context.palette.muted,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

String _rangeName(TrendRange range) => switch (range) {
  TrendRange.week => '周',
  TrendRange.month => '月',
  TrendRange.year => '年',
};

String _rangePeriodLabel(TrendRange range) => switch (range) {
  TrendRange.week => '本周',
  TrendRange.month => '本月',
  TrendRange.year => '本年',
};

String _chartBucketName(TrendRange range) => switch (range) {
  TrendRange.week || TrendRange.month => '日',
  TrendRange.year => '月',
};

String _bucketUnit(TrendRange range) => switch (range) {
  TrendRange.week => '天',
  TrendRange.month => '天',
  TrendRange.year => '月',
};

/// 纸本周 / 月 / 年切换：选中项用主题色 + 2dp 下划线，右侧显示距离单位。
class _RangeTabs extends StatelessWidget {
  const _RangeTabs({
    required this.range,
    required this.unitLabel,
    required this.onChanged,
  });

  final TrendRange range;
  final String unitLabel;
  final ValueChanged<TrendRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    const Map<TrendRange, String> labels = <TrendRange, String>{
      TrendRange.week: '周',
      TrendRange.month: '月',
      TrendRange.year: '年',
    };
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceS, kSpaceL, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (final TrendRange value in TrendRange.values)
                Expanded(
                  child: InkWell(
                    key: Key('stats-range-${value.name}'),
                    onTap: () => onChanged(value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: kSpaceS),
                      child: Column(
                        children: <Widget>[
                          Text(
                            labels[value]!,
                            style: kSectionTextStyle.copyWith(
                              color: value == range
                                  ? palette.accentInk
                                  : palette.muted,
                              fontWeight: value == range
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 2,
                            color: value == range
                                ? palette.accentInk
                                : Colors.transparent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: kSpaceM),
              Padding(
                padding: const EdgeInsets.only(bottom: kSpaceS),
                child: Text(
                  unitLabel,
                  style: kLabelTextStyle.copyWith(
                    color: palette.muted,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: palette.hairline),
      ],
    );
  }
}

/// 范围内三项主读数 + 可选功率次级行。
class _Totals extends StatelessWidget {
  const _Totals({
    required this.trend,
    required this.unit,
    required this.showPowerRow,
  });

  final TrendSummary trend;
  final DistanceUnit unit;
  final bool showPowerRow;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final ({String value, String unit}) distance = formatDistanceParts(
      trend.distanceM,
      unit,
    );
    final ({String value, String unit}) climb = _splitUnit(
      formatElevation(trend.elevationGainM, unit),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceL, kSpaceL, kSpaceL),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _MainTotal(
                key: const Key('totals-distance'),
                label: '总距离',
                value: distance.value,
                unit: distance.unit,
              ),
              const SizedBox(width: kSpaceM),
              _MainTotal(
                key: const Key('totals-duration'),
                label: '总时长',
                value: formatDuration(trend.durationS),
              ),
              const SizedBox(width: kSpaceM),
              _MainTotal(
                key: const Key('totals-gain'),
                label: '总爬升',
                value: climb.value,
                unit: climb.unit,
              ),
            ],
          ),
          if (showPowerRow) ...<Widget>[
            Divider(height: kSpaceXl, color: palette.hairline),
            Row(
              children: <Widget>[
                _PowerReadout(
                  key: const Key('totals-avg-power'),
                  label: '平均功率',
                  value: formatPower(trend.avgPowerW),
                ),
                const SizedBox(width: kSpaceM),
                _PowerReadout(
                  key: const Key('totals-max-power'),
                  label: '最高功率',
                  value: formatPower(trend.maxPowerW?.toDouble()),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static ({String value, String unit}) _splitUnit(String text) {
    final int space = text.lastIndexOf(' ');
    if (space <= 0) return (value: text, unit: '');
    return (value: text.substring(0, space), unit: text.substring(space + 1));
  }
}

class _MainTotal extends StatelessWidget {
  const _MainTotal({
    required this.label,
    required this.value,
    this.unit,
    super.key,
  });

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: kLabelTextStyle.copyWith(
              color: palette.muted,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  style: kSerifHeadingTextStyle.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                    fontFeatures: kTabularFigures,
                  ),
                ),
                if (unit != null && unit!.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 3),
                  Text(
                    unit!,
                    style: kLabelTextStyle.copyWith(
                      fontSize: 10,
                      letterSpacing: 0,
                      color: palette.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PowerReadout extends StatelessWidget {
  const _PowerReadout({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: kLabelTextStyle.copyWith(
                color: palette.muted,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: kSpaceS),
            Text(
              value,
              style: kMetricTextStyle.copyWith(
                fontSize: 15,
                color: palette.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 筛选下没有任何记录时的空态。页脚/图表都不渲染，避免摆一排零。
class _EmptyStats extends ConsumerWidget {
  const _EmptyStats({required this.filter});

  final ActivityType? filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: kSpaceL,
      vertical: kSpaceXxl,
    ),
    child: Column(
      children: <Widget>[
        Text(
          filter == null ? '还没有运动记录' : '还没有${filter!.label}记录',
          style: kMutedTextStyle,
        ),
        if (filter != null) ...<Widget>[
          const SizedBox(height: kSpaceS),
          TextButton(
            key: const Key('stats-show-all'),
            onPressed: () =>
                ref.read(statsFilterProvider.notifier).state = null,
            child: const Text('查看全部运动'),
          ),
        ],
      ],
    ),
  );
}
