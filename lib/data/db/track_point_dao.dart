import 'package:sqflite/sqflite.dart';

import '../../domain/models/track_point.dart';

/// `track_points` 表的读写。
class TrackPointDao {
  TrackPointDao(this._db);

  final Database _db;

  /// 一个事务内批量插入。空列表直接返回，不开启事务。
  Future<void> insertBatch(List<TrackPoint> points) async {
    if (points.isEmpty) return;
    final Batch batch = _db.batch();
    for (final TrackPoint p in points) {
      final Map<String, Object?> row = p.toDbMap()..remove('id');
      batch.insert('track_points', row);
    }
    await batch.commit(noResult: true);
  }

  Future<List<TrackPoint>> listByRide(int rideId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'track_points',
      where: 'ride_id = ?',
      whereArgs: <Object?>[rideId],
      orderBy: 't_ms ASC',
    );
    return rows.map(TrackPoint.fromDbMap).toList();
  }

  Future<int> countByRide(int rideId) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM track_points WHERE ride_id = ?',
      <Object?>[rideId],
    );
    return (rows.first['c'] as num).toInt();
  }

  Future<TrackPoint?> lastByRide(int rideId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'track_points',
      where: 'ride_id = ?',
      whereArgs: <Object?>[rideId],
      orderBy: 't_ms DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : TrackPoint.fromDbMap(rows.first);
  }

  Future<void> deleteByRide(int rideId) async {
    await _db.delete('track_points', where: 'ride_id = ?', whereArgs: <Object?>[rideId]);
  }
}
