import 'dart:io';

import 'package:cycling_app/data/db/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('建表后三张表都存在', () async {
    final Database db = await openAppDatabase(path: inMemoryDatabasePath);
    addTearDown(db.close);

    final List<Map<String, Object?>> tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
    );
    final Set<String> names = tables
        .map((Map<String, Object?> r) => r['name'] as String)
        .toSet();

    expect(
      names,
      containsAll(<String>['workouts', 'track_points', 'settings']),
    );
  });

  test('track_points 上有 (ride_id, t_ms) 索引', () async {
    final Database db = await openAppDatabase(path: inMemoryDatabasePath);
    addTearDown(db.close);

    final List<Map<String, Object?>> indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'track_points'",
    );
    final Set<String> names = indexes
        .map((Map<String, Object?> r) => r['name'] as String)
        .toSet();

    expect(names, contains('idx_track_points_ride_t'));
  });

  test('删除 workouts 行会级联删除 track_points', () async {
    final Database db = await openAppDatabase(path: inMemoryDatabasePath);
    addTearDown(db.close);

    final int rideId = await db.insert('workouts', <String, Object?>{
      'started_at': 1000,
      'status': 'finished',
    });
    await db.insert('track_points', <String, Object?>{
      'ride_id': rideId,
      't_ms': 1000,
      'lat': 31.23,
      'lon': 121.47,
    });

    await db.delete('workouts', where: 'id = ?', whereArgs: <Object?>[rideId]);

    expect(await db.query('track_points'), isEmpty);
  });

  test('v2 → v3 迁移：rides 改名 workouts 并补 activity_type 默认骑行', () async {
    // 手工建一个 v2 库（老 schema 的 rides 表），再用 onUpgrade 路径升级。
    final String path =
        '${Directory.systemTemp.path}/migrate_v2_v3_${DateTime.now().microsecondsSinceEpoch}.db';
    final Database v2 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE rides (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              started_at INTEGER NOT NULL,
              status TEXT NOT NULL,
              title TEXT,
              distance_m REAL
            )
          ''');
          await db.execute('''
            CREATE TABLE track_points (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              ride_id INTEGER NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
              t_ms INTEGER NOT NULL
            )
          ''');
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    await v2.insert('rides', <String, Object?>{
      'started_at': 1000,
      'status': 'finished',
    });
    await v2.close();

    // 用同一路径重开 → 触发 onUpgrade 到当前版本。
    final Database v3 = await openAppDatabase(path: path);
    addTearDown(() async {
      await v3.close();
      await File(path).delete();
    });

    final List<Map<String, Object?>> rows = await v3.query('workouts');
    expect(rows.single['activity_type'], 'cycling');
    expect(rows.single['started_at'], 1000);

    // 迁移后外键仍指向改名后的 workouts：插入引用行不应抛错。
    final int rideId = rows.single['id'] as int;
    await v3.insert('track_points', <String, Object?>{
      'ride_id': rideId,
      't_ms': 2000,
    });
  });

  test('v1 → v3 直接升级：先补功率列再改名加类型列', () async {
    // 手工建一个 v1 库（rides / track_points 均无功率列），再用 onUpgrade 路径
    // 一路升到 v3，验证 v1→v2 与 v2→v3 两个分支按顺序执行。
    final String path =
        '${Directory.systemTemp.path}/migrate_v1_v3_${DateTime.now().microsecondsSinceEpoch}.db';
    final Database v1 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE rides (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              started_at INTEGER NOT NULL,
              status TEXT NOT NULL,
              title TEXT,
              distance_m REAL
            )
          ''');
          await db.execute('''
            CREATE TABLE track_points (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              ride_id INTEGER NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
              t_ms INTEGER NOT NULL,
              lat REAL,
              lon REAL
            )
          ''');
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    await v1.insert('rides', <String, Object?>{
      'started_at': 1000,
      'status': 'finished',
    });
    await v1.close();

    // 用同一路径重开 → 触发 onUpgrade 从 v1 升到当前版本。
    final Database v3 = await openAppDatabase(path: path);
    addTearDown(() async {
      await v3.close();
      await File(path).delete();
    });

    // 表名已改、activity_type 回填为骑行、原数据保留。
    final List<Map<String, Object?>> rows = await v3.query('workouts');
    expect(rows.single['activity_type'], 'cycling');
    expect(rows.single['started_at'], 1000);

    // 先执行了 v1→v2 分支（补功率列），再执行 v2→v3 分支（改名）。
    final List<Map<String, Object?>> trackCols = await v3.rawQuery(
      'PRAGMA table_info(track_points)',
    );
    final Set<String> colNames = trackCols
        .map((Map<String, Object?> r) => r['name'] as String)
        .toSet();
    expect(colNames, contains('power_w'));
  });
}
