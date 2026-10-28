import 'dart:convert';

import 'package:cycling_app/data/geocode/place_service.dart';
import 'package:cycling_app/domain/analysis/gcj02.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _jsonResponse(Object body, {int statusCode = 200}) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );

Object _regeocode({
  Object? city = '成都市',
  Object? district = '武侯区',
  Object? province = '四川省',
  Object? township = '桂溪街道',
}) => <String, Object?>{
  'status': '1',
  'regeocode': <String, Object?>{
    'addressComponent': <String, Object?>{
      'city': city,
      'district': district,
      'province': province,
      'township': township,
    },
  },
};

void main() {
  group('AmapPlaceService', () {
    test('没有配置 Key 时直接返回 null，不发请求', () async {
      int calls = 0;
      final AmapPlaceService service = AmapPlaceService(
        client: MockClient((_) async {
          calls++;
          return _jsonResponse(_regeocode());
        }),
        key: '   ',
      );

      expect(await service.place(lat: 30, lon: 120), isNull);
      expect(calls, 0);
    });

    test('请求前把 WGS-84 转成 GCJ-02，并解析地址分量', () async {
      Uri? requested;
      final AmapPlaceService service = AmapPlaceService(
        client: MockClient((http.Request request) async {
          requested = request.url;
          return _jsonResponse(_regeocode());
        }),
        key: 'test-key',
      );

      // 天安门：测试里用与 gcj02_test 相同的已知偏移值。
      final PlaceInfo? place = await service.place(
        lat: 39.90750,
        lon: 116.39123,
      );

      expect(place!.cityDistrict, '成都市 · 武侯区');
      expect(place.full, '成都市 · 武侯区 · 桂溪街道');
      expect(place.short, '武侯区');
      expect(requested!.host, 'restapi.amap.com');
      expect(requested!.path, '/v3/geocode/regeo');
      expect(requested!.queryParameters['key'], 'test-key');
      expect(requested!.queryParameters['extensions'], 'base');
      expect(requested!.queryParameters['radius'], '1000');

      final ({double lat, double lon}) gcj = wgs84ToGcj02(39.90750, 116.39123);
      expect(
        requested!.queryParameters['location'],
        '${gcj.lon.toStringAsFixed(6)},${gcj.lat.toStringAsFixed(6)}',
      );
    });

    test('高德把 city 返回成空数组时退回区县', () async {
      final AmapPlaceService service = AmapPlaceService(
        client: MockClient(
          (_) async =>
              _jsonResponse(_regeocode(city: <Object?>[], district: '龙泉驿区')),
        ),
        key: 'test-key',
      );

      final PlaceInfo? place = await service.place(lat: 30, lon: 120);
      expect(place!.short, '龙泉驿区');
      expect(place.full, '龙泉驿区 · 桂溪街道');
    });

    test('没有城市与区县时退回省份，再退回街道', () async {
      Future<PlaceInfo?> query(
        Object? city,
        Object? district,
        Object? province,
      ) => AmapPlaceService(
        client: MockClient(
          (_) async => _jsonResponse(
            _regeocode(
              city: city,
              district: district,
              province: province,
              township: '桂溪街道',
            ),
          ),
        ),
        key: 'test-key',
      ).place(lat: 30, lon: 120);

      final PlaceInfo? provinceOnly = await query(null, null, '四川省');
      expect(provinceOnly!.short, '四川省');
      expect(provinceOnly.cityDistrict, '四川省');

      final PlaceInfo? townshipOnly = await query(null, null, null);
      expect(townshipOnly!.short, '桂溪街道');
      expect(townshipOnly.cityDistrict, '桂溪街道');
    });

    test('status 不是 1、非 200、畸形 JSON 时返回 null', () async {
      Future<PlaceInfo?> query(MockClient client) => AmapPlaceService(
        client: client,
        key: 'test-key',
      ).place(lat: 30, lon: 120);

      expect(
        await query(
          MockClient(
            (_) async => _jsonResponse(<String, Object?>{
              'status': '0',
              'info': 'INVALID_USER_KEY',
            }),
          ),
        ),
        isNull,
      );
      expect(
        await query(
          MockClient((_) async => _jsonResponse(_regeocode(), statusCode: 500)),
        ),
        isNull,
      );
      expect(
        await query(MockClient((_) async => http.Response('not json', 200))),
        isNull,
      );
    });

    test('网络异常返回 null', () async {
      final PlaceInfo? value = await AmapPlaceService(
        client: MockClient((_) async => throw const SocketExceptionLike()),
        key: 'test-key',
      ).place(lat: 30, lon: 120);

      expect(value, isNull);
    });

    test('超时返回 null', () async {
      final AmapPlaceService service = AmapPlaceService(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return _jsonResponse(_regeocode());
        }),
        key: 'test-key',
        timeout: const Duration(milliseconds: 10),
      );

      expect(await service.place(lat: 30, lon: 120), isNull);
    });

    test('同一网格 10 分钟内复用缓存，过期后重新请求', () async {
      int calls = 0;
      int nowMs = 1000;
      final AmapPlaceService service = AmapPlaceService(
        client: MockClient((_) async {
          calls++;
          return _jsonResponse(_regeocode());
        }),
        key: 'test-key',
        nowMs: () => nowMs,
      );

      expect(
        (await service.place(lat: 30.5728, lon: 104.0668))!.cityDistrict,
        '成都市 · 武侯区',
      );
      expect(
        (await service.place(lat: 30.5731, lon: 104.0671))!.cityDistrict,
        '成都市 · 武侯区',
      );
      expect(calls, 1);

      nowMs += 9 * 60 * 1000;
      await service.place(lat: 30.5728, lon: 104.0668);
      expect(calls, 1);

      nowMs += 2 * 60 * 1000;
      await service.place(lat: 30.5728, lon: 104.0668);
      expect(calls, 2);
    });
  });
}

/// 用自定义异常模拟网络错误，避免测试依赖 `dart:io`。
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
