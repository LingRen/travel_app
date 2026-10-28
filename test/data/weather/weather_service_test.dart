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
    test('按 WGS-84 坐标请求当前天气，并把气温四舍五入到整数', () async {
      Uri? requested;
      final OpenMeteoWeatherService service = OpenMeteoWeatherService(
        client: MockClient((http.Request request) async {
          requested = request.url;
          return _jsonResponse(<String, Object?>{
            'current': <String, Object?>{
              'temperature_2m': 20.2,
              'weather_code': 0,
            },
          });
        }),
      );

      final WeatherNow? value = await service.currentWeather(
        lat: 30.5728,
        lon: 104.0668,
      );

      expect(value!.temperatureC, 20);
      expect(value.description, '晴');
      expect(value.label, '晴 20°C');
      expect(requested!.host, 'api.open-meteo.com');
      expect(requested!.path, '/v1/forecast');
      expect(requested!.queryParameters['latitude'], '30.5728');
      expect(requested!.queryParameters['longitude'], '104.0668');
      expect(
        requested!.queryParameters['current'],
        'temperature_2m,weather_code',
      );
      expect(requested!.queryParameters['temperature_unit'], 'celsius');
    });

    test('天气码缺失时仍返回温度，描述为 null', () async {
      final WeatherNow? value = await OpenMeteoWeatherService(
        client: MockClient(
          (_) async => _jsonResponse(<String, Object?>{
            'current': <String, Object?>{'temperature_2m': 18.6},
          }),
        ),
      ).currentWeather(lat: 30, lon: 120);

      expect(value!.temperatureC, 19);
      expect(value.description, isNull);
      expect(value.label, '19°C');
    });

    test('未知天气码不编造描述', () {
      expect(weatherDescriptionOf(123), isNull);
      expect(weatherDescriptionOf(null), isNull);
      expect(weatherDescriptionOf(61), '小雨');
      expect(weatherDescriptionOf(95), '雷阵雨');
    });

    test('响应缺字段、非 JSON 或非 200 时返回 null', () async {
      Future<WeatherNow?> query(MockClient client) =>
          OpenMeteoWeatherService(client: client)
              .currentWeather(lat: 30, lon: 120);

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
      final WeatherNow? value = await OpenMeteoWeatherService(
        client: MockClient((_) async => throw const SocketExceptionLike()),
      ).currentWeather(lat: 30, lon: 120);

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

      expect(await service.currentWeather(lat: 30, lon: 120), isNull);
    });

    test('同一网格 10 分钟内复用缓存，过期后重新请求', () async {
      int calls = 0;
      int nowMs = 1000;
      final OpenMeteoWeatherService service = OpenMeteoWeatherService(
        client: MockClient((_) async {
          calls++;
          return _jsonResponse(<String, Object?>{
            'current': <String, Object?>{
              'temperature_2m': 20.2,
              'weather_code': 0,
            },
          });
        }),
        nowMs: () => nowMs,
      );

      expect(
        (await service.currentWeather(lat: 30.5728, lon: 104.0668))
            ?.temperatureC,
        20,
      );
      // 同一网格内的微小移动：仍然只算一次请求。
      expect(
        (await service.currentWeather(lat: 30.5731, lon: 104.0671))
            ?.temperatureC,
        20,
      );
      expect(calls, 1);

      nowMs += 9 * 60 * 1000;
      await service.currentWeather(lat: 30.5728, lon: 104.0668);
      expect(calls, 1);

      nowMs += 2 * 60 * 1000;
      await service.currentWeather(lat: 30.5728, lon: 104.0668);
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

      await service.currentWeather(lat: 30.57, lon: 104.06);
      await service.currentWeather(lat: 30.62, lon: 104.11);

      expect(calls, 2);
    });
  });
}

/// 用自定义异常模拟网络错误，避免测试依赖 `dart:io`。
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
