import 'dart:math' as math;

import 'package:cycling_app/domain/analysis/gcj02.dart';
import 'package:flutter_test/flutter_test.dart';

/// 两点间的球面距离（米），用于断言往返误差。经纬度单位是度。
double _distanceM(double lat1, double lon1, double lat2, double lon2) {
  const double earthRadiusM = 6371000.0;
  final double dLat = (lat2 - lat1) * math.pi / 180.0;
  final double dLon = (lon2 - lon1) * math.pi / 180.0;
  final double a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * earthRadiusM * math.asin(math.sqrt(a));
}

void main() {
  group('gcj02ToWgs84', () {
    // 往返：WGS-84 -> GCJ-02 -> WGS-84，误差应远小于定位本身误差。
    test('成都、北京、海岸线往返误差 ≤2 米', () {
      const List<({double lat, double lon})> points = <({double lat, double lon})>[
        (lat: 30.6570, lon: 104.0657), // 成都天府广场
        (lat: 39.90750, lon: 116.39123), // 北京天安门
        (lat: 24.4798, lon: 118.0894), // 厦门（海岸线附近）
        (lat: 36.0671, lon: 120.3826), // 青岛（海岸线附近）
      ];

      for (final ({double lat, double lon}) wgs in points) {
        final ({double lat, double lon}) gcj = wgs84ToGcj02(wgs.lat, wgs.lon);
        final ({double lat, double lon}) back = gcj02ToWgs84(gcj.lat, gcj.lon);
        expect(
          _distanceM(wgs.lat, wgs.lon, back.lat, back.lon),
          lessThan(2.0),
          reason: '往返误差超限：$wgs -> $gcj -> $back',
        );
      }
    });

    test('靠近中国边界但仍在境内时同样收敛', () {
      const double lat = 40.0;
      const double lon = 72.01; // 西边界 72.004 之内
      final ({double lat, double lon}) gcj = wgs84ToGcj02(lat, lon);
      final ({double lat, double lon}) back = gcj02ToWgs84(gcj.lat, gcj.lon);
      expect(_distanceM(lat, lon, back.lat, back.lon), lessThan(2.0));
    });

    test('境外点原样返回', () {
      final ({double lat, double lon}) w = gcj02ToWgs84(35.6762, 139.6503);
      expect(w.lat, 35.6762);
      expect(w.lon, 139.6503);
    });

    test('非法输入不抛出异常也不过界', () {
      expect(gcj02ToWgs84(double.nan, 104.0).lat.isNaN, isTrue);
      expect(gcj02ToWgs84(30.0, double.infinity).lon.isInfinite, isTrue);
      expect(gcj02ToWgs84(95.0, 104.0).lat, lessThanOrEqualTo(95.0));
    });

    test('对已是 WGS-84 的点不会把坐标推向境外或 NaN', () {
      final ({double lat, double lon}) w = gcj02ToWgs84(39.90750, 116.39123);
      expect(w.lat.isFinite, isTrue);
      expect(w.lon.isFinite, isTrue);
      expect(isOutOfChina(w.lat, w.lon), isFalse);
      // 逆变换会把「当作 GCJ 的 WGS 点」往西南挪几百米，量级应在 0.001~0.02 度。
      expect((w.lat - 39.90750).abs(), inInclusiveRange(0.0001, 0.02));
    });
  });
}
