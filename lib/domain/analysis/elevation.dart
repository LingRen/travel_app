import 'dart:math' as math;

/// 对可空高程序列做中值滤波，窗口以当前点为中心。
///
/// 越界处复制最邻近的边界值（等价于把序列两端向外延展），而不是把窗口
/// 截短：截短会把线性升降在两端压平（例如 100…106 的匀速爬坡滤波后只剩
/// 4 米落差），导致爬升被系统性少算。
/// 窗口内只统计非空值；窗口内全为空时输出 null。
List<double?> medianFilterElevation(List<double?> values, int window) {
  assert(window.isOdd && window > 0, '窗口必须为正奇数');
  final int half = window ~/ 2;
  final List<double?> out = List<double?>.filled(values.length, null);
  for (int i = 0; i < values.length; i++) {
    final List<double> buf = <double>[];
    for (int j = i - half; j <= i + half; j++) {
      final int k = math.min(values.length - 1, math.max(0, j));
      final double? v = values[k];
      if (v != null) buf.add(v);
    }
    if (buf.isEmpty) continue;
    buf.sort();
    out[i] = buf.length.isOdd
        ? buf[buf.length ~/ 2]
        : (buf[buf.length ~/ 2 - 1] + buf[buf.length ~/ 2]) / 2;
  }
  return out;
}

/// 累加单次上升超过 [thresholdM] 的区段，得到总爬升（米）。
///
/// 用「滞回」方式实现：小幅波动不推进基准点，因此缓慢但持续的爬坡会被
/// 正确累加，而上下抖动不会；下降超过阈值时才把基准点下移。
double elevationGainMeters(List<double?> filtered, double thresholdM) {
  double gain = 0;
  double? baseline;
  for (final double? v in filtered) {
    if (v == null) continue;
    if (baseline == null) {
      baseline = v;
      continue;
    }
    final double delta = v - baseline;
    if (delta >= thresholdM) {
      gain += delta;
      baseline = v;
    } else if (delta <= -thresholdM) {
      baseline = v;
    }
  }
  return gain;
}
