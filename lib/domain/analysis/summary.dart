import '../models/ride_summary.dart';
import '../models/track_point.dart';
import 'calories.dart';
import 'constants.dart';
import 'elevation.dart';
import 'geo.dart';
import 'heart_rate.dart';
import 'speed.dart';

/// 由轨迹点算出一次骑行的全部汇总指标。
///
/// [durationS] 由调用方给出：正常结束时用会话累计时长（不含暂停），
/// 崩溃恢复结算时用「末点时间 − 起始时间」近似。
RideSummary computeSummary({
  required List<TrackPoint> points,
  required int durationS,
  required int maxHeartRate,
  required double weightKg,
}) {
  double distanceM = 0;
  for (int i = 1; i < points.length; i++) {
    distanceM += segmentDistanceMeters(points[i - 1], points[i]);
  }

  final MovingStats moving = splitMovingStationary(points, kStationarySpeedMps);

  final double elevationGainM = elevationGainOf(points);

  final double? maxSpeedMps = maxSmoothedSpeed(
    <double?>[for (final TrackPoint p in points) p.speedMps],
    kSpeedFilterWindow,
  );

  final HrZoneBreakdown zones = hrZoneBreakdown(points, maxHeartRate);

  final List<double> cadences = <double>[
    for (final TrackPoint p in points)
      if (p.cadence != null) p.cadence!.toDouble(),
  ];

  final List<double> powers = <double>[
    for (final TrackPoint p in points)
      if (p.powerW != null) p.powerW!.toDouble(),
  ];

  final int movingS = moving.movingSeconds.round();

  return RideSummary(
    distanceM: distanceM,
    durationS: durationS,
    movingS: movingS,
    avgSpeedMps: durationS <= 0 ? 0 : distanceM / durationS,
    movingAvgSpeedMps: movingS <= 0 ? 0 : distanceM / movingS,
    maxSpeedMps: maxSpeedMps,
    elevationGainM: elevationGainM,
    avgHr: averageHr(points),
    maxHr: observedMaxHr(points),
    avgCadence: cadences.isEmpty
        ? null
        : cadences.reduce((double a, double b) => a + b) / cadences.length,
    avgPowerW: powers.isEmpty
        ? null
        : powers.reduce((double a, double b) => a + b) / powers.length,
    maxPowerW: powers.isEmpty
        ? null
        : powers.reduce((double a, double b) => a > b ? a : b).round(),
    calories: estimateCalories(zones: zones, weightKg: weightKg),
    pointCount: points.length,
  );
}
