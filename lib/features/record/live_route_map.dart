import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// latlong2 也导出了同名 `Path`，这里要的是 dart:ui 的绘制路径，藏掉前者。
import 'package:latlong2/latlong.dart' hide Path;

import '../../app/theme.dart';
import '../../domain/analysis/gcj02.dart';
import '../../domain/analysis/heading.dart';
import '../../domain/analysis/route_segments.dart';
import '../../domain/models/location_fix.dart';
import '../../domain/models/track_point.dart';

/// 骑行界面里的实时轨迹地图。见设计文档 9.4。
///
/// 与详情页的 [RouteMap] 是两回事，所以没有复用它：
///   - 详情页的地图是一次性画完的，用 `initialCameraFit` 定死取景就够；
///   - 这里轨迹在骑行中一直长，必须自己拿 [MapController] 跟着当前位置走，
///     否则骑出去一会儿箭头就出了画面（见 [_LiveRouteMapState._syncCamera]）。
///
/// 复用它的**纯部分**：`buildRouteSegments` 的分段着色与断点规则、`TileLayer` /
/// `PolylineLayer` 的画法、坐标转换口径（跟随瓦片源决定是否转 GCJ-02）。
///
/// 不可交互：骑行中它不该吃掉手指，页面上的按钮才是手势目标。地图现在铺满整页
/// （[height] 为 null），读数与按钮浮在它上方（见 10.1）。
class LiveRouteMap extends StatefulWidget {
  const LiveRouteMap({
    required this.points,
    required this.tileUrlTemplate,
    this.breakIndexes = const <int>{},
    this.previewFix,
    this.startPoint,
    this.headingDeg,
    this.subdomains = const <String>[],
    this.height,
    this.placeholderAlignment = Alignment.center,
    this.showPlaceholder = true,
    super.key,
  });

  /// 轨迹点。**每次刷新请传同一个列表对象**（没变就别新建）：这里靠
  /// [identical] 判断轨迹有没有真的变，从而跳过重算折线。
  final List<TrackPoint> points;

  /// 真实 GPS 丢失造成的段首下标；见 `RecordState.liveTrackBreaks`。
  ///
  /// 不能改成在这里按时间差判断：这张图上的点是抽稀过的，相邻两点隔 15 秒是
  /// 常态（慢速骑行、红绿灯），按 10 秒阈值卡会把连续轨迹切成一截截。
  final Set<int> breakIndexes;

  /// 开始记录时的一次粗略定位。第一个真实轨迹点到达前用它把地图点亮，
  /// 并画一个圆点标出大致位置；有真实点后由上层置空。
  final LocationFix? previewFix;

  /// 起点标记的位置。落位后不再移动，由 [RecordingSession] 判定（见设计文档
  /// 9.4）；这里只负责画，不自己挑点。
  final LocationFix? startPoint;

  /// 当前朝向（度，0 为正北，顺时针）。null 表示还没建立，只画圆点不画箭头。
  final double? headingDeg;

  /// 瓦片源，来自设置（设计文档 9.1 的对冲措施：接口失效时可换源）。
  final String tileUrlTemplate;

  final List<String> subdomains;

  /// 地图高度。null 表示铺满父级给的约束（骑行界面把它当整页背景）。
  final double? height;

  ///「等待定位…」占位文案的位置。铺满整页时浮层会盖住正中，占位要挪到露出的
  /// 那一条带上，否则用户看不到任何提示。
  final AlignmentGeometry placeholderAlignment;

  /// 没有定位点时是否显示「等待定位…」。待机页已有一张说明卡片时可以关掉，
  /// 避免同一句话出现两次；地图底仍铺纸色。
  final bool showPlaceholder;

  @override
  State<LiveRouteMap> createState() => _LiveRouteMapState();
}

