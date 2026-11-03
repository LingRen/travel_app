import 'dart:async';

import 'package:amap_map/amap_map.dart' as amap;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// latlong2 也导出了同名 `Path`，这里要的是 dart:ui 的绘制路径，藏掉前者。
import 'package:latlong2/latlong.dart' hide Path;
// amap_map 的经纬度类型来自 x_amap_base；用前缀导入避免与 latlong2 的 LatLng 重名。
import 'package:x_amap_base/x_amap_base.dart' as amap_base;

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/analysis/gcj02.dart';
import '../../domain/analysis/heading.dart';
import '../../domain/analysis/route_segments.dart';
import '../../domain/models/location_fix.dart';
import '../../domain/models/track_point.dart';
import '../map/amap_basemap.dart';
import '../map/map_backend.dart';
import '../map/map_overlays.dart';
import '../map/map_projection.dart';
import '../privacy/privacy_consent.dart';

/// 构造原生底图。默认使用 [AmapBasemap]；widget 测试可换成纯 Flutter 占位，
/// 避免在测试环境创建 platform view。
typedef AmapBasemapBuilder =
    Widget Function(
      BuildContext context,
      amap.CameraPosition initialCamera,
      ValueChanged<amap.AMapController> onMapCreated,
    );

/// 高德 SDK 的经纬度类型别名，避免与 flutter_map 的 `LatLng` 混淆。
typedef AmapLatLng = amap_base.LatLng;

/// 骑行界面里的实时轨迹地图。见设计文档 9.4。
///
/// 对外仍是「一块跟随当前位置的地图」，内部按 `mapBackendProvider` 选择：
///   - [MapBackend.amap]：高德原生底图 + Flutter 覆盖层（轨迹、标记、比例尺）；
///   - [MapBackend.legacy]：原有 `flutter_map` 栅格实现，无 Key 或排障时使用。
///
/// 原生底图必须先取得隐私同意（[AmapPrivacyGate]），未同意时继续用 legacy。
///
/// 不可交互：骑行中它不该吃掉手指，页面上的按钮才是手势目标。地图现在铺满整页
/// （[height] 为 null），读数与按钮浮在它上方（见 10.1）。
class LiveRouteMap extends ConsumerWidget {
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
    this.amapBasemapBuilder,
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
  /// 仅在 legacy 后端使用；原生后端始终是 GCJ-02 高德底图。
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

  /// 测试用的原生底图替身。为 null 时使用真实的高德平台视图。
  final AmapBasemapBuilder? amapBasemapBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool hasFix =
        previewFix?.hasPosition == true ||
        points.any((TrackPoint p) => p.hasPosition);
    final MapBackend backend = ref.watch(mapBackendProvider);

    final Widget body;
    if (!hasFix) {
      body = _placeholder(context);
    } else {
      final _LegacyBody legacy = _LegacyBody(
        points: points,
        tileUrlTemplate: tileUrlTemplate,
        breakIndexes: breakIndexes,
        previewFix: previewFix,
        startPoint: startPoint,
        headingDeg: headingDeg,
        subdomains: subdomains,
      );
      body = backend == MapBackend.amap
          ? AmapPrivacyGate(
              fallback: legacy,
              child: _AmapBody(
                points: points,
                breakIndexes: breakIndexes,
                previewFix: previewFix,
                startPoint: startPoint,
                headingDeg: headingDeg,
                basemapBuilder: amapBasemapBuilder ?? _defaultBasemap,
              ),
            )
          : legacy;
    }

    return SizedBox(
      key: const Key('live-route-map'),
      height: height,
      child: body,
    );
  }

  Widget _placeholder(BuildContext context) => showPlaceholder
      ? Align(
          alignment: placeholderAlignment,
          child: Text(
            '等待定位…',
            style: kLabelTextStyle.copyWith(color: context.palette.muted),
          ),
        )
      : ColoredBox(color: context.palette.paper);

  Widget _defaultBasemap(
    BuildContext context,
    amap.CameraPosition initialCamera,
    ValueChanged<amap.AMapController> onMapCreated,
  ) => AmapBasemap(
    initialCamera: initialCamera,
    onMapCreated: onMapCreated,
  );
}

