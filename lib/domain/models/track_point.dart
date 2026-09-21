/// 轨迹点与传感器采样的合并行，对应 `track_points` 表。
///
/// `lat`/`lon` 可空：GPS 丢失时仍记录心率与踏频，这类点只画曲线不上地图。
class TrackPoint {
  const TrackPoint({
    this.id,
    required this.rideId,
    required this.tMs,
    this.lat,
    this.lon,
    this.altitudeM,
    this.speedMps,
    this.accuracyM,
    this.hr,
    this.cadence,
  });

  final int? id;
  final int rideId;
  final int tMs;
  final double? lat;
  final double? lon;
  final double? altitudeM;
  final double? speedMps;
  final double? accuracyM;
  final int? hr;
  final int? cadence;

  bool get hasPosition => lat != null && lon != null;

  Map<String, Object?> toDbMap() => <String, Object?>{
        if (id != null) 'id': id,
        'ride_id': rideId,
        't_ms': tMs,
        'lat': lat,
        'lon': lon,
        'altitude_m': altitudeM,
        'speed_mps': speedMps,
        'accuracy_m': accuracyM,
        'hr': hr,
        'cadence': cadence,
      };

  static TrackPoint fromDbMap(Map<String, Object?> m) => TrackPoint(
        id: (m['id'] as num?)?.toInt(),
        rideId: (m['ride_id'] as num).toInt(),
        tMs: (m['t_ms'] as num).toInt(),
        lat: (m['lat'] as num?)?.toDouble(),
        lon: (m['lon'] as num?)?.toDouble(),
        altitudeM: (m['altitude_m'] as num?)?.toDouble(),
        speedMps: (m['speed_mps'] as num?)?.toDouble(),
        accuracyM: (m['accuracy_m'] as num?)?.toDouble(),
        hr: (m['hr'] as num?)?.toInt(),
        cadence: (m['cadence'] as num?)?.toInt(),
      );
}