class _LiveRouteMapState extends State<LiveRouteMap>
    with SingleTickerProviderStateMixin {
  final MapController _controller = MapController();

  /// 跟随平移的补间。[MapController.move] 是瞬移，安全区一破就「唰」地把整张图
  /// 拽回去很刺眼；320ms 滑过去，看起来就是地图在往前走。
  late final AnimationController _pan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..addListener(_applyPan);

  LatLng? _panFrom;
  LatLng? _panTarget;

  /// 折线缓存。只在轨迹点换了对象、或主题色变了时重算。
  List<Polyline<Object>> _polylines = const <Polyline<Object>>[];

  /// [_polylines] 是用哪个主题色画的。主题色在设置页随时可换，缓存的折线要跟着
  /// 作废——它不在 widget 参数里（来自 `context.palette`），`didUpdateWidget`
  /// 看不出这个变化。
  Color? _polylinesAccent;

  /// 最近一次分段的顶点组。主题色变化时只需重挂颜色，不必重跑分段。
  List<RouteSegment> _segments = const <RouteSegment>[];

  /// 与 [_polylines] 同源的顶点（已按瓦片源做过坐标转换），用来算取景范围。
  List<LatLng> _vertices = const <LatLng>[];

  /// [LiveRouteMap.previewFix] 转换到当前瓦片坐标系后的位置。
  LatLng? _previewVertex;

  /// [LiveRouteMap.startPoint] 转换到当前瓦片坐标系后的位置。
  LatLng? _startVertex;

  /// 箭头累计转过的角度。补间必须沿最短弧累加，见 [_updateHeading]。
  double _unwrappedDeg = 0;

  /// 上一拍的朝向，用来算最短弧差。与 [_unwrappedDeg] 分开保存：后者是连续
  /// 展开的角度，可以直接除以 360 交给 [AnimatedRotation]。
  double? _lastHeadingDeg;

  double get _headingTurns => _unwrappedDeg / 360;

  /// 首帧取景交给 `initialCameraFit`：它在拿到尺寸之后才生效，自己调
  /// `fitCamera` 有可能赶在布局之前，算出来的缩放级别是错的。
  CameraFit? _initialFit;

  bool _ready = false;

  /// 跟随安全区：可见范围四周各让出这么多比例后剩下的中间一块。
  ///
  /// 上下都压着读数浮层，只有中间这条带子是真正「看得见路」的；箭头停在
  /// 边缘等于没跟随，所以它一旦出这块安全区就把相机拉回中心。
  static const double _kFollowSafeInset = 0.25;

  /// 首次取景的缩放上限。只有两三个点时，自动取景会一路缩到 19 级去拉一堆瓦片，
  /// 而 25 米外的两个点根本不需要那个层级。
  static const double _kMaxZoom = 16;

  @override
  void initState() {
    super.initState();
    _rebuild(widget.points);
    _updatePreview(widget.previewFix);
    _updateStart(widget.startPoint);
    _updateHeading(widget.headingDeg);
    // 首帧就以当前位置为中心：绘制的是「我跟到哪儿了」，不是整段轨迹的全貌。
    // 没有真实点时退到粗略定位。
    final LatLng? center = _currentVertex ?? _markerPoint;
    if (center != null) _initialFit = _fitForPoint(center);
  }

  @override
  void didUpdateWidget(LiveRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 朝向每秒都可能在变，但它只影响箭头，不该让折线重算。先把它接掉，
    // 下面那组「轨迹没变就早退」照旧成立。
    if (oldWidget.headingDeg != widget.headingDeg) {
      _updateHeading(widget.headingDeg);
    }
    if (oldWidget.startPoint != widget.startPoint) {
      _updateStart(widget.startPoint);
    }
    // 没变就不重算：每秒重建一次折线会逼 flutter_map 重走一遍折线布局，
    // 而轨迹实际只在攒够 25 米时才多一个点。起点不参与顶点与取景，换它只需
    // 重新 build 时画新环，不必重跑分段。
    if (identical(oldWidget.points, widget.points) &&
        identical(oldWidget.breakIndexes, widget.breakIndexes) &&
        identical(oldWidget.previewFix, widget.previewFix)) {
      return;
    }
    _rebuild(widget.points);
    _updatePreview(widget.previewFix);
    // 首次取景还没生效（地图刚因粗略定位被创建）时补上中心，否则会以 (0,0)
    // 起跳。已经建好的地图不走这里，由 _syncCamera 按轨迹接管。
    if (!_ready && _vertices.length < 2 && _markerPoint != null) {
      _initialFit = _fitForPoint(_markerPoint!);
    }
    _scheduleSyncCamera();
  }

  @override
  void dispose() {
    _pan.dispose();
    _controller.dispose();
    super.dispose();
  }

  CameraFit _fitForPoint(LatLng point) =>
      CameraFit.coordinates(coordinates: <LatLng>[point], maxZoom: _kMaxZoom);

  /// 地图上要标圆点的位置：粗略定位优先；它被真实点取代后，第一次只有
  /// 一个真实点时仍以它为准——那时还画不出折线，不标点地图就是空的。
  LatLng? get _markerPoint =>
      _previewVertex ?? (_vertices.length == 1 ? _vertices.single : null);

  /// 当前位置：轨迹的最后一个顶点。没有真实点时为空（此时只有粗略定位圆点）。
  LatLng? get _currentVertex => _vertices.isEmpty ? null : _vertices.last;

  /// 换算到当前瓦片坐标系：口径与轨迹完全一致（GCJ-02 源才转）。
  LatLng _toMap(double lat, double lon) {
    if (!isGcj02TileSource(widget.tileUrlTemplate)) return LatLng(lat, lon);
    final ({double lat, double lon}) gcj = wgs84ToGcj02(lat, lon);
    return LatLng(gcj.lat, gcj.lon);
  }

  /// 把粗略定位换算到当前瓦片坐标系，口径与轨迹完全一致。
  void _updatePreview(LocationFix? fix) {
    final double? lat = fix?.lat;
    final double? lon = fix?.lon;
    _previewVertex = (lat == null || lon == null) ? null : _toMap(lat, lon);
  }

  /// 把起点换算到当前瓦片坐标系，口径与轨迹完全一致。
  void _updateStart(LocationFix? fix) {
    final double? lat = fix?.lat;
    final double? lon = fix?.lon;
    _startVertex = (lat == null || lon == null) ? null : _toMap(lat, lon);
  }

  /// 把新的朝向接到连续角度上，交给 [AnimatedRotation] 补间。
  ///
  /// 不能直接用 `heading / 360` 当 `turns`：359° → 1° 会得到 -358°，箭头倒转
  /// 一整圈。累计最短弧差后，同样的变化只有 +2°，箭头沿最短一侧转过去。
  void _updateHeading(double? headingDeg) {
    if (headingDeg == null) return;
    final double? prev = _lastHeadingDeg;
    _unwrappedDeg = prev == null
        ? headingDeg
        : _unwrappedDeg + shortestArcDelta(prev, headingDeg);
    _lastHeadingDeg = headingDeg;
  }

  void _rebuild(List<TrackPoint> points) {
    _segments = buildRouteSegments(
      points,
      toGcj02: isGcj02TileSource(widget.tileUrlTemplate),
      // 抽稀过的点不能按时间差断开，断点由采集侧标好传进来。
      breakBefore: widget.breakIndexes,
    );
    // 折线要等 build 里拿到主题色才能挂颜色，先把缓存作废。
    _polylines = const <Polyline<Object>>[];
    _polylinesAccent = null;
    _vertices = <LatLng>[
      for (final RouteSegment s in _segments)
        for (final RouteVertex v in s.vertices) LatLng(v.lat, v.lon),
    ];
    // 段组至少要两个点才成立（`buildRouteSegments` 的规则），只有一个点时就
    // 一个顶点都拿不到。但此时地图不能退回占位：第一个真实点顶掉粗略定位的
    // 那一小会儿会「亮一下又黑回去」。补上这一个点，让地图留在原地。
    if (_vertices.isEmpty) {
      final List<TrackPoint> located = points
          .where((TrackPoint p) => p.hasPosition)
          .toList();
      if (located.length == 1) {
        final TrackPoint p = located.single;
        _vertices = <LatLng>[_toMap(p.lat!, p.lon!)];
      }
    }
  }

  /// 按当前主题色产出折线。缓存命中时不重建——每秒一次的状态刷新会走到这里，
  /// 新对象会逼 `flutter_map` 重走一遍投影。
  List<Polyline<Object>> _polylinesWith(Color accent) {
    if (_polylinesAccent == accent) return _polylines;
    _polylinesAccent = accent;
    return _polylines = <Polyline<Object>>[
      for (final RouteSegment s in _segments)
        Polyline<Object>(
          points: <LatLng>[
            for (final RouteVertex v in s.vertices) LatLng(v.lat, v.lon),
          ],
          strokeWidth: kRouteStrokeWidth,
          color: accent,
          // 描边让轨迹在黄白路面与深色底图上都立得住，见 [kRouteCasing]。
          borderStrokeWidth: kRouteCasingWidth,
          borderColor: kRouteCasing,
        ),
    ];
  }

  void _scheduleSyncCamera() {
    if (!_ready) return;
    // 放到帧后：`fitCamera` 会通知监听者，在构建期间直接调会触发
    // 「构建期间 setState」。
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncCamera());
  }

  /// 让相机跟着当前位置走。
  ///
  /// 这里曾经拿「轨迹包围盒」判断要不要重新取景，但那个盒子按定义永远包含
  /// 最新点，条件恒成立——首帧之后相机再没动过，骑出去几分钟箭头就出了画面。
  /// 现在改用相机自己的可见范围：当前位置跑出正中那块安全区，就把它滑回中心。
  /// 只平移、不改缩放，避免每秒重新取景带来的整体抖动。
  void _syncCamera() {
    if (!mounted || !_ready || _vertices.isEmpty) return;
    final LatLng current = _vertices.last;
    if (_vertices.length == 1) {
      _controller.fitCamera(_fitForPoint(current));
      return;
    }
    final MapCamera camera = _controller.camera;
    if (_safeBounds(camera.visibleBounds).contains(current)) return;
    _panTo(current);
  }

  /// 从相机当前中心滑到 [target]。动画期间又来新点时，从当前位置重新起步，
  /// 不会先跳回上一次的终点。
  void _panTo(LatLng target) {
    _panFrom = _controller.camera.center;
    _panTarget = target;
    _pan.forward(from: 0);
  }

  void _applyPan() {
    final LatLng? from = _panFrom;
    final LatLng? to = _panTarget;
    if (from == null || to == null) return;
    final double t = Curves.easeOut.transform(_pan.value);
    _controller.move(
      LatLng(
        from.latitude + (to.latitude - from.latitude) * t,
        from.longitude + (to.longitude - from.longitude) * t,
      ),
      _controller.camera.zoom,
    );
  }

  /// 可见范围中间那块安全区：四周各让出 [_kFollowSafeInset]。
  static LatLngBounds _safeBounds(LatLngBounds visible) {
    final double latSpan = visible.north - visible.south;
    final double lonSpan = visible.east - visible.west;
    return LatLngBounds(
      LatLng(
        visible.south + latSpan * _kFollowSafeInset,
        visible.west + lonSpan * _kFollowSafeInset,
      ),
      LatLng(
        visible.north - latSpan * _kFollowSafeInset,
        visible.east - lonSpan * _kFollowSafeInset,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('live-route-map'),
    height: widget.height,
    child: _vertices.isEmpty && _previewVertex == null
        ? _placeholder(context)
        : _map(context),
  );

  Widget _placeholder(BuildContext context) => widget.showPlaceholder
      ? Align(
          alignment: widget.placeholderAlignment,
          child: Text(
            '等待定位…',
            style: kLabelTextStyle.copyWith(color: context.palette.muted),
          ),
        )
      : ColoredBox(color: context.palette.paper);

  Widget _map(BuildContext context) {
    // 360×640 这类矮屏上，上下浮层把地图带压到一百来像素；指北与比例尺
    // 要再往上收一档，否则会落到主读数上。正常屏保持设计稿的中段位置。
    final bool compact = MediaQuery.sizeOf(context).height < 700;
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCameraFit: _initialFit,
        backgroundColor: context.palette.paper,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
        onMapReady: () {
          _ready = true;
          _scheduleSyncCamera();
        },
      ),
      children: <Widget>[
        // 瓦片降饱和 + 纸色薄罩，让高德的彩色底图接近设计稿的纸本舆图。
        // 只包 TileLayer：轨迹与指北/比例尺不受影响。
        ColorFiltered(
          key: const Key('live-map-color-filter'),
          colorFilter: ColorFilter.mode(
            context.palette.paper.withValues(alpha: 0.16),
            BlendMode.srcOver,
          ),
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix(kMapTileColorMatrix),
            child: TileLayer(
              urlTemplate: widget.tileUrlTemplate,
              subdomains: widget.subdomains,
              userAgentPackageName: 'com.ling.cycling_app',
            ),
          ),
        ),
        PolylineLayer<Object>(
          polylines: _polylinesWith(context.palette.accentInk),
        ),
        if (_startVertex != null ||
            _currentVertex != null ||
            _previewVertex != null)
          MarkerLayer(
            markers: <Marker>[
              // 起点先挂、当前位置后挂：两者重合时箭头盖在环上，用户只看得到
              // 一个朝向前方的箭头（spec 的「起步瞬间的重合」）。
              if (_startVertex != null)
                Marker(
                  point: _startVertex!,
                  width: _StartRing.size,
                  height: _StartRing.size,
                  child: const _StartRing(),
                ),
              if (_currentVertex != null)
                Marker(
                  point: _currentVertex!,
                  // 盒子要按内容给：还没建立朝向时只画 12 dp 圆点，仍按箭头盒
                  // 的 28 dp 开会被撑成一个大墨团。
                  width: widget.headingDeg == null
                      ? _PositionDot.size
                      : _HeadingArrow.box,
                  height: widget.headingDeg == null
                      ? _PositionDot.size
                      : _HeadingArrow.box,
                  // 还没建立朝向时只画圆点，不能凭空指一个方向。
                  child: widget.headingDeg == null
                      ? const _PositionDot()
                      : _HeadingArrow(turns: _headingTurns),
                )
              else if (_previewVertex != null)
                Marker(
                  point: _previewVertex!,
                  width: _PositionDot.size,
                  height: _PositionDot.size,
                  child: const _PositionDot(),
                ),
            ],
          ),
        // 指北与比例尺只是参照，不吃手势。正常屏放在地图带中段，矮屏
        // 往上收一档，避免压到主读数。
        IgnorePointer(
          child: Align(
            alignment: compact
                ? const Alignment(0.9, -0.3)
                : const Alignment(0.9, 0.04),
            child: const _NorthIndicator(),
          ),
        ),
        IgnorePointer(
          child: Align(
            alignment: compact
                ? const Alignment(-0.86, -0.3)
                : const Alignment(-0.86, 0.2),
            child: const _MapScaleBar(),
          ),
        ),
      ],
    );
  }
}

