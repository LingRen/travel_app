import 'package:cycling_app/domain/analysis/geo.dart';
import 'package:cycling_app/domain/analysis/summary.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('距离按时长与坐标累加，均速按总时长、移动均速按移动时长', () {
    // 速度序列 [5, 5, 5, 0] 对应「骑手在前 3 秒移动、最后 1 秒停下」。
    // splitMovingStationary 按「区间末点的瞬时速度」归属区间，4 个点只有
    // 3 个区间：(p0,p1) 取 p1=5 → 移动；(p1,p2) 取 p2=5 → 移动；
    // (p2,p3) 取 p3=0 → 静止。故 movingS == 2。
    final List<TrackPoint> points = <TrackPoint>[
      _p(0, 121.4700, speed: 5.0, alt: 10),
      _p(1000, 121.4701, speed: 5.0, alt: 10),
      _p(2000, 121.4702, speed: 5.0, alt: 10),
      _p(3000, 121.4703, speed: 0.0, alt: 10),
    ];
    final double segment = haversineMeters(31.23, 121.4700, 31.23, 121.4701);

    final RideSummary s = computeSummary(
      points: points,
      durationS: 4,
      maxHeartRate: 190,
      weightKg: 70,
    );

    expect(s.distanceM, closeTo(segment * 3, 1e-6));
    expect(s.durationS, 4);
    expect(s.movingS, 2);
    expect(s.avgSpeedMps, closeTo(segment * 3 / 4, 1e-6));
    expect(s.movingAvgSpeedMps, closeTo(segment * 3 / 2, 1e-6));
    expect(s.elevationGainM, 0);
    expect(s.pointCount, 4);
    expect(s.maxHr, isNull);
    expect(s.calories, isNull);
  });

  test('GPS 跳变不计入距离', () {
    final RideSummary s = computeSummary(
      points: <TrackPoint>[_p(0, 121.47, speed: 5.0), _p(1000, 122.47, lat: 32.23, speed: 5.0)],
      durationS: 1,
      maxHeartRate: 190,
      weightKg: 70,
    );
    expect(s.distanceM, 0);
  });

  test('爬升经过滤波后累加，最高速经过平滑后取峰值', () {
    // 高程 100→101→110→103→104→105：第 3 点是一个高程尖刺。
    // 中值滤波（窗口 5）滤掉尖刺后为 100,101,103,104,105,105，累加得 5 米；
    // 若不滤波直接用原始高程，则爬升为 12 米。尖刺使「滤波生效」这一断言
    // 真正具备区分能力（严格单调的序列滤波前后完全相同）。
    // 速度 30 的尖刺在窗口 5 的滑动平均下被摊薄，峰值必然小于 30。
    final List<TrackPoint> points = <TrackPoint>[
      _p(0, 121.4700, alt: 100, speed: 5),
      _p(1000, 121.4701, alt: 101, speed: 5),
      _p(2000, 121.4702, alt: 110, speed: 30),
      _p(3000, 121.4703, alt: 103, speed: 5),
      _p(4000, 121.4704, alt: 104, speed: 5),
      _p(5000, 121.4705, alt: 105, speed: 5),
    ];
    final RideSummary s = computeSummary(
      points: points,
      durationS: 5,
      maxHeartRate: 190,
      weightKg: 70,
    );
    expect(s.elevationGainM, closeTo(5, 1e-9));
    expect(s.maxSpeedMps! < 30, isTrue);
  });

  test('有心率时给出心率均值、峰值与卡路里', () {
    final List<TrackPoint> points = <TrackPoint>[
      _p(0, 121.4700, speed: 5, hr: 120),
      _p(1000, 121.4701, speed: 5, hr: 120),
      _p(2000, 121.4702, speed: 5, hr: 120),
    ];
    final RideSummary s = computeSummary(
      points: points,
      durationS: 2,
      maxHeartRate: 200,
      weightKg: 70,
    );
    expect(s.avgHr, closeTo(120, 1e-9));
    expect(s.maxHr, 120);
    // 2 秒全在 Z2（MET 6）：6 × 70 × 2 / 3600
    expect(s.calories, closeTo(6 * 70 * 2 / 3600, 1e-9));
  });

  test('空轨迹返回全零汇总', () {
    final RideSummary s = computeSummary(
      points: const <TrackPoint>[],
      durationS: 0,
      maxHeartRate: 190,
      weightKg: 70,
    );
    expect(s.distanceM, 0);
    expect(s.pointCount, 0);
    expect(s.avgSpeedMps, 0);
    expect(s.movingAvgSpeedMps, 0);
  });
}

TrackPoint _p(
  int tMs,
  double lon, {
  double lat = 31.23,
  double? alt,
  double? speed,
  int? hr,
}) =>
    TrackPoint(
      rideId: 1,
      tMs: tMs,
      lat: lat,
      lon: lon,
      altitudeM: alt,
      speedMps: speed,
      hr: hr,
    );
