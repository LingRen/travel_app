/// WGS-84 到 GCJ-02 的坐标转换。见设计文档 9.1。
///
/// 高德瓦片用 GCJ-02（俗称「火星坐标」），手机 GPS 输出 WGS-84，直接叠加会
/// 偏移数百米。本文件只服务**显示**：落盘的轨迹点与导出的 GPX 一律保持
/// WGS-84 原始坐标，否则导出给第三方平台的数据会带上偏移。
///
/// 反解（GCJ-02 → WGS-84）本计划不需要，不做，避免无用代码。
library;

import 'dart:math' as math;

const double _pi = math.pi;
double _sin(double v) => math.sin(v);
double _cos(double v) => math.cos(v);
double _sqrt(double v) => math.sqrt(v);

/// 克拉索夫斯基椭球长半轴（米）。GCJ-02 算法规定值。
const double _axis = 6378245.0;

/// 偏心率平方。GCJ-02 算法规定值。
const double _eccentricitySquared = 0.00669342162296594323;

/// 该瓦片源用的是不是 GCJ-02 坐标。
///
/// 判定必须跟着瓦片源走，不能写死：设计文档 9.1 把「换源」当作高德接口失效
/// 时的对冲措施，而 OSM、Carto 这类源都是 WGS-84。对 WGS-84 源再转一次
/// GCJ-02，轨迹会整体偏出几百米——真机验证时在 OSM 源上实测偏约 310 米。
///
/// 只看域名，不看路径：`https://example.org/autonavi.com` 这种把域名写进路径
/// 的地址不是高德源，按子串判定会误判，轨迹就白偏几百米。
bool isGcj02TileSource(String urlTemplate) {
  final String host = _hostOf(urlTemplate);
  return _isUnderDomain(host, 'autonavi.com') || _isUnderDomain(host, 'amap.com');
}

/// 从瓦片地址模板里取主机名。模板里的 `{s}`、`{x}` 等占位符不是合法 URL
/// 字符，所以不用 `Uri.parse`，手工切出 `scheme://` 与第一个 `/` 之间的部分。
String _hostOf(String urlTemplate) {
  final String lower = urlTemplate.toLowerCase();
  final int scheme = lower.indexOf('://');
  final String rest = scheme >= 0 ? lower.substring(scheme + 3) : lower;
  final int slash = rest.indexOf('/');
  String host = slash >= 0 ? rest.substring(0, slash) : rest;
  final int at = host.indexOf('@'); // 去掉 userinfo
  if (at >= 0) host = host.substring(at + 1);
  final int colon = host.indexOf(':'); // 去掉端口
  return colon >= 0 ? host.substring(0, colon) : host;
}

bool _isUnderDomain(String host, String domain) =>
    host == domain || host.endsWith('.$domain');

/// 是否在中国境外。境外不做偏移（算法只在中国境内标定）。
///
/// 判定用闭区间：恰好落在边界上的点算境内。
bool isOutOfChina(double lat, double lon) =>
    lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271;

/// 把 WGS-84 经纬度转成 GCJ-02 经纬度。
///
/// 境外点原样返回。返回记录类型而不是自定义类，是为了让测试能直接用
/// 结构化相等，也避免 domain 层引入多余的模型。
({double lat, double lon}) wgs84ToGcj02(double lat, double lon) {
  if (isOutOfChina(lat, lon)) return (lat: lat, lon: lon);

  final double dLat = _transformLat(lon - 105.0, lat - 35.0);
  final double dLon = _transformLon(lon - 105.0, lat - 35.0);

  final double radLat = lat / 180.0 * _pi;
  double magic = _sin(radLat);
  magic = 1 - _eccentricitySquared * magic * magic;
  final double sqrtMagic = _sqrt(magic);

  final double correctedLat = (dLat * 180.0) /
      ((_axis * (1 - _eccentricitySquared)) / (magic * sqrtMagic) * _pi);
  final double correctedLon =
      (dLon * 180.0) / (_axis / sqrtMagic * _cos(radLat) * _pi);

  return (lat: lat + correctedLat, lon: lon + correctedLon);
}

double _transformLat(double x, double y) {
  double ret = -100.0 +
      2.0 * x +
      3.0 * y +
      0.2 * y * y +
      0.1 * x * y +
      0.2 * _sqrt(x.abs());
  ret += (20.0 * _sin(6.0 * x * _pi) + 20.0 * _sin(2.0 * x * _pi)) * 2.0 / 3.0;
  ret += (20.0 * _sin(y * _pi) + 40.0 * _sin(y / 3.0 * _pi)) * 2.0 / 3.0;
  ret +=
      (160.0 * _sin(y / 12.0 * _pi) + 320 * _sin(y * _pi / 30.0)) * 2.0 / 3.0;
  return ret;
}

double _transformLon(double x, double y) {
  double ret =
      300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * _sqrt(x.abs());
  ret += (20.0 * _sin(6.0 * x * _pi) + 20.0 * _sin(2.0 * x * _pi)) * 2.0 / 3.0;
  ret += (20.0 * _sin(x * _pi) + 40.0 * _sin(x / 3.0 * _pi)) * 2.0 / 3.0;
  ret +=
      (150.0 * _sin(x / 12.0 * _pi) + 300.0 * _sin(x / 30.0 * _pi)) * 2.0 / 3.0;
  return ret;
}