/// 指北标识。地图不旋转，所以永远指北。
class _NorthIndicator extends StatelessWidget {
  const _NorthIndicator();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Container(
      key: const Key('map-north'),
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.paper.withValues(alpha: 0.88),
        border: Border.all(color: palette.hairline),
      ),
      child: Text(
        '北',
        style: kLabelTextStyle.copyWith(
          fontSize: 11,
          letterSpacing: 0,
          color: palette.ink,
        ),
      ),
    );
  }
}

/// 比例尺。按当前缩放与纬度把米/像素换算成一个整数距离，画一段横线。
///
/// 地图记录中不可交互，但「这段路有多长」仍需要一个参照；比例尺只做显示，
/// 用 [IgnorePointer] 包住，不改变地图的手势行为。
class _MapScaleBar extends StatelessWidget {
  const _MapScaleBar();

  /// 目标横线长度（逻辑像素）。实际会取一个不超过它的 1/2/5 整十距离。
  static const double _targetWidth = 80;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final MapCamera camera = MapCamera.of(context);
    final double metersPerPixel = _metersPerPixel(camera);
    final double niceMeters = _niceDistance(metersPerPixel * _targetWidth);
    final double width = (niceMeters / metersPerPixel).clamp(24.0, 140.0);
    final String label = niceMeters >= 1000
        ? '${(niceMeters / 1000).toStringAsFixed(niceMeters % 1000 == 0 ? 0 : 1)} km'
        : '${niceMeters.round()} m';

