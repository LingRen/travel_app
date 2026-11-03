import 'dart:math' as math;

import 'package:amap_map/amap_map.dart' as amap;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:x_amap_base/x_amap_base.dart' as amap_base;

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/analysis/route_segments.dart';
import '../map/amap_basemap.dart';
import '../map/map_backend.dart';
import '../map/map_projection.dart';
import '../privacy/privacy_consent.dart';

/// 构造详情页原生底图。默认使用 [AmapBasemap]；widget 测试可换成纯 Flutter
/// 占位，避免在测试环境创建 platform view。
typedef DetailAmapBasemapBuilder =
    Widget Function(
      BuildContext context,
      amap.CameraPosition initialCamera,
      ValueChanged<amap.AMapController> onMapCreated,
      bool interactive,
      ValueChanged<amap.CameraPosition>? onCameraMove,
    );

/// 详情页顶部的着色轨迹地图。见设计文档 9.1 / 9.2。
///
/// 底图按 `mapBackendProvider` 在 legacy 栅格与高德原生之间选择；轨迹、起终点、
/// 断口端点与指北全部由 Flutter 覆盖层绘制，两套后端共用同一批顶点。
/// 喂进来的 [segments] 由 `buildRouteSegments` 算好并已单测覆盖。
class RouteMap extends ConsumerWidget {
  const RouteMap({
    required this.segments,
    required this.tileUrlTemplate,
    this.subdomains = const <String>[],
    this.gapEnds = const <LatLng>[],
    this.bridgedGaps = const <RouteGap>[],
    this.height = 260,
    this.amapBasemapBuilder,
    super.key,
  });

  final List<RouteSegment> segments;

  /// 瓦片源地址，来自设置（设计文档 9.1 的对冲措施：接口失效时可换源）。
  final String tileUrlTemplate;

  final List<String> subdomains;

  /// 信号中断断口两侧的定位点。
  ///
  /// 缺口两侧各画一个小圆点：线断在那里，但用户要知道那是信号丢了，不是记录
  /// 出了问题。不画连接线——断口之间的直线是假数据。
  final List<LatLng> gapEnds;

  /// 短缺口（10~30 秒没有定位）。用虚线跨过两端点，不画端点标记。
  ///
  /// 虚线表示「这里没有实测点」：既不让轨迹看着断掉，也不把估算路径画成实线。
  /// 超过 30 秒的缺口仍走 [gapEnds]，两侧留空。
  final List<RouteGap> bridgedGaps;

  final double height;

  /// 原生底图构造器，仅测试注入。
  final DetailAmapBasemapBuilder? amapBasemapBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<LatLng> all = <LatLng>[
      for (final RouteSegment s in segments)
        for (final RouteVertex v in s.vertices) LatLng(v.lat, v.lon),
    ];

    if (all.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            '没有可显示的轨迹',
            style: kLabelTextStyle.copyWith(color: context.palette.muted),
          ),
        ),
      );
    }

    // 起终点直接取首段首点与末段末点：断口会把一条轨迹切成多段，这样取才和
    // 画出来的线一致。不另外接收参数，避免两处取点口径分叉。
    final LatLng start = all.first;
    final LatLng finish = all.last;

    final Widget legacy = _LegacyBody(
      segments: segments,
      tileUrlTemplate: tileUrlTemplate,
      subdomains: subdomains,
      gapEnds: gapEnds,
      bridgedGaps: bridgedGaps,
      start: start,
      finish: finish,
    );

    final MapBackend backend = ref.watch(mapBackendProvider);
    final Widget body = backend == MapBackend.amap
        ? AmapPrivacyGate(
            fallback: legacy,
            child: _AmapBody(
              segments: segments,
              gapEnds: gapEnds,
              bridgedGaps: bridgedGaps,
              start: start,
              finish: finish,
              height: height,
              basemapBuilder: amapBasemapBuilder ?? _defaultBasemap,
            ),
          )
        : legacy;

    return SizedBox(height: height, child: body);
  }
}

Widget _defaultBasemap(
  BuildContext context,
  amap.CameraPosition initialCamera,
  ValueChanged<amap.AMapController> onMapCreated,
  bool interactive,
  ValueChanged<amap.CameraPosition>? onCameraMove,
) => AmapBasemap(
  initialCamera: initialCamera,
  onMapCreated: onMapCreated,
  interactive: interactive,
  onCameraMove: onCameraMove,
);

/// legacy 栅格底图体。无 Key、隐私未同意或强制回退时走这里，行为与迁移前一致。
class _LegacyBody extends StatelessWidget {
  const _LegacyBody({
    required this.segments,
    required this.tileUrlTemplate,
    required this.subdomains,
    required this.gapEnds,
    required this.bridgedGaps,
    required this.start,
    required this.finish,
  });

