import 'dart:math' as math;

import '../models/track_point.dart';
import 'constants.dart';
import 'geo.dart';

/// 剔除不可信的高程点，返回与 [points] 等长的高程序列；被剔除的位置为 null，
/// 交给 [medianFilterElevation] 按邻域填充。
///
/// 设计文档 8.1 只处理了「噪声放大」，没处理「整个点不可信」：水平的跳变有
/// [kMaxPlausibleSpeedMps] 兜底，高程原本一个合理性检查都没有，于是「首个
/// 定位点给出 0、次点才是真实海拔」会被整段算成爬升——模拟定位验证时就出现
/// 过 500 米的假爬升。
///
/// 判定条件是「变化够大 且 坡度不成立」，而不是给单步高程变化设一个上限：
/// GPS 断点（隧道、桥下）之后的海拔突变是真实存在的，那里水平位移大，按坡度
/// 算下来完全正常，不该被当成异常吃掉。
List<double?> plausibleElevationSeries(List<TrackPoint> points) {
  final List<double?> out = <double?>[
    for (final TrackPoint p in points) p.altitudeM,
  ];

  for (int i = 1; i < points.length; i++) {
    final double? a = points[i - 1].altitudeM;
    final double? b = points[i].altitudeM;
    if (a == null || b == null) continue;
    if (!_isImplausibleJump(points[i - 1], points[i], b - a)) continue;
    // 只看相邻两点分不出错的是哪一个：既可能是后一个点跳飞了，也可能是前一个
    // 点本来就不对（首个定位点常给出 0）。两个都剔掉，交给中值滤波按邻域里的
    // 稳定值填充，好过赌其中一个——赌错的代价是把异常值当成新基准，后面再也
    // 判不出异常。
    out[i - 1] = null;
    out[i] = null;
  }
  return out;
}

/// 从 [from] 到 [to] 的高程变化 [deltaAlt] 是否物理上不成立。
bool _isImplausibleJump(TrackPoint from, TrackPoint to, double deltaAlt) {
  final double change = deltaAlt.abs();
  if (change < kSuspectElevationJumpM) return false;

  // 没有坐标的点（GPS 丢失期间写下的纯传感器点）无从比较水平位移，按「没动」
  // 处理：这种点上出现十米以上的高程变化，同样不可信。
  final double horizontal = from.hasPosition && to.hasPosition
      ? haversineMeters(from.lat!, from.lon!, to.lat!, to.lon!)
      : 0;
  return horizontal <= 0 || change / horizontal > kMaxPlausibleGrade;
}

/// 对可空高程序列做中值滤波，窗口以当前点为中心。
///
/// 序列开头的窗口向右延展到 [i] + half，缺少的左侧用首值补齐（等价于向外
/// 复制最近的边界值）；序列末尾则**截短**窗口，不去复制尾值。两侧都复制会
/// 让一个落在末尾的高程尖刺在窗口里重复出现七八次，直接变成中值——结算时
/// 最后一个点上的尖刺就会白送几米爬升。开头不需要截短：截短会把匀速爬坡的
/// 起点抬高，反而少算爬升。
///
/// 窗口内只统计非空值；窗口内全为空时输出 null。
///
/// 序列比窗口还短时按「不超过序列长度的最大奇数」收窄窗口：否则窗口里大半
/// 是首尾复制出来的值，一条只有十几个点的短轨迹会被整段抹平。
List<double?> medianFilterElevation(List<double?> values, int window) {
  assert(window.isOdd && window > 0, '窗口必须为正奇数');
  final int effective = math.min(
    window,
    values.length.isOdd ? values.length : values.length - 1,
  );
  final int half = math.max(0, effective ~/ 2);
  final List<double?> out = List<double?>.filled(values.length, null);
  for (int i = 0; i < values.length; i++) {
    final List<double> buf = <double>[];
    final int hi = math.min(values.length - 1, i + half);
    for (int j = i - half; j <= hi; j++) {
      final double? v = values[math.max(0, j)];
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

/// 取序列末尾最多 [window] 个值的中值；序列为空时返回 null。
///
/// 实时路径专用：结算可以取当前点前后的样点做中值，实时只看得到过去，因此
/// 用尾部窗口近似。窗口 [kElevationFilterWindow] 与结算一致，保证骑行中与
/// 结算后两个读数不会差一个量级。
double? trailingMedian(List<double> values, int window) {
  if (values.isEmpty) return null;
  final int start = math.max(0, values.length - window);
  final List<double> buf = values.sublist(start)..sort();
  return buf[buf.length ~/ 2];
}

/// 累加单次上升超过 [thresholdM] 的区段，得到总爬升（米）。
///
/// 用「滞回」方式实现：小幅波动不推进基准点，因此缓慢但持续的爬坡会被
/// 正确累加，而上下抖动不会；下降超过阈值时才把基准点下移。
///
/// [startIndex] 之前的样点只用来定基准（等价于直接跳过）：[elevationGainOf]
/// 用它实现「前 [kElevationWarmupMs] 不累计」的沉降期。
double elevationGainMeters(
  List<double?> filtered,
  double thresholdM, {
  int startIndex = 0,
}) {
  double gain = 0;
  double? baseline;
  for (int i = startIndex; i < filtered.length; i++) {
    final double? v = filtered[i];
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

/// 从整条轨迹算总爬升（米）。
///
/// 「剔除不可信点 → 中值滤波 → 滞回累加」这三步是一条固定口径，汇总（`summary.dart`）
/// 与崩溃恢复（`RecordController.resumeExisting`）都必须走同一条，否则同一趟骑行
/// 在结算前后会给出两个爬升数。见设计文档 8.1。
double elevationGainOf(List<TrackPoint> points) {
  if (points.isEmpty) return 0;
  final List<double?> filtered = medianFilterElevation(
    plausibleElevationSeries(points),
    kElevationFilterWindow,
  );
  // 前 kElevationWarmupMs 只定基准不累计：冷启动高程收敛与真实爬坡同形，
  // 不沉降就会把收敛段整段算成起步爬升。
  final int warmupEndMs = points.first.tMs + kElevationWarmupMs;
  int startIndex = 0;
  while (startIndex < points.length && points[startIndex].tMs < warmupEndMs) {
    startIndex++;
  }
  return elevationGainMeters(
    filtered,
    kElevationGainThresholdM,
    startIndex: startIndex,
  );
}
