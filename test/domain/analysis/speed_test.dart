import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/analysis/speed.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('maxSmoothedSpeed', () {
    test('单点毛刺被滑动平均抹平', () {
      // 30 m/s 的单点毛刺前后各留 4 个 5 m/s 采样，让毛刺始终落在窗口正中，
      // 于是滤波后的峰值是 5 + (30 - 5) / 5 = 10 —— 未滤波时峰值是 30。
      //
      // 窗口 5 必然包含毛刺本身，所以单点毛刺不可能被完全抹回基线 5：10 是
      // 该窗口下能达到的最小峰值。毛刺贴边时窗口被裁剪，反而会算出更大的
      // 峰值（毛刺在 index 1 时是 (5+5+5+30)/4 = 11.25），那是边界裁剪的
      // 产物，与被测意图无关，因此这里把毛刺放在序列中间。
      final List<double?> speeds = <double?>[5, 5, 5, 5, 30, 5, 5, 5, 5];
      expect(maxSmoothedSpeed(speeds, kSpeedFilterWindow), closeTo(10, 1e-9));
    });

    test('持续高速保留真实峰值', () {
      final List<double?> speeds = <double?>[5, 5, 12, 12, 12, 12, 12, 5, 5];
      expect(maxSmoothedSpeed(speeds, kSpeedFilterWindow), closeTo(12, 1e-9));
    });

    test('全部为空时返回 null', () {
      expect(maxSmoothedSpeed(<double?>[null, null], kSpeedFilterWindow), isNull);
    });
  });

  group('splitMovingStationary', () {
    test('等红灯的时间计入静止', () {
      // 移动 2 秒、静止 3 秒：两侧时长必须不相等，否则把移动/静止判反了
      // 也照样能凑出同样的总数，测试就失去区分能力。
      final List<TrackPoint> points = <TrackPoint>[
        _p(0, 5.0),
        _p(1000, 5.0),
        _p(2000, 0.1),
        _p(3000, 0.1),
        _p(4000, 0.1),
        _p(5000, 5.0),
      ];
      final MovingStats s = splitMovingStationary(points, kStationarySpeedMps);
      expect(s.movingSeconds, closeTo(2.0, 1e-9));
      expect(s.stationarySeconds, closeTo(3.0, 1e-9));
    });

    test('超过 10 秒的 GPS 断点两个区间都不计入', () {
      final MovingStats s =
          splitMovingStationary(<TrackPoint>[_p(0, 5.0), _p(15000, 5.0)], kStationarySpeedMps);
      expect(s.movingSeconds, 0);
      expect(s.stationarySeconds, 0);
    });

    test('缺速度的区间不计入', () {
      final MovingStats s =
          splitMovingStationary(<TrackPoint>[_p(0, null), _p(1000, null)], kStationarySpeedMps);
      expect(s.movingSeconds, 0);
      expect(s.stationarySeconds, 0);
    });
  });
}

TrackPoint _p(int tMs, double? speed) => TrackPoint(rideId: 1, tMs: tMs, speedMps: speed);