  final List<RouteSegment> segments;
  final String tileUrlTemplate;
  final List<String> subdomains;
  final List<LatLng> gapEnds;
  final List<RouteGap> bridgedGaps;
  final LatLng start;
  final LatLng finish;

  @override
  Widget build(BuildContext context) {
    // 轨迹统一跟随文字安全色：不再按速度分档着色（见 app/theme.dart）。
    final Color trackColor = context.palette.accentInk;
    final List<LatLng> all = <LatLng>[
      for (final RouteSegment s in segments)
        for (final RouteVertex v in s.vertices) LatLng(v.lat, v.lon),
    ];

    return FlutterMap(
      options: MapOptions(
        backgroundColor: context.palette.paper,
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(all),
          padding: const EdgeInsets.all(24),
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
        ),
      ),
      children: <Widget>[
        // 与记录页同一套纸本滤镜：降饱和 + 纸色薄罩，轨迹与断点不受影响。
        ColorFiltered(
          key: const Key('detail-map-color-filter'),
          colorFilter: ColorFilter.mode(
            context.palette.paper.withValues(alpha: 0.16),
            BlendMode.srcOver,
          ),
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix(kMapTileColorMatrix),
            child: TileLayer(
              urlTemplate: tileUrlTemplate,
              subdomains: subdomains,
              userAgentPackageName: 'com.ling.cycling_app',
            ),
          ),
        ),
        PolylineLayer(
          polylines: <Polyline<Object>>[
            for (final RouteSegment s in segments)
              Polyline<Object>(
                points: <LatLng>[
                  for (final RouteVertex v in s.vertices)
                    LatLng(v.lat, v.lon),
                ],
                strokeWidth: kRouteStrokeWidth,
                color: trackColor,
                // 描边让轨迹在黄白路面与深色底图上都立得住，见 [kRouteCasing]。
                borderStrokeWidth: kRouteCasingWidth,
                borderColor: kRouteCasing,
              ),
            // 短缺口：虚线跨过。画在实线之后，缺口两侧的线头会盖住虚线的端点，
            // 看起来是一条连续的虚线过渡，而不是两截断线。
            for (final RouteGap gap in bridgedGaps)
              Polyline<Object>(
                points: <LatLng>[
                  LatLng(gap.before.lat, gap.before.lon),
                  LatLng(gap.after.lat, gap.after.lon),
                ],
                strokeWidth: kRouteStrokeWidth,
                color: context.palette.warning,
                pattern: StrokePattern.dashed(
                  segments: const <double>[6, 5],
                ),
              ),
          ],
        ),
        const IgnorePointer(
          child: Align(
            alignment: Alignment(0.9, -0.82),
            child: _NorthBadge(),
          ),
        ),
        MarkerLayer(
          markers: <Marker>[
            // 断口端点先挂：起终点是这一程的锚点，重合时压在上面。
            for (final LatLng p in gapEnds)
              Marker(
                point: p,
                width: _GapEndDot.size,
                height: _GapEndDot.size,
                child: const _GapEndDot(),
              ),
            Marker(
              point: start,
              width: _StartMarker.size,
              height: _StartMarker.size,
              child: const _StartMarker(),
            ),
            Marker(
              point: finish,
              width: _FinishMarker.size,
              height: _FinishMarker.size,
              child: const _FinishMarker(),
            ),
          ],
        ),
      ],
    );
  }
}

/// 高德原生底图体：底图交给 SDK，覆盖层按相机投影逐帧重画。
///
/// 详情页允许拖动与缩放，因此相机完全由用户手势驱动，这里只在
/// `onCameraMove` 里同步覆盖层的投影中心与缩放。
class _AmapBody extends StatefulWidget {
  const _AmapBody({
    required this.segments,
    required this.gapEnds,
    required this.bridgedGaps,
    required this.start,
    required this.finish,
    required this.height,
    required this.basemapBuilder,
  });

  final List<RouteSegment> segments;
  final List<LatLng> gapEnds;
  final List<RouteGap> bridgedGaps;
  final LatLng start;
  final LatLng finish;
  final double height;
  final DetailAmapBasemapBuilder basemapBuilder;

  @override
  State<_AmapBody> createState() => _AmapBodyState();
}

class _AmapBodyState extends State<_AmapBody> {
  amap.CameraPosition? _camera;

