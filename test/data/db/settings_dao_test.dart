import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/settings_dao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late SettingsDao dao;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    dao = SettingsDao(db);
  });

  tearDown(() => db.close());

  test('未设置的键返回 null', () async {
    expect(await dao.getString('missing'), isNull);
  });

  test('写入后可读回', () async {
    await dao.setString('max_heart_rate', '185');
    expect(await dao.getString('max_heart_rate'), '185');
  });

  test('重复写入同一键会覆盖而不是报错', () async {
    await dao.setString('weight_kg', '70');
    await dao.setString('weight_kg', '72');
    expect(await dao.getString('weight_kg'), '72');
  });

  test('getAll 返回全部键值', () async {
    await dao.setString('a', '1');
    await dao.setString('b', '2');
    expect(await dao.getAll(), <String, String>{'a': '1', 'b': '2'});
  });

  test('remove 删掉键后读回 null', () async {
    final SettingsDao dao = SettingsDao(db);
    await dao.setString('hr_sensor_id', 'AA:BB');
    await dao.setString('weight_kg', '70');

    await dao.remove('hr_sensor_id');

    expect(await dao.getString('hr_sensor_id'), isNull);
    expect(await dao.getString('weight_kg'), '70');
  });

  test('remove 一个不存在的键不抛错', () async {
    await SettingsDao(db).remove('never_set');
    expect(await SettingsDao(db).getString('never_set'), isNull);
  });
}
