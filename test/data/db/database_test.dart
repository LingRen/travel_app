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
    final Set<String> names =
        tables.map((Map<String, Object?> r) => r['name'] as String).toSet();

    expect(names, containsAll(<String>['rides', 'track_points', 'settings']));
  });

  test('track_points 上有 (ride_id, t_ms) 索引', () async {
    final Database db = await openAppDatabase(path: inMemoryDatabasePath);
    addTearDown(db.close);

    final List<Map<String, Object?>> indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'track_points'",
    );
    final Set<String> names =
        indexes.map((Map<String, Object?> r) => r['name'] as String).toSet();

    expect(names, contains('idx_track_points_ride_t'));
  });

  test('删除 rides 行会级联删除 track_points', () async {
    final Database db = await openAppDatabase(path: inMemoryDatabasePath);
    addTearDown(db.close);

    final int rideId = await db.insert('rides', <String, Object?>{
      'started_at': 1000,
      'status': 'finished',
    });
    await db.insert('track_points', <String, Object?>{
      'ride_id': rideId,
      't_ms': 1000,
      'lat': 31.23,
      'lon': 121.47,
    });

    await db.delete('rides', where: 'id = ?', whereArgs: <Object?>[rideId]);

    expect(await db.query('track_points'), isEmpty);
  });
}