    return Column(
      key: const Key('map-scale-bar'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: kLabelTextStyle.copyWith(
            fontSize: 10,
            letterSpacing: 0,
            color: palette.ink,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Container(width: 2, height: 8, color: palette.ink),
            Container(width: width, height: 2, color: palette.ink),
            Container(width: 2, height: 8, color: palette.ink),
          ],
        ),
      ],
    );
  }

  /// Web Mercator 下每像素代表的米数。瓦片边长按 flutter_map 默认的 256。
  static double _metersPerPixel(MapCamera camera) {
    const double equatorMeters = 40075016.686;
    final double latRad = camera.center.latitude * math.pi / 180;
    final double scale = math.pow(2, camera.zoom).toDouble();
    return equatorMeters * math.cos(latRad) / (256 * scale);
  }

  /// 取 1、2、5 乘以 10 的整数次幂中不超过 [raw] 的最大值。
  static double _niceDistance(double raw) {
    if (!raw.isFinite || raw <= 0) return 100;
    final double exponent = math
        .pow(10, (math.log(raw) / math.ln10).floor())
        .toDouble();
    final double fraction = raw / exponent;
    final double nice = fraction >= 5
        ? 5
        : fraction >= 2
        ? 2
        : 1;
    return nice * exponent;
  }
}

