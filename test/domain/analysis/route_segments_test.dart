import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/analysis/gcj02.dart';
import 'package:cycling_app/domain/analysis/route_segments.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPoint pt(
  int tMs, {
  double? lat = 31.0,
  double? lon = 121.0,
  double? speed,
}) =>
    TrackPoint(rideId: 1, tMs: tMs, lat: lat, lon: lon, speedMps: speed);

void main() {
  group('基本行为', () {
    test('空输入返回空列表', () {
      expect(buildRouteSegments(const <TrackPoint>[]), isEmpty);
    });

    test('单点构不成折线，返回空列表', () {
      expect(buildRouteSegments(<TrackPoint>[pt(0, speed: 5)]), isEmpty);
    });

    test('无坐标的点被跳过，不影响连线', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 5),
        const TrackPoint(rideId: 1, tMs: 500, hr: 140), // 无坐标
        pt(1000, lat: 31.0001, speed: 6),
      ]);

      expect(segs.length, 1);
      expect(segs.single.vertices.length, 2);
    });

    test('坐标经过 WGS-84 → GCJ-02 转换', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, lat: 39.90750, lon: 116.39123, speed: 5),
        pt(1000, lat: 39.90760, lon: 116.39133, speed: 6),
      ]);

      final ({double lat, double lon}) expected = wgs84ToGcj02(39.90750, 116.39123);
      expect(segs.single.vertices.first.lat, closeTo(expected.lat, 1e-9));
      expect(segs.single.vertices.first.lon, closeTo(expected.lon, 1e-9));
    });

    test('境外点不做转换', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, lat: 35.6762, lon: 139.6503, speed: 5),
        pt(1000, lat: 35.6763, lon: 139.6504, speed: 6),
      ]);

      expect(segs.single.vertices.first.lat, 35.6762);
      expect(segs.single.vertices.first.lon, 139.6503);
    });
  });

  group('断线规则', () {
    test('时间间隔超过 kGpsGapMs 时断开', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 5),
        pt(1000, lat: 31.0001, speed: 5),
        pt(1000 + kGpsGapMs + 1, lat: 31.0002, speed: 5),
        pt(2000 + kGpsGapMs + 1, lat: 31.0003, speed: 5),
      ]);

      expect(segs.length, 2);
      expect(segs[0].vertices.length, 2);
      expect(segs[1].vertices.length, 2);
    });

    test('恰好等于 kGpsGapMs 不断开', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 5),
        pt(kGpsGapMs, lat: 31.0001, speed: 5),
      ]);

      expect(segs.length, 1);
    });

    // 上面的用例带速度，跳变判定（`isTrustedSegment`）里也会查一遍时间间隔，
    // 于是 `_connectable` 自己的间隔判定被掩盖了：把它改成 `kGpsGapMs * 100`
    // 上面那条照样绿。这条用**没有速度**的点，逼 `_connectable` 自己判间隔。
    test('缺速度时长间隔超过 kGpsGapMs 也断开', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0),
        pt(1000, lat: 31.0001),
        pt(1000 + kGpsGapMs + 1, lat: 31.0002),
        pt(2000 + kGpsGapMs + 1, lat: 31.0003),
      ]);

      expect(segs.length, 2);
      expect(segs[0].vertices.length, 2);
      expect(segs[1].vertices.length, 2);
    });

    test('时间不前进时断开', () {
      // 时间倒流 → 断开。断开后前后各只剩一个顶点，`_flush` 会丢弃单顶点段，
      // 所以结果是空列表（不是「两段各一个点」）。
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(1000, speed: 5),
        pt(500, lat: 31.0001, speed: 5),
      ]);

      expect(segs, isEmpty);
    });

    // 计划书原用例只断言「两段」但实现返回空列表；上面那条已按真实行为改正。
    // 但仅靠它证明不了「时间倒流处真的断开了」——断开发生在两点之间时，
    // 前后各只有一个顶点，看不出有没有断。这条把断开放在中间，前后各两个
    // 顶点：若不断开，四点会连成一段（segs.length == 1）。
    test('时间倒流处断开，前后各成一段', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, lat: 31.0),
        pt(1000, lat: 31.0001),
        pt(500, lat: 31.0002),
        pt(1500, lat: 31.0003),
      ]);

      expect(segs.length, 2);
      expect(segs[0].vertices.length, 2);
      expect(segs[1].vertices.length, 2);
      expect(segs[0].vertices.last.lat, isNot(segs[1].vertices.first.lat));
    });

    test('隐含速度超过 kMaxPlausibleSpeedMps 时断开（GPS 跳变）', () {
      // 1 秒内跨 0.01 度纬度 ≈ 1113 米，远超 30 m/s。
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 5),
        pt(1000, lat: 31.01, speed: 5),
        pt(2000, lat: 31.0101, speed: 5),
      ]);

      // 第一对是跳变（断开），但断开后它只剩一个孤立顶点，`_flush` 会丢弃，
      // 因此只有后一对构成的可画段。
      expect(segs.length, 1);
      expect(segs.single.vertices.length, 2);
    });

    // 同上：只有「跳变两侧各有可画段」才能证明跳变处真的断开，
    // 而不是「跳变点恰好是首点所以没得连」。
    test('跳变处真的断开，跳变前后各成一段', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, lat: 31.0, speed: 5),
        pt(1000, lat: 31.0001, speed: 5),
        pt(2000, lat: 31.01, speed: 5), // 从 31.0001 跳 0.0099 度 → 跳变
        pt(3000, lat: 31.0101, speed: 5),
        pt(4000, lat: 31.0102, speed: 5),
      ]);

      expect(segs.length, 2);
      expect(segs[0].vertices.length, 2);
      expect(segs[1].vertices.length, 3);
      // 跳变的那一对不能被连起来。
      expect(segs[1].vertices.first.lat, isNot(segs[0].vertices.last.lat));
    });

    test('缺速度时不判跳变，按时间判定', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0),
        pt(1000, lat: 31.01), // 大跳但没速度
        pt(2000, lat: 31.0101),
      ]);

      expect(segs.length, 1);
    });
  });

  group('分组与着色', () {
    test('连续点被分成不超过 maxVerticesPerSegment 个顶点的段', () {
      final List<TrackPoint> points = <TrackPoint>[
        for (int i = 0; i < 100; i++)
          pt(i * 1000, lat: 31.0 + i * 0.0001, speed: 5),
      ];

      final List<RouteSegment> segs =
          buildRouteSegments(points, maxVerticesPerSegment: 10);

      for (final RouteSegment s in segs) {
        expect(s.vertices.length, lessThanOrEqualTo(10));
      }
      expect(segs.length, greaterThan(1));
    });

    test('相邻两段共享一个顶点，折线才连得上', () {
      final List<TrackPoint> points = <TrackPoint>[
        for (int i = 0; i < 30; i++)
          pt(i * 1000, lat: 31.0 + i * 0.0001, speed: 5),
      ];

      final List<RouteSegment> segs =
          buildRouteSegments(points, maxVerticesPerSegment: 10);

      expect(segs.length, greaterThan(1));
      for (int i = 1; i < segs.length; i++) {
        final RouteVertex prevLast = segs[i - 1].vertices.last;
        final RouteVertex curFirst = segs[i].vertices.first;
        expect(curFirst.lat, prevLast.lat);
        expect(curFirst.lon, prevLast.lon);
      }
    });

    test('快的那一段颜色与慢的那一段不同', () {
      final List<RouteSegment> slow = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 1),
        pt(1000, lat: 31.0001, speed: 1),
      ]);
      final List<RouteSegment> fast = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 14),
        pt(1000, lat: 31.0001, speed: 14),
      ]);

      expect(slow.single.colorArgb, isNot(fast.single.colorArgb));
    });

    test('没有速度时按 0 处理，不抛错', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0),
        pt(1000, lat: 31.0001),
      ]);

      expect(segs.single.colorArgb, isNotNull);
    });
  });
}
