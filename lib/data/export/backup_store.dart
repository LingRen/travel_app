import 'package:sqflite/sqflite.dart';

import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';
import '../db/ride_dao.dart';
import '../db/track_point_dao.dart';
import 'backup.dart';

/// 备份数据的读写。抽成接口是为了让设置页的 widget 测试不必碰真实数据库。
abstract class BackupStore {
  /// 全部已完成的骑行。
  Future<List<Ride>> listRides();

  /// 全部轨迹点。
  Future<List<TrackPoint>> listPoints();

  /// 把备份写回数据库。
  Future<void> apply(BackupPayload payload, {required bool replaceExisting});
}

/// 生产实现：直接读写本地 SQLite。
class SqliteBackupStore implements BackupStore {
  SqliteBackupStore(this._db);

  final Database _db;

  @override
  Future<List<Ride>> listRides() => RideDao(_db).listFinished();

  @override
  Future<List<TrackPoint>> listPoints() => TrackPointDao(_db).listAll();

  @override
  Future<void> apply(
    BackupPayload payload, {
    required bool replaceExisting,
  }) =>
      applyBackup(payload, db: _db, replaceExisting: replaceExisting);
}
