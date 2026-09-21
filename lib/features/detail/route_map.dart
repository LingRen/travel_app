import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
    this.height = 260,
    super.key,
  });

  final List<RouteSegment> segments;

  /// 瓦片源地址，来自设置（设计文档 9.1 的对冲措施：接口失效时可换源）。
  final String tileUrlTemplate;

  final List<String> subdomains;
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
        child: const Center(child: Text('这次骑行没有可显示的轨迹')),
      );
    }

    return SizedBox(
      height: height,
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(all),
            padding: const EdgeInsets.all(24),
          ),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
          ),
        ),
        children: <Widget>[
          TileLayer(
            urlTemplate: tileUrlTemplate,
            subdomains: subdomains,
            userAgentPackageName: 'com.ling.cycling_app',
          ),
          PolylineLayer(
            polylines: <Polyline<Object>>[
              for (final RouteSegment s in segments)
                Polyline<Object>(
                  points: <LatLng>[
                    for (final RouteVertex v in s.vertices) LatLng(v.lat, v.lon),
                  ],
                  strokeWidth: 4,
                  color: Color(s.colorArgb),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