  void _onCameraMove(amap.CameraPosition next) {
    setState(() => _camera = next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        final amap.CameraPosition camera = _camera ??= _fitCamera(size);
        final MapProjection projection = MapProjection(
          centerLat: camera.target.latitude,
          centerLon: camera.target.longitude,
          zoom: camera.zoom,
          viewportSize: size,
        );
        final AppPalette palette = context.palette;

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              widget.basemapBuilder(
                context,
                camera,
                (_) {},
                true,
                _onCameraMove,
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _AmapRoutePainter(
                            segments: widget.segments,
                            bridgedGaps: widget.bridgedGaps,
                            projection: projection,
                            trackColor: palette.accentInk,
                            warningColor: palette.warning,
                          ),
                        ),
                      ),
                      for (final LatLng p in widget.gapEnds)
                        _pin(
                          projection.toScreen(p.latitude, p.longitude),
                          _GapEndDot.size,
                          const _GapEndDot(),
                        ),
                      _pin(
                        projection.toScreen(
                          widget.start.latitude,
                          widget.start.longitude,
                        ),
                        _StartMarker.size,
                        const _StartMarker(),
                      ),
                      _pin(
                        projection.toScreen(
                          widget.finish.latitude,
                          widget.finish.longitude,
                        ),
                        _FinishMarker.size,
                        const _FinishMarker(),
                      ),
                      const Align(
                        alignment: Alignment(0.9, -0.82),
                        child: _NorthBadge(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 覆盖层用一个固定尺寸的盒子挂在投影点上，标记自身的绘制尺寸不变。
  Widget _pin(Offset center, double size, Widget child) => Positioned(
    left: center.dx - size / 2,
    top: center.dy - size / 2,
    width: size,
    height: size,
    child: child,
  );

  /// 按包围盒取景：从最大缩放向下找第一个能让所有顶点落进 24dp 内边距的级别。
  ///
  /// 与 legacy 的 `CameraFit.bounds` 同一口径；固定高度由外部传入，宽度来自
  /// `LayoutBuilder`，所以在这里算而不是在 `initState`。
  amap.CameraPosition _fitCamera(Size size) {
    final List<RouteVertex> vertices = <RouteVertex>[
      for (final RouteSegment s in widget.segments)
        for (final RouteVertex v in s.vertices) v,
    ];
    if (vertices.isEmpty) {
      return amap.CameraPosition(
        target: amap_base.LatLng(0, 0),
        zoom: 16,
      );
    }

    double minLat = vertices.first.lat;
    double maxLat = vertices.first.lat;
    double minLon = vertices.first.lon;
    double maxLon = vertices.first.lon;
    for (final RouteVertex v in vertices) {
      minLat = math.min(minLat, v.lat);
      maxLat = math.max(maxLat, v.lat);
      minLon = math.min(minLon, v.lon);
      maxLon = math.max(maxLon, v.lon);
    }

    final double centerLat = (minLat + maxLat) / 2;
    final double centerLon = (minLon + maxLon) / 2;
    const double padding = 24;
    for (double zoom = 18; zoom >= 2; zoom -= 0.25) {
      final MapProjection projection = MapProjection(
        centerLat: centerLat,
        centerLon: centerLon,
        zoom: zoom,
        viewportSize: size,
      );
      final bool fits = vertices.every((RouteVertex v) {
        final Offset point = projection.toScreen(v.lat, v.lon);
        return point.dx >= padding &&
            point.dx <= size.width - padding &&
            point.dy >= padding &&
            point.dy <= size.height - padding;
      });
      if (fits) {
        return amap.CameraPosition(
          target: amap_base.LatLng(centerLat, centerLon),
          zoom: zoom,
        );
      }
    }

    return amap.CameraPosition(
      target: amap_base.LatLng(centerLat, centerLon),
      zoom: 2,
    );
  }
}

/// 原生底图上的轨迹覆盖层。
///
/// 画法与 legacy 的 `PolylineLayer` 对齐：先描一圈纸墨色 casing，再画主题色
/// 实线；短缺口用 6/5 的虚线跨过。起终点与断口端点由 widget 叠在它上面。
class _AmapRoutePainter extends CustomPainter {
  _AmapRoutePainter({
    required this.segments,
    required this.bridgedGaps,
    required this.projection,
    required this.trackColor,
    required this.warningColor,
  });

  final List<RouteSegment> segments;
  final List<RouteGap> bridgedGaps;
  final MapProjection projection;
  final Color trackColor;
  final Color warningColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint casing = Paint()
      ..color = kRouteCasing
      ..strokeWidth = kRouteStrokeWidth + 2 * kRouteCasingWidth
      ..style = PaintingStyle.stroke;
    final Paint stroke = Paint()
      ..color = trackColor
      ..strokeWidth = kRouteStrokeWidth
      ..style = PaintingStyle.stroke;

    for (final RouteSegment segment in segments) {
      final Path path = Path();
      for (int i = 0; i < segment.vertices.length; i++) {
        final RouteVertex v = segment.vertices[i];
        final Offset point = projection.toScreen(v.lat, v.lon);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, casing);
      canvas.drawPath(path, stroke);
    }

    final Paint dashed = Paint()
      ..color = warningColor
      ..strokeWidth = kRouteStrokeWidth
      ..style = PaintingStyle.stroke;
    for (final RouteGap gap in bridgedGaps) {
      _drawDashed(
        canvas,
        dashed,
        projection.toScreen(gap.before.lat, gap.before.lon),
        projection.toScreen(gap.after.lat, gap.after.lon),
      );
    }
  }

  /// 6/5 的虚线：与 legacy `StrokePattern.dashed(segments: [6, 5])` 同参数。
  void _drawDashed(Canvas canvas, Paint paint, Offset from, Offset to) {
    const List<double> pattern = <double>[6, 5];
    final Offset delta = to - from;
    final double length = delta.distance;
    if (length <= 0) return;
    final Offset direction = delta / length;
    double traveled = 0;
    int index = 0;
    bool visible = true;
    while (traveled < length) {
      final double segment = math.min(pattern[index % pattern.length], length - traveled);
      if (visible) {
        canvas.drawLine(
          from + direction * traveled,
          from + direction * (traveled + segment),
          paint,
        );
      }
      traveled += segment;
      visible = !visible;
      index++;
    }
  }

  @override
  bool shouldRepaint(_AmapRoutePainter oldDelegate) =>
      oldDelegate.projection != projection ||
      oldDelegate.segments != segments ||
      oldDelegate.bridgedGaps != bridgedGaps ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.warningColor != warningColor;
}

/// 指北标识。详情地图不旋转，所以永远指北。
class _NorthBadge extends StatelessWidget {
  const _NorthBadge();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Container(
      key: const Key('detail-map-north'),
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.paper.withValues(alpha: 0.88),
        border: Border.all(color: palette.hairline),
      ),
      child: Text(
        '北',
        style: kLabelTextStyle.copyWith(
          fontSize: 10,
          letterSpacing: 0,
          color: palette.ink,
        ),
      ),
    );
  }
}

