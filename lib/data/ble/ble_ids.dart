/// 标准 GATT 标识的 16 位短 UUID。见设计文档 4 与 14。
///
/// 华为 Fit 3 的心率广播**已真机验证**是标准 HRS（0x180D）：扫描能发现该服务，
/// 按标准 HRS 订阅后读数正常，所以这里直接用标准 UUID，不改心率来源。
const String kHeartRateServiceShort = '180d';
const String kHeartRateMeasurementShort = '2a37';
const String kCscServiceShort = '1816';
const String kCscMeasurementShort = '2a2b';
const String kCpsServiceShort = '1818';
const String kCpsMeasurementShort = '2a63';

/// 把任意形式的 UUID 归一化成 16 位短形式（小写）。
///
/// 设备上报的 UUID 可能是 `180d`、`0000180d` 或
/// `0000180d-0000-1000-8000-00805f9b34fb` 三种形式之一，
/// 直接字符串比较会漏匹配，所以统一先归一化。
String shortUuid(String uuid) {
  final String firstGroup = uuid.toLowerCase().split('-').first;
  final String trimmed = firstGroup.replaceFirst(RegExp('^0+'), '');
  return trimmed.isEmpty ? '0' : trimmed;
}
