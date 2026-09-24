import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/ride_summary.dart';
import '../../domain/models/track_point.dart';
import 'history_providers.dart';
import 'mini_speed_curve.dart';

/// 历史列表里的一条骑行。见设计文档 10.2。
///
/// 做成「日志条目」而不是卡片：卡片把每条记录封成一个独立的圆角块，一屏里
/// 六张一样的卡读下来分不清主次，也浪费掉左右两侧的联系。改成条目后，
/// 左侧是身份（标题/时间），右侧是数字列（距离/时长），上下用细线分隔——
/// 数字因此纵向对齐，扫一列比扫一堆散落的字符串快得多。
///
/// 全条目唯一的颜色来自那条速度缩略图：颜色只表示数据（见 app/theme.dart）。
class RideCard extends ConsumerWidget {
  const RideCard({required this.ride, required this.unit, this.onTap, super.key});

  final Ride ride;
  final DistanceUnit unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RideSummary? s = ride.summary;
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
                        ),
                      ),
                      // 有标题时时间降为副行。没标题时它就是主行，不再重复。
                      if (titled) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          formatDateTime(ride.startedAtMs),
                          style: const TextStyle(
                            fontSize: 12,
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
                  Text(formatDistance(s.distanceM, unit), style: kMetricTextStyle),
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
              // 每项必须各自是独立的 Text：它们既是给人看的读数，也是测试
              // 定位卡片内容的锚点（`find.text('爬升 180 m')`），合并成一个
              // 字符串就断掉了。
              Wrap(
                spacing: kSpaceL,
                runSpacing: kSpaceXs,
                children: <Widget>[
                  Text(formatDuration(s.durationS), style: _metaStyle),
                  Text(
                    '${formatSpeedValue(s.movingAvgSpeedMps, unit)} ${speedUnitLabel(unit)}',
                    style: _metaStyle,
                  ),
                  Text('爬升 ${formatElevation(s.elevationGainM, unit)}', style: _metaStyle),
                  // 没配功率计的那次骑行没有功率，整项不显示：写个 `0 W`
                  // 会被当成「踏空了」。
                  if (s.avgPowerW != null)
                    Text('功率 ${formatPower(s.avgPowerW)}', style: _metaStyle),
                ],
              ),
            ],
            if (ride.id != null) ...<Widget>[
              const SizedBox(height: kSpaceM),
              const Divider(height: 1),
              const SizedBox(height: kSpaceS),
              _MiniCurve(rideId: ride.id),
            ],
          ],
        ),
      ),
    );
  }
}

/// 次级读数：等宽，让三列数字在纵向对齐。
const TextStyle _metaStyle = TextStyle(
  fontSize: 13,
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

    final AsyncValue<List<TrackPoint>> points = ref.watch(ridePointsProvider(id));
    return points.maybeWhen(
      data: (List<TrackPoint> list) => MiniSpeedCurve(points: list),
      orElse: () => const SizedBox(height: MiniSpeedCurve.height),
    );
  }
}