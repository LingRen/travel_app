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
          if (gapEnds.isNotEmpty)
            MarkerLayer(
              markers: <Marker>[
                for (final LatLng p in gapEnds)
                  Marker(
                    point: p,
                    width: _GapEndDot.size,
                    height: _GapEndDot.size,
                    child: const _GapEndDot(),
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

/// 断口端点：一个小圆点，实心警告色 + 深色边。
///
/// 与轨迹的深色描边同源：底图明度不可控，浅色块自己也要带一圈边界。
class _GapEndDot extends StatelessWidget {
  const _GapEndDot();

  static const double size = 10;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: kAppWarning,
      border: Border.all(color: kRouteCasing, width: 1.5),
    ),
  );
}