/// 粗略定位 / 朝向尚未建立时的位置点：12 dp 半透明墨色圆点。
///
/// 不用主题色，也不加白边：它只表示「大概在这儿」，不该和轨迹末端抢注意力。
class _PositionDot extends StatelessWidget {
  const _PositionDot();

  static const double size = 12;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('map-position-dot'),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: context.palette.ink.withValues(alpha: 0.55),
    ),
  );
}

/// 记录页的起点：18 dp 主题色空心环，无字。
///
/// 不带字是为了小屏地图带不挤（起点环、箭头、指北与比例尺会同时出现）。
class _StartRing extends StatelessWidget {
  const _StartRing();

  static const double size = 18;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('map-start-marker'),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: context.palette.accentInk, width: 2),
    ),
  );
}

/// 当前位置箭头：22 dp 实心三角，深墨填充 + 1.5 dp 纸色描边。
///
/// 用墨色而不是主题色：脚下的轨迹就是主题色，同色会融成一片。描边用纸色，
/// 让箭头在深色底图与彩色瓦片上都立得住（与轨迹的 [kRouteCasing] 同一角色）。
class _HeadingArrow extends StatelessWidget {
  const _HeadingArrow({required this.turns});

  /// 视觉尺寸（三角形本身）。
  static const double size = 22;

