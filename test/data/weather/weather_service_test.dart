import 'dart:convert';

import 'package:cycling_app/data/weather/weather_service.dart';
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

void main() {
  group('OpenMeteoWeatherService', () {
    test('按 WGS-84 坐标请求当前气温，并把小数四舍五入到整数', () async {
      Uri? requested;
      final OpenMeteoWeatherService service = OpenMeteoWeatherService(
        client: MockClient((http.Request request) async {
          requested = request.url;
          return _jsonResponse(<String, Object?>{
            'current': <String, Object?>{'temperature_2m': 20.2},
          });
        }),
      );

      final int? value = await service.currentTemperatureC(
        lat: 30.5728,
        lon: 104.0668,
      );

      expect(value, 20);
      expect(requested!.host, 'api.open-meteo.com');
      expect(requested!.path, '/v1/forecast');
      expect(requested!.queryParameters['latitude'], '30.5728');
      expect(requested!.queryParameters['longitude'], '104.0668');
      expect(requested!.queryParameters['current'], 'temperature_2m');
      expect(requested!.queryParameters['temperature_unit'], 'celsius');
    });

    test('响应缺字段、非 JSON 或非 200 时返回 null', () async {
      Future<int?> query(MockClient client) =>
          OpenMeteoWeatherService(client: client)
              .currentTemperatureC(lat: 30, lon: 120);

      expect(
        await query(
          MockClient(
            (_) async => _jsonResponse(<String, Object?>{
              'current': <String, Object?>{},
            }),
          ),
        ),
        isNull,
      );
      expect(
        await query(MockClient((_) async => http.Response('not json', 200))),
        isNull,
      );
      expect(
        await query(
          MockClient(
            (_) async => _jsonResponse(<String, Object?>{
              'current': <String, Object?>{'temperature_2m': 20.2},
            }, statusCode: 500),
          ),
        ),
        isNull,
      );
    });

    test('网络异常返回 null，不向调用方抛出', () async {
      final int? value = await OpenMeteoWeatherService(
        client: MockClient((_) async => throw const SocketExceptionLike()),
      ).currentTemperatureC(lat: 30, lon: 120);

      expect(value, isNull);
    });

    test('超时返回 null', () async {
      final OpenMeteoWeatherService service = OpenMeteoWeatherService(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return _jsonResponse(<String, Object?>{
            'current': <String, Object?>{'temperature_2m': 20.2},
          });
        }),
        timeout: const Duration(milliseconds: 10),
      );

      expect(await service.currentTemperatureC(lat: 30, lon: 120), isNull);
    });

    test('同一网格 10 分钟内复用缓存，过期后重新请求', () async {
      int calls = 0;
      int nowMs = 1000;
      final OpenMeteoWeatherService service = OpenMeteoWeatherService(
        client: MockClient((_) async {
          calls++;
          return _jsonResponse(<String, Object?>{
            'current': <String, Object?>{'temperature_2m': 20.2},
          });
        }),
        nowMs: () => nowMs,
      );

      expect(
        await service.currentTemperatureC(lat: 30.5728, lon: 104.0668),
        20,
      );
      // 同一网格内的微小移动：仍然只算一次请求。
      expect(
        await service.currentTemperatureC(lat: 30.5731, lon: 104.0671),
        20,
      );
      expect(calls, 1);

      nowMs += 9 * 60 * 1000;
      await service.currentTemperatureC(lat: 30.5728, lon: 104.0668);
      expect(calls, 1);

      nowMs += 2 * 60 * 1000;
      await service.currentTemperatureC(lat: 30.5728, lon: 104.0668);
      expect(calls, 2);
    });

    test('不同网格各自缓存', () async {
      int calls = 0;
      final OpenMeteoWeatherService service = OpenMeteoWeatherService(
        client: MockClient((_) async {
          calls++;
          return _jsonResponse(<String, Object?>{
            'current': <String, Object?>{'temperature_2m': 20.2},
          });
        }),
      );

      await service.currentTemperatureC(lat: 30.57, lon: 104.06);
      await service.currentTemperatureC(lat: 30.62, lon: 104.11);

      expect(calls, 2);
    });
  });
}

/// 用自定义异常模拟网络错误，避免测试依赖 `dart:io`。
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
