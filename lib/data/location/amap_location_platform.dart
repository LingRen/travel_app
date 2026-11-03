// 构造参数用公开名（apiKeyAndroid），字段是私有的，无法用 initializing formal，
// 因此这里显式忽略该 lint。
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:amap_flutter_location_plus/amap_flutter_location_plus.dart';
import 'package:amap_flutter_location_plus/amap_location_option.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/analysis/gcj02.dart';
import 'background_keep_alive.dart';
import 'location_service.dart';

/// 高德定位 SDK 的最小抽象。
///
/// 插件本身是静态方法 + 平台通道，单测里既会挂住又无法断言；把这几步收发
/// 抽成接口后，[AmapLocationPlatform] 可以完全在假实现上验证字段映射与坐标口径。
abstract class AmapLocationSdk {
  void setApiKey({required String android, required String ios});

  void updatePrivacyShow({required bool hasContains, required bool hasShow});

  void updatePrivacyAgree({required bool hasAgree});

  /// 设置一次 / 连续定位参数。连续定位间隔 1 秒。
  void configure({required bool onceLocation});

  void start();

  void stop();

  void destroy();

  /// 定位事件流。失败事件也走这条流，里面带 `errorCode`（见设计文档 Spike 结论）。
  Stream<Map<String, Object>> get events;
}

/// 生产实现：转发到 `amap_flutter_location_plus`。
class AmapFlutterLocationSdk implements AmapLocationSdk {
  AmapFlutterLocationSdk() : _location = AMapFlutterLocation();

  final AMapFlutterLocation _location;
  Stream<Map<String, Object>>? _events;

  @override
  Stream<Map<String, Object>> get events => _events ??= _location
      .onLocationChanged()
      // 插件的内部控制器是单订阅流；看门狗会重建订阅，必须包成广播流才允许
      // 反复 listen。
      .asBroadcastStream();

  @override
  void setApiKey({required String android, required String ios}) =>
      AMapFlutterLocation.setApiKey(android, ios);

  @override
  void updatePrivacyShow({required bool hasContains, required bool hasShow}) =>
      AMapFlutterLocation.updatePrivacyShow(hasContains, hasShow);

  @override
  void updatePrivacyAgree({required bool hasAgree}) =>
      AMapFlutterLocation.updatePrivacyAgree(hasAgree);

  @override
  void configure({required bool onceLocation}) {
    _location.setLocationOption(
      AMapLocationOption(
        // 与系统定位同一个节拍：落盘、曲线采样与断点判定都按 1 Hz 设计。
        locationInterval: 1000,
        // 只要坐标，不做逆地理编码：省流量，也省掉一次网络等待。
        needAddress: false,
        locationMode: AMapLocationMode.Hight_Accuracy,
        onceLocation: onceLocation,
        // iOS 后台定位能力随 Phase 4 接入；未配置 capability 前打开会抛异常。
        allowsBackgroundLocationUpdates: false,
        pausesLocationUpdatesAutomatically: false,
        // 与系统定位的 bestForNavigation 对齐，骑行遮挡后更容易接回。
        desiredAccuracy: DesiredAccuracy.BestForNavigation,
        // 不在 SDK 侧做距离过滤，保留用于平滑的原始点。
        distanceFilter: -1,
      ),
    );
  }

  @override
  void start() => _location.startLocation();

  @override
  void stop() => _location.stopLocation();

  @override
  void destroy() {
    _events = null;
    _location.destroy();
  }
}

/// 把一条高德定位事件映射成 geolocator 的 [Position]；失败或字段不完整时返回
/// null。
///
/// 坐标在这里从 GCJ-02 转回 WGS-84，之后就与系统定位同一口径。速度 / 朝向
/// 缺失或无效时给 -1，沿用 [toLocationFix] 的约定（负朝向由它置空）。
Position? positionFromAmapEvent(Map<String, Object> event) {
  // 定位失败与定位成功共用一条流，必须先判错误码（见 Spike 结论）。
  if (event.containsKey('errorCode')) return null;

  final Object? rawLat = event['latitude'];
  final Object? rawLon = event['longitude'];
  final Object? rawAccuracy = event['accuracy'];
  if (rawLat is! num || rawLon is! num || rawAccuracy is! num) return null;

  final double lat = rawLat.toDouble();
  final double lon = rawLon.toDouble();
  if (!lat.isFinite || !lon.isFinite) return null;

  final ({double lat, double lon}) wgs = gcj02ToWgs84(lat, lon);
  final DateTime timestamp =
      _parseAmapTime(event['locationTime']) ?? DateTime.now();

  return Position(
    latitude: wgs.lat,
    longitude: wgs.lon,
    timestamp: timestamp,
    // Android 上非 GPS 点没有海拔，给 0；这类点通常会因精度差被 50 m 门槛挡掉。
    altitude: _asDouble(event['altitude']) ?? 0.0,
    altitudeAccuracy: 0.0,
    accuracy: rawAccuracy.toDouble(),
    // -1 表示本次没有方向，交给 toLocationFix 置空。
    heading: _asDouble(event['bearing']) ?? -1.0,
    headingAccuracy: 0.0,
    speed: _asDouble(event['speed']) ?? -1.0,
    speedAccuracy: 0.0,
  );
}

