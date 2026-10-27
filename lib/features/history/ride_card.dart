import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/models/track_point.dart';
import '../../domain/models/workout.dart';
import '../../domain/models/workout_summary.dart';
import 'history_providers.dart';
import 'mini_speed_curve.dart';

/// 历史列表里的一条运动。见设计文档 10.2。
///
/// 做成「日志条目」而不是卡片：左侧是日期与星期，中间是标题与出发时间，
/// 右侧是距离主读数；下方四项读数按固定四列排开，最下面一条迷你曲线。
/// 条目之间用发丝线分隔，不包圆角卡片。
class WorkoutCard extends ConsumerWidget {
  const WorkoutCard({
    required this.ride,
    required this.unit,
    this.onTap,
    this.highlight = false,
    super.key,
  });

  final Workout ride;
  final DistanceUnit unit;
  final VoidCallback? onTap;

  /// 首屏最近一条：迷你曲线用主题色；更早的条目用弱一档的墨色。
  final bool highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = context.palette;
    final WorkoutSummary? s = ride.summary;
    final String? rawTitle = ride.title?.trim();
    final String title = (rawTitle == null || rawTitle.isEmpty)
        ? '${ride.activityType.label}记录'
        : rawTitle;
    final ({String value, String unit}) distance = formatDistanceParts(
      s?.distanceM ?? 0,
      unit,
    );
    final bool usesPace = ride.activityType.usesPace;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceM, kSpaceL, kSpaceM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 日期列：日号大、星期小。月份由页眉/分组标题承担。
                SizedBox(
                  width: 52,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        formatMonthDayDot(ride.startedAtMs),
                        style: kSerifHeadingTextStyle.copyWith(
                          fontSize: 22,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatChineseWeekday(ride.startedAtMs),
                        style: kLabelTextStyle.copyWith(
                          color: palette.muted,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: kSpaceM),
                // 标题与出发时间。没有用户标题时用「{类型}记录」，不拿日期
                // 冒充标题——日期已经在左边那一列了。
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kSerifHeadingTextStyle.copyWith(fontSize: 21),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatTimeHm(ride.startedAtMs)} 出发',
                        style: TextStyle(
                          fontSize: kFontMeta,
                          color: palette.muted,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: kSpaceM),
                // 距离主读数：衬线大数字 + 小单位。数值与单位分开，单位不
                // 跟着数字一起放大。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      distance.value,
                      key: ValueKey<String>('ride-distance-${ride.id}'),
                      style: kSerifDisplayTextStyle.copyWith(
                        fontSize: 36,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      distance.unit,
                      style: kLabelTextStyle.copyWith(
                        fontSize: 10,
                        letterSpacing: 0,
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (s == null)
              Padding(
                padding: const EdgeInsets.only(top: kSpaceS),
                child: Text('这条记录还没有汇总指标', style: kMutedTextStyle),
              )
            else ...<Widget>[
              const SizedBox(height: kSpaceM),
              // 四列读数：标签在上、值在下，列宽等分，跨条目对齐。
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Stat(label: '时长', value: formatDuration(s.durationS)),
                  const SizedBox(width: kSpaceS),
                  _Stat(
                    label: usesPace ? '配速' : '均速',
                    value: usesPace
                        ? formatPace(s.movingAvgSpeedMps, unit)
                        : '${formatSpeedValue(s.movingAvgSpeedMps, unit)} '
                              '${speedUnitLabel(unit)}',
                  ),
                  const SizedBox(width: kSpaceS),
                  _Stat(
                    label: '爬升',
                    value: formatElevation(s.elevationGainM, unit),
                  ),
                  const SizedBox(width: kSpaceS),
                  _Stat(
                    label: ride.activityType.supportsPower ? '功率' : null,
                    value: ride.activityType.supportsPower
                        ? (s.avgPowerW == null ? '—' : formatPower(s.avgPowerW))
                        : null,
                  ),
                ],
              ),
            ],
            if (ride.id != null) ...<Widget>[
              const SizedBox(height: kSpaceS),
              _MiniCurve(rideId: ride.id, highlight: highlight),
            ],
          ],
        ),
      ),
    );
  }
}

/// 四列读数里的一格。标签或值缺省时仍保留列宽，保证跨条目对齐。
class _Stat extends StatelessWidget {
  const _Stat({this.label, this.value});

  final String? label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (label != null)
            Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: kLabelTextStyle.copyWith(
                color: palette.muted,
                letterSpacing: 0,
              ),
            ),
          const SizedBox(height: 2),
          // 速度列带 km/h，360dp 的四等分里比其它三列宽；用 FittedBox
          // 等比缩小，不要让单位被省略号截成 `km...`。
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value ?? '',
              maxLines: 1,
              softWrap: false,
              style: kMetricTextStyle.copyWith(
                fontSize: 16,
                color: value == null ? palette.muted : palette.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 迷你曲线单独拆一个 Consumer，让轨迹点的加载不影响卡片其余部分的重建。
class _MiniCurve extends ConsumerWidget {
  const _MiniCurve({required this.rideId, required this.highlight});

  final int? rideId;
  final bool highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int? id = rideId;
    if (id == null) return const SizedBox(height: MiniSpeedCurve.height);

    final AsyncValue<List<TrackPoint>> points = ref.watch(
      ridePointsProvider(id),
    );
    return points.maybeWhen(
      data: (List<TrackPoint> list) => MiniSpeedCurve(
        points: list,
        color: highlight
            ? context.palette.accentInk
            : context.palette.muted.withValues(alpha: 0.45),
      ),
      orElse: () => const SizedBox(height: MiniSpeedCurve.height),
    );
  }
}
