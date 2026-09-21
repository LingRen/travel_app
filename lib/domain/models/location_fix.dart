/// 一次定位结果。字段全部可空，因为 GPS 丢失时可能只有时间戳。
class LocationFix {
  const LocationFix({
    required this.tMs,
    this.lat,
    this.lon,
    this.altitudeM,
    this.speedMps,
    this.accuracyM,
  });

  final int tMs;
  final double? lat;
  final double? lon;
  final double? altitudeM;
  final double? speedMps;
  final double? accuracyM;

  bool get hasPosition => lat != null && lon != null;
}
