import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';
import '../../domain/analysis/gcj02.dart';
import '../../domain/analysis/route_segments.dart';
import '../../domain/models/track_point.dart';

/// 骑行界面里的实时轨迹缩略图。见设计文档 9.4。
///
/// 与详情页的 [RouteMap] 是两回事，所以没有复用它：
///   - 详情页的地图是一次性画完的，用 `initialCameraFit` 定死取景就够；
///   - 这里轨迹在骑行中一直长，必须自己拿 [MapController] 决定「什么时候重新
///     取景」。120pt 高的条上每秒重新缩放一次，看起来就是整张图在抖。
///
/// 复用它的**纯部分**：`buildRouteSegments` 的分段着色与断点规则、`TileLayer` /
/// `PolylineLayer` 的画法、坐标转换口径（跟随瓦片源决定是否转 GCJ-02）。
///
/// 不可交互：骑行中这根条不该吃掉手指，页面上的两个大按钮才是手势目标。
class LiveRouteMap extends StatefulWidget {
  const LiveRouteMap({
    required this.points,
    required this.tileUrlTemplate,
    this.subdomains = const <String>[],
    this.height = 120,
    super.key,
  });

  /// 轨迹点。**每次刷新请传同一个列表对象**（没变就别新建）：这里靠
  /// [identical] 判断轨迹有没有真的变，从而跳过重算折线。
  final List<TrackPoint> points;

  /// 瓦片源，来自设置（设计文档 9.1 的对冲措施：接口失效时可换源）。
  final String tileUrlTemplate;

  final List<String> subdomains;
  final double height;

  @override
  State<LiveRouteMap> createState() => _LiveRouteMapState();
}

class _LiveRouteMapState extends State<LiveRouteMap> {
  final MapController _controller = MapController();

  /// 折线缓存。只在轨迹点换了对象时重算。
  List<Polyline<Object>> _polylines = const <Polyline<Object>>[];

  /// 与 [_polylines] 同源的顶点（已按瓦片源做过坐标转换），用来算取景范围。
  List<LatLng> _vertices = const <LatLng>[];

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
    if (_vertices.length >= 2) {
      _fitted = LatLngBounds.fromPoints(_vertices);
      _initialFit = _fitFor(_fitted!);
    }
  }

  @override
  void didUpdateWidget(LiveRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 没变就不重算：每秒重建一次折线会逼 flutter_map 重走一遍折线布局，
    // 而轨迹实际只在攒够 25 米时才多一个点。
    if (identical(oldWidget.points, widget.points)) return;
    _rebuild(widget.points);
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

  void _rebuild(List<TrackPoint> points) {
    final List<RouteSegment> segments = buildRouteSegments(
      points,
      toGcj02: isGcj02TileSource(widget.tileUrlTemplate),
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
    if (!mounted || _vertices.length < 2) return;
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
        child: _polylines.isEmpty ? _placeholder() : _map(),
      );

  Widget _placeholder() => const Center(
        child: Text('等待定位…', style: kLabelTextStyle),
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
        ],
      );
}