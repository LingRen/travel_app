import 'package:xml/xml.dart';

import '../../domain/analysis/constants.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';

/// GPX 1.1 命名空间。
const String kGpxNamespace = 'http://www.topografix.com/GPX/1/1';

/// Garmin 轨迹点扩展命名空间。心率与踏频必须放在这里，第三方平台才认。
const String kGpxTpxNamespace =
    'http://www.garmin.com/xmlschemas/TrackPointExtension/v1';

/// GPX 文件里的 creator 标识。
const String kGpxCreator = 'cycling_app';

/// 生成 GPX 1.1 文本。见设计文档 12。
///
/// **坐标一律用落盘的 WGS-84 原始值**，不做 GCJ-02 转换：那个转换只服务地图
/// 显示（见 `domain/analysis/gcj02.dart`），导给 Strava 的必须是标准坐标。
///
/// 没有坐标的点（GPS 丢失时只有心率/踏频）不输出：`trkpt` 的 lat/lon 是必需
/// 属性。时间间隔超过 [kGpsGapMs] 或时间不前进处拆成新的 `trkseg`，
/// 否则第三方平台会画出一条横穿隧道的假直线（设计文档 9.3）。
String buildGpx({required Ride ride, required List<TrackPoint> points}) {
  final String name = _trackName(ride);
  final List<List<TrackPoint>> segments = _splitSegments(
    points.where((TrackPoint p) => p.hasPosition).toList(),
  );

  final XmlBuilder builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element(
    'gpx',
    attributes: <String, String>{
      'version': '1.1',
      'creator': kGpxCreator,
      'xmlns': kGpxNamespace,
      'xmlns:gpxtpx': kGpxTpxNamespace,
    },
    nest: () {
      builder.element('metadata', nest: () {
        builder.element('name', nest: name);
        builder.element('time', nest: _isoUtc(ride.startedAtMs));
      });

      builder.element('trk', nest: () {
        builder.element('name', nest: name);
        builder.element('type', nest: 'cycling');

        if (segments.isEmpty) {
          // 没有可用点时也留一个空 trkseg，保证结构一致、可被解析。
          builder.element('trkseg');
          return;
        }
        for (final List<TrackPoint> segment in segments) {
          builder.element('trkseg', nest: () {
            for (final TrackPoint p in segment) {
              _writeTrackPoint(builder, p);
            }
          });
        }
      });
    },
  );

  return builder.buildDocument().toXmlString(pretty: true);
}

void _writeTrackPoint(XmlBuilder builder, TrackPoint p) {
  builder.element(
    'trkpt',
    attributes: <String, String>{
      'lat': p.lat!.toStringAsFixed(6),
      'lon': p.lon!.toStringAsFixed(6),
    },
    nest: () {
      final double? altitude = p.altitudeM;
      if (altitude != null) {
        builder.element('ele', nest: altitude.toStringAsFixed(2));
      }
      builder.element('time', nest: _isoUtc(p.tMs));

      final int? hr = p.hr;
      final int? cadence = p.cadence;
      if (hr == null && cadence == null) return;

      builder.element('extensions', nest: () {
        builder.element('gpxtpx:TrackPointExtension', nest: () {
          if (hr != null) builder.element('gpxtpx:hr', nest: '$hr');
          if (cadence != null) builder.element('gpxtpx:cad', nest: '$cadence');
        });
      });
    },
  );
}

/// 按 GPS 断点把点拆成若干段。首点自成一段的开头。
List<List<TrackPoint>> _splitSegments(List<TrackPoint> located) {
  final List<List<TrackPoint>> segments = <List<TrackPoint>>[];
  List<TrackPoint>? current;
  int? prevTMs;

  for (final TrackPoint p in located) {
    final int? prev = prevTMs;
    final bool needNew = current == null ||
        prev == null ||
        p.tMs - prev <= 0 ||
        p.tMs - prev > kGpsGapMs;
    if (needNew) {
      current = <TrackPoint>[];
      segments.add(current);
    }
    current.add(p);
    prevTMs = p.tMs;
  }

  return segments;
}

String _trackName(Ride ride) {
  final String title = ride.title?.trim() ?? '';
  if (title.isNotEmpty) return title;
  final DateTime start = DateTime.fromMillisecondsSinceEpoch(ride.startedAtMs);
  return '骑行 ${start.year}-${_two(start.month)}-${_two(start.day)}';
}

String _isoUtc(int epochMs) =>
    DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true).toIso8601String();

String _two(int value) => value.toString().padLeft(2, '0');
