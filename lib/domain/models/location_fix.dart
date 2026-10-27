/// 一次定位结果。字段全部可空，因为 GPS 丢失时可能只有时间戳。
class LocationFix {
  const LocationFix({
    required this.tMs,
    this.lat,
    this.lon,
    this.altitudeM,
    this.speedMps,
    this.accuracyM,
    this.headingDeg,
  });

  final int tMs;
  final double? lat;
  final double? lon;
  final double? altitudeM;
  final double? speedMps;
  final double? accuracyM;

  /// 运动方向（度，0 为正北，顺时针）。
  ///
  /// **只在内存里用于实时显示**：不进 `TrackPoint`、不进数据库、不进 GPX
  /// （ADR-0002）。设备没给方向时为 null。
  final double? headingDeg;

  bool get hasPosition => lat != null && lon != null;
}
