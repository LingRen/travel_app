import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/trend.dart';
import '../../domain/models/activity_type.dart';
import '../../domain/models/workout.dart';

/// 个人最佳纪录。见设计文档 10.4 / 12。
///
/// **跨全部历史统计**，不受周/月/年范围切换影响。按 01–04 编号排列最远距离、
/// 最快均速（配速类型改为最快配速）、单次爬升、单次时长；有功率记录时追加
/// 最高功率。每行右侧标出创造该纪录的日期与标题。
class PersonalBestsCard extends StatelessWidget {
  const PersonalBestsCard({
    required this.bests,
    required this.unit,
    required this.rides,
    this.filter,
    super.key,
  });

  final PersonalBests bests;
  final DistanceUnit unit;

  /// 用于把最佳记录的 rideId 还原成日期与标题。
  final List<Workout> rides;

  /// 当前筛选类型；配速类型把「最快均速」改成「最快配速」。
  final ActivityType? filter;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Map<int, Workout> byId = <int, Workout>{
      for (final Workout ride in rides)
        if (ride.id != null) ride.id!: ride,
    };
    final bool usesPace = filter?.usesPace ?? false;
    final List<_BestEntry> entries = <_BestEntry>[
      if (bests.longestDistanceM != null)
        _BestEntry(
          label: '最远距离',
          value: _distanceText(bests.longestDistanceM!.value),
          best: bests.longestDistanceM!,
        ),
      if (bests.fastestMovingAvgMps != null)
        _BestEntry(
          label: usesPace ? '最快配速' : '最快均速',
          value: usesPace
              ? '${formatPace(bests.fastestMovingAvgMps!.value, unit)} '
                    '${paceUnitLabel(unit)}'
              : '${formatSpeedValue(bests.fastestMovingAvgMps!.value, unit)} '
                    '${speedUnitLabel(unit)}',
          best: bests.fastestMovingAvgMps!,
        ),
      if (bests.mostElevationGainM != null)
        _BestEntry(
          label: '单次爬升',
          value: formatElevation(bests.mostElevationGainM!.value, unit),
          best: bests.mostElevationGainM!,
        ),
      if (bests.longestDurationS != null)
        _BestEntry(
          label: '单次时长',
          value: formatDuration(bests.longestDurationS!.value.round()),
          best: bests.longestDurationS!,
        ),
      if (bests.highestPowerW != null)
        _BestEntry(
          label: '最高功率',
          value: formatPower(bests.highestPowerW!.value),
          best: bests.highestPowerW!,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kSpaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Divider(height: 1, color: palette.hairline),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: kSpaceM),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '个人最佳',
                    style: kSectionTextStyle.copyWith(
                      fontFamily: kSerifFamily,
                      fontFamilyFallback: kSerifFallback,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '全部历史',
                  style: kLabelTextStyle.copyWith(
                    color: palette.muted,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: kSpaceM),
              child: Text('还没有可统计的记录', style: kMutedTextStyle),
            )
          else
            for (int i = 0; i < entries.length; i++) ...<Widget>[
              if (i > 0) Divider(height: 1, color: palette.hairline),
              _BestRow(
                index: i + 1,
                entry: entries[i],
                ride: byId[entries[i].best.rideId],
              ),
            ],
        ],
      ),
    );
  }

  String _distanceText(double meters) {
    final ({String value, String unit}) parts = formatDistanceParts(
      meters,
      unit,
    );
    return '${parts.value} ${parts.unit}';
  }
}

class _BestEntry {
  const _BestEntry({
    required this.label,
    required this.value,
    required this.best,
  });

  final String label;
  final String value;
  final PersonalBest best;
}

class _BestRow extends StatelessWidget {
  const _BestRow({
    required this.index,
    required this.entry,
    required this.ride,
  });

  final int index;
  final _BestEntry entry;
  final Workout? ride;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final String? title = ride?.title?.trim();
    final String rideTitle = (title == null || title.isEmpty)
        ? '${ride?.activityType.label ?? '运动'}记录'
        : title;
    final String source = ride == null
        ? ''
        : '${formatMonthDayDot(ride!.startedAtMs)} · $rideTitle';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kSpaceS),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          SizedBox(
            width: 28,
            child: Text(
              index.toString().padLeft(2, '0'),
              style: kLabelTextStyle.copyWith(
                color: palette.muted,
                letterSpacing: 0,
              ),
            ),
          ),
          SizedBox(
            width: 88,
            child: Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: kLabelTextStyle.copyWith(
                color: palette.ink,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  entry.value,
                  maxLines: 1,
                  softWrap: false,
                  style: kSerifHeadingTextStyle.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: kSpaceS),
          SizedBox(
            width: 104,
            child: Text(
              source,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: kLabelTextStyle.copyWith(
                color: palette.muted,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
