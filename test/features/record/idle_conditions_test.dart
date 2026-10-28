import 'dart:async';

import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/geocode/place_service.dart';
import 'package:cycling_app/data/weather/weather_service.dart';
import 'package:cycling_app/domain/models/location_fix.dart';
import 'package:cycling_app/features/record/idle_conditions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

const LocationFix _fix = LocationFix(tMs: 1000, lat: 30.5728, lon: 104.0668);

class _FakePlaceService implements PlaceService {
  String? result;
  Object? error;
  Completer<String?>? completer;
  int calls = 0;
  double? lastLat;
  double? lastLon;

  @override
  Future<String?> placeName({required double lat, required double lon}) async {
    calls++;
    lastLat = lat;
    lastLon = lon;
    if (error != null) throw error!;
    if (completer != null) return completer!.future;
    return result;
  }
}

class _FakeWeatherService implements WeatherService {
  int? result;
  Object? error;
  Completer<int?>? completer;
  int calls = 0;

  @override
  Future<int?> currentTemperatureC({
    required double lat,
    required double lon,
  }) async {
    calls++;
    if (error != null) throw error!;
    if (completer != null) return completer!.future;
    return result;
  }
}

void main() {
  late _FakePlaceService places;
  late _FakeWeatherService weather;
  late ProviderContainer container;

  setUp(() {
    places = _FakePlaceService();
    weather = _FakeWeatherService();
    container = ProviderContainer(
      overrides: <Override>[
        placeServiceProvider.overrideWithValue(places),
        weatherServiceProvider.overrideWithValue(weather),
      ],
    );
  });

  tearDown(() => container.dispose());

  IdleConditionsController controller() =>
      container.read(idleConditionsProvider.notifier);

  IdleConditions conditions() => container.read(idleConditionsProvider);

  test('待机且有定位时并行查地名与天气', () async {
    places.result = '成都市 · 武侯区';
    weather.result = 20;

    controller().update(idle: true, fix: _fix);
    await Future<void>.delayed(Duration.zero);

    expect(places.calls, 1);
    expect(weather.calls, 1);
    expect(places.lastLat, 30.5728);
    expect(places.lastLon, 104.0668);
    expect(conditions().place, '成都市 · 武侯区');
    expect(conditions().temperatureC, 20);
    expect(conditions().label, '成都市 · 武侯区 · 20°C');
  });

  test('地名缺失回退「当前位置」，气温缺失时只显示地名', () async {
    places.result = null;
    weather.result = 20;
    controller().update(idle: true, fix: _fix);
    await Future<void>.delayed(Duration.zero);
    expect(conditions().label, '当前位置 · 20°C');

    places = _FakePlaceService()..result = '成都市 · 武侯区';
    weather = _FakeWeatherService()..result = null;
    container.dispose();
    container = ProviderContainer(
      overrides: <Override>[
        placeServiceProvider.overrideWithValue(places),
        weatherServiceProvider.overrideWithValue(weather),
      ],
    );
    controller().update(idle: true, fix: _fix);
    await Future<void>.delayed(Duration.zero);
    expect(conditions().label, '成都市 · 武侯区');
  });

  test('未开始记录前不请求', () async {
    controller().update(idle: false, fix: _fix);
    controller().update(idle: true, fix: null);
    await Future<void>.delayed(Duration.zero);

    expect(places.calls, 0);
    expect(weather.calls, 0);
    expect(conditions().isEmpty, isTrue);
  });

  test('同一网格不重复请求，换一个街区才重新查', () async {
    places.result = '成都市 · 武侯区';
    weather.result = 20;

    controller().update(idle: true, fix: _fix);
    await Future<void>.delayed(Duration.zero);
    controller().update(
      idle: true,
      fix: const LocationFix(tMs: 2000, lat: 30.5731, lon: 104.0671),
    );
    await Future<void>.delayed(Duration.zero);

    expect(places.calls, 1);
    expect(weather.calls, 1);

    controller().update(
      idle: true,
      fix: const LocationFix(tMs: 3000, lat: 30.62, lon: 104.11),
    );
    await Future<void>.delayed(Duration.zero);

    expect(places.calls, 2);
    expect(weather.calls, 2);
  });

  test('开始记录后清空，并在途响应不会写回', () async {
    places.completer = Completer<String?>();
    weather.completer = Completer<int?>();

    controller().update(idle: true, fix: _fix);
    controller().update(idle: false, fix: _fix);

    places.completer!.complete('成都市 · 武侯区');
    weather.completer!.complete(20);
    await Future<void>.delayed(Duration.zero);

    expect(conditions().isEmpty, isTrue);
  });

  test('服务抛异常时保持静默，不留下半截状态', () async {
    places.error = StateError('boom');
    weather.error = StateError('boom');

    controller().update(idle: true, fix: _fix);
    await Future<void>.delayed(Duration.zero);

    expect(conditions().isEmpty, isTrue);
  });
}
