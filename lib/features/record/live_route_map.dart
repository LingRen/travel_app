import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';
import '../../domain/analysis/gcj02.dart';
import '../../domain/analysis/route_segments.dart';
import '../../domain/models/location_fix.dart';
import '../../domain/models/track_point.dart';

/// 骑行界面里的实时轨迹地图。见设计文档 9.4。
///
/// 与详情页的 [RouteMap] 是两回事，所以没有复用它：
///   - 详情页的地图是一次性画完的，用 `initialCameraFit` 定死取景就够；
///   - 这里轨迹在骑行中一直长，必须自己拿 [MapController] 决定「什么时候重新
///     取景」。每秒重新缩放一次，看起来就是整张图在抖。
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

class _LiveRouteMapState extends State<LiveRouteMap> {
  final MapController _controller = MapController();

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

  /// 首次取景交给 `initialCameraFit`：它在拿到尺寸之后才生效，自己调
  /// `fitCamera` 有可能赶在布局之前，算出来的缩放级别是错的。
  CameraFit? _initialFit;

  /// 上一次取景用的范围。之后只在最新点跑出这个范围时才重新取景。
  LatLngBounds? _fitted;

  bool _ready = false;

  static const EdgeInsets _kFitPadding = EdgeInsets.all(24);

  /// 取景的缩放上限。只有两三个点时，自动取景会一路缩到 19 级去拉一堆瓦片，
  /// 而 25 米外的两个点根本不需要那个层级。
  static const double _kMaxZoom = 16;

  @override
  void initState() {
    super.initState();
    _rebuild(widget.points);
    _updatePreview(widget.previewFix);
    if (_vertices.length >= 2) {
      _fitted = LatLngBounds.fromPoints(_vertices);
      _initialFit = _fitFor(_fitted!);
    } else if (_markerPoint != null) {
      // 只有一个点时没有包围盒可算，直接把它放到取景中心。
      _initialFit = _fitForPoint(_markerPoint!);
    }
  }

  @override
  void didUpdateWidget(LiveRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 没变就不重算：每秒重建一次折线会逼 flutter_map 重走一遍折线布局，
    // 而轨迹实际只在攒够 25 米时才多一个点。
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
    _controller.dispose();
    super.dispose();
  }

  CameraFit _fitFor(LatLngBounds bounds) => CameraFit.bounds(
    bounds: bounds,
    padding: _kFitPadding,
    maxZoom: _kMaxZoom,
  );

  /// 只有一个点时的取景：直接以它为中心，缩放压到街区级。
  CameraFit _fitForPoint(LatLng point) =>
      CameraFit.coordinates(coordinates: <LatLng>[point], maxZoom: _kMaxZoom);

  /// 地图上要标圆点的位置：粗略定位优先；它被真实点取代后，第一次只有
  /// 一个真实点时仍以它为准——那时还画不出折线，不标点地图就是空的。
  LatLng? get _markerPoint =>
      _previewVertex ?? (_vertices.length == 1 ? _vertices.single : null);

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

  /// 只在最新点已经跑出上次取景的范围时才重新取景。
  ///
  /// 换成「每秒都重新 fit」的话，相机每一帧都在轻微缩放，整张图看着在抖；
  /// 而骑行中轨迹本来就是往外长的，等到新点出框再放一次，肉眼是「一步步长大」。
  void _syncCamera() {
    if (!mounted || _vertices.isEmpty) return;
    if (_vertices.length == 1) {
      _fitted = null;
      _controller.fitCamera(_fitForPoint(_vertices.single));
      return;
    }
    final LatLngBounds bounds = LatLngBounds.fromPoints(_vertices);
    final LatLngBounds? fitted = _fitted;
    if (fitted != null && fitted.contains(_vertices.last)) return;
    _fitted = bounds;
    _controller.fitCamera(_fitFor(bounds));
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
        if (_markerPoint != null)
          MarkerLayer(
            markers: <Marker>[
              Marker(
                point: _markerPoint!,
                width: 18,
                height: 18,
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

/// 当前位置的指示点：强调色圆点加白边，和轨迹线区分开。
class _PositionDot extends StatelessWidget {
  const _PositionDot();

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: context.palette.accent,
      border: Border.all(color: Colors.white, width: 2),
    ),
  );
}
