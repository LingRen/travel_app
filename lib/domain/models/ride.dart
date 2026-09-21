import 'ride_status.dart';
import 'ride_summary.dart';

/// 一次骑行，对应 `rides` 表的一行。
class Ride {
  const Ride({
    this.id,
    required this.startedAtMs,
    this.endedAtMs,
    required this.status,
    this.title,
    this.summary,
    this.hrDeviceName,
    this.cadenceDeviceName,
  });

  final int? id;
  final int startedAtMs;
  final int? endedAtMs;
  final RideStatus status;
  final String? title;

  /// 进行中的骑行为 null。
  final RideSummary? summary;
  final String? hrDeviceName;
  final String? cadenceDeviceName;

  Map<String, Object?> toDbMap() => <String, Object?>{
        if (id != null) 'id': id,
        'started_at': startedAtMs,
        'ended_at': endedAtMs,
        'status': status.dbValue,
        'title': title,
        'hr_device_name': hrDeviceName,
        'cadence_device_name': cadenceDeviceName,
        if (summary != null) ...summary!.toDbColumns(),
      };

  static Ride fromDbMap(Map<String, Object?> m) => Ride(
        id: (m['id'] as num?)?.toInt(),
        startedAtMs: (m['started_at'] as num).toInt(),
        endedAtMs: (m['ended_at'] as num?)?.toInt(),
        status: RideStatus.fromDb(m['status'] as String),
        title: m['title'] as String?,
        summary: m['distance_m'] == null ? null : RideSummary.fromDbColumns(m),
        hrDeviceName: m['hr_device_name'] as String?,
        cadenceDeviceName: m['cadence_device_name'] as String?,
      );
}
