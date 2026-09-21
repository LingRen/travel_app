import 'db/settings_dao.dart';

/// 距离单位。仅支持公里与英里两种，不涉及多语言。
enum DistanceUnit {
  kilometer('km'),
  mile('mi');

  const DistanceUnit(this.dbValue);

  final String dbValue;

  static DistanceUnit fromDb(String? value) => DistanceUnit.values.firstWhere(
        (DistanceUnit u) => u.dbValue == value,
        orElse: () => DistanceUnit.kilometer,
      );
}

const int kDefaultMaxHeartRate = 190;
const double kDefaultWeightKg = 70;
const int kMinPlausibleMaxHeartRate = 100;
const int kMaxPlausibleMaxHeartRate = 230;

/// 高德栅格瓦片。无需 Key，但属于非官方接口，因此做成可配置项（设计文档 9.1）。
const String kDefaultMapTileUrlTemplate =
    'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}';

const List<String> kDefaultMapTileSubdomains = <String>['1', '2', '3', '4'];

/// 用户可配置项。
class AppSettings {
  const AppSettings({
    required this.maxHeartRate,
    required this.weightKg,
    required this.distanceUnit,
    required this.mapTileUrlTemplate,
  });

  final int maxHeartRate;
  final double weightKg;
  final DistanceUnit distanceUnit;
  final String mapTileUrlTemplate;

  AppSettings copyWith({
    int? maxHeartRate,
    double? weightKg,
    DistanceUnit? distanceUnit,
    String? mapTileUrlTemplate,
  }) =>
      AppSettings(
        maxHeartRate: maxHeartRate ?? this.maxHeartRate,
        weightKg: weightKg ?? this.weightKg,
        distanceUnit: distanceUnit ?? this.distanceUnit,
        mapTileUrlTemplate: mapTileUrlTemplate ?? this.mapTileUrlTemplate,
      );
}

/// 类型化的设置读写。存储值损坏或越界时回退到默认值，不让 UI 崩掉。
class SettingsRepository {
  SettingsRepository(this._dao);

  final SettingsDao _dao;

  Future<AppSettings> load() async {
    final Map<String, String> raw = await _dao.getAll();

    final int? hr = int.tryParse(raw['max_heart_rate'] ?? '');
    final double? weight = double.tryParse(raw['weight_kg'] ?? '');
    final String tileUrl = raw['map_tile_url'] ?? '';

    return AppSettings(
      maxHeartRate:
          (hr != null && hr >= kMinPlausibleMaxHeartRate && hr <= kMaxPlausibleMaxHeartRate)
              ? hr
              : kDefaultMaxHeartRate,
      weightKg: (weight != null && weight > 0) ? weight : kDefaultWeightKg,
      distanceUnit: DistanceUnit.fromDb(raw['distance_unit']),
      mapTileUrlTemplate: tileUrl.isEmpty ? kDefaultMapTileUrlTemplate : tileUrl,
    );
  }

  Future<void> save(AppSettings settings) async {
    await _dao.setString('max_heart_rate', settings.maxHeartRate.toString());
    await _dao.setString('weight_kg', settings.weightKg.toString());
    await _dao.setString('distance_unit', settings.distanceUnit.dbValue);
    await _dao.setString('map_tile_url', settings.mapTileUrlTemplate);
  }
}
