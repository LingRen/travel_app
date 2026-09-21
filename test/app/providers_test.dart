import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/ble/ble_scanner.dart';
import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/ride_dao.dart';
import 'package:cycling_app/data/db/track_point_dao.dart';
import 'package:cycling_app/data/location/location_service.dart';
import 'package:cycling_app/data/ride_repository.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late ProviderContainer container;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    container = ProviderContainer(
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// 直接往注入的连接里写一条进行中的骑行与三个轨迹点。
  Future<int> seedRide(int startedAtMs) async {
    final int id = await RideDao(db)
        .insert(Ride(startedAtMs: startedAtMs, status: RideStatus.recording));
    await TrackPointDao(db).insertBatch(<TrackPoint>[
      TrackPoint(rideId: id, tMs: 0, lat: 31.2300, lon: 121.4700, hr: 120),
      TrackPoint(rideId: id, tMs: 1000, lat: 31.2300, lon: 121.4701, hr: 150),
      TrackPoint(rideId: id, tMs: 2000, lat: 31.2300, lon: 121.4702, hr: 150),
    ]);
    return id;
  }

  test('databaseProvider 未 override 时抛 UnimplementedError，强制在 main() 注入', () {
    final ProviderContainer bare = ProviderContainer(
      retry: (int retryCount, Object error) => null,
    );
    addTearDown(bare.dispose);

    // riverpod 3 会把 provider 内抛出的异常包成 ProviderException。
    expect(
      () => bare.read(databaseProvider),
      throwsA(
        isA<ProviderException>().having(
          (ProviderException e) => e.exception,
          'exception',
          isA<UnimplementedError>(),
        ),
      ),
    );
  });

  test('rideRepositoryProvider 复用注入的数据库连接', () async {
    final int id = await seedRide(1000);

    final List<Ride> unfinished =
        await container.read(rideRepositoryProvider).findUnfinished();

    expect(unfinished.map((Ride r) => r.id).toList(), <int>[id]);
  });

  test('rideRepositoryProvider 的 rides/points 装配到同一连接', () async {
    final int id = await seedRide(1000);
    final RideRepository repo = container.read(rideRepositoryProvider);

    expect((await repo.getPoints(id)).length, 3);
    expect((await repo.lastPoint(id))!.tMs, 2000);
  });

  test('rideRepositoryProvider 的 settings 装配到同一连接（体重影响卡路里）', () async {
    final RideRepository repo = container.read(rideRepositoryProvider);

    final int a = await seedRide(0);
    final RideSummary withDefaultWeight =
        await repo.finishRide(a, endedAtMs: 2000, durationS: 2);
    expect(withDefaultWeight.calories, isNotNull);

    await container.read(settingsRepositoryProvider).save(const AppSettings(
          maxHeartRate: kDefaultMaxHeartRate,
          weightKg: 140,
          distanceUnit: DistanceUnit.kilometer,
          mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
        ));

    final int b = await seedRide(100000);
    final RideSummary withDoubleWeight =
        await repo.finishRide(b, endedAtMs: 102000, durationS: 2);

    expect(withDoubleWeight.calories, closeTo(withDefaultWeight.calories! * 2, 1e-6));
  });

  test('appSettingsProvider 读出默认值，包含可配置的瓦片源地址', () async {
    final AppSettings settings = await container.read(appSettingsProvider.future);

    // 字面量：钉住默认值本身，避免断言与常量自指。
    expect(settings.maxHeartRate, 190);
    expect(settings.weightKg, 70);
    expect(settings.distanceUnit, DistanceUnit.kilometer);
    expect(settings.mapTileUrlTemplate, kDefaultMapTileUrlTemplate);
    expect(settings.mapTileUrlTemplate, isNotEmpty);
  });

  test('appSettingsProvider 在 invalidate 后反映已保存的设置', () async {
    const AppSettings saved = AppSettings(
      maxHeartRate: 200,
      weightKg: 82.5,
      distanceUnit: DistanceUnit.mile,
      mapTileUrlTemplate: 'https://tiles.example.com/{z}/{x}/{y}.png',
    );
    await container.read(settingsRepositoryProvider).save(saved);

    container.invalidate(appSettingsProvider);
    final AppSettings reloaded = await container.read(appSettingsProvider.future);

    expect(reloaded.maxHeartRate, 200);
    expect(reloaded.weightKg, 82.5);
    expect(reloaded.distanceUnit, DistanceUnit.mile);
    expect(reloaded.mapTileUrlTemplate, 'https://tiles.example.com/{z}/{x}/{y}.png');
  });

  test('locationServiceProvider / bleScannerProvider 返回生产实现', () {
    expect(container.read(locationServiceProvider), isA<LocationService>());
    expect(container.read(bleScannerProvider), isA<BleScanner>());
  });

  test('仓储 provider 是长生命周期单例，不会每次读都新建', () {
    expect(
      identical(
        container.read(rideRepositoryProvider),
        container.read(rideRepositoryProvider),
      ),
      isTrue,
    );
    expect(
      identical(
        container.read(settingsRepositoryProvider),
        container.read(settingsRepositoryProvider),
      ),
      isTrue,
    );
  });

  test('nowProvider 返回当前 epoch 毫秒', () {
    final int before = DateTime.now().millisecondsSinceEpoch;
    final int now = container.read(nowProvider)();
    final int after = DateTime.now().millisecondsSinceEpoch;

    expect(now, greaterThanOrEqualTo(before));
    expect(now, lessThanOrEqualTo(after));
  });

  test('resumeRideIdProvider 初始为 null，可写入', () {
    expect(container.read(resumeRideIdProvider), isNull);

    container.read(resumeRideIdProvider.notifier).state = 7;

    expect(container.read(resumeRideIdProvider), 7);
  });
}
