import 'package:flutter/foundation.dart';

/// 高德开放平台「Web 服务」Key。
///
/// 通过 `--dart-define=AMAP_WEB_KEY=...` 注入，仓库里不保存真实 Key。
/// 本地开发用 `tool/run_local.sh`：它从被 git 忽略的 `config/amap_key.txt`
/// 读取 Key 再传给 Flutter。未配置时逆地理编码直接跳过，待机页显示
/// 「当前位置」，不会报错。
const String kAmapWebKey = String.fromEnvironment('AMAP_WEB_KEY');

/// 高德原生地图 SDK 的 Android / iOS Key。
///
/// 通过 `--dart-define=AMAP_MAP_KEY_ANDROID=...` 与
/// `--dart-define=AMAP_MAP_KEY_IOS=...` 分别注入；Android Key 绑定包名 +
/// SHA1，iOS Key 绑定 Bundle ID。未配置时记录页与详情页自动回落到内置栅格底图。
const String kAmapMapKeyAndroid = String.fromEnvironment(
  'AMAP_MAP_KEY_ANDROID',
);
const String kAmapMapKeyIos = String.fromEnvironment('AMAP_MAP_KEY_IOS');

/// 当前平台应使用的高德 Key。
String amapMapKeyFor(TargetPlatform platform) =>
    platform == TargetPlatform.iOS ? kAmapMapKeyIos : kAmapMapKeyAndroid;

/// 高德自定义地图样式二进制在包内的路径。
///
/// 高德控制台「自定义地图」导出目录里的 `style.data` 与 `style_extra.data`
/// 放到 `assets/amap/` 下并在 `pubspec.yaml` 声明即可；文件缺失时原生地图
/// 使用 SDK 默认样式。插件不接受 styleId，只能用这份二进制。
const String kAmapMapStyleAsset = 'assets/amap/style.data';
const String kAmapMapStyleExtraAsset = 'assets/amap/style_extra.data';

/// 底图后端覆盖值：`amap`、`legacy` 或留空按 Key 自动选择。
///
/// 排障时可用 `--dart-define=MAP_BACKEND=legacy` 强制回到栅格底图。
const String kMapBackendOverride = String.fromEnvironment('MAP_BACKEND');
