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

  /// 指定时间区间内已完成的骑行，按开始时间正序。区间为左闭右开。
  ///
  /// 统计页按周/月/年取数用；正序是为了让调用方直接按顺序落桶。
  Future<List<Ride>> listFinishedBetween({
    required int fromMs,
    required int toMs,
  }) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'rides',
      where: "status = 'finished' AND started_at >= ? AND started_at < ?",
      whereArgs: <Object?>[fromMs, toMs],
      orderBy: 'started_at ASC',
    );
    return rows.map(Ride.fromDbMap).toList();
  }

  /// 已完成的骑行条数。备份的 manifest.json 里要写这个数字。
  Future<int> countFinished() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      "SELECT COUNT(*) AS c FROM rides WHERE status = 'finished'",
    );
    return (rows.first['c'] as num).toInt();
  }

  /// 带上 id 插入，供备份恢复还原原始 id。
  ///
  /// 与 [insert] 的区别是不剥掉 `id` 列，因此 `track_points.ride_id` 的外键
  /// 关系能原样重建。
  Future<void> insertWithId(Ride ride) async {
    await _db.insert('rides', ride.toDbMap());
  }

  /// 清空 rides 表。恢复备份前调用，语义是「替换成备份里的状态」。
  Future<void> deleteAll() async {
    await _db.delete('rides');
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
