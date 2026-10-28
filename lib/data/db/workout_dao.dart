import 'package:sqflite/sqflite.dart';

import '../../domain/models/activity_type.dart';
import '../../domain/models/workout.dart';
import '../../domain/models/workout_conditions.dart';
import '../../domain/models/workout_status.dart';
import '../../domain/models/workout_summary.dart';

/// `workouts` 表的读写。
class WorkoutDao {
  WorkoutDao(this._db);

  final DatabaseExecutor _db;

  /// 插入一行并返回新 id。进行中的运动汇总列全部为 NULL。
  Future<int> insert(Workout workout) async {
    final Map<String, Object?> row = workout.toDbMap()..remove('id');
    return _db.insert('workouts', row);
  }

  Future<Workout?> findById(int id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'workouts',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Workout.fromDbMap(rows.first);
  }

  /// 扫描未结束的运动，用于启动时的崩溃恢复。按开始时间倒序。
  Future<List<Workout>> findUnfinished() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'workouts',
      where: "status IN ('recording', 'paused')",
      orderBy: 'started_at DESC',
    );
    return rows.map(Workout.fromDbMap).toList();
  }

  /// 已完成的运动，按开始时间倒序。
  Future<List<Workout>> listFinished({
    int? limit,
    int? offset,
    ActivityType? activityType,
  }) async {
    final String where = activityType == null
        ? "status = 'finished'"
        : "status = 'finished' AND activity_type = ?";
    final List<Object?>? args = activityType == null
        ? null
        : <Object?>[activityType.dbValue];
    final List<Map<String, Object?>> rows = await _db.query(
      'workouts',
      where: where,
      whereArgs: args,
      orderBy: 'started_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Workout.fromDbMap).toList();
  }

  /// 指定时间区间内已完成的运动，按开始时间正序。区间为左闭右开。
  ///
  /// 统计页按周/月/年取数用；正序是为了让调用方直接按顺序落桶。
  Future<List<Workout>> listFinishedBetween({
    required int fromMs,
    required int toMs,
  }) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'workouts',
      where: "status = 'finished' AND started_at >= ? AND started_at < ?",
      whereArgs: <Object?>[fromMs, toMs],
      orderBy: 'started_at ASC',
    );
    return rows.map(Workout.fromDbMap).toList();
  }

  /// 已完成的运动条数。备份的 manifest.json 里要写这个数字。
  Future<int> countFinished() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      "SELECT COUNT(*) AS c FROM workouts WHERE status = 'finished'",
    );
    return (rows.first['c'] as num).toInt();
  }

  /// 带上 id 插入，供备份恢复还原原始 id。
  ///
  /// 与 [insert] 的区别是不剥掉 `id` 列，因此 `track_points.ride_id` 的外键
  /// 关系能原样重建。
  Future<void> insertWithId(Workout workout) async {
    await _db.insert('workouts', workout.toDbMap());
  }

  /// 清空 workouts 表。恢复备份前调用，语义是「替换成备份里的状态」。
  Future<void> deleteAll() async {
    await _db.delete('workouts');
  }

  Future<void> markFinished({
    required int id,
    required int endedAtMs,
    required WorkoutSummary summary,
  }) async {
    await _db.update(
      'workouts',
      <String, Object?>{
        'ended_at': endedAtMs,
        'status': WorkoutStatus.finished.dbValue,
        ...summary.toDbColumns(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> updateStatus(int id, WorkoutStatus status) async {
    await _db.update(
      'workouts',
      <String, Object?>{'status': status.dbValue},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> updateTitle(int id, String? title) async {
    await _db.update(
      'workouts',
      <String, Object?>{'title': title},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 写入开始时捕获的地点 / 天气。
  ///
  /// 只更新有值的列：地点和天气是两个独立请求，任何一边失败都不该把另一边
  /// 已经写好的值擦成 null。全部为空时直接返回。
  Future<void> updateConditions(int id, WorkoutConditions conditions) async {
    final Map<String, Object?> values = <String, Object?>{
      if (conditions.placeName != null) 'place_name': conditions.placeName,
      if (conditions.placeShort != null) 'place_short': conditions.placeShort,
      if (conditions.weatherText != null) 'weather_text': conditions.weatherText,
      if (conditions.weatherTempC != null)
        'weather_temp_c': conditions.weatherTempC,
    };
    if (values.isEmpty) return;
    await _db.update(
      'workouts',
      values,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> delete(int id) async {
    await _db.delete('workouts', where: 'id = ?', whereArgs: <Object?>[id]);
  }
}
