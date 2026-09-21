import 'package:cycling_app/core/format.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDistance', () {
    test('不足 1 公里用米', () {
      expect(formatDistance(500, DistanceUnit.kilometer), '500 m');
    });

    test('超过 1 公里用公里', () {
      expect(formatDistance(1234, DistanceUnit.kilometer), '1.23 km');
    });

    test('英里单位', () {
      expect(formatDistance(1609.344, DistanceUnit.mile), '1.00 mi');
    });

    test('不足 0.1 英里用英尺', () {
      expect(formatDistance(30, DistanceUnit.mile), '98 ft');
    });

    // 以下为计划书之外的边界补测。
    test('0 米显示 0 m', () {
      expect(formatDistance(0, DistanceUnit.kilometer), '0 m');
    });

    test('999.9 米仍走米分支，四舍五入成 1000 m', () {
      // 临界点的已知观感问题：999.9 米显示成「1000 m」而不是「1.00 km」。
      // 这里把真实行为钉住，避免以后改换算时无声漂移。
      expect(formatDistance(999.9, DistanceUnit.kilometer), '1000 m');
    });

    test('整 1000 米切到公里', () {
      expect(formatDistance(1000, DistanceUnit.kilometer), '1.00 km');
    });

    test('0 米在英里单位下显示 0 ft', () {
      expect(formatDistance(0, DistanceUnit.mile), '0 ft');
    });

    test('整 0.1 英里（160.9344 米）已切到英里', () {
      // 1609.344 * 0.1 = 160.9344，浮点除法恰好得到 0.1，不再走英尺分支。
      expect(formatDistance(160.9344, DistanceUnit.mile), '0.10 mi');
    });

    test('1 米换英尺的换算常量核对（1 / 0.3048 ≈ 3.28084）', () {
      // 3.28084 是 1/0.3048 = 3.280839895… 的常用近似，30 米 = 98.4252 英尺。
      expect(formatDistance(1, DistanceUnit.mile), '3 ft');
      expect(formatDistance(100, DistanceUnit.mile), '328 ft');
    });
  });

  group('速度与时长', () {
    test('速度数值按单位换算', () {
      expect(formatSpeedValue(6.0, DistanceUnit.kilometer), '21.6');
      expect(formatSpeedValue(6.0, DistanceUnit.mile), '13.4');
    });

    test('速度单位标签', () {
      expect(speedUnitLabel(DistanceUnit.kilometer), 'km/h');
      expect(speedUnitLabel(DistanceUnit.mile), 'mph');
    });

    test('不足一小时用 mm:ss', () {
      expect(formatDuration(90), '01:30');
    });

    test('超过一小时用 h:mm:ss', () {
      expect(formatDuration(3661), '1:01:01');
    });

    // 以下为计划书之外的边界补测。
    test('速度为 0 时两种单位都是 0.0', () {
      expect(formatSpeedValue(0, DistanceUnit.kilometer), '0.0');
      expect(formatSpeedValue(0, DistanceUnit.mile), '0.0');
    });

    test('6 m/s = 21.6 km/h = 13.42 mph 的换算常量核对', () {
      // 21.6 = 6 * 3.6；13.42 = 6 * 3600 / 1609.344 = 13.4216…
      expect(formatSpeedValue(10, DistanceUnit.kilometer), '36.0');
      expect(formatSpeedValue(10, DistanceUnit.mile), '22.4');
    });

    test('时长为 0 显示 00:00', () {
      expect(formatDuration(0), '00:00');
    });

    test('3599 秒仍是 mm:ss', () {
      expect(formatDuration(3599), '59:59');
    });

    test('整 3600 秒切到 h:mm:ss', () {
      expect(formatDuration(3600), '1:00:00');
    });

    test('负时长按 0 处理', () {
      expect(formatDuration(-5), '00:00');
    });
  });

  group('formatDateTime', () {
    test('按本地时区输出 yyyy-MM-dd HH:mm', () {
      final int ms = DateTime(2026, 9, 21, 8, 5).millisecondsSinceEpoch;
      expect(formatDateTime(ms), '2026-09-21 08:05');
    });

    test('个位数月日与时分都补零', () {
      final int ms = DateTime(2026, 1, 2, 3, 4).millisecondsSinceEpoch;
      expect(formatDateTime(ms), '2026-01-02 03:04');
    });

    test('午夜输出 00:00', () {
      final int ms = DateTime(2026, 12, 31).millisecondsSinceEpoch;
      expect(formatDateTime(ms), '2026-12-31 00:00');
    });
  });
}