/// legacy 栅格底图。原有 `flutter_map` 实现原样保留：无 Key、测试与排障都走这里。
class _LegacyBody extends StatefulWidget {
  const _LegacyBody({
    required this.points,
    required this.tileUrlTemplate,
    this.breakIndexes = const <int>{},
    this.previewFix,
    this.startPoint,
    this.headingDeg,
    this.subdomains = const <String>[],
  });

  final List<TrackPoint> points;
  final Set<int> breakIndexes;
  final LocationFix? previewFix;
  final LocationFix? startPoint;
  final double? headingDeg;
  final String tileUrlTemplate;
  final List<String> subdomains;

  @override
  State<_LegacyBody> createState() => _LegacyBodyState();
}

class _LegacyBodyState extends State<_LegacyBody>
    with SingleTickerProviderStateMixin {
  final MapController _controller = MapController();

  /// 跟随平移的补间。[MapController.move] 是瞬移，新点一来「唰」地把中心拽过去
  /// 很刺眼；320ms 滑过去，看起来就是地图在往前走。
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

  /// 朝向累计转过的角度。补间必须沿最短弧累加。
  final _HeadingTurns _heading = _HeadingTurns();

  /// 首帧取景交给 `initialCameraFit`：它在拿到尺寸之后才生效，自己调
  /// `fitCamera` 有可能赶在布局之前，算出来的缩放级别是错的。
  CameraFit? _initialFit;

  bool _ready = false;

  /// 首次取景的缩放上限。只有两三个点时，自动取景会一路缩到 19 级去拉一堆瓦片，
  /// 而 25 米外的两个点根本不需要那个层级。
  static const double _kMaxZoom = 16;

  @override
  void initState() {
    super.initState();
    _rebuild(widget.points);
    _updatePreview(widget.previewFix);
    _updateStart(widget.startPoint);
    _heading.update(widget.headingDeg);
    // 首帧就以当前位置为中心：绘制的是「我跟到哪儿了」，不是整段轨迹的全貌。
    // 没有真实点时退到粗略定位。
    final LatLng? center = _currentVertex ?? _markerPoint;
    if (center != null) _initialFit = _fitForPoint(center);
  }

  @override
  void didUpdateWidget(_LegacyBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 朝向每秒都可能在变，但它只影响箭头，不该让折线重算。先把它接掉，
    // 下面那组「轨迹没变就早退」照旧成立。
    if (oldWidget.headingDeg != widget.headingDeg) {
      _heading.update(widget.headingDeg);
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

  /// 让相机跟着当前位置走：每一个新点都把当前位置放到屏幕正中。
  ///
  /// 这里曾经拿「轨迹包围盒」判断要不要重新取景，但那个盒子按定义永远包含
  /// 最新点，条件恒成立——首帧之后相机再没动过，骑出去几分钟箭头就出了画面。
  /// 也试过「出安全区才回中」，高速下攒一段才跳一次，看起来一冲一冲的。
  /// 现在每一拍都对准当前位置，只平移、不改缩放，320ms 滑过去就是连续前进。
  void _syncCamera() {
    if (!mounted || !_ready || _vertices.isEmpty) return;
    final LatLng current = _vertices.last;
    if (_vertices.length == 1) {
      _controller.fitCamera(_fitForPoint(current));
      return;
    }
    _panTo(current);
  }

  /// 从相机当前中心滑到 [target]。动画期间又来新点时，从当前位置重新起步，
  /// 不会先跳回上一次的终点。
  void _panTo(LatLng target) {
    // 已经在正中就别再起一遍动画：连续几拍同一位置会反复重启动画。
    if (_controller.camera.center == target) return;
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

  @override
  Widget build(BuildContext context) {
    // 360×640 这类矮屏上，上下浮层把地图带压到一百来像素；指北与比例尺
    // 要再往上收一档，否则会落到主读数上。正常屏保持设计稿的中段位置。
    final bool compact = MediaQuery.sizeOf(context).height < 700;
    final AppPalette palette = context.palette;
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCameraFit: _initialFit,
        backgroundColor: palette.paper,
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
            palette.paper.withValues(alpha: 0.16),
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
        PolylineLayer<Object>(polylines: _polylinesWith(palette.accentInk)),
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
                  width: MapStartRing.size,
                  height: MapStartRing.size,
                  child: const MapStartRing(),
                ),
              if (_currentVertex != null)
                Marker(
                  point: _currentVertex!,
                  // 盒子要按内容给：还没建立朝向时只画 12 dp 圆点，仍按箭头盒
                  // 的 28 dp 开会被撑成一个大墨团。
                  width: widget.headingDeg == null
                      ? MapPositionDot.size
                      : MapHeadingArrow.box,
                  height: widget.headingDeg == null
                      ? MapPositionDot.size
                      : MapHeadingArrow.box,
                  // 还没建立朝向时只画圆点，不能凭空指一个方向。
                  child: widget.headingDeg == null
                      ? const MapPositionDot()
                      : MapHeadingArrow(turns: _heading.turns),
                )
              else if (_previewVertex != null)
                Marker(
                  point: _previewVertex!,
                  width: MapPositionDot.size,
                  height: MapPositionDot.size,
                  child: const MapPositionDot(),
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
            child: const MapNorthIndicator(),
          ),
        ),
        IgnorePointer(
          child: Align(
            alignment: compact
                ? const Alignment(-0.86, -0.3)
                : const Alignment(-0.86, 0.2),
            // MapCamera.of 只能在地图内部读：Builder 的 context 才是
            // FlutterMap 的后代，State 的 context 在它之上。
            child: Builder(
              builder: (BuildContext context) {
                final MapCamera camera = MapCamera.of(context);
                return MapScaleBar(
                  metersPerPixel: MapProjection.metersPerPixelAt(
                    lat: camera.center.latitude,
                    zoom: camera.zoom,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// 高德原生底图 + Flutter 覆盖层。
///
/// 覆盖层不依赖 SDK 的 Marker / Polyline：轨迹与标记继续用熟悉的 Flutter
/// 组件绘制，测试锚点（`map-heading-arrow` 等）因此保持不变。相机跟随仍由
/// 本组件驱动，320ms 补间与 legacy 一致。
class _AmapBody extends StatefulWidget {
  const _AmapBody({
    required this.points,
    required this.basemapBuilder,
    this.breakIndexes = const <int>{},
    this.previewFix,
    this.startPoint,
    this.headingDeg,
  });

  final List<TrackPoint> points;
  final Set<int> breakIndexes;
  final LocationFix? previewFix;
  final LocationFix? startPoint;
  final double? headingDeg;
  final AmapBasemapBuilder basemapBuilder;

  @override
  State<_AmapBody> createState() => _AmapBodyState();
}

class _AmapBodyState extends State<_AmapBody>
    with SingleTickerProviderStateMixin {
  /// 原生底图始终是 GCJ-02，与 legacy 的「按瓦片源转换」不同。
  static const bool _toGcj02 = true;

  late final AnimationController _pan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..addListener(_applyPan);

  final _HeadingTurns _heading = _HeadingTurns();

  List<RouteSegment> _segments = const <RouteSegment>[];
  List<AmapLatLng> _vertices = const <AmapLatLng>[];
  AmapLatLng? _previewVertex;
  AmapLatLng? _startVertex;

  /// 首帧相机。之后由 [_center] 与 320ms 补间接管。
  late final amap.CameraPosition _initialCamera;

  /// 覆盖层使用的相机中心（GCJ-02）。与原生相机保持同步。
  AmapLatLng? _center;

  double _zoom = 16;

  amap.AMapController? _controller;
  bool _mapReady = false;

  AmapLatLng? _panFrom;
  AmapLatLng? _panTarget;

  @override
  void initState() {
    super.initState();
    _rebuild(widget.points);
    _updatePreview(widget.previewFix);
    _updateStart(widget.startPoint);
    _heading.update(widget.headingDeg);
    final AmapLatLng center =
        _currentVertex ??
        _previewVertex ??
        // 理论上构造前已有定位；这个兜底只为避免空 target。
        const AmapLatLng(39.909187, 116.397451);
    _center = center;
    _initialCamera = amap.CameraPosition(target: center, zoom: _zoom);
  }

  @override
  void didUpdateWidget(_AmapBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.headingDeg != widget.headingDeg) {
      _heading.update(widget.headingDeg);
    }
    if (oldWidget.startPoint != widget.startPoint) {
      _updateStart(widget.startPoint);
    }
    if (identical(oldWidget.points, widget.points) &&
        identical(oldWidget.breakIndexes, widget.breakIndexes) &&
        identical(oldWidget.previewFix, widget.previewFix)) {
      return;
    }
    _rebuild(widget.points);
    _updatePreview(widget.previewFix);
    _scheduleSyncCamera();
  }

  @override
  void dispose() {
    _pan.dispose();
    super.dispose();
  }

  AmapLatLng? get _currentVertex => _vertices.isEmpty ? null : _vertices.last;

  AmapLatLng _toMap(double lat, double lon) {
    final ({double lat, double lon}) gcj = wgs84ToGcj02(lat, lon);
    return AmapLatLng(gcj.lat, gcj.lon);
  }

  void _updatePreview(LocationFix? fix) {
    final double? lat = fix?.lat;
    final double? lon = fix?.lon;
    _previewVertex = (lat == null || lon == null) ? null : _toMap(lat, lon);
  }

  void _updateStart(LocationFix? fix) {
    final double? lat = fix?.lat;
    final double? lon = fix?.lon;
    _startVertex = (lat == null || lon == null) ? null : _toMap(lat, lon);
  }

  void _rebuild(List<TrackPoint> points) {
    _segments = buildRouteSegments(
      points,
      toGcj02: _toGcj02,
      breakBefore: widget.breakIndexes,
    );
    _vertices = <AmapLatLng>[
      for (final RouteSegment s in _segments)
        for (final RouteVertex v in s.vertices) AmapLatLng(v.lat, v.lon),
    ];
    if (_vertices.isEmpty) {
      final List<TrackPoint> located = points
          .where((TrackPoint p) => p.hasPosition)
          .toList();
      if (located.length == 1) {
        final TrackPoint p = located.single;
        _vertices = <AmapLatLng>[_toMap(p.lat!, p.lon!)];
      }
    }
  }

  void _scheduleSyncCamera() {
    if (!_mapReady) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncCamera());
  }

  void _syncCamera() {
    if (!mounted || !_mapReady || _vertices.isEmpty) return;
    final AmapLatLng current = _vertices.last;
    if (_vertices.length == 1) {
      _zoom = 16;
      _moveCameraNow(current);
      return;
    }
    _panTo(current);
  }

  void _panTo(AmapLatLng target) {
    if (_center == target) return;
    _panFrom = _center;
    _panTarget = target;
    _pan.forward(from: 0);
  }

  void _applyPan() {
    final AmapLatLng? from = _panFrom;
    final AmapLatLng? to = _panTarget;
    if (from == null || to == null) return;
    final double t = Curves.easeOut.transform(_pan.value);
    _moveCameraNow(
      AmapLatLng(
        from.latitude + (to.latitude - from.latitude) * t,
        from.longitude + (to.longitude - from.longitude) * t,
      ),
    );
  }

  /// 原生相机紧跟覆盖层：动画每一拍都无补间地设到当前插值点，两者不会漂移。
  void _moveCameraNow(AmapLatLng center) {
    _center = center;
    final amap.AMapController? controller = _controller;
    if (controller == null) return;
    unawaited(
      controller.moveCamera(
        amap.CameraUpdate.newCameraPosition(
          amap.CameraPosition(target: center, zoom: _zoom),
        ),
        animated: false,
      ),
    );
  }

  void _onMapCreated(amap.AMapController controller) {
    _controller = controller;
    _mapReady = true;
    _scheduleSyncCamera();
  }

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).height < 700;
    final AppPalette palette = context.palette;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        final AmapLatLng center = _center ?? _initialCamera.target;
        final MapProjection projection = MapProjection(
          centerLat: center.latitude,
          centerLon: center.longitude,
          zoom: _zoom,
          viewportSize: size,
        );
        final AmapLatLng? current = _currentVertex;
        final AmapLatLng? preview = _previewVertex;

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              widget.basemapBuilder(
                context,
                _initialCamera,
                _onMapCreated,
              ),
              // 轨迹：覆盖层自绘，避免依赖 SDK 的 Polyline 与 id 缓存。
              IgnorePointer(
                child: CustomPaint(
                  key: const Key('live-map-overlay'),
                  painter: _AmapRoutePainter(
                    segments: _segments,
                    projection: projection,
                    color: palette.accentInk,
                  ),
                ),
              ),
              if (_startVertex != null)
                _positionedMarker(
                  projection: projection,
                  point: _startVertex!,
                  size: MapStartRing.size,
                  child: const MapStartRing(),
                ),
              if (current != null)
                _positionedMarker(
                  projection: projection,
                  point: current,
                  size: widget.headingDeg == null
                      ? MapPositionDot.size
                      : MapHeadingArrow.box,
                  child: widget.headingDeg == null
                      ? const MapPositionDot()
                      : MapHeadingArrow(turns: _heading.turns),
                )
              else if (preview != null)
                _positionedMarker(
                  projection: projection,
                  point: preview,
                  size: MapPositionDot.size,
                  child: const MapPositionDot(),
                ),
              IgnorePointer(
                child: Align(
                  alignment: compact
                      ? const Alignment(0.9, -0.3)
                      : const Alignment(0.9, 0.04),
                  child: const MapNorthIndicator(),
                ),
              ),
              IgnorePointer(
                child: Align(
                  alignment: compact
                      ? const Alignment(-0.86, -0.3)
                      : const Alignment(-0.86, 0.2),
                  child: MapScaleBar(metersPerPixel: projection.metersPerPixel),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _positionedMarker({
    required MapProjection projection,
    required AmapLatLng point,
    required double size,
    required Widget child,
  }) {
    final Offset screen = projection.toScreen(
      point.latitude,
      point.longitude,
    );
    return Positioned(
      left: screen.dx - size / 2,
      top: screen.dy - size / 2,
      width: size,
      height: size,
      child: child,
    );
  }
}

/// 原生覆盖层的轨迹画笔：与 legacy 相同的描边 / 填充两遍绘制。
class _AmapRoutePainter extends CustomPainter {
  _AmapRoutePainter({
    required this.segments,
    required this.projection,
    required this.color,
  });

  final List<RouteSegment> segments;
  final MapProjection projection;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;
    final Paint casing = Paint()
      ..color = kRouteCasing
      ..style = PaintingStyle.stroke
      ..strokeWidth = kRouteStrokeWidth + kRouteCasingWidth * 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final Paint fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = kRouteStrokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // 先把所有描边画完，再画彩色线：段与段交叠时不会被别人的描边压住。
    for (final RouteSegment segment in segments) {
      final Path? path = _pathFor(segment);
      if (path != null) canvas.drawPath(path, casing);
    }
    for (final RouteSegment segment in segments) {
      final Path? path = _pathFor(segment);
      if (path != null) canvas.drawPath(path, fill);
    }
  }

  Path? _pathFor(RouteSegment segment) {
    if (segment.vertices.length < 2) return null;
    final Path path = Path();
    for (int i = 0; i < segment.vertices.length; i++) {
      final RouteVertex vertex = segment.vertices[i];
      final Offset point = projection.toScreen(vertex.lat, vertex.lon);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(_AmapRoutePainter old) =>
      old.segments != segments ||
      old.color != color ||
      old.projection.centerLat != projection.centerLat ||
      old.projection.centerLon != projection.centerLon ||
      old.projection.zoom != projection.zoom ||
      old.projection.viewportSize != projection.viewportSize;
}

/// 朝向累计转过的角度。359° → 1° 只累加 +2°，箭头沿最短弧转过去。
class _HeadingTurns {
  double _unwrappedDeg = 0;
  double? _lastHeadingDeg;

  void update(double? headingDeg) {
    if (headingDeg == null) return;
    final double? prev = _lastHeadingDeg;
    _unwrappedDeg = prev == null
        ? headingDeg
        : _unwrappedDeg + shortestArcDelta(prev, headingDeg);
    _lastHeadingDeg = headingDeg;
  }

  double get turns => _unwrappedDeg / 360;
}
