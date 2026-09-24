/// 一次骑行的汇总指标。冗余存储在 `rides` 表中，列表页与统计页直接读取。
class RideSummary {
  const RideSummary({
    required this.distanceM,
    required this.durationS,
    required this.movingS,
    required this.avgSpeedMps,
    required this.movingAvgSpeedMps,
    this.maxSpeedMps,
    required this.elevationGainM,
    this.avgHr,
    this.maxHr,
    this.avgCadence,
    this.avgPowerW,
    this.maxPowerW,
    this.calories,
    required this.pointCount,
  });

  final double distanceM;
  final int durationS;
  final int movingS;
  final double avgSpeedMps;
  final double movingAvgSpeedMps;

  /// 无速度数据时为 null。
  final double? maxSpeedMps;
  final double elevationGainM;

  /// 无心率数据时为 null。
  final double? avgHr;
  final int? maxHr;

  /// 无踏频数据时为 null。
  final double? avgCadence;

  /// 无功率数据时为 null。
  final double? avgPowerW;
  final int? maxPowerW;

  /// 无心率数据时无法估算，为 null。
  final double? calories;

  final int pointCount;

  Map<String, Object?> toDbColumns() => <String, Object?>{
        'distance_m': distanceM,
        'duration_s': durationS,
        'moving_s': movingS,
        'avg_speed_mps': avgSpeedMps,
        'moving_avg_speed_mps': movingAvgSpeedMps,
        'max_speed_mps': maxSpeedMps,
        'elevation_gain_m': elevationGainM,
        'avg_hr': avgHr,
        'max_hr': maxHr,
        'avg_cadence': avgCadence,
        'avg_power_w': avgPowerW,
        'max_power_w': maxPowerW,
        'calories': calories,
        'point_count': pointCount,
      };

  static RideSummary fromDbColumns(Map<String, Object?> m) => RideSummary(
        distanceM: (m['distance_m'] as num?)?.toDouble() ?? 0,
        durationS: (m['duration_s'] as num?)?.toInt() ?? 0,
        movingS: (m['moving_s'] as num?)?.toInt() ?? 0,
        avgSpeedMps: (m['avg_speed_mps'] as num?)?.toDouble() ?? 0,
        movingAvgSpeedMps: (m['moving_avg_speed_mps'] as num?)?.toDouble() ?? 0,
        maxSpeedMps: (m['max_speed_mps'] as num?)?.toDouble(),
        elevationGainM: (m['elevation_gain_m'] as num?)?.toDouble() ?? 0,
        avgHr: (m['avg_hr'] as num?)?.toDouble(),
        maxHr: (m['max_hr'] as num?)?.toInt(),
        avgCadence: (m['avg_cadence'] as num?)?.toDouble(),
        avgPowerW: (m['avg_power_w'] as num?)?.toDouble(),
        maxPowerW: (m['max_power_w'] as num?)?.toInt(),
        calories: (m['calories'] as num?)?.toDouble(),
        pointCount: (m['point_count'] as num?)?.toInt() ?? 0,
      );
}
