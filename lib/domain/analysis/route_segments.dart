import '../models/track_point.dart';
import 'constants.dart';
import 'gcj02.dart';
import 'geo.dart';

/// 地图折线上的一个顶点（已转成 GCJ-02）。
class RouteVertex {
  const RouteVertex(this.lat, this.lon);

  final double lat;
  final double lon;
}

/// 地图折线的一段：一组顶点。
///
/// 不再带颜色：轨迹统一用主题色绘制（见 `app/theme.dart` 的颜色说明），分段只剩
/// 「哪里必须断开」这一个职责。
class RouteSegment {
  const RouteSegment({required this.vertices});

  final List<RouteVertex> vertices;
}

/// 把轨迹点整理成地图可用的分段折线。见设计文档 9.2 与 9.3。
///
/// **坐标默认转成 GCJ-02**：高德瓦片是 GCJ-02，直接用 WGS-84 画会偏移数百米。
/// 但 OSM、Carto 这类源本身就是 WGS-84，对它们再转一次反而偏出几百米，因此
/// 调用方必须按瓦片源传 [toGcj02]（用 `isGcj02TileSource(tileUrl)` 判定）。
/// 转换只发生在这里，落盘与 GPX 导出的仍是 WGS-84 原始坐标。
///
/// **两种情况下断开折线**，否则地图上会出现横穿隧道或建筑物的假直线：
/// - 时间间隔超过 [kGpsGapMs] **且**位移超过 [kGapBreakMinDistanceM]（设计文档
///   9.3；只看时间会在每次停车处断开，见 [isMeaningfulGap]）
/// - 隐含速度超过 [kMaxPlausibleSpeedMps]（GPS 跳变）
///
/// [maxVerticesPerSegment] 是对设计文档 9.2「按相邻两点平均速度分段着色」的
/// 工程取舍：那条规则原本要为每个点对生成一条 `Polyline`，一小时骑行 3000+ 个点
/// 就是 3000+ 条，`flutter_map` 会卡。现在轨迹统一用主题色，分段只为「断点」与
/// 「单条折线的顶点数上限」而存在，但仍保留分组：一条折线几千个顶点同样会拖慢
/// 投影。断点一定会断开，不受分组影响。相邻两段共享一个顶点，折线才连得上。
///
/// [breakBefore] 给出「第 i 个点与上一个点之间必须断开」的下标集合（下标对
/// [points] 的顺序，不是过滤掉无坐标点之后的下标）。给了它就不再按时间间隔判
/// 断点——输入已经被抽稀过的情况（实时轨迹缩略图，见 9.4）里，点与点的时间跨度
/// 是抽稀的产物，拿 [kGpsGapMs] 去卡会把连续轨迹切成一截截。跳变检查仍然生效。
List<RouteSegment> buildRouteSegments(
  List<TrackPoint> points, {
  bool toGcj02 = true,
  int maxVerticesPerSegment = 24,
  Set<int>? breakBefore,
}) {
  assert(maxVerticesPerSegment >= 2, '一段至少要两个顶点才画得出线');

  final List<({int index, TrackPoint point})> located =
      <({int index, TrackPoint point})>[
        for (int i = 0; i < points.length; i++)
          if (points[i].hasPosition) (index: i, point: points[i]),
      ];
  if (located.length < 2) return const <RouteSegment>[];

  final List<RouteSegment> segments = <RouteSegment>[];

  /// 当前正在攒的顶点。段与段之间靠「保留最后一个顶点」连起来。
  List<RouteVertex> current = <RouteVertex>[
    _vertex(located.first.point, toGcj02),
  ];

  for (int i = 1; i < located.length; i++) {
    final TrackPoint prev = located[i - 1].point;
    final TrackPoint cur = located[i].point;

    final bool explicitBreak = breakBefore?.contains(located[i].index) ?? false;
    if (explicitBreak ||
        !_connectable(prev, cur, checkTimeGap: breakBefore == null)) {
      _flush(segments, current);
      current = <RouteVertex>[_vertex(cur, toGcj02)];
      continue;
    }

    if (current.length >= maxVerticesPerSegment) {
      _flush(segments, current);
      // 新段从上一段的末点开始，保证折线在视觉上是连着的。
      current = <RouteVertex>[current.last];
    }

    current.add(_vertex(cur, toGcj02));
  }

  _flush(segments, current);
  return segments;
}

void _flush(List<RouteSegment> out, List<RouteVertex> vertices) {
  if (vertices.length < 2) return;
  out.add(RouteSegment(vertices: List<RouteVertex>.unmodifiable(vertices)));
}

bool _connectable(TrackPoint a, TrackPoint b, {bool checkTimeGap = true}) {
  final int dt = b.tMs - a.tMs;
  if (dt <= 0) return false;
  if (checkTimeGap && isMeaningfulGap(a, b)) return false;
  // 缺速度时判不出跳变，退回纯时间判定（与 splitMovingStationary 一致）。
  final double? speedA = a.speedMps;
  final double? speedB = b.speedMps;
  if (speedA == null || speedB == null) return true;
  // 不能直接调 `isTrustedSegment`：它内部还带着 [kGpsGapMs] 的时间判定，
  // 这里已经按调用方的要求把那一半关掉了。
  return haversineMeters(a.lat!, a.lon!, b.lat!, b.lon!) / (dt / 1000.0) <=
      kMaxPlausibleSpeedMps;
}

RouteVertex _vertex(TrackPoint p, bool toGcj02) {
  if (!toGcj02) return RouteVertex(p.lat!, p.lon!);
  final ({double lat, double lon}) converted = wgs84ToGcj02(p.lat!, p.lon!);
  return RouteVertex(converted.lat, converted.lon);
}

/// 一次 GPS 信号中断：断口两侧的最后一个 / 第一个定位点，以及中断时长。
///
/// 口径与画线用的 [isMeaningfulGap] 完全一致——轨迹上断开的地方，这里就有一条。
/// 详情页拿它在地图上标出断口、在顶部写一行「信号中断 N 段」。**不用于填补数据**：
/// 缺口是真的没测到，插值出来的线是假的。
class RouteGap {
  const RouteGap({
    required this.startMs,
    required this.endMs,
    required this.before,
    required this.after,
  });

  /// 最后一次拿到定位的时刻。
  final int startMs;

  /// 恢复定位的时刻。
  final int endMs;

  /// 断口前最后一个定位点（已按瓦片源转换）。
  final RouteVertex before;

  /// 断口后第一个定位点（已按瓦片源转换）。
  final RouteVertex after;

  /// 中断时长（秒）。
  int get durationS => ((endMs - startMs) / 1000).round();
}

/// 找出轨迹里所有值得标出来的信号中断。口径见 [findRouteGaps] 的类注释。
List<RouteGap> findRouteGaps(List<TrackPoint> points, {bool toGcj02 = true}) {
  final List<TrackPoint> located = <TrackPoint>[
    for (final TrackPoint p in points)
      if (p.hasPosition) p,
  ];

  final List<RouteGap> gaps = <RouteGap>[];
  for (int i = 1; i < located.length; i++) {
    final TrackPoint a = located[i - 1];
    final TrackPoint b = located[i];
    if (!isMeaningfulGap(a, b)) continue;
    gaps.add(
      RouteGap(
        startMs: a.tMs,
        endMs: b.tMs,
        before: _vertex(a, toGcj02),
        after: _vertex(b, toGcj02),
      ),
    );
  }
  return gaps;
}
