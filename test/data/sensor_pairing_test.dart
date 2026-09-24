import 'package:cycling_app/data/ble/sensor_monitor.dart';
import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/settings_dao.dart';
import 'package:cycling_app/data/sensor_pairing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late SensorPairingRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = SensorPairingRepository(SettingsDao(db));
  });

  tearDown(() => db.close());

  test('没配对过时读回 null', () async {
    expect(await repo.load(SensorKind.heartRate), isNull);
    expect(await repo.load(SensorKind.cadence), isNull);
  });

  test('保存后可读回 id 与名字', () async {
    await repo.save(
      SensorKind.heartRate,
      const PairedSensor(id: 'AA:01', name: 'FIT 3'),
    );

    final PairedSensor? p = await repo.load(SensorKind.heartRate);
    expect(p!.id, 'AA:01');
    expect(p.name, 'FIT 3');
  });

  test('心率与踏频各自独立，互不覆盖', () async {
    await repo.save(
      SensorKind.heartRate,
      const PairedSensor(id: 'AA:01', name: 'FIT 3'),
    );
    await repo.save(
      SensorKind.cadence,
      const PairedSensor(id: 'BB:02', name: 'CADENCE'),
    );

    expect((await repo.load(SensorKind.heartRate))!.id, 'AA:01');
    expect((await repo.load(SensorKind.cadence))!.id, 'BB:02');
  });

  test('功率计与心率、踏频各自独立，互不覆盖', () async {
    await repo.save(
      SensorKind.heartRate,
      const PairedSensor(id: 'AA:01', name: 'FIT 3'),
    );
    await repo.save(
      SensorKind.cadence,
      const PairedSensor(id: 'BB:02', name: 'CADENCE'),
    );
    await repo.save(
      SensorKind.power,
      const PairedSensor(id: 'CC:03', name: 'ASSIOMA'),
    );

    expect((await repo.load(SensorKind.power))!.id, 'CC:03');
    expect((await repo.load(SensorKind.heartRate))!.id, 'AA:01');
    expect((await repo.load(SensorKind.cadence))!.id, 'BB:02');
  });

  test('clear 功率计不影响另外两种传感器', () async {
    await repo.save(
      SensorKind.cadence,
      const PairedSensor(id: 'BB:02', name: 'CADENCE'),
    );
    await repo.save(
      SensorKind.power,
      const PairedSensor(id: 'CC:03', name: 'ASSIOMA'),
    );

    await repo.clear(SensorKind.power);

    expect(await repo.load(SensorKind.power), isNull);
    expect((await repo.load(SensorKind.cadence))!.id, 'BB:02');
  });

  test('重复保存同一种传感器时覆盖旧值', () async {
    await repo.save(
      SensorKind.heartRate,
      const PairedSensor(id: 'AA:01', name: 'FIT 3'),
    );
    await repo.save(
      SensorKind.heartRate,
      const PairedSensor(id: 'AA:09', name: 'FIT 4'),
    );

    final PairedSensor p = (await repo.load(SensorKind.heartRate))!;
    expect(p.id, 'AA:09');
    expect(p.name, 'FIT 4');
  });

  test('clear 后读回 null，且不影响另一种传感器', () async {
    await repo.save(
      SensorKind.heartRate,
      const PairedSensor(id: 'AA:01', name: 'FIT 3'),
    );
    await repo.save(
      SensorKind.cadence,
      const PairedSensor(id: 'BB:02', name: 'CADENCE'),
    );

    await repo.clear(SensorKind.heartRate);

    expect(await repo.load(SensorKind.heartRate), isNull);
    expect((await repo.load(SensorKind.cadence))!.id, 'BB:02');
  });

  test('clear 一个没配对的传感器不抛错', () async {
    await repo.clear(SensorKind.cadence);
    expect(await repo.load(SensorKind.cadence), isNull);
  });

  test('clear 同时清掉 id 与名字，不留残值', () async {
    await repo.save(
      SensorKind.heartRate,
      const PairedSensor(id: 'AA:01', name: 'FIT 3'),
    );

    await repo.clear(SensorKind.heartRate);

    // 只删 id 键、把名字键留在库里，读回虽然仍是 null，但「配对管理」界面
    // 或后续按名字查询时会读到上一台设备的残值，所以这里直接盯住存储本身。
    final Map<String, String> all = await SettingsDao(db).getAll();
    expect(all.values, isNot(contains('FIT 3')));
    expect(all, isEmpty);
  });

  test('只有 id 没有名字时也能读回，名字为空串', () async {
    await repo.save(SensorKind.cadence, const PairedSensor(id: 'BB:02', name: ''));

    final PairedSensor p = (await repo.load(SensorKind.cadence))!;
    expect(p.id, 'BB:02');
    expect(p.name, isEmpty);
  });

  test('id 为空串视为未配对', () async {
    await repo.save(SensorKind.heartRate, const PairedSensor(id: '', name: 'x'));
    expect(await repo.load(SensorKind.heartRate), isNull);
  });
}
