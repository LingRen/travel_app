/// 记录页与详情页可用的底图后端。
enum MapBackend {
  /// 高德原生地图 SDK，需要 `AMAP_MAP_KEY`。
  amap,

  /// 内置的 `flutter_map` 栅格底图，无 Key 或排障时使用。
  legacy,
}

/// 按覆盖值与 Key 是否存在决定底图后端。
///
/// 覆盖值优先：`legacy` 强制回落，`amap` 在没有 Key 时也回落；留空或
/// 无法识别时按 Key 自动选择。覆盖值只影响底图，不改变坐标口径。
MapBackend resolveMapBackend({required String key, required String override}) {
  final String normalizedOverride = override.trim().toLowerCase();
  if (normalizedOverride == 'legacy') {
    return MapBackend.legacy;
  }
  final bool hasKey = key.trim().isNotEmpty;
  if (normalizedOverride == 'amap' && !hasKey) {
    return MapBackend.legacy;
  }
  return hasKey ? MapBackend.amap : MapBackend.legacy;
}
