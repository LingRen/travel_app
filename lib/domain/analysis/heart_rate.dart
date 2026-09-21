import '../models/track_point.dart';
import 'constants.dart';

/// 心率区间定义。区间为左闭右开：[minRatio, maxRatio)。
class HrZone {
  const HrZone({
    required this.index,
    required this.label,
    required this.minRatio,
    required this.maxRatio,
  });

  final int index;
  final String label;
  final double minRatio;
  final double maxRatio;
}

/// 按最大心率的百分比切分的五个区间。见设计文档 8.2。
const List<HrZone> kHrZones = <HrZone>[
  HrZone(index: 1, label: 'Z1 恢复', minRatio: 0.0, maxRatio: 0.6),
  HrZone(index: 2, label: 'Z2 耐力', minRatio: 0.6, maxRatio: 0.7),
  HrZone(index: 3, label: 'Z3 节奏', minRatio: 0.7, maxRatio: 0.8),
  HrZone(index: 4, label: 'Z4 阈值', minRatio: 0.8, maxRatio: 0.9),
  HrZone(index: 5, label: 'Z5 无氧', minRatio: 0.9, maxRatio: double.infinity),
];

/// 心率落在哪个区间（1..5）。[maxHeartRate] 非正数时返回 null。
int? zoneIndexForHr(int hr, int maxHeartRate) {
  if (maxHeartRate <= 0) return null;
  final double ratio = hr / maxHeartRate;
  for (final HrZone z in kHrZones) {
    if (ratio >= z.minRatio && ratio < z.maxRatio) return z.index;
  }
  return kHrZones.last.index;
}

/// 各心率区间的停留时长分布。
class HrZoneBreakdown {
  const HrZoneBreakdown({required this.secondsByZone, required this.totalSeconds});

  final Map<int, double> secondsByZone;
  final double totalSeconds;

  double ratioOf(int zoneIndex) =>
      totalSeconds <= 0 ? 0 : (secondsByZone[zoneIndex] ?? 0) / totalSeconds;
}

/// 按相邻点的时间差把时长归入各心率区间。
/// 时间不前进、缺心率、或间隔超过 [kGpsGapMs] 的区间不计入。
HrZoneBreakdown hrZoneBreakdown(List<TrackPoint> points, int maxHeartRate) {
  final Map<int, double> seconds = <int, double>{};
  double total = 0;
  for (int i = 1; i < points.length; i++) {
    final int dtMs = points[i].tMs - points[i - 1].tMs;
    if (dtMs <= 0 || dtMs > kGpsGapMs) continue;
    final int? hr = points[i].hr;
    if (hr == null) continue;
    final int? zone = zoneIndexForHr(hr, maxHeartRate);
    if (zone == null) continue;
    final double dt = dtMs / 1000.0;
    seconds[zone] = (seconds[zone] ?? 0) + dt;
    total += dt;
  }
  return HrZoneBreakdown(secondsByZone: seconds, totalSeconds: total);
}

/// 时长时间加权的心率均值。无心率数据时返回 null。
double? averageHr(List<TrackPoint> points) {
  double weighted = 0;
  double total = 0;
  for (int i = 1; i < points.length; i++) {
    final int dtMs = points[i].tMs - points[i - 1].tMs;
    if (dtMs <= 0 || dtMs > kGpsGapMs) continue;
    final int? hr = points[i].hr;
    if (hr == null) continue;
    final double dt = dtMs / 1000.0;
    weighted += hr * dt;
    total += dt;
  }
  return total <= 0 ? null : weighted / total;
}

/// 出现过的最高心率。无心率数据时返回 null。
int? observedMaxHr(List<TrackPoint> points) {
  int? best;
  for (final TrackPoint p in points) {
    final int? hr = p.hr;
    if (hr == null) continue;
    if (best == null || hr > best) best = hr;
  }
  return best;
}
