import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/analysis/gcj02.dart';

/// 逆地理编码：把 GPS 坐标翻译成可显示的地名。
///
/// 抽成接口是为了让待机页测试不碰高德接口，也不依赖 Key 是否配置。
abstract class PlaceService {
  /// 返回「城市 · 区县」形式的短地名；没有 Key、网络失败、响应畸形或
  /// 没有可用地址字段时返回 null。
  Future<String?> placeName({required double lat, required double lon});
}

/// 高德逆地理编码。高德要求 GCJ-02 坐标，而 GPS 与落盘轨迹是 WGS-84，
/// 请求前必须先转换；否则地名会偏出几百米。
class AmapPlaceService implements PlaceService {
  AmapPlaceService({
    required this._client,
    required String key,
    int Function()? nowMs,
    this._timeout = const Duration(seconds: 5),
  }) : _key = key.trim(),
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final http.Client _client;
  final String _key;
  final int Function() _nowMs;
  final Duration _timeout;

  static const int _cacheTtlMs = 10 * 60 * 1000;

  final Map<String, _CachedPlace> _cache = <String, _CachedPlace>{};

  @override
  Future<String?> placeName({required double lat, required double lon}) async {
    // 没配 Key 时直接降级成「当前位置」，不把请求发出去。
    if (_key.isEmpty) return null;

    final String cacheKey = _cacheKey(lat, lon);
    final int now = _nowMs();
    final _CachedPlace? cached = _cache[cacheKey];
    if (cached != null && now - cached.atMs < _cacheTtlMs) {
      return cached.value;
    }

    try {
      final ({double lat, double lon}) gcj = wgs84ToGcj02(lat, lon);
      final Uri uri = Uri.https(
        'restapi.amap.com',
        '/v3/geocode/regeo',
        <String, String>{
          'key': _key,
          'location':
              '${gcj.lon.toStringAsFixed(6)},${gcj.lat.toStringAsFixed(6)}',
          'extensions': 'base',
          'radius': '1000',
        },
      );
      final http.Response response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) return null;
      if (_text(decoded['status']) != '1') return null;

      final Object? regeocode = decoded['regeocode'];
      if (regeocode is! Map<String, Object?>) return null;
      final Object? component = regeocode['addressComponent'];
      if (component is! Map<String, Object?>) return null;

      final String? name = _formatPlace(component);
      if (name == null) return null;
      _cache[cacheKey] = _CachedPlace(value: name, atMs: now);
      return name;
    } catch (_) {
      // 地名只是待机页的附加信息：失败就显示「当前位置」，不弹错误。
      return null;
    }
  }

  /// 取「城市 · 区县」；高德在部分区域会把 city 返回成空数组。
  String? _formatPlace(Map<String, Object?> component) {
    final String city = _text(component['city']);
    final String district = _text(component['district']);
    final String province = _text(component['province']);
    final String township = _text(component['township']);

    if (city.isNotEmpty && district.isNotEmpty && city != district) {
      return '$city · $district';
    }
    if (city.isNotEmpty) return city;
    if (district.isNotEmpty) return district;
    if (province.isNotEmpty) return province;
    if (township.isNotEmpty) return township;
    return null;
  }

  /// 高德把空字段编码成空数组而不是空字符串，统一成字符串再判断。
  String _text(Object? value) => value is String ? value.trim() : '';

  String _cacheKey(double lat, double lon) =>
      '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';
}

class _CachedPlace {
  const _CachedPlace({required this.value, required this.atMs});

  final String value;
  final int atMs;
}
