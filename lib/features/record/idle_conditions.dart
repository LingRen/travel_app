import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/geocode/place_service.dart';
import '../../data/weather/weather_service.dart';
import '../../domain/models/location_fix.dart';

/// 记录待机页显示的位置名称与气温。
///
/// 两者都是「有就显示、没有就降级」的附加信息：地名缺失时界面回退成
/// 「当前位置」，气温缺失时整段省略。这里不保存坐标，也不写数据库。
class IdleConditions {
  const IdleConditions({this.place, this.temperatureC});

  /// 形如「成都市 · 武侯区」。null 表示没查到或没配 Key。
  final String? place;

  /// 当前气温（摄氏度，整数）。null 表示查询失败。
  final int? temperatureC;

  static const IdleConditions none = IdleConditions();

  bool get isEmpty => place == null && temperatureC == null;

  /// 待机卡片上的一行文字。调用方只在拿到定位后使用。
  ///
  /// 没有地名时用「当前位置」占位，而不是留空——用户至少能确认定位已生效；
  /// 没有温度时只显示地名，不显示 `--` 之类会被误读成读数的占位。
  String get label {
    final String placeLabel = place ?? '当前位置';
    if (temperatureC == null) return placeLabel;
    return '$placeLabel · $temperatureC°C';
  }
}

/// 待机页位置 / 天气的加载状态。
///
/// 只在待机时请求；开始记录、结束或定位丢失时清空并作废在途响应。位置按
/// 约 1 km 的网格去重，配合服务内部的 10 分钟缓存，定位刷新不会反复打接口。
class IdleConditionsController extends Notifier<IdleConditions> {
  int _generation = 0;
  String? _requestedKey;

  @override
  IdleConditions build() => IdleConditions.none;

  /// 由记录页在 [RecordState] 变化时调用。
  ///
  /// [idle] 为 false 时只清空、不请求；[fix] 没有坐标时同样不请求。
  void update({required bool idle, LocationFix? fix}) {
    if (!idle || fix == null || !fix.hasPosition) {
      _reset();
      return;
    }

    final String key =
        '${fix.lat!.toStringAsFixed(2)},${fix.lon!.toStringAsFixed(2)}';
    if (key == _requestedKey) return;

    _requestedKey = key;
    // 位置换了，旧地名与旧温度都不再成立。先清掉，避免在新结果回来前
    // 短暂显示上一个街区的地名。
    final int generation = ++_generation;
    state = IdleConditions.none;

    unawaited(_loadPlace(generation, fix.lat!, fix.lon!));
    unawaited(_loadTemperature(generation, fix.lat!, fix.lon!));
  }

  Future<void> _loadPlace(int generation, double lat, double lon) async {
    PlaceInfo? info;
    try {
      info = await ref.read(placeServiceProvider).place(lat: lat, lon: lon);
    } catch (_) {
      return;
    }
    if (!ref.mounted || generation != _generation || info == null) return;
    state = IdleConditions(
      place: info.cityDistrict,
      temperatureC: state.temperatureC,
    );
  }

  Future<void> _loadTemperature(int generation, double lat, double lon) async {
    WeatherNow? weather;
    try {
      weather = await ref
          .read(weatherServiceProvider)
          .currentWeather(lat: lat, lon: lon);
    } catch (_) {
      return;
    }
    if (!ref.mounted || generation != _generation || weather == null) {
      return;
    }
    state = IdleConditions(
      place: state.place,
      temperatureC: weather.temperatureC,
    );
  }

  void _reset() {
    // 自增让在途响应回来后直接丢弃：开始记录后即使请求刚好返回，也不会
    // 把地名 / 温度写回界面。
    _generation++;
    _requestedKey = null;
    if (!state.isEmpty) state = IdleConditions.none;
  }
}

final NotifierProvider<IdleConditionsController, IdleConditions>
idleConditionsProvider =
    NotifierProvider<IdleConditionsController, IdleConditions>(
      IdleConditionsController.new,
    );
