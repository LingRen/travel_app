import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/models/track_point.dart';
import '../../domain/models/workout.dart';
import '../../domain/models/workout_summary.dart';

/// 详情页的两行三列汇总。见设计文档 10.3 的第 2 块。
///
/// 第一行是距离 / 时长 / 爬升，第二行是均速（或配速）/ 心率 / 功率；非骑行
/// 类型没有功率，用该次记录的最高海拔替代。数值用衬线大字，单位降一档，
/// 列与列之间靠留白分隔，不画竖线。
class SummaryGrid extends StatelessWidget {
  const SummaryGrid({
    required this.ride,
    required this.unit,
    this.points = const <TrackPoint>[],
    super.key,
  });

  final Workout ride;
  final DistanceUnit unit;

  /// 用于取最高海拔；非骑行类型把功率格换成海拔时才会读它。
  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) {
    final WorkoutSummary? s = ride.summary;
    if (s == null) {
      return const Padding(
        padding: EdgeInsets.all(kSpaceL),
        child: Text('这条记录还没有汇总指标', style: kMutedTextStyle),
      );
    }

    final bool usesPace = ride.activityType.usesPace;
    final ({String value, String unit}) distance = formatDistanceParts(
      s.distanceM,
      unit,
    );
    final ({String value, String unit}) climb = _splitUnit(
      formatElevation(s.elevationGainM, unit),
    );
    final double? maxAltitude = ride.activityType.supportsPower
        ? null
        : _maxAltitude(points);

    final List<_SummaryCell> firstRow = <_SummaryCell>[
      _SummaryCell(label: '距离', value: distance.value, unit: distance.unit),
      _SummaryCell(label: '时长', value: formatDuration(s.durationS)),
      _SummaryCell(label: '爬升', value: climb.value, unit: climb.unit),
    ];
    final List<_SummaryCell> secondRow = <_SummaryCell>[
      _SummaryCell(
        label: usesPace ? '配速' : '均速',
        value: usesPace
            ? formatPace(s.movingAvgSpeedMps, unit)
            : formatSpeedValue(s.movingAvgSpeedMps, unit),
        unit: usesPace ? paceUnitLabel(unit) : speedUnitLabel(unit),
      ),
      _SummaryCell(
        label: '心率',
        value: s.avgHr?.round().toString() ?? '—',
        unit: s.avgHr == null ? null : 'bpm',
      ),
      if (ride.activityType.supportsPower)
        _SummaryCell(
          label: '功率',
          value: s.avgPowerW?.round().toString() ?? '—',
          unit: s.avgPowerW == null ? null : 'W',
        )
      else
        _SummaryCell(
          label: '海拔',
          value: maxAltitude?.round().toString() ?? '—',
          unit: maxAltitude == null ? null : 'm',
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceL, kSpaceL, 0),
      child: Column(
        children: <Widget>[
          Row(children: _cells(firstRow)),
          Divider(height: 1, color: context.palette.hairline),
          Row(children: _cells(secondRow)),
        ],
      ),
    );
  }

  static List<Widget> _cells(List<_SummaryCell> cells) => <Widget>[
    for (int i = 0; i < cells.length; i++) ...<Widget>[
      if (i > 0) const SizedBox(width: kSpaceM),
      Expanded(child: cells[i]),
    ],
  ];

  static ({String value, String unit}) _splitUnit(String text) {
    final int space = text.lastIndexOf(' ');
    if (space <= 0) return (value: text, unit: '');
    return (value: text.substring(0, space), unit: text.substring(space + 1));
  }

  static double? _maxAltitude(List<TrackPoint> points) {
    double? max;
    for (final TrackPoint p in points) {
      final double? altitude = p.altitudeM;
      if (altitude == null) continue;
      if (max == null || altitude > max) max = altitude;
    }
    return max;
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kSpaceS),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: kLabelTextStyle.copyWith(
              color: palette.muted,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: kSerifHeadingTextStyle.copyWith(
                      fontSize: 30,
                      fontWeight: FontWeight.w500,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
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
        ],
      ),
    );
  }
}