/// 断口端点：警告色空心环，不填充。
///
/// 原来用实心警告色圆点，加上起终点后两种「点」会混淆——实心块看起来像终点。
/// 空心环只表示「线在这里断了」，与实心的终点、空心的起点环都不撞。
class _GapEndDot extends StatelessWidget {
  const _GapEndDot();

  static const double size = 10;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('detail-gap-end'),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: context.palette.warning, width: 1.5),
    ),
  );
}

/// 起点：22 dp 主题色环，环内衬纸色圆底 +「起」。
///
/// 不能只画空心环：「起」是主题色，而轨迹也是主题色，标记又正落在轨迹端点上，
/// 字会整块融进线里（真机截图可见）。纸色圆底把轨迹压住，字才立得住；最外圈
/// 再留 2 dp 纸色边，环跨过轨迹时也不至于糊成一片。
class _StartMarker extends StatelessWidget {
  const _StartMarker();

  static const double size = 22;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Semantics(
      label: '起点',
      child: Container(
        key: const Key('detail-start-marker'),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, color: palette.paper),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: palette.accentInk, width: 2),
          ),
          child: Text(
            '起',
            style: TextStyle(
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w700,
              color: palette.accentInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// 终点：22 dp 主题色实心旗标 +「终」。
///
/// 画成旗而不是实心圆，是为了和「断口端点 / 起点环」这两种圆形标记分开：
/// 一眼就能认出哪头是收尾。
class _FinishMarker extends StatelessWidget {
  const _FinishMarker();

  static const double size = 22;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Semantics(
      label: '终点',
      child: SizedBox(
        key: const Key('detail-finish-marker'),
        width: size,
        height: size,
        child: Stack(
          children: <Widget>[
            // 旗杆。
            Positioned(
              left: 2.5,
              top: 2,
              bottom: 2,
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: palette.accentInk,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
            // 旗面。
            Positioned(
              left: 5,
              top: 2,
              child: Container(
                width: 15,
                height: 11,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.accentInk,
                  borderRadius: BorderRadius.circular(1.5),
                ),
                child: Text(
                  '终',
                  style: TextStyle(
                    fontSize: 8.5,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: palette.onAccent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
