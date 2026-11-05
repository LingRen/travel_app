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
    Duration keepAliveStopDelay = const Duration(seconds: 2),
  }) : _apiKeyAndroid = apiKeyAndroid,
       _apiKeyIos = apiKeyIos,
       _sdk = sdk ?? AmapFlutterLocationSdk(),
       _fallback = fallback,
       _keepAlive = keepAlive ?? defaultBackgroundKeepAlive(),
       _previewTimeout = previewTimeout,
       _keepAliveStopDelay = keepAliveStopDelay;

  final String _apiKeyAndroid;
  final String _apiKeyIos;
  final AmapLocationSdk _sdk;
  final LocationPlatform _fallback;

  /// Android 前台服务；熄屏后靠它保住进程，iPhone 上是空实现。
  final BackgroundKeepAlive _keepAlive;

  /// 一次定位的超时。超过就回退系统定位，不让待机页一直空着。
  final Duration _previewTimeout;

  /// 全部退订后回收前台服务的延迟。
  ///
  /// 看门狗重建订阅是「取消旧订阅 → 立刻重新订阅」，不留缓冲就会退化成
  /// 一次 stopService + startForegroundService 的抖动。
  final Duration _keepAliveStopDelay;

  bool _initialized = false;

  /// 连续定位是否正在占用同一个原生客户端。
  ///
  /// 一次定位与连续定位共用 [_sdk]（插件按 pluginKey 复用原生客户端），
  /// 所以一次定位的收尾必须知道记录是否已经在跑，不能无条件 stop。
  bool _continuousActive = false;

  /// 当前活跃的连续定位订阅数。
  int _activeStreams = 0;

  /// 本次记录是否已经拉起过前台服务。
  ///
  /// Android 12+ 禁止从后台启动前台服务；重建订阅发生在熄屏骑行中时，如果再
  /// 拉起一次，系统会拒绝并抛 `ForegroundServiceDidNotStartInTimeException`
  /// 把整个进程杀掉（K40 实测闪退）。所以整个记录期只拉起一次，后续重建复用它。
  bool _keepAliveStarted = false;

  /// 退订后回收服务的定时器；重建订阅会把它取消。
  Timer? _keepAliveStopTimer;

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
  ///
  /// 订阅必须早于 [AmapLocationSdk.configure] / [AmapLocationSdk.start]：插件在
  /// 第一次设置参数或启动时创建原生定位客户端，并用当时从 EventChannel 拿到的
  /// sink 回传结果。先启动后订阅时 sink 还是 null，回调会被整条丢弃，且不报错。
  @override
  Stream<Position> positionStream({
    required LocationSettings locationSettings,
  }) {
    _ensureInitialized();

    late StreamController<Position> controller;
    late StreamSubscription<Map<String, Object>> subscription;
    controller = StreamController<Position>(
      onCancel: () async {
        _continuousActive = false;
        _sdk.stop();
        await subscription.cancel();
        _detachKeepAlive();
      },
    );
    subscription = _sdk.events.listen((Map<String, Object> event) {
      final Position? position = positionFromAmapEvent(event);
      if (position != null) controller.add(position);
    });

    _sdk.configure(onceLocation: false);
    _sdk.start();
    _continuousActive = true;
    _attachKeepAlive();

    return controller.stream;
  }

  /// 订阅建立：整个记录期只拉起一次前台服务。
  ///
  /// 启动失败（例如通知权限被拒、后台启动被系统限制）不影响定位本身，静默降级；
  /// 同时记住已经尝试过，避免在后台反复重试触发系统的后台启动限制。
  void _attachKeepAlive() {
    _activeStreams++;
    _keepAliveStopTimer?.cancel();
    _keepAliveStopTimer = null;
    if (_keepAliveStarted) return;
    _keepAliveStarted = true;
    unawaited(_keepAlive.start().catchError((Object _) {}));
  }

  /// 订阅取消：等所有订阅都退出后再回收服务。
  ///
  /// 看门狗的「取消旧订阅 → 立刻重新订阅」会在这个延迟内重新建立订阅，
  /// 于是服务既不停止也不会被重复启动。
  void _detachKeepAlive() {
    _activeStreams--;
    if (_activeStreams > 0) return;
    _keepAliveStopTimer?.cancel();
    _keepAliveStopTimer = Timer(_keepAliveStopDelay, () {
      _keepAliveStopTimer = null;
      _keepAliveStarted = false;
      unawaited(_keepAlive.stop().catchError((Object _) {}));
    });
  }

  /// 一次定位：优先高德，超时或失败时回退系统定位一次（见设计文档）。
  @override
  Future<Position> getCurrentPosition({
    required LocationSettings locationSettings,
  }) async {
    _ensureInitialized();

    // 同 [positionStream]：先订阅拿到 sink，再启动定位客户端。
    final Stream<Map<String, Object>> events = _sdk.events;
    final Completer<Position> completer = Completer<Position>();
    final StreamSubscription<Map<String, Object>> subscription = events.listen(
      (Map<String, Object> event) {
        final Position? position = positionFromAmapEvent(event);
        if (position != null && !completer.isCompleted) {
          completer.complete(position);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );

    try {
      _sdk.configure(onceLocation: true);
      _sdk.start();
      return await completer.future.timeout(_previewTimeout);
    } catch (_) {
      return _fallback.getCurrentPosition(locationSettings: locationSettings);
    } finally {
      // 记录已经接管同一个原生客户端时不能停：待机页这次一次定位常常在开始
      // 记录之后才超时，这里 stop() 会把刚启动的连续定位一起停掉，整条流
      // 再也收不到回调（11:37 真机日志复现：连续 start 后 3 秒被 stop）。
      if (!_continuousActive) _sdk.stop();
      await subscription.cancel();
    }
  }
}
