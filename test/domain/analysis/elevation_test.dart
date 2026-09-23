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

void main() {
  group('medianFilterElevation', () {
    test('窗口为 5 时输出等长序列', () {
      final List<double?> raw = <double?>[100, 100.5, 99.8, 100.2, 99.9, 100.4, 100.0];
      expect(medianFilterElevation(raw, kElevationFilterWindow).length, raw.length);
    });

    test('空值邻域内仍有非空值时会被填充', () {
      final List<double?> out = medianFilterElevation(<double?>[100, null, 102, null, 104], 3);
      expect(out[1], closeTo(101, 1e-9));
      expect(out[3], closeTo(103, 1e-9));
    });
  });

  group('elevationGainMeters', () {
    test('平坦高程噪声不产生爬升', () {
      final List<double?> raw = <double?>[100, 100.5, 99.8, 100.2, 99.9, 100.4, 100.0];
      final List<double?> filtered = medianFilterElevation(raw, kElevationFilterWindow);
      expect(elevationGainMeters(filtered, kElevationGainThresholdM), 0);
    });

    test('线性爬升被完整累加', () {
      final List<double?> raw = <double?>[100, 101, 102, 103, 104, 105, 106];
      final List<double?> filtered = medianFilterElevation(raw, kElevationFilterWindow);
      expect(elevationGainMeters(filtered, kElevationGainThresholdM), closeTo(6, 1e-9));
    });

    test('锯齿噪声不放大爬升', () {
      // 原始序列逐点波动约 4 米（真实爬升约 4.5 米）。
      //
      // 窗口为 5 的中值滤波无法把这种周期为 2 的锯齿彻底消掉：任意 5 点窗口
      // 里两种相位总是 3:2，中值必然落在其中一种相位上，于是滤波后仍在锯齿。
      // 所以这里断言的是「滤波显著抑制放大」而非「完全消除」：
      // 未滤波直接累加会被锯齿放大到 23 米，滤波后收敛到 11 米。
      final List<double?> raw = <double?>[100, 103, 99, 104, 100, 105, 101, 106, 102, 107];
      final List<double?> filtered = medianFilterElevation(raw, kElevationFilterWindow);
      final double gain = elevationGainMeters(filtered, kElevationGainThresholdM);
      final double rawGain = elevationGainMeters(raw, kElevationGainThresholdM);
      expect(rawGain, closeTo(23, 1e-9));
      expect(gain, greaterThan(3));
      expect(gain, lessThan(rawGain));
    });

    test('下降段不计入爬升', () {
      final List<double?> raw = <double?>[200, 190, 180, 170, 160, 150];
      final List<double?> filtered = medianFilterElevation(raw, kElevationFilterWindow);
      expect(elevationGainMeters(filtered, kElevationGainThresholdM), 0);
    });

    test('空值被跳过', () {
      final List<double?> out = medianFilterElevation(<double?>[100, null, 102, null, 104], 3);
      expect(elevationGainMeters(out, kElevationGainThresholdM), closeTo(4, 1e-9));
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
      final List<TrackPoint> points = <TrackPoint>[
        _pt(0, 121.4700, alt: 0),
        _pt(1000, 121.4701, alt: 500),
      ];
      final List<double?> naive = medianFilterElevation(
        <double?>[for (final TrackPoint p in points) p.altitudeM],
        kElevationFilterWindow,
      );
      final List<double?> guarded = medianFilterElevation(
        plausibleElevationSeries(points),
        kElevationFilterWindow,
      );

      expect(elevationGainMeters(naive, kElevationGainThresholdM), 500);
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
}
