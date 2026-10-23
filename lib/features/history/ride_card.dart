import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/models/activity_type.dart';
import '../../domain/models/track_point.dart';
import '../../domain/models/workout.dart';
import '../../domain/models/workout_summary.dart';
import 'history_providers.dart';
import 'mini_speed_curve.dart';

/// 历史列表里的一条运动。见设计文档 10.2。
///
/// 做成「日志条目」而不是卡片：卡片把每条记录封成一个独立的圆角块，一屏里
/// 六张一样的卡读下来分不清主次，也浪费掉左右两侧的联系。改成条目后，
/// 左侧是身份（标题/时间），右侧是距离主读数，下方四项次级读数排成固定四列——
/// 每列左边缘跨条目对齐，扫一列比扫一堆散落的字符串快得多。
///
/// 条目内部没有分隔线：条目之间那条由列表画，里面再画一条就成了每行两道线。
///
/// 全条目唯一的颜色来自那条速度缩略图：颜色只表示数据（见 app/theme.dart）。
class WorkoutCard extends ConsumerWidget {
  const WorkoutCard({
    required this.ride,
    required this.unit,
    this.onTap,
    super.key,
  });

  final Workout ride;
  final DistanceUnit unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WorkoutSummary? s = ride.summary;
    final String? title = ride.title?.trim();
    final bool titled = title != null && title.isNotEmpty;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kSpaceL,
          vertical: kSpaceM,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 类型图标：不占色（装饰一律不上色，见 app/theme.dart），
                // 只让混合类型的列表在扫读时能一眼分出骑行与跑步。
                Icon(
                  _activityIcon(ride.activityType),
                  size: 16,
                  color: kAppTextMuted,
                ),
                const SizedBox(width: kSpaceS),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        titled ? title : formatDateTime(ride.startedAtMs),
                        style: const TextStyle(
                          fontSize: kFontSubtitle,
                          fontWeight: FontWeight.w600,
                          color: kAppTextPrimary,
                          // 没有标题时这一行就是日期，数字要等宽；有标题时是中文，
                          // 不受影响。
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                      // 有标题时时间降为副行。没标题时它就是主行，不再重复。
                      if (titled) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          formatDateTime(ride.startedAtMs),
                          style: const TextStyle(
                            fontSize: kFontLabel,
                            color: kAppTextMuted,
                            fontFeatures: kTabularFigures,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (s != null) ...<Widget>[
                  const SizedBox(width: kSpaceM),
                  Text(
                    formatDistance(s.distanceM, unit),
                    style: kMetricTextStyle,
                  ),
                ],
              ],
            ),
            if (s == null)
              const Padding(
                padding: EdgeInsets.only(top: kSpaceS),
                child: Text('这条记录还没有汇总指标', style: kMutedTextStyle),
              )
            else ...<Widget>[
              const SizedBox(height: kSpaceM),
              // 四项读数排成固定四列。每项必须各自是独立的 Text：它们既是给人看
              // 的读数，也是测试定位卡片内容的锚点（`find.text('爬升 180 m')`），
              // 合并成一个字符串就断掉了。
              //
              // 四项里只有爬升带中文标签：它的单位 `m` 与距离的 `m` 会混，其余
              // 三项（时长、`km/h`、`W`）的单位自明，再加标签只是重复。
              //
              // 四列不等宽（4:4:5:3）。等宽在 360dp 上会把爬升列挤破：一列只有
              // 76dp，而「爬升 1240 m」是两个汉字加四个数字，比 `23.9 km/h` 还宽，
              // 末位的 `m` 会被挤到第二行去。爬升列多分一档、从最宽的功率列匀出
              // 一档就够。宽度对每一条记录都是同一个定值，左边缘照旧跨条目对齐。
              Row(
                children: <Widget>[
                  _MetaCell(formatDuration(s.durationS), flex: 4),
                  const SizedBox(width: kSpaceS),
                  // 骑行主读数是均速，跑步/健走/徒步是配速（见 activity_type.dart
                  // 的 usesPace）。配速不含单位尾缀：`5'30"` 在公里制下自明。
                  _MetaCell(
                    ride.activityType.usesPace
                        ? '配速 ${formatPace(s.movingAvgSpeedMps, unit)}'
                        : '${formatSpeedValue(s.movingAvgSpeedMps, unit)} '
                            '${speedUnitLabel(unit)}',
                    flex: 4,
                  ),
                  const SizedBox(width: kSpaceS),
                  _MetaCell(
                    '爬升 ${formatElevation(s.elevationGainM, unit)}',
                    flex: 5,
                  ),
                  const SizedBox(width: kSpaceS),
                  // 没配功率计的那次骑行没有功率，整项不显示：写个 `0 W` 会被
                  // 当成「踏空了」。但格子要留着——抽掉它，前三列会跟着变宽，
                  // 和配了功率计的条目就对不起齐了。
                  _MetaCell(
                    s.avgPowerW == null ? null : formatPower(s.avgPowerW),
                    flex: 3,
                  ),
                ],
              ),
            ],
            if (ride.id != null) ...<Widget>[
              const SizedBox(height: kSpaceM),
              _MiniCurve(rideId: ride.id),
            ],
          ],
        ),
      ),
    );
  }
}

/// 各运动类型的图标。图标只做类型区分，四个值都要能映射到，缺一个卡片就崩。
IconData _activityIcon(ActivityType t) => switch (t) {
      ActivityType.cycling => Icons.directions_bike,
      ActivityType.running => Icons.directions_run,
      ActivityType.walking => Icons.directions_walk,
      ActivityType.hiking => Icons.terrain,
    };

/// 四列读数里的一格。内容为 null 时留空占位，保住其余各列的位置。
///
/// [flex] 是本列在四列里分到的宽度权重。四列按需要不等宽，但每一条记录用的都是
/// 同一组权重，所以左边缘照样跨条目对齐。
class _MetaCell extends StatelessWidget {
  const _MetaCell(this.text, {required this.flex});

  final String? text;

  final int flex;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: text == null
        ? const SizedBox.shrink()
        : Text(text!, style: _metaStyle),
  );
}

/// 次级读数：等宽数字，让四列在纵向对齐。
const TextStyle _metaStyle = TextStyle(
  fontSize: kFontMeta,
  color: kAppTextMuted,
  fontFeatures: kTabularFigures,
);

/// 迷你曲线单独拆一个 Consumer，让轨迹点的加载不影响卡片其余部分的重建。
class _MiniCurve extends ConsumerWidget {
  const _MiniCurve({required this.rideId});

  final int? rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int? id = rideId;
    if (id == null) return const SizedBox(height: MiniSpeedCurve.height);

    final AsyncValue<List<TrackPoint>> points = ref.watch(
      ridePointsProvider(id),
    );
    return points.maybeWhen(
      data: (List<TrackPoint> list) => MiniSpeedCurve(points: list),
      orElse: () => const SizedBox(height: MiniSpeedCurve.height),
    );
  }
}
