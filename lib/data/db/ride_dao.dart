import 'package:sqflite/sqflite.dart';

import '../../domain/models/ride.dart';
import '../../domain/models/ride_status.dart';
import '../../domain/models/ride_summary.dart';

/// `rides` 表的读写。
class RideDao {
  RideDao(this._db);

  final Database _db;

  /// 插入一行并返回新 id。进行中的骑行汇总列全部为 NULL。
  Future<int> insert(Ride ride) async {
    final Map<String, Object?> row = ride.toDbMap()..remove('id');
    return _db.insert('rides', row);
  }

  Future<Ride?> findById(int id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'rides',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Ride.fromDbMap(rows.first);
  }

  /// 扫描未结束的骑行，用于启动时的崩溃恢复。按开始时间倒序。
  Future<List<Ride>> findUnfinished() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'rides',
      where: "status IN ('recording', 'paused')",
      orderBy: 'started_at DESC',
    );
    return rows.map(Ride.fromDbMap).toList();
  }

  /// 已完成的骑行，按开始时间倒序。
  Future<List<Ride>> listFinished({int? limit, int? offset}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'rides',
      where: "status = 'finished'",
      orderBy: 'started_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Ride.fromDbMap).toList();
  }

  Future<void> markFinished({
    required int id,
    required int endedAtMs,
    required RideSummary summary,
  }) async {
    await _db.update(
      'rides',
      <String, Object?>{
        'ended_at': endedAtMs,
        'status': RideStatus.finished.dbValue,
        ...summary.toDbColumns(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> updateStatus(int id, RideStatus status) async {
    await _db.update(
      'rides',
      <String, Object?>{'status': status.dbValue},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> updateTitle(int id, String? title) async {
    await _db.update(
      'rides',
      <String, Object?>{'title': title},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> delete(int id) async {
    await _db.delete('rides', where: 'id = ?', whereArgs: <Object?>[id]);
  }
}
