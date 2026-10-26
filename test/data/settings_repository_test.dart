import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/settings_dao.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/models/activity_type.dart';
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
    // 用字面量而不是常量：否则常量改了默认值、断言也跟着变，等于没钉住。
    expect(s.maxHeartRate, 190);
    expect(s.weightKg, 70);
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
    expect((await repo.load()).weightKg, 70);
  });

  test('最大心率越界时回退到默认值', () async {
    await SettingsDao(db).setString('max_heart_rate', '10');
    expect((await repo.load()).maxHeartRate, 190);
  });

  test('首次读取的主题色是天青', () async {
    expect((await repo.load()).accent, ThemeAccent.sky);
  });

  test('保存后可读回主题色', () async {
    await repo.save(
      const AppSettings(
        maxHeartRate: 190,
        weightKg: 70,
        distanceUnit: DistanceUnit.kilometer,
        mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
        accent: ThemeAccent.sky,
      ),
    );

    expect((await repo.load()).accent, ThemeAccent.sky);
  });

  test('存储的主题色未知时回退到天青', () async {
    await SettingsDao(db).setString('accent_theme', 'no-such-theme');
    expect((await repo.load()).accent, ThemeAccent.sky);
  });

  test('存储的主题色是已下线的琥珀时回退到天青', () async {
    // 老库里可能存着 'amber'：那一组已随「轨迹跟随主题色」一起移除。
    await SettingsDao(db).setString('accent_theme', 'amber');
    expect((await repo.load()).accent, ThemeAccent.sky);
  });

  group('上次选中的运动类型', () {
    test('首次读取是骑行', () async {
      expect((await repo.load()).lastActivityType, ActivityType.cycling);
    });

    test('保存后可读回', () async {
      await repo.saveLastActivityType(ActivityType.hiking);
      expect((await repo.load()).lastActivityType, ActivityType.hiking);
    });

    test('存储值未知时回退到骑行', () async {
      await SettingsDao(db).setString('last_activity_type', 'swimming');
      expect((await repo.load()).lastActivityType, ActivityType.cycling);
    });

    // 设置页保存是整份写回，手里那份 AppSettings 可能是记录页换类型之前的
    // 旧快照。若 save() 也写这个键，用户刚选的徒步会被悄悄改回旧值。
    test('整份保存不会覆盖已存的运动类型', () async {
      await repo.saveLastActivityType(ActivityType.running);
      await repo.save(
        const AppSettings(
          maxHeartRate: 185,
          weightKg: 72.5,
          distanceUnit: DistanceUnit.mile,
          mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
          lastActivityType: ActivityType.cycling,
        ),
      );
      expect((await repo.load()).lastActivityType, ActivityType.running);
    });
  });
}
