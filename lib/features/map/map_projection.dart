import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// Web Mercator（EPSG:3857）屏幕投影。
///
/// 高德原生底图使用 GCJ-02 的 Web Mercator 瓦片；轨迹与标记仍由 Flutter
/// 覆盖层绘制，需要把同一批 GCJ-02 顶点投影到屏幕，才能与底图道路对齐。
///
/// 口径与 `flutter_map` 的 legacy 路径一致：世界坐标以 [tileSize]（默认 256）
/// 像素的瓦片为基准，缩放级别每加 1，世界像素翻倍。只做平移缩放，不处理旋转
/// 与倾斜——应用里的地图始终北向上。
///
/// 纯函数、不依赖 Flutter 渲染对象，供两套地图体与单测共用。
class MapProjection {
  const MapProjection({
    required this.centerLat,
    required this.centerLon,
    required this.zoom,
    required this.viewportSize,
    this.tileSize = 256,
  });

  /// 视口中心对应的纬度（GCJ-02）。
  final double centerLat;

  /// 视口中心对应的经度（GCJ-02）。
  final double centerLon;

  /// 缩放级别（与高德 / OSM 的 zoom 口径一致）。
  final double zoom;

  /// 视口尺寸（逻辑像素）。
  final Size viewportSize;

  /// 瓦片边长（逻辑像素）。高德与 flutter_map 都用 256。
  final double tileSize;

  double get _scale => math.pow(2, zoom).toDouble();

  /// 把经纬度投影到视口坐标。中心点落在 [Offset(viewportWidth/2, viewportHeight/2)]，
  /// 北在上、东在右。
  Offset toScreen(double lat, double lon) {
    final Offset center = _world(centerLat, centerLon);
    final Offset point = _world(lat, lon);
    return Offset(
      viewportSize.width / 2 + point.dx - center.dx,
      viewportSize.height / 2 + point.dy - center.dy,
    );
  }

  /// 当前视口中心每像素代表的米数。比例尺与覆盖层都用它。
  double get metersPerPixel => metersPerPixelAt(
    lat: centerLat,
    zoom: zoom,
    tileSize: tileSize,
  );

  /// Web Mercator 下每像素代表的米数。
  ///
  /// 与记录页比例尺的既有公式完全一致（`_MapScaleBar._metersPerPixel`），
  /// 避免两套口径算出不同的比例尺。
  static double metersPerPixelAt({
    required double lat,
    required double zoom,
    double tileSize = 256,
  }) {
    const double equatorMeters = 40075016.686;
    final double latRad = lat * math.pi / 180;
    final double scale = math.pow(2, zoom).toDouble();
    return equatorMeters * math.cos(latRad) / (tileSize * scale);
  }

  Offset _world(double lat, double lon) {
    final double x = (lon + 180) / 360 * tileSize * _scale;
    // Web Mercator 在南北极收敛；夹到标准上限，避免 tan/log 溢出。
    final double clampedLat = lat.clamp(-85.05112878, 85.05112878);
    final double latRad = clampedLat * math.pi / 180;
    final double mercatorY = math.log(
      math.tan(math.pi / 4 + latRad / 2),
    );
    final double y = (1 - mercatorY / math.pi) / 2 * tileSize * _scale;
    return Offset(x, y);
  }
}
