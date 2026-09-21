import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/settings_dao.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late SettingsRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = SettingsRepository(SettingsDao(db));
  });

  tearDown(() => db.close());

  test('首次读取返回默认值', () async {
    final AppSettings s = await repo.load();
    expect(s.maxHeartRate, kDefaultMaxHeartRate);
    expect(s.weightKg, kDefaultWeightKg);
    expect(s.distanceUnit, DistanceUnit.kilometer);
    expect(s.mapTileUrlTemplate, kDefaultMapTileUrlTemplate);
  });

  test('保存后可读回', () async {
    await repo.save(
      const AppSettings(
        maxHeartRate: 185,
        weightKg: 72.5,
        distanceUnit: DistanceUnit.mile,
        mapTileUrlTemplate: 'https://example.com/{z}/{x}/{y}.png',
      ),
    );

    final AppSettings s = await repo.load();
    expect(s.maxHeartRate, 185);
    expect(s.weightKg, 72.5);
    expect(s.distanceUnit, DistanceUnit.mile);
    expect(s.mapTileUrlTemplate, 'https://example.com/{z}/{x}/{y}.png');
  });

  test('存储值损坏时回退到默认值而不是抛错', () async {
    await SettingsDao(db).setString('weight_kg', 'not-a-number');
    expect((await repo.load()).weightKg, kDefaultWeightKg);
  });

  test('最大心率越界时回退到默认值', () async {
    await SettingsDao(db).setString('max_heart_rate', '10');
    expect((await repo.load()).maxHeartRate, kDefaultMaxHeartRate);
  });
}
