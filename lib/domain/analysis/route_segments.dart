import '../models/track_point.dart';
import 'color_scale.dart';
import 'constants.dart';
import 'gcj02.dart';
import 'geo.dart';

/// 地图折线上的一个顶点（已转成 GCJ-02）。
class RouteVertex {
  const RouteVertex(this.lat, this.lon);

  final double lat;
  final double lon;
}

/// 地图折线的一段：一组顶点 + 一个颜色。
class RouteSegment {
  const RouteSegment({required this.vertices, required this.colorArgb});

  final List<RouteVertex> vertices;

  /// 0xAARRGGBB。
  final int colorArgb;
}

/// 把轨迹点整理成地图可用的分段折线。见设计文档 9.2 与 9.3。
///
/// **坐标会转成 GCJ-02**：高德瓦片是 GCJ-02，直接用 WGS-84 画会偏移数百米。
/// 转换只发生在这里，落盘与 GPX 导出的仍是 WGS-84 原始坐标。
///
/// **两种情况下断开折线**，否则地图上会出现横穿隧道或建筑物的假直线：
/// - 时间间隔超过 [kGpsGapMs]（设计文档 9.3）
/// - 隐含速度超过 [kMaxPlausibleSpeedMps]（GPS 跳变）
///
/// [maxVerticesPerSegment] 是对设计文档 9.2「按相邻两点平均速度分段着色」的
/// 工程取舍：字面做法会为每个点对生成一条 `Polyline`，一小时骑行 3000+ 个点
/// 就是 3000+ 条，`flutter_map` 会卡。这里把连续点分组，每组一条 `Polyline`、
/// 一个颜色（取该组平均速度）。断点一定会断开，不受分组影响。
/// 相邻两段共享一个顶点，折线才连得上。
List<RouteSegment> buildRouteSegments(
  List<TrackPoint> points, {
  double maxSpeedMps = kColorScaleMaxSpeedMps,
  int maxVerticesPerSegment = 24,
}) {
  assert(maxVerticesPerSegment >= 2, '一段至少要两个顶点才画得出线');

  final List<TrackPoint> located =
      points.where((TrackPoint p) => p.hasPosition).toList();
  if (located.length < 2) return const <RouteSegment>[];

  final List<RouteSegment> segments = <RouteSegment>[];

  /// 当前正在攒的顶点。段与段之间靠「保留最后一个顶点」连起来。
  List<RouteVertex> current = <RouteVertex>[
    _vertex(located.first),
  ];
  final List<double> currentSpeeds = <double>[_speed(located.first)];

  for (int i = 1; i < located.length; i++) {
    final TrackPoint prev = located[i - 1];
    final TrackPoint cur = located[i];

    if (!_connectable(prev, cur)) {
      _flush(segments, current, currentSpeeds, maxSpeedMps);
      current = <RouteVertex>[_vertex(cur)];
      currentSpeeds
        ..clear()
        ..add(_speed(cur));
      continue;
    }

    if (current.length >= maxVerticesPerSegment) {
      _flush(segments, current, currentSpeeds, maxSpeedMps);
      // 新段从上一段的末点开始，保证折线在视觉上是连着的。
      current = <RouteVertex>[current.last];
      currentSpeeds
        ..clear()
        ..add(_speed(prev));
    }

    current.add(_vertex(cur));
    currentSpeeds.add(_speed(cur));
  }

  _flush(segments, current, currentSpeeds, maxSpeedMps);
  return segments;
}

void _flush(
  List<RouteSegment> out,
  List<RouteVertex> vertices,
  List<double> speeds,
  double maxSpeedMps,
) {
  if (vertices.length < 2) return;
  double sum = 0;
  for (final double s in speeds) {
    sum += s;
  }
  final double average = speeds.isEmpty ? 0 : sum / speeds.length;
  out.add(RouteSegment(
    vertices: List<RouteVertex>.unmodifiable(vertices),
    colorArgb: speedColorArgb(average, maxSpeedMps: maxSpeedMps),
  ));
}

bool _connectable(TrackPoint a, TrackPoint b) {
  final int dt = b.tMs - a.tMs;
  if (dt <= 0 || dt > kGpsGapMs) return false;
  // 缺速度时判不出跳变，退回纯时间判定（与 splitMovingStationary 一致）。
  final double? speedA = a.speedMps;
  final double? speedB = b.speedMps;
  if (speedA == null || speedB == null) return true;
  return isTrustedSegment(a, b);
}

RouteVertex _vertex(TrackPoint p) {
  final ({double lat, double lon}) converted = wgs84ToGcj02(p.lat!, p.lon!);
  return RouteVertex(converted.lat, converted.lon);
}

double _speed(TrackPoint p) => p.speedMps ?? 0;