double? _asDouble(Object? value) =>
    value is num && value.toDouble().isFinite ? value.toDouble() : null;

/// 高德的 `locationTime` 是本地时间字符串（`yyyy-MM-dd HH:mm:ss`）。
DateTime? _parseAmapTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// 高德定位接入层：初始化、隐私声明、事件映射与坐标归一。
///
/// 权限校验、系统设置跳转与「粗略定位回退」仍交给系统定位实现（[fallback]），
/// 高德只接管持续定位流与一次定位。这样切换定位源不会改变记录状态语义。
class AmapLocationPlatform implements LocationPlatform {
  AmapLocationPlatform({
    required String apiKeyAndroid,
    required String apiKeyIos,
    AmapLocationSdk? sdk,
    LocationPlatform fallback = const GeolocatorLocationPlatform(),
    BackgroundKeepAlive? keepAlive,
    Duration previewTimeout = const Duration(seconds: 3),
  }) : _apiKeyAndroid = apiKeyAndroid,
       _apiKeyIos = apiKeyIos,
       _sdk = sdk ?? AmapFlutterLocationSdk(),
       _fallback = fallback,
       _keepAlive = keepAlive ?? defaultBackgroundKeepAlive(),
       _previewTimeout = previewTimeout;

  final String _apiKeyAndroid;
  final String _apiKeyIos;
  final AmapLocationSdk _sdk;
  final LocationPlatform _fallback;

  /// Android 前台服务；熄屏后靠它保住进程，iPhone 上是空实现。
  final BackgroundKeepAlive _keepAlive;

  /// 一次定位的超时。超过就回退系统定位，不让待机页一直空着。
  final Duration _previewTimeout;

  bool _initialized = false;

  /// 插件要求在定位前完成 Key 与隐私声明设置，否则 SDK 不会工作。
  void _ensureInitialized() {
    if (_initialized) return;
    _sdk
      ..setApiKey(android: _apiKeyAndroid, ios: _apiKeyIos)
      ..updatePrivacyShow(hasContains: true, hasShow: true)
      ..updatePrivacyAgree(hasAgree: true);
    _initialized = true;
  }

  @override
  Future<bool> isLocationServiceEnabled() =>
      _fallback.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => _fallback.checkPermission();

  @override
  Future<LocationPermission> requestPermission() => _fallback.requestPermission();

  @override
  Future<bool> openAppSettings() => _fallback.openAppSettings();

  @override
  Future<bool> openLocationSettings() => _fallback.openLocationSettings();

  /// 连续定位流。失败事件在这里被丢弃，由看门狗负责「超过 15 秒没点」的重建。
  @override
  Stream<Position> positionStream({
    required LocationSettings locationSettings,
  }) {
    _ensureInitialized();
    _sdk.configure(onceLocation: false);
    _sdk.start();
    // 前台服务启动失败不影响定位本身（例如通知权限被拒），静默降级。
    unawaited(_keepAlive.start().catchError((Object _) {}));

    late StreamController<Position> controller;
    late StreamSubscription<Map<String, Object>> subscription;
    controller = StreamController<Position>(
      onCancel: () async {
        await subscription.cancel();
        _sdk.stop();
        await _keepAlive.stop().catchError((Object _) {});
      },
    );
    subscription = _sdk.events.listen((Map<String, Object> event) {
      final Position? position = positionFromAmapEvent(event);
      if (position != null) controller.add(position);
    });
    return controller.stream;
  }

  /// 一次定位：优先高德，超时或失败时回退系统定位一次（见设计文档）。
  @override
  Future<Position> getCurrentPosition({
    required LocationSettings locationSettings,
  }) async {
    _ensureInitialized();
    try {
      _sdk.configure(onceLocation: true);
      _sdk.start();
      return await _sdk.events
          .map(positionFromAmapEvent)
          .where((Position? position) => position != null)
          .cast<Position>()
          .first
          .timeout(_previewTimeout);
    } catch (_) {
      return _fallback.getCurrentPosition(locationSettings: locationSettings);
    } finally {
      _sdk.stop();
    }
  }
}