  /// 标记盒子：比三角形大一圈，旋转时不裁角。
  static const double box = 28;

  /// 连续展开的圈数。见 `_LiveRouteMapState._updateHeading`。
  final double turns;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    key: const Key('map-heading-arrow'),
    turns: turns,
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOut,
    child: CustomPaint(
      size: const Size(box, box),
      painter: _HeadingArrowPainter(
        fill: context.palette.ink,
        casing: context.palette.paper,
      ),
    ),
  );
}

class _HeadingArrowPainter extends CustomPainter {
  const _HeadingArrowPainter({required this.fill, required this.casing});

  final Color fill;
  final Color casing;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double half = _HeadingArrow.size / 2;
    // 尖端朝上（0° ＝ 正北），底边带一个内凹，像导航箭头。
    final Path path = Path()
      ..moveTo(center.dx, center.dy - half)
      ..lineTo(center.dx + half * 0.72, center.dy + half * 0.78)
      ..lineTo(center.dx, center.dy + half * 0.42)
      ..lineTo(center.dx - half * 0.72, center.dy + half * 0.78)
      ..close();

    // 先描一圈比填充宽 3 的边，再被填充盖住内侧，净剩 1.5 dp 的纸色轮廓。
    canvas.drawPath(
      path,
      Paint()
        ..color = casing
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(path, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_HeadingArrowPainter old) =>
      old.fill != fill || old.casing != casing;
}
