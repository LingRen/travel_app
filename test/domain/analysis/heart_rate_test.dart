import 'package:cycling_app/domain/analysis/heart_rate.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('zoneIndexForHr', () {
    test('边界值归入更高的区间', () {
      expect(zoneIndexForHr(120, 200), 2); // 恰好 60%
      expect(zoneIndexForHr(140, 200), 3); // 恰好 70%
      expect(zoneIndexForHr(160, 200), 4); // 恰好 80%
      expect(zoneIndexForHr(180, 200), 5); // 恰好 90%
    });

    test('边界下方归入更低的区间', () {
      expect(zoneIndexForHr(119, 200), 1);
      expect(zoneIndexForHr(139, 200), 2);
      expect(zoneIndexForHr(159, 200), 3);
      expect(zoneIndexForHr(179, 200), 4);
    });

    test('超出最大心率仍归入 Z5', () {
      expect(zoneIndexForHr(210, 200), 5);
    });

    test('最大心率非正数时返回 null', () {
      expect(zoneIndexForHr(120, 0), isNull);
    });
  });

  group('hrZoneBreakdown', () {
    test('按区间停留时长累计并给出占比', () {
      final List<TrackPoint> points = <TrackPoint>[
        _p(0, 120),
        _p(1000, 120), // Z2
        _p(2000, 160), // Z4
        _p(3000, 160), // Z4
        _p(4000, 190), // Z5
      ];
      final HrZoneBreakdown b = hrZoneBreakdown(points, 200);

      expect(b.totalSeconds, closeTo(4.0, 1e-9));
      expect(b.secondsByZone[2], closeTo(1.0, 1e-9));
      expect(b.secondsByZone[4], closeTo(2.0, 1e-9));
      expect(b.secondsByZone[5], closeTo(1.0, 1e-9));
      expect(b.ratioOf(4), closeTo(0.5, 1e-9));
    });

    test('没有心率数据时总时长为 0', () {
      final List<TrackPoint> points = <TrackPoint>[_p(0, null), _p(1000, null)];
      expect(hrZoneBreakdown(points, 200).totalSeconds, 0);
    });
  });
}

TrackPoint _p(int tMs, int? hr) => TrackPoint(rideId: 1, tMs: tMs, hr: hr);
