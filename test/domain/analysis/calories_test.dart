import 'package:cycling_app/domain/analysis/calories.dart';
import 'package:cycling_app/domain/analysis/heart_rate.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('30 分钟 Z2 区间、70kg 体重约 210 千卡', () {
    // MET 6 × 70kg × 0.5h = 210
    const HrZoneBreakdown zones = HrZoneBreakdown(
      secondsByZone: <int, double>{2: 1800},
      totalSeconds: 1800,
    );
    expect(estimateCalories(zones: zones, weightKg: 70), closeTo(210, 1e-9));
  });

  test('强度越高同一时长消耗越多', () {
    const HrZoneBreakdown easy = HrZoneBreakdown(
      secondsByZone: <int, double>{2: 1800},
      totalSeconds: 1800,
    );
    const HrZoneBreakdown hard = HrZoneBreakdown(
      secondsByZone: <int, double>{5: 1800},
      totalSeconds: 1800,
    );
    final double? low = estimateCalories(zones: easy, weightKg: 70);
    final double? high = estimateCalories(zones: hard, weightKg: 70);
    expect(high! > low!, isTrue);
  });

  test('没有心率数据时返回 null', () {
    final HrZoneBreakdown zones = hrZoneBreakdown(
      <TrackPoint>[TrackPoint(rideId: 1, tMs: 0), TrackPoint(rideId: 1, tMs: 1000)],
      190,
    );
    expect(estimateCalories(zones: zones, weightKg: 70), isNull);
  });

  test('体重非正数时返回 null', () {
    const HrZoneBreakdown zones = HrZoneBreakdown(
      secondsByZone: <int, double>{2: 1800},
      totalSeconds: 1800,
    );
    expect(estimateCalories(zones: zones, weightKg: 0), isNull);
  });
}
