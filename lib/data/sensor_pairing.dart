import 'ble/sensor_monitor.dart';
import 'db/settings_dao.dart';

/// 一个配对成功的传感器。
class PairedSensor {
  const PairedSensor({required this.id, required this.name});

  /// 平台侧设备标识（Android 是 MAC，iOS 是 UUID）。
  final String id;

  /// 配对时的设备名，用于界面展示。
  final String name;
}

/// 已配对传感器的持久化。见设计文档 10.5 的「传感器配对管理」。
///
/// 存 `settings` 表而不是 `rides` 表：这是「用户配置」，与某一次骑行无关。
class SensorPairingRepository {
  SensorPairingRepository(this._dao);

  final SettingsDao _dao;

  static const String _hrIdKey = 'hr_sensor_id';
  static const String _hrNameKey = 'hr_sensor_name';
  static const String _cadenceIdKey = 'cadence_sensor_id';
  static const String _cadenceNameKey = 'cadence_sensor_name';
  static const String _powerIdKey = 'power_sensor_id';
  static const String _powerNameKey = 'power_sensor_name';

  /// 读取已配对的传感器。没配对过、或存下来的 id 是空串时返回 null。
  Future<PairedSensor?> load(SensorKind kind) async {
    final String? id = await _dao.getString(_idKey(kind));
    if (id == null || id.isEmpty) return null;
    final String? name = await _dao.getString(_nameKey(kind));
    return PairedSensor(id: id, name: name ?? '');
  }

  Future<void> save(SensorKind kind, PairedSensor sensor) async {
    await _dao.setString(_idKey(kind), sensor.id);
    await _dao.setString(_nameKey(kind), sensor.name);
  }

  Future<void> clear(SensorKind kind) async {
    await _dao.remove(_idKey(kind));
    await _dao.remove(_nameKey(kind));
  }

  String _idKey(SensorKind kind) => switch (kind) {
        SensorKind.heartRate => _hrIdKey,
        SensorKind.cadence => _cadenceIdKey,
        SensorKind.power => _powerIdKey,
      };

  String _nameKey(SensorKind kind) => switch (kind) {
        SensorKind.heartRate => _hrNameKey,
        SensorKind.cadence => _cadenceNameKey,
        SensorKind.power => _powerNameKey,
      };
}
