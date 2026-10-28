/// 高德开放平台「Web 服务」Key。
///
/// 通过 `--dart-define=AMAP_WEB_KEY=...` 注入，仓库里不保存真实 Key。
/// 本地开发用 `tool/run_local.sh`：它从被 git 忽略的 `config/amap_key.txt`
/// 读取 Key 再传给 Flutter。未配置时逆地理编码直接跳过，待机页显示
/// 「当前位置」，不会报错。
const String kAmapWebKey = String.fromEnvironment('AMAP_WEB_KEY');
