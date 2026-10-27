import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';
import '../../domain/analysis/route_segments.dart';

/// 详情页顶部的着色轨迹地图。见设计文档 9.1 / 9.2。
///
/// 渲染本身不做自动化测试（设计文档 13 把「地图渲染」列为手动验证项）；
/// 喂进来的 [segments] 由 `buildRouteSegments` 算好并已单测覆盖。
class RouteMap extends StatelessWidget {
  const RouteMap({
    required this.segments,
    required this.tileUrlTemplate,
    this.subdomains = const <String>[],
    this.gapEnds = const <LatLng>[],
    this.height = 260,
    super.key,
  });

  final List<RouteSegment> segments;

  /// 瓦片源地址，来自设置（设计文档 9.1 的对冲措施：接口失效时可换源）。
  final String tileUrlTemplate;

  final List<String> subdomains;

  /// 信号中断断口两侧的定位点（已按瓦片源转换）。
  ///
  /// 缺口两侧各画一个小圆点：线断在那里，但用户要知道那是信号丢了，不是记录
  /// 出了问题。不画连接线——断口之间的直线是假数据。
  final List<LatLng> gapEnds;

  final double height;

  @override
  Widget build(BuildContext context) {
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

    // 轨迹统一跟随文字安全色：不再按速度分档着色（见 app/theme.dart）。
    final Color trackColor = context.palette.accentInk;

    // 起终点直接取首段首点与末段末点：断口会把一条轨迹切成多段，这样取才和
    // 画出来的线一致。不另外接收参数，避免两处取点口径分叉。
    final LatLng start = all.first;
    final LatLng finish = all.last;

    return SizedBox(
      height: height,
      child: FlutterMap(
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
      ),
    );
  }
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

/// 起点：18 dp 主题色空心环 +「起」。
class _StartMarker extends StatelessWidget {
  const _StartMarker();

  static const double size = 18;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Semantics(
      label: '起点',
      child: Container(
        key: const Key('detail-start-marker'),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: palette.accentInk, width: 2),
        ),
        child: Text(
          '起',
          style: TextStyle(
            fontSize: 9,
            height: 1,
            fontWeight: FontWeight.w700,
            color: palette.accentInk,
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
