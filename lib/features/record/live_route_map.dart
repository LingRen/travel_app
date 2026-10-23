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

  @override
  State<LiveRouteMap> createState() => _LiveRouteMapState();
}

class _LiveRouteMapState extends State<LiveRouteMap> {
  final MapController _controller = MapController();

  /// 折线缓存。只在轨迹点换了对象时重算。
  List<Polyline<Object>> _polylines = const <Polyline<Object>>[];

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
  CameraFit _fitForPoint(LatLng point) => CameraFit.coordinates(
        coordinates: <LatLng>[point],
        maxZoom: _kMaxZoom,
      );

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
    final List<RouteSegment> segments = buildRouteSegments(
      points,
      toGcj02: isGcj02TileSource(widget.tileUrlTemplate),
      // 抽稀过的点不能按时间差断开，断点由采集侧标好传进来。
      breakBefore: widget.breakIndexes,
    );
    _polylines = <Polyline<Object>>[
      for (final RouteSegment s in segments)
        Polyline<Object>(
          points: <LatLng>[
            for (final RouteVertex v in s.vertices) LatLng(v.lat, v.lon),
          ],
          strokeWidth: 4,
          color: Color(s.colorArgb),
        ),
    ];
    _vertices = <LatLng>[
      for (final RouteSegment s in segments)
        for (final RouteVertex v in s.vertices) LatLng(v.lat, v.lon),
    ];
    // 段组至少要两个点才成立（`buildRouteSegments` 的规则），只有一个点时就
    // 一个顶点都拿不到。但此时地图不能退回占位：第一个真实点顶掉粗略定位的
    // 那一小会儿会「亮一下又黑回去」。补上这一个点，让地图留在原地。
    if (_vertices.isEmpty) {
      final List<TrackPoint> located =
          points.where((TrackPoint p) => p.hasPosition).toList();
      if (located.length == 1) {
        final TrackPoint p = located.single;
        _vertices = <LatLng>[_toMap(p.lat!, p.lon!)];
      }
    }
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
            ? _placeholder()
            : _map(),
      );

  Widget _placeholder() => Align(
        alignment: widget.placeholderAlignment,
        child: const Text('等待定位…', style: kLabelTextStyle),
      );

  Widget _map() => FlutterMap(
        mapController: _controller,
        options: MapOptions(
          initialCameraFit: _initialFit,
          backgroundColor: kAppSurface,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
          onMapReady: () {
            _ready = true;
            _scheduleSyncCamera();
          },
        ),
        children: <Widget>[
          TileLayer(
            urlTemplate: widget.tileUrlTemplate,
            subdomains: widget.subdomains,
            userAgentPackageName: 'com.ling.cycling_app',
          ),
          PolylineLayer<Object>(polylines: _polylines),
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
        ],
      );
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