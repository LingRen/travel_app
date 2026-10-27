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
}) => TrackPoint(rideId: 1, tMs: tMs, lat: lat, lon: lon, speedMps: speed);

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

      final ({double lat, double lon}) expected = wgs84ToGcj02(
        39.90750,
        116.39123,
      );
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

    // 瓦片源不是 GCJ-02（OSM、Carto）时必须原样输出，否则轨迹整体偏几百米。
    test('toGcj02 为 false 时坐标原样输出', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, lat: 31.23042, lon: 121.47370, speed: 5),
        pt(1000, lat: 31.23052, lon: 121.47380, speed: 6),
      ], toGcj02: false);

      expect(segs.single.vertices.first.lat, 31.23042);
      expect(segs.single.vertices.first.lon, 121.47370);
      expect(segs.single.vertices.last.lat, 31.23052);
      expect(segs.single.vertices.last.lon, 121.47380);
    });

    // 两个开关必须真的产生不同的结果，否则上一条用例在「永远不转换」的
    // 实现下也会绿。
    test('toGcj02 两个取值的顶点不同', () {
      final List<TrackPoint> points = <TrackPoint>[
        pt(0, lat: 31.23042, lon: 121.47370, speed: 5),
        pt(1000, lat: 31.23052, lon: 121.47380, speed: 6),
      ];

      final RouteVertex converted = buildRouteSegments(points)
          .single
          .vertices
          .first;
      final RouteVertex raw = buildRouteSegments(
        points,
        toGcj02: false,
      ).single.vertices.first;

      expect(converted.lat, isNot(raw.lat));
      expect(converted.lon, isNot(raw.lon));
    });

    // 默认值就是高德的 GCJ-02：不传参数时行为与修复前一致，避免调用方
    // 漏传时把默认源也画偏。
    test('默认按 GCJ-02 转换', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, lat: 39.90750, lon: 116.39123, speed: 5),
        pt(1000, lat: 39.90760, lon: 116.39133, speed: 6),
      ]);

      final ({double lat, double lon}) expected = wgs84ToGcj02(
        39.90750,
        116.39123,
      );
      expect(segs.single.vertices.first.lat, closeTo(expected.lat, 1e-9));
    });
  });

  group('断线规则', () {
    test('时间间隔超过 kGpsGapMs 且位移明显时断开', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 5),
        pt(1000, lat: 31.0001, speed: 5),
        // 断点两侧真的挪了地方（约 1.1 km），连起来就是一条假直线。
        pt(1000 + kGpsGapMs + 1, lat: 31.0102, speed: 5),
        pt(2000 + kGpsGapMs + 1, lat: 31.0103, speed: 5),
      ]);

      expect(segs.length, 2);
      expect(segs[0].vertices.length, 2);
      expect(segs[1].vertices.length, 2);
    });

    // 真机实测（2026-10-20）：一趟 20 分钟的骑行里 8 处超过 10 秒的间隔有 6 处
    // 只是「停在原地时系统不再送定位」，位移 0~13 米。纯按时间判会在每次停车处
    // 画出断口，看起来就是「断断续续」。
    test('时间间隔超过 kGpsGapMs 但几乎没位移时不断开', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 0),
        pt(1000, lat: 31.0001, speed: 0),
        pt(1000 + kGpsGapMs + 1, lat: 31.00018, speed: 0), // 约 9 米
        pt(2000 + kGpsGapMs + 1, lat: 31.00019, speed: 0),
      ]);

      expect(segs.length, 1);
      expect(segs.single.vertices.length, 4);
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
        pt(1000 + kGpsGapMs + 1, lat: 31.0102),
        pt(2000 + kGpsGapMs + 1, lat: 31.0103),
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

      final List<RouteSegment> segs = buildRouteSegments(
        points,
        maxVerticesPerSegment: 10,
      );

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

      final List<RouteSegment> segs = buildRouteSegments(
        points,
        maxVerticesPerSegment: 10,
      );

      expect(segs.length, greaterThan(1));
      for (int i = 1; i < segs.length; i++) {
        final RouteVertex prevLast = segs[i - 1].vertices.last;
        final RouteVertex curFirst = segs[i].vertices.first;
        expect(curFirst.lat, prevLast.lat);
        expect(curFirst.lon, prevLast.lon);
      }
    });
  });

  // 信号中断的断口：详情页拿它在地图上标两端、在顶部写「信号中断 N 段」。
  // 口径必须与画线用的 isMeaningfulGap 完全一致，否则会出现「线断了但没有标记」
  // 或「标了断口但线连得上」这种自相矛盾。
  group('信号中断断口', () {
    test('超过 10 秒且真的挪了地方才算中断', () {
      final List<RouteGap> gaps = findRouteGaps(<TrackPoint>[
        pt(0),
        pt(1000, lat: 31.0001),
        // 14 秒空档 + 约 1.1 公里位移：真丢了信号。
        pt(15000, lat: 31.01),
        pt(16000, lat: 31.0101),
      ], toGcj02: false);

      expect(gaps.length, 1);
      expect(gaps.single.startMs, 1000);
      expect(gaps.single.endMs, 15000);
      expect(gaps.single.durationS, 14);
      // 断口两端就是那两个定位点本身。
      expect(gaps.single.before.lat, closeTo(31.0001, 1e-9));
      expect(gaps.single.after.lat, closeTo(31.01, 1e-9));
    });

    test('停车时的空档不算中断', () {
      final List<RouteGap> gaps = findRouteGaps(<TrackPoint>[
        pt(0),
        // 14 秒空档，但只挪动了几米：系统在停车时停止送点，不是丢信号。
        pt(14000, lat: 31.00002),
      ], toGcj02: false);

      expect(gaps, isEmpty);
    });

    test('没有坐标的传感器点被跳过，不在它前后各造一个假断口', () {
      final List<RouteGap> gaps = findRouteGaps(<TrackPoint>[
        pt(0),
        const TrackPoint(rideId: 1, tMs: 5000, hr: 140),
        pt(14000, lat: 31.01),
      ], toGcj02: false);

      expect(gaps.length, 1, reason: 'GPS 丢失期间的心率点不参与定位判定');
      expect(gaps.single.startMs, 0);
      expect(gaps.single.endMs, 14000);
    });

    test('断口端点跟随瓦片源做坐标转换', () {
      final List<RouteGap> gaps = findRouteGaps(<TrackPoint>[
        pt(0),
        pt(14000, lat: 31.01),
      ]);
      final ({double lat, double lon}) expected = wgs84ToGcj02(31.01, 121.0);
      expect(gaps.single.after.lat, closeTo(expected.lat, 1e-9));
      expect(gaps.single.after.lon, closeTo(expected.lon, 1e-9));
    });
  });

  // 实时轨迹缩略图（设计文档 9.4）喂进来的是抽稀过的点：相邻两点隔 15 秒是
  // 常态（慢速骑行、红绿灯、400 点后折半压缩），拿 kGpsGapMs 去卡会把一条连续
  // 轨迹切成一截截——真机上看到的「断断续续」。断点改由采集侧显式标记。
  group('抽稀轨迹的显式断点', () {
    test('点了 breakBefore 就不按时间间隔断开', () {
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 5),
        pt(15000, lat: 31.0001, speed: 5),
        pt(30000, lat: 31.0002, speed: 5),
      ], breakBefore: const <int>{});

      expect(segs.length, 1, reason: '15 秒间隔是抽稀的产物，不是丢信号');
      expect(segs.single.vertices.length, 3);
    });

    test('breakBefore 指定的下标处真的断开', () {
      final List<RouteSegment> segs = buildRouteSegments(
        <TrackPoint>[
          pt(0, speed: 5),
          pt(2000, lat: 31.0001, speed: 5),
          pt(4000, lat: 31.2002, speed: 5),
          pt(6000, lat: 31.2003, speed: 5),
        ],
        breakBefore: const <int>{2},
      );

      expect(segs.length, 2);
      expect(segs[0].vertices.length, 2);
      expect(segs[1].vertices.length, 2);
    });

    // 实时轨迹全部带坐标，但断点下标是按原列表算的，写错了会在跳过无坐标点后
    // 错位一格——把「下标口径」钉住。
    test('断点下标按原列表算，无坐标点不影响', () {
      final List<RouteSegment> segs = buildRouteSegments(
        <TrackPoint>[
          pt(0, speed: 5),
          const TrackPoint(rideId: 1, tMs: 1000, hr: 140), // 无坐标
          pt(2000, lat: 31.0001, speed: 5),
          pt(4000, lat: 31.2002, speed: 5),
          pt(6000, lat: 31.2003, speed: 5),
        ],
        // 原列表下标 3 是「31.2002」那个点：断在它前面。
        breakBefore: const <int>{3},
      );

      expect(segs.length, 2);
      expect(segs[0].vertices.length, 2, reason: '31.0 与 31.0001 连成第一段');
      expect(segs[1].vertices.length, 2, reason: '31.2002 与 31.2003 连成第二段');
    });

    test('显式断点模式下跳变仍然断开', () {
      // 1 秒跨 0.01 度 ≈ 1113 米，远超 30 m/s。
      final List<RouteSegment> segs = buildRouteSegments(<TrackPoint>[
        pt(0, speed: 5),
        pt(1000, lat: 31.0, speed: 5),
        pt(2000, lat: 31.01, speed: 5),
        pt(3000, lat: 31.0101, speed: 5),
      ], breakBefore: const <int>{});

      expect(segs.length, 2);
    });
  });
}
