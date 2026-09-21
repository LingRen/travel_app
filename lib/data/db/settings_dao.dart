import 'package:sqflite/sqflite.dart';

/// `settings` 表的键值读写。
class SettingsDao {
  SettingsDao(this._db);

  final Database _db;

  Future<String?> getString(String key) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'settings',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setString(String key, String value) async {
    await _db.insert(
      'settings',
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 删除一个键。键不存在时静默返回。
  Future<void> remove(String key) async {
    await _db.delete('settings', where: 'key = ?', whereArgs: <Object?>[key]);
  }

  Future<Map<String, String>> getAll() async {
    final List<Map<String, Object?>> rows = await _db.query('settings');
    return <String, String>{
      for (final Map<String, Object?> r in rows)
        r['key'] as String: r['value'] as String,
    };
  }
}
