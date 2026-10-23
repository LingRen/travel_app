/// 运动类型。语义归属与 `DistanceUnit` 同层：落设置/数据层，带稳定 dbValue。
///
/// 枚举自带的**能力集**供界面与记录引擎按类型分派：
///   - 骑行独有：踏频、功率、速度跨档提示；
///   - 跑步/健走/徒步：主读数用配速，无踏频/功率概念；
///   - 距离里程碑提示（每 1km / 10km）全类型通用。
/// 新增类型只需加一个枚举值，其余按默认能力（纯 GPS + 心率）走。
enum ActivityType {
  cycling('cycling', '骑行', supportsCadence: true, supportsPower: true),
  running('running', '跑步', usesPace: true),
  walking('walking', '健走', usesPace: true),
  hiking('hiking', '徒步', usesPace: true);

  const ActivityType(
    this.dbValue,
    this.label, {
    this.supportsCadence = false,
    this.supportsPower = false,
    this.usesPace = false,
  });

  /// 落库用的稳定标识，改显示名不影响已存数据。
  final String dbValue;

  /// 界面显示名。
  final String label;

  /// 是否支持踏频采样与踏频读数。
  final bool supportsCadence;

  /// 是否支持功率（实测与估算）。
  final bool supportsPower;

  /// 主读数是否为配速（跑步/健走/徒步）。
  final bool usesPace;

  /// 速度跨档提示只有骑行启用。速度档本身按 km/h 定义，跑步类型无意义。
  bool get supportsSpeedTierCue => !usesPace;

  static ActivityType fromDb(String? value) => ActivityType.values.firstWhere(
        (ActivityType a) => a.dbValue == value,
        orElse: () => ActivityType.cycling,
      );
}
