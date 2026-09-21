import '../models/track_point.dart';
import 'constants.dart';
import 'speed.dart';

/// 曲线要画哪个指标。
enum CurveMetric { speed, heartRate, cadence }

/// 曲线上的一个采样点。
///
/// [segment] 是断点分段号：GPS 断点（时间间隔超过 [kGpsGapMs]）或时间不前进时
/// 递增，图表按它拆成多条折线，避免把隧道两侧连成假直线。见设计文档 9.3。
class CurveSample {
  const CurveSample({
    required this.xSeconds,
    required this.y,
    required this.segment,
  });

  /// 相对首个有效点的秒数。
  final double xSeconds;

  final double y;
  final int segment;
}

/// 把轨迹点整理成图表可用的曲线序列。
///
/// - 速度曲线先做 [kSpeedFilterWindow] 点滑动平均：GPS 瞬时速度毛刺严重，
///   直接画出来是一团噪声（设计文档 8.1）。
/// - 心率与踏频不做平滑，原始值本身就是传感器的输出。
/// - 点数超过 [maxSamples] 时等步长抽稀，**首点与末点一定保留**。
List<CurveSample> buildCurve(
  List<TrackPoint> points, {
  required CurveMetric metric,
  int maxSamples = 240,
}) {
  final List<double?> raw = _rawValues(points, metric);
  final List<double?> values =
      metric == CurveMetric.speed ? movingAverage(raw, kSpeedFilterWindow) : raw;

  final List<CurveSample> all = <CurveSample>[];
  int segment = 0;
  int? prevTMs;
  double? originTMs;

  for (int i = 0; i < points.length; i++) {
    final double? y = values[i];
    if (y == null) continue;

    final int tMs = points[i].tMs;
    if (prevTMs != null) {
      final int dt = tMs - prevTMs;
      if (dt <= 0 || dt > kGpsGapMs) segment++;
    }
    prevTMs = tMs;
    originTMs ??= tMs.toDouble();

    all.add(CurveSample(
      xSeconds: (tMs - originTMs) / 1000.0,
      y: y,
      segment: segment,
    ));
  }

  return _downsample(all, maxSamples);
}

List<double?> _rawValues(List<TrackPoint> points, CurveMetric metric) {
  switch (metric) {
    case CurveMetric.speed:
      return <double?>[for (final TrackPoint p in points) p.speedMps];
    case CurveMetric.heartRate:
      return <double?>[
        for (final TrackPoint p in points) p.hr?.toDouble(),
      ];
    case CurveMetric.cadence:
      return <double?>[
        for (final TrackPoint p in points) p.cadence?.toDouble(),
      ];
  }
}

/// 等步长抽稀。首末点必留；被抽掉的位置不改变 segment 的相对顺序。
List<CurveSample> _downsample(List<CurveSample> samples, int maxSamples) {
  if (maxSamples < 2 || samples.length <= maxSamples) return samples;

  final int last = samples.length - 1;
  final List<CurveSample> out = <CurveSample>[];
  for (int i = 0; i < maxSamples; i++) {
    final int index = (i * last / (maxSamples - 1)).round();
    final CurveSample s = samples[index];
    // 抽稀后相邻两点可能落在不同 segment，这里保持原样即可：
    // 图表按 segment 分组，跨段的两点不会被连起来。
    if (out.isNotEmpty && identical(out.last, s)) continue;
    out.add(s);
  }
  return out;
}
