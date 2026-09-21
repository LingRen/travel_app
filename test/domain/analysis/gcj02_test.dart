import 'package:cycling_app/domain/analysis/gcj02.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isOutOfChina', () {
    test('中国境内的点返回 false', () {
      expect(isOutOfChina(39.90750, 116.39123), isFalse); // 天安门
      expect(isOutOfChina(31.23042, 121.47370), isFalse); // 上海人民广场
    });

    test('经度超出东界返回 true', () {
      expect(isOutOfChina(35.6762, 139.6503), isTrue); // 东京
    });

    test('纬度超出北界返回 true', () {
      expect(isOutOfChina(55.9, 100.0), isTrue);
    });

    test('纬度低于南界返回 true', () {
      expect(isOutOfChina(0.5, 100.0), isTrue);
    });

    test('经度低于西界返回 true', () {
      expect(isOutOfChina(39.9, 71.0), isTrue);
    });

    test('边界值本身算境内（判定用开区间）', () {
      expect(isOutOfChina(55.8271, 100.0), isFalse);
      expect(isOutOfChina(0.8293, 100.0), isFalse);
      expect(isOutOfChina(39.9, 72.004), isFalse);
      expect(isOutOfChina(39.9, 137.8347), isFalse);
    });
  });

  group('wgs84ToGcj02', () {
    test('天安门：偏移量落在已知区间', () {
      final ({double lat, double lon}) g = wgs84ToGcj02(39.90750, 116.39123);
      // 期望值由标准 GCJ-02 算法独立算得，见实施偏差记录。
      expect(g.lat, closeTo(39.90890124, 1e-6));
      expect(g.lon, closeTo(116.39747114, 1e-6));
    });

    test('上海人民广场：纬度偏移为负、经度偏移为正', () {
      final ({double lat, double lon}) g = wgs84ToGcj02(31.23042, 121.47370);
      expect(g.lat, closeTo(31.22847775, 1e-6));
      expect(g.lon, closeTo(121.47822306, 1e-6));
      expect(g.lat, lessThan(31.23042));
      expect(g.lon, greaterThan(121.47370));
    });

    test('境外点原样返回', () {
      final ({double lat, double lon}) g = wgs84ToGcj02(35.6762, 139.6503);
      expect(g.lat, 35.6762);
      expect(g.lon, 139.6503);
    });

    test('偏移量在经度方向约 0.004~0.007 度，量级正确', () {
      final ({double lat, double lon}) g = wgs84ToGcj02(39.90750, 116.39123);
      expect((g.lon - 116.39123).abs(), inInclusiveRange(0.004, 0.007));
    });

    test('转换是纯函数：同一输入两次结果完全相同', () {
      final ({double lat, double lon}) a = wgs84ToGcj02(23.12911, 113.26439);
      final ({double lat, double lon}) b = wgs84ToGcj02(23.12911, 113.26439);
      expect(a.lat, b.lat);
      expect(a.lon, b.lon);
    });
  });
}
