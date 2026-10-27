import 'package:cycling_app/domain/analysis/geo.dart';
import 'package:cycling_app/domain/analysis/summary.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/models/workout_summary.dart';
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

    final WorkoutSummary s = computeSummary(
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
    final WorkoutSummary s = computeSummary(
      points: <TrackPoint>[
        _p(0, 121.47, speed: 5.0),
        _p(1000, 122.47, lat: 32.23, speed: 5.0),
      ],
      durationS: 1,
      maxHeartRate: 190,
      weightKg: 70,
    );
    expect(s.distanceM, 0);
  });

  test('爬升经过滤波后累加，最高速经过平滑后取峰值', () {
    // 5 分钟轨迹，2 秒一个点：前 60 秒在 100 米平路，之后 4 分钟线性爬升 30 米。
    // 第 20 个点（平路中段）插一个 6 米的高程尖刺，中值滤波（窗口 15）应把它
    // 抹掉；只靠滞回阈值的话这个尖刺会白送 6 米爬升——1 Hz 采样下这类噪声
    // 每几分钟就有一个，正是真机上「平路爬升几百米」的来源。
    // 速度 30 的尖刺在滑动平均下被摊薄，峰值必然小于 30。
    final List<TrackPoint> points = <TrackPoint>[];
    for (int i = 0; i < 150; i++) {
      final double t = i * 2.0;
      double alt = t < 60 ? 100 : 100 + (t - 60) * (30 / 240);
      if (i == 20) alt = 106;
      points.add(
        _p(i * 2000, 121.4700 + i * 0.00013, alt: alt, speed: i == 30 ? 30 : 5),
      );
    }
    final WorkoutSummary s = computeSummary(
      points: points,
      durationS: 300,
      maxHeartRate: 190,
      weightKg: 70,
    );
    // 沉降期从 60 秒起算，之后实际爬升 30 米；中值窗口边缘与滞回留白使
    // 读数略小于 30。
    expect(s.elevationGainM, closeTo(29, 2));
    expect(s.maxSpeedMps! < 30, isTrue);
  });

  test('停车时的位置抖动不计入里程', () {
    // 停着不动，定位点在一两米范围内来回抖：逐段求和会白送几十米。
    final List<TrackPoint> points = <TrackPoint>[
      for (int i = 0; i < 10; i++)
        _p(i * 1000, 121.4700 + (i.isEven ? 0.00002 : -0.00002), speed: 0),
    ];
    final WorkoutSummary s = computeSummary(
      points: points,
      durationS: 9,
      maxHeartRate: 190,
      weightKg: 70,
    );
    expect(s.distanceM, 0);
  });

  test('起步那一段仍算里程，不被静止判定吞掉', () {
    // 前两点停着（抖动不计），第三点动起来：这一小段位移是真的，不能因为
    // 起点速度为 0 就一起丢掉。
    final double segment = haversineMeters(31.23, 121.4701, 31.23, 121.4702);
    final List<TrackPoint> points = <TrackPoint>[
      _p(0, 121.4700, speed: 0),
      _p(1000, 121.4701, speed: 0),
      _p(2000, 121.4702, speed: 5),
    ];
    final WorkoutSummary s = computeSummary(
      points: points,
      durationS: 2,
      maxHeartRate: 190,
      weightKg: 70,
    );
    expect(s.distanceM, closeTo(segment, 1e-6));
  });

  test('首个定位点的高程异常不会变成爬升', () {
    // 模拟定位验证时的真实场景：首点高程为 0，次点跳到 500，水平只差几米。
    // 修复前这条轨迹会算出 500 米爬升。
    final List<TrackPoint> points = <TrackPoint>[
      _p(0, 121.4700, alt: 0, speed: 5),
      _p(1000, 121.4701, alt: 500, speed: 5),
      _p(2000, 121.4702, alt: 500, speed: 5),
    ];
    final WorkoutSummary s = computeSummary(
      points: points,
      durationS: 2,
      maxHeartRate: 190,
      weightKg: 70,
    );
    expect(s.elevationGainM, 0);
  });

  test('有心率时给出心率均值、峰值与卡路里', () {
    final List<TrackPoint> points = <TrackPoint>[
      _p(0, 121.4700, speed: 5, hr: 120),
      _p(1000, 121.4701, speed: 5, hr: 120),
      _p(2000, 121.4702, speed: 5, hr: 120),
    ];
    final WorkoutSummary s = computeSummary(
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
    final WorkoutSummary s = computeSummary(
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
}) => TrackPoint(
  rideId: 1,
  tMs: tMs,
  lat: lat,
  lon: lon,
  altitudeM: alt,
  speedMps: speed,
  hr: hr,
);
