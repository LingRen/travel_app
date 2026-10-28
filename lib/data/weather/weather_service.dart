import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 当前气温查询。抽成接口是为了让待机页的 widget / provider 测试
/// 不碰真实网络，也不依赖 Open-Meteo 的可用性。
abstract class WeatherService {
  /// 返回当前气温（摄氏度，四舍五入到整数）。
  ///
  /// 网络失败、超时、响应畸形或字段缺失一律返回 null；调用方据此
  /// 省略温度，不显示占位或假数据。
  Future<int?> currentTemperatureC({required double lat, required double lon});
}

/// Open-Meteo 当前气温。免 Key、按经纬度查询；坐标使用 WGS-84。
class OpenMeteoWeatherService implements WeatherService {
  OpenMeteoWeatherService({
    required this._client,
    int Function()? nowMs,
    this._timeout = const Duration(seconds: 6),
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final http.Client _client;
  final int Function() _nowMs;
  final Duration _timeout;

  /// 同一网格 10 分钟内不重复请求。待机页可能因定位刷新反复重建，
  /// 缓存能把「每次重建都打一次 API」压成一次。
  static const int _cacheTtlMs = 10 * 60 * 1000;

  final Map<String, _CachedTemperature> _cache = <String, _CachedTemperature>{};

  @override
  Future<int?> currentTemperatureC({
    required double lat,
    required double lon,
  }) async {
    final String key = _cacheKey(lat, lon);
    final int now = _nowMs();
    final _CachedTemperature? cached = _cache[key];
    if (cached != null && now - cached.atMs < _cacheTtlMs) {
      return cached.value;
    }

    try {
      final Uri uri = Uri.https(
        'api.open-meteo.com',
        '/v1/forecast',
        <String, String>{
          'latitude': lat.toStringAsFixed(4),
          'longitude': lon.toStringAsFixed(4),
          'current': 'temperature_2m',
          'temperature_unit': 'celsius',
        },
      );
      final http.Response response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) return null;
      final Object? current = decoded['current'];
      if (current is! Map<String, Object?>) return null;
      final Object? raw = current['temperature_2m'];
      if (raw is! num) return null;

      final int value = raw.round();
      _cache[key] = _CachedTemperature(value: value, atMs: now);
      return value;
    } catch (_) {
      // 网络、超时、JSON 解析失败都走这里：温度只是待机页的附加信息，
      // 不值得为它弹错误或拖慢开始记录。
      return null;
    }
  }

  /// 约 1 km 的网格。定位在同一个街区里微动时复用缓存。
  String _cacheKey(double lat, double lon) =>
      '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';
}

class _CachedTemperature {
  const _CachedTemperature({required this.value, required this.atMs});

  final int value;
  final int atMs;
}
