import 'dart:math' as math;

import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/analysis/elevation.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

/// 有坐标的轨迹点。[lon] 每差 0.0001 度约 9.5 米（北纬 31.23）。
TrackPoint _pt(int tMs, double lon, {double? alt}) =>
    TrackPoint(rideId: 1, tMs: tMs, lat: 31.23, lon: lon, altitudeM: alt);

/// 没有坐标的点：GPS 丢失期间写下的纯传感器点。
TrackPoint _bare(int tMs, {double? alt}) =>
    TrackPoint(rideId: 1, tMs: tMs, altitudeM: alt);

/// 2 秒一个点、约 12 米一步（6 m/s）的轨迹。真实记录就是这个量级的采样。
List<TrackPoint> _track(List<double> alts) => <TrackPoint>[
      for (int i = 0; i < alts.length; i++)
        _pt(i * 2000, 121.0 + i * 0.00013, alt: alts[i]),
    ];

void main() {
  group('medianFilterElevation', () {
    test('窗口为 15 时输出等长序列', () {
      final List<double?> raw = <double?>[
        for (int i = 0; i < 40; i++) 100 + (i % 3) * 0.5,
      ];
      expect(
        medianFilterElevation(raw, kElevationFilterWindow).length,
        raw.length,
      );
    });

    test('空值邻域内仍有非空值时会被填充', () {
      final List<double?> out =
          medianFilterElevation(<double?>[100, null, 102, null, 104], 3);
      expect(out[1], closeTo(101, 1e-9));
      expect(out[3], closeTo(103, 1e-9));
    });
  });

  group('trailingMedian', () {
    test('取序列末尾窗口的中值', () {
      // 末尾 5 个是 104,100,104,100,104，中值是 104。
      expect(trailingMedian(<double>[100, 104, 100, 104, 100, 104], 5), 104);
    });

    test('序列为空时返回 null', () {
      expect(trailingMedian(<double>[], 5), isNull);
    });
  });

  group('elevationGainMeters', () {
    test('平坦高程噪声不产生爬升', () {
      // 逐点抖动 ±2 米，小于滞回阈值，基准不动。
      final List<double?> raw = <double?>[
        for (int i = 0; i < 40; i++) 100 + (i.isEven ? 2 : 0),
      ];
      expect(
        elevationGainMeters(
          medianFilterElevation(raw, kElevationFilterWindow),
          kElevationGainThresholdM,
        ),
        0,
      );
    });

    test('线性爬升按滞回档位累加', () {
      final List<double?> raw = <double?>[100, 101, 102, 103, 104, 105, 106];
      final List<double?> filtered =
          medianFilterElevation(raw, kElevationFilterWindow);
      // 滞回只在跨过阈值时结算：从 100 涨到 106 跨过 3 米一档，已经结算 3 米；
      // 剩下不到 3 米的尾巴留作下一次的基准，所以这里是 3 而不是 6。
      expect(
        elevationGainMeters(filtered, kElevationGainThresholdM),
        closeTo(3, 1e-9),
      );
    });

    test('孤立尖刺被中值滤波抹掉，不放大爬升', () {
      // 平路 100 米，每 5 个点插一个 6 米高的尖刺。不滤波时每个尖刺先加 6 米
      // 再被下一个正常值打回，6 个尖刺累计 36 米；窗口 15 的中值把它们全抹掉。
      final List<double?> raw = <double?>[
        for (int i = 0; i < 30; i++) i % 5 == 4 ? 106 : 100,
      ];
      final List<double?> filtered =
          medianFilterElevation(raw, kElevationFilterWindow);
      expect(
        elevationGainMeters(raw, kElevationGainThresholdM),
        closeTo(36, 1e-9),
      );
      expect(elevationGainMeters(filtered, kElevationGainThresholdM), 0);
    });

    test('下降段不计入爬升', () {
      final List<double?> raw = <double?>[200, 190, 180, 170, 160, 150];
      final List<double?> filtered =
          medianFilterElevation(raw, kElevationFilterWindow);
      expect(elevationGainMeters(filtered, kElevationGainThresholdM), 0);
    });

    test('空值被跳过', () {
      // 两个空位由邻域里的 106 / 112 补齐，序列变成 100 → 106 → 109 的阶梯，
      // 两档各跨过 3 米阈值，累计 6 米（最后一档 3 米已结算，尾巴留作基准）。
      final List<double?> out = medianFilterElevation(
        <double?>[100, null, 106, null, 112],
        5,
      );
      expect(
        elevationGainMeters(out, kElevationGainThresholdM),
        closeTo(9, 1e-9),
      );
    });

    test('startIndex 之前的样点只定基准，不累计', () {
      // 前两个点属于沉降期：从 100 起算，而不是从 0 算 100 米。
      final List<double?> raw = <double?>[0, 50, 100, 103, 106];
      expect(
        elevationGainMeters(raw, kElevationGainThresholdM, startIndex: 2),
        closeTo(6, 1e-9),
      );
    });
  });

  group('plausibleElevationSeries', () {
    test('输出与输入等长，原本为空的高程仍为空', () {
      final List<TrackPoint> points = <TrackPoint>[
        _pt(0, 121.4700, alt: 100),
        _bare(1000),
        _pt(2000, 121.4701, alt: 101),
      ];

      final List<double?> out = plausibleElevationSeries(points);

      expect(out.length, 3);
      expect(out[1], isNull);
    });

    test('首个定位点给出 0、次点才是真实海拔时，异常段被剔除', () {
      // 模拟定位验证时出现的场景：mock 位置的首点高程为 0，次点跳到 500，
      // 两点水平只差 9.5 米。相邻两点分不出错的是哪一个，因此两个都剔除，
      // 交给中值滤波按邻域里的稳定值填充。
      final List<TrackPoint> points = <TrackPoint>[
        _pt(0, 121.4700, alt: 0),
        _pt(1000, 121.4701, alt: 500),
        _pt(2000, 121.4702, alt: 500),
      ];

      final List<double?> out = plausibleElevationSeries(points);

      expect(out, <double?>[null, null, 500]);
      // 邻域里的 500 把前两个空位填满，整段变成平的，爬升为 0。
      expect(
        elevationGainMeters(
          medianFilterElevation(out, kElevationFilterWindow),
          kElevationGainThresholdM,
        ),
        0,
      );
    });

    test('整段算下来确实是 500 米假爬升（对照组）', () {
      // 上一条只断言了「剔除了」，这里补上「不剔除会怎样」：没有这组对照，
      // 把 plausibleElevationSeries 改成恒等返回也照样能让上面那条通过。
      // 用 20 个点而不是 2 个：更接近真实轨迹的采样量，也让中值窗口正常大小
      // 生效（2 个点时窗口被收窄到 1，两边的差异就不在中值滤波上了）。
      final List<TrackPoint> points = <TrackPoint>[
        _pt(0, 121.4700, alt: 0),
        for (int i = 1; i < 20; i++)
          _pt(i * 1000, 121.4700 + i * 0.0001, alt: 500),
      ];
      final List<double?> naive = medianFilterElevation(
        <double?>[for (final TrackPoint p in points) p.altitudeM],
        kElevationFilterWindow,
      );
      final List<double?> guarded = medianFilterElevation(
        plausibleElevationSeries(points),
        kElevationFilterWindow,
      );

      expect(
        elevationGainMeters(naive, kElevationGainThresholdM),
        closeTo(500, 1e-9),
      );
      expect(elevationGainMeters(guarded, kElevationGainThresholdM), 0);
    });

    test('正常渐进爬升一个点都不剔', () {
      final List<TrackPoint> points = <TrackPoint>[
        _pt(0, 121.4700, alt: 100),
        _pt(1000, 121.4701, alt: 101),
        _pt(2000, 121.4702, alt: 102),
        _pt(3000, 121.4703, alt: 103),
      ];

      expect(
        plausibleElevationSeries(points),
        <double?>[100, 101, 102, 103],
      );
    });

    test('GPS 断点后的真实海拔突变被保留', () {
      // 隧道里断了十分钟，出来时已经骑到 1.8 公里外的另一处高地：350 米的
      // 海拔变化对应坡度不到 0.2，物理上成立，不能当异常吃掉。
      final List<TrackPoint> points = <TrackPoint>[
        _pt(0, 121.4700, alt: 100),
        _pt(1000, 121.4701, alt: 100),
        _pt(602000, 121.4900, alt: 450),
        _pt(603000, 121.4901, alt: 450),
      ];

      final List<double?> out = plausibleElevationSeries(points);

      expect(out[2], 450);
      expect(out[3], 450);
      // 断点两侧的落差照常计入爬升。
      expect(
        elevationGainMeters(
          medianFilterElevation(out, kElevationFilterWindow),
          kElevationGainThresholdM,
        ),
        greaterThan(0),
      );
    });

    test('变化不足 kSuspectElevationJumpM 时不判异常，静止漂移照常保留', () {
      // 水平完全没动却涨了 8 米：坡度算下来是无穷大，但幅度没过下限，
      // 属于 GPS 高程的正常漂移，不该剔除。
      final List<TrackPoint> points = <TrackPoint>[
        _pt(0, 121.4700, alt: 100),
        _pt(2000, 121.4700, alt: 108),
      ];

      expect(plausibleElevationSeries(points), <double?>[100, 108]);
    });

    test('没有坐标的点上出现大幅高程变化时同样剔除', () {
      final List<TrackPoint> points = <TrackPoint>[
        _pt(0, 121.4700, alt: 100),
        _bare(1000, alt: 500),
      ];

      expect(plausibleElevationSeries(points)[1], isNull);
    });

    test('连续跳变时整段都被剔除，不会只剔掉一半', () {
      // 相邻两点无法判断错的是哪一个，因此两个都剔；第三个点又与前一个构成
      // 跳变，同样被剔。整段为空后中值滤波无从填充，爬升为 0——好过把某个
      // 假海拔当成新基准，让后面的异常再也判不出来。
      final List<TrackPoint> points = <TrackPoint>[
        _pt(0, 121.4700, alt: 100),
        _pt(1000, 121.4701, alt: 500),
        _pt(2000, 121.4702, alt: 510),
      ];

      final List<double?> out = plausibleElevationSeries(points);

      expect(out, <double?>[null, null, null]);
      expect(
        elevationGainMeters(
          medianFilterElevation(out, kElevationFilterWindow),
          kElevationGainThresholdM,
        ),
        0,
      );
    });
  });

  group('elevationGainOf 沉降期', () {
    test('平路 GPS 高程噪声不会累积成爬升', () {
      // 真实海拔恒定 100 米，噪声 σ=3 米、2 秒一个点、骑 20 分钟。手机 GPS
      // 高程的抖动就是这个量级：不滤波只靠滞回阈值时，这类序列能读出几十上百米
      // 「爬升」，正是真机上「刚起步爬升就偏高」的来源。
      int state = 7;
      double gauss() {
        double u = 0;
        for (int i = 0; i < 6; i++) {
          state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
          u += state / 0x7FFFFFFF;
        }
        return u - 3;
      }

      final List<double> alts = <double>[
        for (int i = 0; i < 600; i++) 100 + gauss() * 3,
      ];

      expect(elevationGainOf(_track(alts)), lessThan(8));
    });

    test('冷启动高程收敛不被算成爬升', () {
      // 真实海拔 100 米，上报值从 0 按 20 秒时间常数收敛（前 60 秒几乎走完），
      // 之后 120~300 秒真实爬升 20 米。若不设沉降期，收敛段会被算成约 100 米。
      double altAt(double t) => t >= 120
          ? 100 + 20 * math.min(1.0, (t - 120) / 180)
          : 100 - 100 * math.exp(-t / 20);
      final List<double> alts = <double>[
        for (int i = 0; i < 180; i++) altAt(i * 2.0),
      ];

      final double gain = elevationGainOf(_track(alts));

      // 不设沉降期时这里会读出约 100 米（收敛段从头算起）。沉降期从第 60 秒
      // 起算，此时高程已收敛到 95 米左右，剩下的 5 米尾巴仍会被算进来——这是
      // 60 秒沉降期（约 3 个时间常数）的固有残差，量级上可以接受。
      expect(gain, lessThan(30));
      expect(gain, greaterThan(15));
    });

    test('沉降期之后的爬升照常累加', () {
      // 前 60 秒高程从 0 收敛到 100，随后 4 分钟再爬 30 米。
      double altAt(double t) => t >= 60
          ? 100 + 30 * math.min(1.0, (t - 60) / 240)
          : 100 - 100 * math.exp(-t / 20);
      final List<double> alts = <double>[
        for (int i = 0; i < 150; i++) altAt(i * 2.0),
      ];

      final double gain = elevationGainOf(_track(alts));

      expect(gain, closeTo(27, 2));
    });
  });
}
