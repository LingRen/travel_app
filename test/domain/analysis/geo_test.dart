import 'package:cycling_app/domain/analysis/geo.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('haversineMeters', () {
    test('同一点距离为 0', () {
      expect(haversineMeters(31.23, 121.47, 31.23, 121.47), 0);
    });

    test('北纬 31.23 处经度相差 0.01 度约等于 950.8 米', () {
      expect(haversineMeters(31.23, 121.47, 31.23, 121.48), closeTo(950.8, 1.0));
    });

    test('纬度相差 0.01 度约等于 1111.9 米', () {
      expect(haversineMeters(31.23, 121.47, 31.24, 121.47), closeTo(1111.9, 1.0));
    });
  });

  group('segmentDistanceMeters', () {
    test('正常相邻两点返回实际距离', () {
      expect(
        segmentDistanceMeters(_p(0, 31.23, 121.47), _p(1000, 31.23, 121.4701)),
        closeTo(9.5, 0.5),
      );
    });

    test('任一缺坐标时返回 0', () {
      expect(segmentDistanceMeters(_p(0, 31.23, 121.47), _p(1000, null, null)), 0);
    });

    test('时间间隔超过 10 秒的 GPS 断点返回 0', () {
      expect(segmentDistanceMeters(_p(0, 31.23, 121.47), _p(11000, 31.23, 121.48)), 0);
    });

    test('时间不前进时返回 0', () {
      expect(segmentDistanceMeters(_p(1000, 31.23, 121.47), _p(1000, 31.23, 121.48)), 0);
    });

    test('隐含速度超过上限的 GPS 跳变返回 0', () {
      // 1 秒内跳了约 140 公里
      expect(segmentDistanceMeters(_p(0, 31.23, 121.47), _p(1000, 32.23, 122.47)), 0);
    });
  });
}

TrackPoint _p(int tMs, double? lat, double? lon) =>
    TrackPoint(rideId: 1, tMs: tMs, lat: lat, lon: lon);
