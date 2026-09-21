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

/// 历史列表里的一张骑行卡片。见设计文档 10.2。
class RideCard extends ConsumerWidget {
  const RideCard({required this.ride, required this.unit, this.onTap, super.key});

  final Ride ride;
  final DistanceUnit unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RideSummary? s = ride.summary;

    return Card(
      color: kAppSurface,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      ride.title?.trim().isNotEmpty == true
                          ? ride.title!.trim()
                          : formatDateTime(ride.startedAtMs),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (ride.title?.trim().isNotEmpty == true)
                    Text(
                      formatDateTime(ride.startedAtMs),
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (s == null)
                const Text('这条记录还没有汇总指标', style: TextStyle(fontSize: 13))
              else ...<Widget>[
                Text(
                  formatDistance(s.distanceM, unit),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: kAppAccent,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: <Widget>[
                    Text(formatDuration(s.durationS), style: _metaStyle),
                    Text(
                      '${formatSpeedValue(s.movingAvgSpeedMps, unit)} ${speedUnitLabel(unit)}',
                      style: _metaStyle,
                    ),
                    Text('爬升 ${s.elevationGainM.round()} m', style: _metaStyle),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              _MiniCurve(rideId: ride.id),
            ],
          ),
        ),
      ),
    );
  }
}

const TextStyle _metaStyle = TextStyle(fontSize: 13, color: Colors.white70);

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
