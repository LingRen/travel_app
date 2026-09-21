import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider 在 riverpod 3 里只从 legacy 入口导出。
import 'package:flutter_riverpod/legacy.dart';
import 'package:sqflite/sqflite.dart';

import '../data/ble/ble_platform.dart';
import '../data/ble/ble_scanner.dart';
import '../data/db/ride_dao.dart';
import '../data/db/settings_dao.dart';
import '../data/db/track_point_dao.dart';
import '../data/location/location_service.dart';
import '../data/ride_repository.dart';
import '../data/sensor_pairing.dart';
import '../data/settings_repository.dart';

/// 数据库连接。在 `main()` 里打开后用 override 注入，因此这里不需要异步。
final Provider<Database> databaseProvider = Provider<Database>(
  (Ref ref) => throw UnimplementedError('databaseProvider 必须在 main() 中 override'),
);

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
  (Ref ref) => SettingsRepository(SettingsDao(ref.watch(databaseProvider))),
);

final Provider<RideRepository> rideRepositoryProvider = Provider<RideRepository>(
  (Ref ref) => RideRepository(
    rides: RideDao(ref.watch(databaseProvider)),
    points: TrackPointDao(ref.watch(databaseProvider)),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

/// 当前生效的设置。修改设置后 invalidate 本 provider 即可刷新。
final FutureProvider<AppSettings> appSettingsProvider = FutureProvider<AppSettings>(
  (Ref ref) => ref.watch(settingsRepositoryProvider).load(),
);

final Provider<LocationService> locationServiceProvider =
    Provider<LocationService>((Ref ref) => const LocationService());

/// 当前时间（epoch 毫秒）。做成 provider 是为了让记录控制器能在测试里
/// 用假时钟驱动，而不必等待真实时间流逝。
final Provider<int Function()> nowProvider =
    Provider<int Function()>((Ref ref) => () => DateTime.now().millisecondsSinceEpoch);

/// BLE 平台。抽成 provider 是为了让记录控制器的自动重连能在测试里注入假实现。
final Provider<BlePlatform> blePlatformProvider =
    Provider<BlePlatform>((Ref ref) => const FlutterBluePlusPlatform());

final Provider<BleScanner> bleScannerProvider = Provider<BleScanner>(
  (Ref ref) => BleScanner(platform: ref.watch(blePlatformProvider)),
);

/// 已配对传感器的读写。设置页与记录控制器共用。
final Provider<SensorPairingRepository> sensorPairingProvider =
    Provider<SensorPairingRepository>(
  (Ref ref) => SensorPairingRepository(SettingsDao(ref.watch(databaseProvider))),
);

/// 崩溃恢复时用户选择「继续」的骑行 id。记录页读到后调用
/// `RecordController.resumeExisting` 续写该会话。
final StateProvider<int?> resumeRideIdProvider = StateProvider<int?>((Ref ref) => null);
