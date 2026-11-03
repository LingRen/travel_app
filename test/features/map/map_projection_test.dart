import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:cycling_app/features/map/map_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const Size viewport = Size(360, 640);
  const MapProjection projection = MapProjection(
    centerLat: 30.0,
    centerLon: 120.0,
    zoom: 16,
    viewportSize: viewport,
  );

  group('Web Mercator 屏幕投影', () {
    test('中心点落在视口正中', () {
      expect(projection.toScreen(30.0, 120.0), const Offset(180, 320));
    });

    test('北在上、南在下', () {
      final Offset north = projection.toScreen(30.001, 120.0);
      final Offset south = projection.toScreen(29.999, 120.0);
      expect(north.dx, closeTo(180, 1e-6));
      expect(north.dy, lessThan(320));
      expect(south.dy, greaterThan(320));
    });

    test('东在右、西在左', () {
      final Offset east = projection.toScreen(30.0, 120.001);
      final Offset west = projection.toScreen(30.0, 119.999);
      expect(east.dy, closeTo(320, 1e-6));
      expect(east.dx, greaterThan(180));
      expect(west.dx, lessThan(180));
    });

    test('缩放每加一级，同一段距离在屏幕上翻倍', () {
      final Offset base = projection.toScreen(30.001, 120.0);
      const MapProjection zoomed = MapProjection(
        centerLat: 30.0,
        centerLon: 120.0,
        zoom: 17,
        viewportSize: viewport,
      );
      final Offset next = zoomed.toScreen(30.001, 120.0);
      expect(next.dy - 320, closeTo((base.dy - 320) * 2, 1e-6));
    });
  });

  group('米/像素', () {
    test('赤道、zoom 0 时约等于一个世界像素', () {
      // 40075016.686 / 256 ≈ 156543.03 m/px。
      expect(
        MapProjection.metersPerPixelAt(lat: 0, zoom: 0),
        closeTo(156543.03, 0.01),
      );
    });

    test('纬度越高，同样的屏幕距离代表的米数越少', () {
      final double equator = MapProjection.metersPerPixelAt(lat: 0, zoom: 16);
      final double mid = MapProjection.metersPerPixelAt(lat: 30, zoom: 16);
      final double high = MapProjection.metersPerPixelAt(lat: 60, zoom: 16);
      expect(mid, lessThan(equator));
      expect(high, lessThan(mid));
      // cos(60°) = 0.5，高纬度的米/像素正好是赤道的一半。
      expect(high, closeTo(equator * 0.5, 1e-9));
    });

    test('缩放每加一级，米/像素减半', () {
      final double z16 = MapProjection.metersPerPixelAt(lat: 30, zoom: 16);
      final double z17 = MapProjection.metersPerPixelAt(lat: 30, zoom: 17);
      expect(z17, closeTo(z16 / 2, 1e-9));
      expect(projection.metersPerPixel, closeTo(z16, 1e-9));
    });

    test('与既有比例尺公式同源', () {
      const double equatorMeters = 40075016.686;
      final double latRad = 30 * math.pi / 180;
      final double expected =
          equatorMeters * math.cos(latRad) / (256 * math.pow(2, 16));
      expect(
        MapProjection.metersPerPixelAt(lat: 30, zoom: 16),
        closeTo(expected, 1e-9),
      );
    });
  });
}
