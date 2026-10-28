import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 当前天气：气温与 WMO 天气码。
///
/// 气温一定有值；天气码可能缺失，此时 [description] 为 null，界面只显示
/// 温度，不用「未知」占位。
class WeatherNow {
  const WeatherNow({required this.temperatureC, this.weatherCode});

  /// 当前气温（摄氏度，四舍五入到整数）。
  final int temperatureC;

  /// Open-Meteo 的 `weather_code`（WMO 4677）。
  final int? weatherCode;

  /// 中文天气描述，例如「晴」「小雨」。未知天气码返回 null。
  String? get description => weatherDescriptionOf(weatherCode);

  /// 界面上的完整天气文字，例如「晴 18°C」。
  String get label {
    final String? text = description;
    return text == null ? '$temperatureC°C' : '$text $temperatureC°C';
  }
}

/// WMO 天气码到中文描述的映射。只覆盖 Open-Meteo 当前天气会返回的码。
String? weatherDescriptionOf(int? code) => switch (code) {
  0 => '晴',
  1 => '晴间多云',
  2 => '多云',
  3 => '阴',
  45 || 48 => '雾',
  51 || 53 || 55 => '毛毛雨',
  56 || 57 => '冻毛毛雨',
  61 => '小雨',
  63 => '中雨',
  65 => '大雨',
  66 || 67 => '冻雨',
  71 => '小雪',
  73 => '中雪',
  75 => '大雪',
  77 => '米雪',
  80 => '阵雨',
  81 => '强阵雨',
  82 => '暴雨',
  85 => '阵雪',
  86 => '强阵雪',
  95 => '雷阵雨',
  96 || 99 => '雷暴伴冰雹',
  _ => null,
};

/// 当前天气查询。抽成接口是为了让待机页与记录控制器的测试
/// 不碰真实网络，也不依赖 Open-Meteo 的可用性。
abstract class WeatherService {
  /// 返回当前气温与天气码；网络失败、超时、响应畸形或温度字段缺失时
  /// 返回 null。调用方据此省略整段天气，不显示占位或假数据。
  Future<WeatherNow?> currentWeather({
    required double lat,
    required double lon,
  });
}

/// Open-Meteo 当前天气。免 Key、按经纬度查询；坐标使用 WGS-84。
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

  final Map<String, _CachedWeather> _cache = <String, _CachedWeather>{};

  @override
  Future<WeatherNow?> currentWeather({
    required double lat,
    required double lon,
  }) async {
    final String key = _cacheKey(lat, lon);
    final int now = _nowMs();
    final _CachedWeather? cached = _cache[key];
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
          'current': 'temperature_2m,weather_code',
          'temperature_unit': 'celsius',
        },
      );
      final http.Response response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) return null;
      final Object? current = decoded['current'];
      if (current is! Map<String, Object?>) return null;
      final Object? rawTemperature = current['temperature_2m'];
      if (rawTemperature is! num) return null;
      final Object? rawCode = current['weather_code'];

      final WeatherNow value = WeatherNow(
        temperatureC: rawTemperature.round(),
        weatherCode: rawCode is num ? rawCode.toInt() : null,
      );
      _cache[key] = _CachedWeather(value: value, atMs: now);
      return value;
    } catch (_) {
      // 网络、超时、JSON 解析失败都走这里：天气只是附加信息，
      // 不值得为它弹错误或拖慢开始记录。
      return null;
    }
  }

  /// 约 1 km 的网格。定位在同一个街区里微动时复用缓存。
  String _cacheKey(double lat, double lon) =>
      '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';
}

class _CachedWeather {
  const _CachedWeather({required this.value, required this.atMs});

  final WeatherNow value;
  final int atMs;
}
