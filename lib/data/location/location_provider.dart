/// 定位采集源。默认系统定位；高德定位只作为试点源，需构建参数或 debug 开关
/// 显式启用。
enum LocationProviderKind {
  system('system', '系统定位'),
  amap('amap', '高德定位');

  const LocationProviderKind(this.dbValue, this.label);

  /// 落库与构建参数使用的稳定标识。
  final String dbValue;

  /// 设置页显示名。
  final String label;

  /// 解析存储值 / 构建参数。未知值一律按系统定位，不让配置错误变成崩溃。
  static LocationProviderKind parse(String? value) => switch (value) {
    'amap' => LocationProviderKind.amap,
    _ => LocationProviderKind.system,
  };
}

/// 定位源选择结果。
class LocationProviderSelection {
  const LocationProviderSelection({required this.kind, this.fallbackReason});

  final LocationProviderKind kind;

  /// 非空表示请求的高德定位不可用而降级，值是可直接展示的中文原因。
  final String? fallbackReason;

  bool get isFallback => fallbackReason != null;
}

/// 解析当前应使用的定位源。
///
/// 顺序：debug 构建的调试值 → `LOCATION_PROVIDER` 构建参数 → 系统定位。
/// release 构建不读取调试值，避免已验收前被误开。选择高德但 Key 为空时回落
/// 到系统定位，并带上可读原因（见设计文档「Provider 选择」）。
LocationProviderSelection resolveLocationProvider({
  required bool isDebug,
  required String buildOverride,
  required String? debugStoredValue,
  required String amapKey,
}) {
  final String requested = (isDebug && (debugStoredValue ?? '').isNotEmpty)
      ? debugStoredValue!
      : buildOverride;

  if (LocationProviderKind.parse(requested) != LocationProviderKind.amap) {
    return const LocationProviderSelection(kind: LocationProviderKind.system);
  }
  if (amapKey.isEmpty) {
    return const LocationProviderSelection(
      kind: LocationProviderKind.system,
      fallbackReason: '未配置高德 Key，已回落到系统定位',
    );
  }
  return const LocationProviderSelection(kind: LocationProviderKind.amap);
}
