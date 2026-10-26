import 'dart:ui' show Color;

import '../domain/analysis/constants.dart';
import '../domain/models/activity_type.dart';
import 'db/settings_dao.dart';

/// 可选主题色。语义恒为「正在发生 / 可交互 / 已选中」，只是色相交给用户挑。
///
/// 依赖方向：这个枚举是用户设置的一种取值，和 [DistanceUnit] 一样归设置层所有。
/// 它放在这里（而不是 app 的主题文件）是为了让数据层不反向依赖 UI 层——主题色
/// 的定义属于「有哪些值可选」，怎么渲染属于 UI 层。
///
/// 每组色相都必须能和**数据色**（心率区间色）与**安全色**（警告、危险）区分开：
/// 色相相差 ≥30°，或相对亮度比 ≥1.30。详情页上心率曲线用主题色绘制、心率区间条
/// 用区间色，两者同屏，撞色就读不出来。该约束由 `test/app/theme_test.dart` 的
/// 门禁守住。
///
/// 曾经有第四组暖色（琥珀）作为默认色：它落在心率「暖身」段上，只能靠亮度与
/// 语义区分，靠门禁豁免放行。轨迹与速度曲线改为跟随主题色之后，暖色与地图黄白
/// 路面对撞的问题凸显出来，于是整组移除，默认改为天青。
enum ThemeAccent {
  mint('mint', '薄荷', Color(0xFF33D69F)),
  // 比初版 #38BDF8 更亮：初版与心率区间蓝（#64B5F6）色相仅差 8°、亮度几乎相同，
  // 详情页上心率曲线（主题色）与区间条会撞色。提亮后亮度比 1.33，可区分。
  sky('sky', '天青', Color(0xFF7DD3FC)),
  violet('violet', '紫罗兰', Color(0xFFA78BFA));

  const ThemeAccent(this.dbValue, this.label, this.color);

  /// 落库用的稳定标识，改显示名不影响已存数据。
  final String dbValue;

  /// 设置页显示名。
  final String label;

  /// 强调色本体。
  final Color color;

  static ThemeAccent fromDb(String? value) => ThemeAccent.values.firstWhere(
        (ThemeAccent a) => a.dbValue == value,
        orElse: () => ThemeAccent.sky,
      );
}

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

/// 用户没设体重时的默认值。与估算功率用的兜底值取同一个常量，避免两处分叉。
const double kDefaultWeightKg = kDefaultRiderWeightKg;

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
    this.accent = ThemeAccent.sky,
    this.lastActivityType = ActivityType.cycling,
  });

  final int maxHeartRate;
  final double weightKg;
  final DistanceUnit distanceUnit;
  final String mapTileUrlTemplate;

  /// 主题强调色。缺省为天青。
  final ThemeAccent accent;

  /// 上次在记录页选中的运动类型。下次冷启动沿用，避免选好类型后进程被回收、
  /// 再打开又悄悄变回骑行（类型落库错了，事后只能手改库）。
  final ActivityType lastActivityType;

  AppSettings copyWith({
    int? maxHeartRate,
    double? weightKg,
    DistanceUnit? distanceUnit,
    String? mapTileUrlTemplate,
    ThemeAccent? accent,
    ActivityType? lastActivityType,
  }) =>
      AppSettings(
        maxHeartRate: maxHeartRate ?? this.maxHeartRate,
        weightKg: weightKg ?? this.weightKg,
        distanceUnit: distanceUnit ?? this.distanceUnit,
        mapTileUrlTemplate: mapTileUrlTemplate ?? this.mapTileUrlTemplate,
        accent: accent ?? this.accent,
        lastActivityType: lastActivityType ?? this.lastActivityType,
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
      accent: ThemeAccent.fromDb(raw['accent_theme']),
      lastActivityType: ActivityType.fromDb(raw['last_activity_type']),
    );
  }

  Future<void> save(AppSettings settings) async {
    await _dao.setString('max_heart_rate', settings.maxHeartRate.toString());
    await _dao.setString('weight_kg', settings.weightKg.toString());
    await _dao.setString('distance_unit', settings.distanceUnit.dbValue);
    await _dao.setString('map_tile_url', settings.mapTileUrlTemplate);
    await _dao.setString('accent_theme', settings.accent.dbValue);
    // last_activity_type 不在这里写：设置页整份保存时手里那份 AppSettings
    // 可能是旧快照（用户在记录页刚换过类型），整份写回会把它覆盖掉。
    // 该字段只由 [saveLastActivityType] 写入。
  }

  /// 记住记录页这次选中的运动类型，下次冷启动沿用。
  Future<void> saveLastActivityType(ActivityType type) async {
    await _dao.setString('last_activity_type', type.dbValue);
  }
}
