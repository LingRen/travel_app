import 'package:sqflite/sqflite.dart';

import '../../domain/models/track_point.dart';
import '../../domain/models/workout.dart';
import '../db/track_point_dao.dart';
import '../db/workout_dao.dart';
import 'backup.dart';

/// 备份数据的读写。抽成接口是为了让设置页的 widget 测试不必碰真实数据库。
abstract class BackupStore {
  /// 全部已完成的运动。
  Future<List<Workout>> listWorkouts();

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
  Future<List<Workout>> listWorkouts() => WorkoutDao(_db).listFinished();

  @override
  Future<List<TrackPoint>> listPoints() => TrackPointDao(_db).listAll();

  @override
  Future<void> apply(
    BackupPayload payload, {
    required bool replaceExisting,
  }) =>
      applyBackup(payload, db: _db, replaceExisting: replaceExisting);
}
