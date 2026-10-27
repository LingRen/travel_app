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
/// 每组颜料有**两个**颜色：
///   - [color]：原始颜料，用于设置页色点与大面积标记；
///   - [inkColor]：文字安全色，用于文字、图标、按钮、选中态、轨迹与图表线。
///
/// 青瓷与藤黄的原始颜料在纸底上只有 2.70:1 / 2.12:1，不能直接承担文字；
/// 文字安全色都 ≥4.5:1。该约束由 `test/app/theme_test.dart` 的门禁守住。
enum ThemeAccent {
  cinnabar('cinnabar', '朱砂', Color(0xFFB4452F), Color(0xFFB4452F)),
  celadon('celadon', '青瓷', Color(0xFF7C9A8B), Color(0xFF4F6E60)),
  indigo('indigo', '黛蓝', Color(0xFF3E5A6B), Color(0xFF3E5A6B)),
  gamboge('gamboge', '藤黄', Color(0xFFC5A25E), Color(0xFF7E5F27));

  const ThemeAccent(this.dbValue, this.label, this.color, this.inkColor);

  /// 落库用的稳定标识，改显示名不影响已存数据。
  final String dbValue;

  /// 设置页显示名。
  final String label;

  /// 原始标记色：色点与大面积标记。
  final Color color;

  /// 文字安全色：文字、图标、选中态、轨迹与图表线。
  final Color inkColor;

  /// 读取设置时迁移旧主题值；未知值回退朱砂，不写回损坏值。
  static ThemeAccent fromDb(String? value) {
    switch (value) {
      case 'mint':
        return ThemeAccent.celadon;
      case 'sky':
      case 'violet':
        return ThemeAccent.indigo;
      case 'amber':
        return ThemeAccent.gamboge;
    }
    return ThemeAccent.values.firstWhere(
      (ThemeAccent a) => a.dbValue == value,
      orElse: () => ThemeAccent.cinnabar,
    );
  }
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
    this.accent = ThemeAccent.cinnabar,
    this.lastActivityType = ActivityType.cycling,
  });

  final int maxHeartRate;
  final double weightKg;
  final DistanceUnit distanceUnit;
  final String mapTileUrlTemplate;

  /// 主题强调色。缺省为朱砂。
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

  /// 上次导出备份的时间（epoch ms）。没有导出过时返回 null。
  Future<int?> lastBackupAt() async {
    final String? raw = await _dao.getString('last_backup_at');
    return int.tryParse(raw ?? '');
  }

  /// 记住上次成功导出备份的时间，供设置页「数据」分组显示。
  Future<void> saveLastBackupAt(int epochMs) =>
      _dao.setString('last_backup_at', '$epochMs');

  /// 记住记录页这次选中的运动类型，下次冷启动沿用。
  Future<void> saveLastActivityType(ActivityType type) async {
    await _dao.setString('last_activity_type', type.dbValue);
  }
}
