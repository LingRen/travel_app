import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider 在 riverpod 3 里只从 legacy 入口导出。
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../config/app_config.dart';
import '../data/ble/ble_platform.dart';
import '../data/ble/ble_scanner.dart';
import '../data/db/settings_dao.dart';
import '../data/db/track_point_dao.dart';
import '../data/db/workout_dao.dart';
import '../data/export/backup_io.dart';
import '../data/export/backup_store.dart';
import '../data/geocode/place_service.dart';
import '../data/location/location_service.dart';
import '../data/sensor_pairing.dart';
import '../data/settings_repository.dart';
import '../data/weather/weather_service.dart';
import '../data/workout_repository.dart';

/// 数据库连接。`main()` 发起打开、`CyclingApp` 在连接就绪后 override 注入，
/// 因此这里不需要异步；测试里直接 override 成内存库。
final Provider<Database> databaseProvider = Provider<Database>(
  (Ref ref) => throw UnimplementedError('databaseProvider 必须在启动时 override'),
);

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
      (Ref ref) => SettingsRepository(SettingsDao(ref.watch(databaseProvider))),
    );

final Provider<WorkoutRepository> workoutRepositoryProvider =
    Provider<WorkoutRepository>(
      (Ref ref) => WorkoutRepository(
        workouts: WorkoutDao(ref.watch(databaseProvider)),
        points: TrackPointDao(ref.watch(databaseProvider)),
        settings: ref.watch(settingsRepositoryProvider),
        onWorkoutDataChanged: () =>
            ref.read(rideDataRevisionProvider.notifier).markChanged(),
      ),
    );

/// 骑行数据的版本号。任何改变「已完成骑行」的写操作之后自增，历史页、
/// 统计页、详情页的缓存型 provider 都 watch 它来自动失效。
///
/// 集中成一个信号而不是在每个保存点逐个 `invalidate`：结束、崩溃结算、
/// 改标题、删除、恢复备份都要刷新同一批列表，漏掉任何一处都会重新长出
/// 「保存后历史页还是旧数据」这个缺陷。
class RideDataRevision extends Notifier<int> {
  @override
  int build() => 0;

  /// 标记骑行数据已变更，让 watch 本 provider 的列表重新查库。
  void markChanged() => state++;
}

final NotifierProvider<RideDataRevision, int> rideDataRevisionProvider =
    NotifierProvider<RideDataRevision, int>(RideDataRevision.new);

/// 当前生效的设置。修改设置后 invalidate 本 provider 即可刷新。
final FutureProvider<AppSettings> appSettingsProvider =
    FutureProvider<AppSettings>(
      (Ref ref) => ref.watch(settingsRepositoryProvider).load(),
    );

final Provider<LocationService> locationServiceProvider =
    Provider<LocationService>((Ref ref) => const LocationService());

/// 待机页查地名与天气共用的 HTTP 客户端。
///
/// 单独做成 provider 是为了让测试一次替换掉两处网络，也方便在 provider
/// 销毁时关掉连接池。
final Provider<http.Client> httpClientProvider = Provider<http.Client>((
  Ref ref,
) {
  final http.Client client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// 逆地理编码。没有配置 `AMAP_WEB_KEY` 时服务内部直接返回 null，
/// 待机页回退成「当前位置」。
final Provider<PlaceService> placeServiceProvider = Provider<PlaceService>(
  (Ref ref) =>
      AmapPlaceService(client: ref.watch(httpClientProvider), key: kAmapWebKey),
);

/// 当前气温。免 Key 的 Open-Meteo，失败时返回 null，待机页省略温度。
final Provider<WeatherService> weatherServiceProvider =
    Provider<WeatherService>(
      (Ref ref) =>
          OpenMeteoWeatherService(client: ref.watch(httpClientProvider)),
    );

/// 当前时间（epoch 毫秒）。做成 provider 是为了让记录控制器能在测试里
/// 用假时钟驱动，而不必等待真实时间流逝。
final Provider<int Function()> nowProvider = Provider<int Function()>(
  (Ref ref) =>
      () => DateTime.now().millisecondsSinceEpoch,
);

/// BLE 平台。抽成 provider 是为了让记录控制器的自动重连能在测试里注入假实现。
final Provider<BlePlatform> blePlatformProvider = Provider<BlePlatform>(
  (Ref ref) => const FlutterBluePlusPlatform(),
);

final Provider<BleScanner> bleScannerProvider = Provider<BleScanner>(
  (Ref ref) => BleScanner(platform: ref.watch(blePlatformProvider)),
);

/// 已配对传感器的读写。设置页与记录控制器共用。
final Provider<SensorPairingRepository> sensorPairingProvider =
    Provider<SensorPairingRepository>(
      (Ref ref) =>
          SensorPairingRepository(SettingsDao(ref.watch(databaseProvider))),
    );

/// 崩溃恢复时用户选择「继续」的骑行 id。记录页读到后调用
/// `RecordController.resumeExisting` 续写该会话。
final StateProvider<int?> resumeRideIdProvider = StateProvider<int?>(
  (Ref ref) => null,
);

/// 备份数据的读写。设置页用；抽成 provider 是为了让 widget 测试注入假实现。
final Provider<BackupStore> backupStoreProvider = Provider<BackupStore>(
  (Ref ref) => SqliteBackupStore(ref.watch(databaseProvider)),
);

/// 备份文件的读写（系统分享 / 文件选择器）。
final Provider<BackupIo> backupIoProvider = Provider<BackupIo>(
  (Ref ref) => const FileBackupIo(),
);
