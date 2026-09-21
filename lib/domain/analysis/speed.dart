import 'dart:math' as math;

import '../models/track_point.dart';
import 'constants.dart';

/// 滑动平均，窗口以当前点为中心并裁剪到序列边界。
/// 窗口内只统计非空值；窗口内全为空时输出 null。
List<double?> movingAverage(List<double?> values, int window) {
  assert(window > 0, '窗口必须为正数');
  final int half = window ~/ 2;
  final List<double?> out = List<double?>.filled(values.length, null);
  for (int i = 0; i < values.length; i++) {
    final int start = math.max(0, i - half);
    final int end = math.min(values.length - 1, i + half);
    double sum = 0;
    int count = 0;
    for (int j = start; j <= end; j++) {
      final double? v = values[j];
      if (v == null) continue;
      sum += v;
      count++;
    }
    if (count > 0) out[i] = sum / count;
  }
  return out;
}

/// 滑动平均后的峰值速度（m/s）。无数据时返回 null。
double? maxSmoothedSpeed(List<double?> speeds, int window) {
  double? best;
  for (final double? v in movingAverage(speeds, window)) {
    if (v == null) continue;
    if (best == null || v > best) best = v;
  }
  return best;
}

/// 移动时长与静止时长（秒）。
class MovingStats {
  const MovingStats({required this.movingSeconds, required this.stationarySeconds});

  final double movingSeconds;
  final double stationarySeconds;
}

/// 按速度阈值切分移动/静止时长。
///
/// 以相邻两点的时间差作为该区间的时长，速度取区间末点的瞬时速度。
/// 时间不前进、缺速度、或间隔超过 [kGpsGapMs] 的区间不计入任何一侧
/// —— 后者与设计文档 9.3 的 GPS 断点定义保持一致。
MovingStats splitMovingStationary(List<TrackPoint> points, double thresholdMps) {
  double moving = 0;
  double stationary = 0;
  for (int i = 1; i < points.length; i++) {
    final int dtMs = points[i].tMs - points[i - 1].tMs;
    if (dtMs <= 0 || dtMs > kGpsGapMs) continue;
    final double? v = points[i].speedMps;
    if (v == null) continue;
    final double dt = dtMs / 1000.0;
    if (v < thresholdMps) {
      stationary += dt;
    } else {
      moving += dt;
    }
  }
  return MovingStats(movingSeconds: moving, stationarySeconds: stationary);
}
