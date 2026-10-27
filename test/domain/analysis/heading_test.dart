import 'package:cycling_app/domain/analysis/heading.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeDegrees', () {
    test('负角度回到 0..360', () {
      expect(normalizeDegrees(-10), closeTo(350, 1e-9));
      expect(normalizeDegrees(-370), closeTo(350, 1e-9));
    });

    test('超过一圈或多圈都折回', () {
      expect(normalizeDegrees(360), 0);
      expect(normalizeDegrees(370), closeTo(10, 1e-9));
      expect(normalizeDegrees(720 + 45), closeTo(45, 1e-9));
    });

    test('0 与正常角度保持不变', () {
      expect(normalizeDegrees(0), 0);
      expect(normalizeDegrees(90), 90);
    });
  });

  group('shortestArcDelta', () {
    test('跨越 0/360 只转 2 度，不倒整圈', () {
      // 359° → 1°：直接相减是 -358°，最短弧应是 +2°。
      expect(shortestArcDelta(359, 1), closeTo(2, 1e-9));
      expect(shortestArcDelta(1, 359), closeTo(-2, 1e-9));
    });

    test('±170° 之间走 20 度的一侧', () {
      // 170° 到 -170°（＝190°）的最短路径是 +20°，而不是 -340°。
      expect(shortestArcDelta(170, -170), closeTo(20, 1e-9));
      expect(shortestArcDelta(-170, 170), closeTo(-20, 1e-9));
    });

    test('180 度保持半圈，方向按输入符号', () {
      expect(shortestArcDelta(0, 180), closeTo(180, 1e-9));
      expect(shortestArcDelta(180, 0), closeTo(-180, 1e-9));
      expect(shortestArcDelta(90, 270), closeTo(180, 1e-9));
      expect(shortestArcDelta(270, 90), closeTo(-180, 1e-9));
    });

    test('同角度差为 0', () {
      expect(shortestArcDelta(0, 360), 0);
      expect(shortestArcDelta(45, 45), 0);
    });
  });

  group('bearingDegrees', () {
    test('正北 / 正东 / 正南 / 正西', () {
      // 纬度 0 附近取很短的距离，方位角就是象限角。
      expect(bearingDegrees(0, 0, 1, 0), closeTo(0, 1e-6));
      expect(bearingDegrees(0, 0, 0, 1), closeTo(90, 1e-6));
      expect(bearingDegrees(0, 0, -1, 0), closeTo(180, 1e-6));
      expect(bearingDegrees(0, 0, 0, -1), closeTo(270, 1e-6));
    });

    test('两点重合时返回 0，由调用方判断是否可用', () {
      expect(bearingDegrees(31, 121, 31, 121), 0);
    });
  });

  group('headingUpdateFor', () {
    test('三档速度门槛', () {
      expect(headingUpdateFor(3.0), HeadingUpdate.adopt);
      expect(headingUpdateFor(1.0), HeadingUpdate.adopt);
      expect(headingUpdateFor(0.9), HeadingUpdate.hold);
      expect(headingUpdateFor(0.5), HeadingUpdate.hold);
      expect(headingUpdateFor(0.49), HeadingUpdate.freeze);
      expect(headingUpdateFor(0), HeadingUpdate.freeze);
    });
  });

  group('resolveHeadingDeg', () {
    test('速度达标时采用上报值', () {
      expect(
        resolveHeadingDeg(currentDeg: 10, reportedDeg: 200, speedMps: 2),
        closeTo(200, 1e-9),
      );
    });

    test('上报值先归一化', () {
      expect(
        resolveHeadingDeg(currentDeg: null, reportedDeg: 370, speedMps: 2),
        closeTo(10, 1e-9),
      );
    });

    test('上报值缺失时保持原朝向，不甩回正北', () {
      expect(
        resolveHeadingDeg(currentDeg: 200, reportedDeg: null, speedMps: 5),
        200,
      );
      expect(
        resolveHeadingDeg(currentDeg: null, reportedDeg: null, speedMps: 5),
        isNull,
      );
    });

    test('低速冻结在最后一次朝向', () {
      expect(
        resolveHeadingDeg(currentDeg: 200, reportedDeg: 0, speedMps: 0),
        200,
      );
    });

    test('中间档保持原值', () {
      expect(
        resolveHeadingDeg(currentDeg: 200, reportedDeg: 0, speedMps: 0.8),
        200,
      );
    });
  });

  group('最短弧累加', () {
    test('跨零连续累加保持单调，不倒整圈', () {
      double unwrapped = 350;
      double prev = 350;
      for (final double next in <double>[355, 1, 5, 10]) {
        unwrapped += shortestArcDelta(prev, next);
        prev = next;
      }
      // 350 → 355 → 1 → 5 → 10，总共 +20 度，而不是绕回去 340 度。
      expect(unwrapped, closeTo(370, 1e-9));
      expect(unwrapped / 360, greaterThan(1));
    });
  });
}
