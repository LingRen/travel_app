import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/analysis/curve.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一串等间隔的轨迹点。`hr`/`cadence` 与序号绑定，便于断言取到的是哪个点。
List<TrackPoint> buildPoints(int count, {int stepMs = 1000, int? gapAfter}) {
  return <TrackPoint>[
    for (int i = 0; i < count; i++)
      TrackPoint(
        rideId: 1,
        tMs: (gapAfter != null && i > gapAfter)
            ? i * stepMs + kGpsGapMs + 1
            : i * stepMs,
        lat: 31.0 + i * 0.0001,
        lon: 121.0,
        speedMps: i.toDouble(),
        hr: 100 + i,
        cadence: 60 + i,
      ),
  ];
}

void main() {
  group('buildCurve 基本行为', () {
    test('速度曲线取平滑后的速度，x 是相对首点的秒数', () {
      final List<TrackPoint> points = buildPoints(5);
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.speed);

      expect(curve.length, 5);
      expect(curve.first.xSeconds, 0);
      expect(curve.last.xSeconds, 4);
      // 速度 0,1,2,3,4 经过 5 点滑动平均，中点附近应落在区间内。
      expect(curve[2].y, inInclusiveRange(1.0, 3.0));
    });

    test('心率曲线取原始心率值，不做平滑', () {
      final List<CurveSample> curve = buildCurve(
        buildPoints(3),
        metric: CurveMetric.heartRate,
      );
      expect(curve.map((CurveSample s) => s.y).toList(), <double>[100, 101, 102]);
    });

    test('踏频曲线取原始踏频值', () {
      final List<CurveSample> curve = buildCurve(
        buildPoints(3),
        metric: CurveMetric.cadence,
      );
      expect(curve.map((CurveSample s) => s.y).toList(), <double>[60, 61, 62]);
    });

    test('速度曲线对尖峰做滑动平均，毛刺被削弱', () {
      // 静止中夹一个 10 m/s 的 GPS 毛刺：5 点滑动平均后中点应为 2.0。
      // 若实现漏掉 movingAverage，中点仍是原始的 10.0。
      final List<TrackPoint> points = <TrackPoint>[
        for (int i = 0; i < 7; i++)
          TrackPoint(rideId: 1, tMs: i * 1000, speedMps: i == 3 ? 10.0 : 0.0),
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.speed);
      expect(curve.length, 7);
      expect(curve[3].y, closeTo(2.0, 1e-6));
    });

    test('缺该指标的轨迹点被跳过', () {
      final List<TrackPoint> points = <TrackPoint>[
        const TrackPoint(rideId: 1, tMs: 0, hr: 100),
        const TrackPoint(rideId: 1, tMs: 1000), // 没有心率
        const TrackPoint(rideId: 1, tMs: 2000, hr: 120),
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.heartRate);
      expect(curve.length, 2);
      expect(curve.map((CurveSample s) => s.y).toList(), <double>[100, 120]);
    });

    test('空输入返回空曲线', () {
      expect(buildCurve(<TrackPoint>[], metric: CurveMetric.speed), isEmpty);
    });
  });

  group('buildCurve 断点分段', () {
    test('时间间隔超过 kGpsGapMs 时 segment 递增', () {
      final List<TrackPoint> points = buildPoints(6, gapAfter: 2);
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.heartRate);

      // 前 3 个点（下标 0,1,2）同段；下标 3 起时间跳变，进入新段。
      expect(curve[0].segment, 0);
      expect(curve[2].segment, 0);
      expect(curve[3].segment, 1);
      expect(curve[5].segment, 1);
    });

    test('时间不前进时也递增 segment', () {
      final List<TrackPoint> points = <TrackPoint>[
        const TrackPoint(rideId: 1, tMs: 1000, hr: 100),
        const TrackPoint(rideId: 1, tMs: 500, hr: 110), // 时间倒流
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.heartRate);
      expect(curve[0].segment, 0);
      expect(curve[1].segment, 1);
    });

    test('时间相同（dt 为 0）时也递增 segment', () {
      final List<TrackPoint> points = <TrackPoint>[
        const TrackPoint(rideId: 1, tMs: 1000, hr: 100),
        const TrackPoint(rideId: 1, tMs: 1000, hr: 110), // 时间没前进
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.heartRate);
      expect(curve[0].segment, 0);
      expect(curve[1].segment, 1);
    });

    test('恰好等于 kGpsGapMs 不算断点', () {
      final List<TrackPoint> points = <TrackPoint>[
        const TrackPoint(rideId: 1, tMs: 0, hr: 100),
        const TrackPoint(rideId: 1, tMs: kGpsGapMs, hr: 110),
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.heartRate);
      expect(curve[1].segment, 0);
    });
  });

  group('buildCurve 降采样', () {
    test('点数超过 maxSamples 时抽稀到不超过上限', () {
      final List<TrackPoint> points = buildPoints(1000);
      final List<CurveSample> curve = buildCurve(
        points,
        metric: CurveMetric.heartRate,
        maxSamples: 100,
      );
      expect(curve.length, lessThanOrEqualTo(100));
      expect(curve.length, greaterThan(50));
    });

    test('降采样保留首点与末点', () {
      final List<TrackPoint> points = buildPoints(1000);
      final List<CurveSample> curve = buildCurve(
        points,
        metric: CurveMetric.heartRate,
        maxSamples: 100,
      );
      expect(curve.first.y, 100); // 首点 hr = 100
      expect(curve.last.y, 100 + 999); // 末点 hr = 1099
    });

    test('点数不超上限时原样返回，不抽稀', () {
      final List<CurveSample> curve = buildCurve(
        buildPoints(10),
        metric: CurveMetric.heartRate,
        maxSamples: 100,
      );
      expect(curve.length, 10);
    });

    test('降采样后 x 仍单调不减', () {
      final List<CurveSample> curve = buildCurve(
        buildPoints(1000),
        metric: CurveMetric.heartRate,
        maxSamples: 50,
      );
      for (int i = 1; i < curve.length; i++) {
        expect(curve[i].xSeconds, greaterThanOrEqualTo(curve[i - 1].xSeconds));
      }
    });
  });
}
