import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/analysis/gcj02.dart';

/// 逆地理编码返回的地址分量。
///
/// 高德在部分区域会把城市、区县或街道返回成空数组，构造时统一成去掉首尾
/// 空白的字符串；全部为空时服务返回 null，而不是一个空壳对象。
class PlaceInfo {
  const PlaceInfo({
    required this.city,
    required this.district,
    required this.township,
    required this.province,
  });

  final String city;
  final String district;
  final String township;
  final String province;

  /// 待机页用的「城市 · 区县」，例如「成都市 · 武侯区」。
  String get cityDistrict {
    final String joined = _join(<String>[city, district]);
    return joined.isEmpty ? short : joined;
  }

  /// 详情页用的「城市 · 区县 · 街道/乡镇」。
  String get full {
    final String joined = _join(<String>[city, district, township]);
    return joined.isEmpty ? short : joined;
  }

  /// 历史列表用的短地名：优先区县，其次城市、省份、街道。
  String get short {
    for (final String value in <String>[district, city, province, township]) {
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// 去掉空字段与相邻重复项，避免「成都市 · 成都市」这种高德特殊返回。
  static String _join(List<String> parts) {
    final List<String> out = <String>[];
    for (final String part in parts) {
      final String value = part.trim();
      if (value.isEmpty) continue;
      if (out.isNotEmpty && out.last == value) continue;
      out.add(value);
    }
    return out.join(' · ');
  }
}

/// 逆地理编码：把 GPS 坐标翻译成可显示的地名。
///
/// 抽成接口是为了让待机页与记录控制器的测试不碰高德接口，也不依赖 Key
/// 是否配置。
abstract class PlaceService {
  /// 返回地址分量；没有 Key、网络失败、响应畸形或没有可用地址字段时
  /// 返回 null。
  Future<PlaceInfo?> place({required double lat, required double lon});
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
  Future<PlaceInfo?> place({required double lat, required double lon}) async {
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

      final PlaceInfo? place = _parsePlace(component);
      if (place == null) return null;
      _cache[cacheKey] = _CachedPlace(value: place, atMs: now);
      return place;
    } catch (_) {
      // 地名只是附加信息：失败就显示「当前位置」或省略，不弹错误。
      return null;
    }
  }

  /// 解析高德 `addressComponent`。四个字段都为空时返回 null。
  PlaceInfo? _parsePlace(Map<String, Object?> component) {
    final PlaceInfo place = PlaceInfo(
      city: _text(component['city']),
      district: _text(component['district']),
      township: _text(component['township']),
      province: _text(component['province']),
    );
    if (place.short.isEmpty) return null;
    return place;
  }

  /// 高德把空字段编码成空数组而不是空字符串，统一成字符串再判断。
  String _text(Object? value) => value is String ? value.trim() : '';

  String _cacheKey(double lat, double lon) =>
      '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';
}

class _CachedPlace {
  const _CachedPlace({required this.value, required this.atMs});

  final PlaceInfo value;
  final int atMs;
}
