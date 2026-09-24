import '../models/track_point.dart';
import 'constants.dart';
import 'speed.dart';

/// 曲线要画哪个指标。
enum CurveMetric { speed, heartRate, cadence, power }

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
/// - 速度曲线先做 [kSpeedCurveFilterWindow] 点滑动平均：GPS 瞬时速度毛刺严重，
///   直接画出来是一团噪声（设计文档 8.1）。
/// - 心率 / 踏频 / 功率做 [kSensorCurveFilterWindow] 点滑动平均：同样是毛刺
///   问题，只是来源从 GPS 换成了传感器。平滑**只影响画线**，页面上的平均与
///   最高读数仍取原始值（见 `summary.dart`），所以「曲线圆润」与「读数准确」
///   互不冲突。
/// - 平滑不填补空缺：踏频器中途才连上时，前半段不会凭空长出一条踏频曲线。
/// - 点数超过 [maxSamples] 时等步长抽稀，**首点与末点一定保留**。
List<CurveSample> buildCurve(
  List<TrackPoint> points, {
  required CurveMetric metric,
  int maxSamples = 240,
}) {
  final List<double?> raw = _rawValues(points, metric);
  final List<double?> values = switch (metric) {
    CurveMetric.speed => movingAverage(raw, kSpeedCurveFilterWindow),
    CurveMetric.heartRate ||
    CurveMetric.cadence ||
    CurveMetric.power =>
      _smoothKeepingGaps(raw, kSensorCurveFilterWindow),
  };

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
    case CurveMetric.power:
      return <double?>[
        for (final TrackPoint p in points) p.powerW?.toDouble(),
      ];
  }
}

/// 滑动平均，但**不填补原本为空的位置**。
///
/// [movingAverage] 会用相邻点把空缺补上（窗口内有非空值就输出均值）。对曲线
/// 来说这是造数据：踏频器骑到一半才连上，前半段会凭空长出一条踏频曲线。这里
/// 把原本为空的位置原样置回 null，只抹圆已有数据。
List<double?> _smoothKeepingGaps(List<double?> values, int window) {
  final List<double?> smoothed = movingAverage(values, window);
  for (int i = 0; i < values.length; i++) {
    if (values[i] == null) smoothed[i] = null;
  }
  return smoothed;
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

/// 一条曲线上的极值：最大与最小各自落在哪个采样点。
///
/// 取的是**画出来的这条曲线**的极值，不是 `summary.dart` 里的读数：读数用
/// [kSpeedFilterWindow]（口径是「最高速」），曲线用 [kSpeedCurveFilterWindow]，
/// 两者不是同一个数。标在曲线上的点必须真的落在曲线上，否则标注本身成了误导。
class CurveExtremes {
  const CurveExtremes({
    required this.maxIndex,
    required this.maxY,
    required this.minIndex,
    required this.minY,
  });

  /// 最大值所在的采样点下标与数值。
  final int maxIndex;
  final double maxY;

  /// 最小值所在的采样点下标与数值。
  final int minIndex;
  final double minY;

  /// 曲线是平的（上下限重合）——标一个点就够了，两个标签会叠在一起。
  bool get isFlat => maxY == minY;
}

/// 找出曲线上的最高点与最低点。空曲线返回 null。
CurveExtremes? curveExtremes(List<CurveSample> samples) {
  if (samples.isEmpty) return null;
  int maxIndex = 0;
  int minIndex = 0;
  for (int i = 1; i < samples.length; i++) {
    if (samples[i].y > samples[maxIndex].y) maxIndex = i;
    if (samples[i].y < samples[minIndex].y) minIndex = i;
  }
  return CurveExtremes(
    maxIndex: maxIndex,
    maxY: samples[maxIndex].y,
    minIndex: minIndex,
    minY: samples[minIndex].y,
  );
}

/// 归一化到 0..1 的一个点：x 是时间轴、y 是数值轴，y 不翻转。
class CurvePoint {
  const CurvePoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is CurvePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'CurvePoint($x, $y)';
}

/// 一段平滑曲线：三次贝塞尔，四个控制点都已归一化到 0..1。
class CurveArc {
  const CurveArc({
    required this.fromIndex,
    required this.toIndex,
    required this.from,
    required this.control1,
    required this.control2,
    required this.to,
  });

  /// 对应的采样点下标。颜色仍然按这一对的数值取，和折线时代一致。
  final int fromIndex;
  final int toIndex;

  final CurvePoint from;
  final CurvePoint control1;
  final CurvePoint control2;
  final CurvePoint to;

  @override
  String toString() =>
      'CurveArc($fromIndex→$toIndex, $from, $control1, $control2, $to)';
}

/// 把折线整理成经过每个采样点的三次贝塞尔（Catmull-Rom 转贝塞尔）。
///
/// 相邻点直连的数据密集时是一团毛毛棱棱的折线：抽稀后仍有 240 个采样点挤在
/// 三百多像素宽里，每段只有一两个像素，转折全靠折角表达，真机上看就是锯齿。
/// 换成 Catmull-Rom 之后曲线**仍然严格穿过每一个采样点**（峰谷不抹平，读数
/// 不骗人），只是把折角换成连续切线；贝塞尔控制点可能略微越过极值，画笔那边
/// 会按图表区域裁剪。
///
/// [pairs] 由 `drawnCurveSegments` / `drawnMiniCurveSegments` 给出——连接规则
/// 只有一处定义，这里不再判断 segment。
///
/// 切线用的邻居在断口处退化成端点自身，而不是借用断口另一侧的点：否则隧道
/// 两侧的点会被拉进同一条切线，等于又把它们连了起来（设计文档 9.3）。
List<CurveArc> curveArcs(
  List<CurveSample> samples,
  List<(int, int)> pairs, {
  required double maxX,
  required double maxY,
}) {
  final List<CurveArc> arcs = <CurveArc>[];
  for (final (int i, int j) in pairs) {
    final CurvePoint p0 = _normalized(samples[i], maxX, maxY);
    final CurvePoint p1 = _normalized(samples[j], maxX, maxY);

    final CurvePoint prev =
        i - 1 >= 0 && samples[i - 1].segment == samples[i].segment
            ? _normalized(samples[i - 1], maxX, maxY)
            : p0;
    final CurvePoint next =
        j + 1 < samples.length && samples[j + 1].segment == samples[j].segment
            ? _normalized(samples[j + 1], maxX, maxY)
            : p1;

    arcs.add(CurveArc(
      fromIndex: i,
      toIndex: j,
      from: p0,
      to: p1,
      control1: CurvePoint(
        p0.x + (p1.x - prev.x) / kCurveTensionDivisor,
        p0.y + (p1.y - prev.y) / kCurveTensionDivisor,
      ),
      control2: CurvePoint(
        p1.x - (next.x - p0.x) / kCurveTensionDivisor,
        p1.y - (next.y - p0.y) / kCurveTensionDivisor,
      ),
    ));
  }
  return arcs;
}

CurvePoint _normalized(CurveSample s, double maxX, double maxY) =>
    CurvePoint(s.xSeconds / maxX, s.y / maxY);
