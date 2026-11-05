import 'dart:async';
import 'dart:math' as math;

import 'package:cycling_app/data/location/amap_location_platform.dart';
import 'package:cycling_app/data/location/background_keep_alive.dart';
import 'package:cycling_app/data/location/location_service.dart';
import 'package:cycling_app/domain/analysis/gcj02.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

/// 假的高德 SDK：记录调用顺序，事件由测试手动灌入。
class FakeAmapSdk implements AmapLocationSdk {
  /// 广播控制器：同一条流允许被看门狗反复订阅。
  ///
  /// `onListen` 记进 [calls]，用来断言「先订阅、后启动」——真实插件的原生
  /// sink 就是在这时候注册的。
  late final StreamController<Map<String, Object>> controller =
      StreamController<Map<String, Object>>.broadcast(
        onListen: () => calls.add('listen'),
        onCancel: () => calls.add('cancel'),
      );

  final List<String> calls = <String>[];
  bool lastOnceLocation = false;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Stream<Map<String, Object>> get events => controller.stream;

  @override
  void setApiKey({required String android, required String ios}) {
    calls.add('setApiKey');
  }

  @override
  void updatePrivacyShow({required bool hasContains, required bool hasShow}) {
    calls.add('updatePrivacyShow');
  }

  @override
  void updatePrivacyAgree({required bool hasAgree}) {
    calls.add('updatePrivacyAgree');
  }

  @override
  void configure({required bool onceLocation}) {
    calls.add('configure');
    lastOnceLocation = onceLocation;
  }

  @override
  void start() {
    calls.add('start');
    startCalls++;
  }

  @override
  void stop() {
    calls.add('stop');
    stopCalls++;
  }

  @override
  void destroy() => calls.add('destroy');
}

/// 记录前台服务在测试里的替身：只记启停次数。
class FakeBackgroundKeepAlive implements BackgroundKeepAlive {
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<void> start() async => startCalls++;

  @override
  Future<void> stop() async => stopCalls++;
}

/// 启动即失败的替身：对应 Android 12+ 拒绝后台启动前台服务。
class _FailingBackgroundKeepAlive implements BackgroundKeepAlive {
  @override
  Future<void> start() async =>
      throw StateError('Background started FGS: Disallowed');

  @override
  Future<void> stop() async {}
}

/// 只用于验证回退与权限透传的假系统平台。
class FakeFallbackPlatform implements LocationPlatform {
  Position? currentPosition;
  int currentPositionCalls = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Stream<Position> positionStream({
    required LocationSettings locationSettings,
  }) => const Stream<Position>.empty();

  @override
  Future<Position> getCurrentPosition({
    required LocationSettings locationSettings,
  }) async {
    currentPositionCalls++;
    final Position? position = currentPosition;
    if (position == null) throw TimeoutException('系统定位也不可用');
    return position;
  }
}

/// 两点间的近似距离（米）。测试范围只有几百米，等距投影足够。
double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const double metersPerDeg = 111320.0;
  final double dx =
      (lon2 - lon1) * metersPerDeg * math.cos(lat1 * math.pi / 180);
  final double dy = (lat2 - lat1) * metersPerDeg;
  return math.sqrt(dx * dx + dy * dy);
}

/// 一条完整的高德定位事件。缺省值对应成都的 GCJ-02 点。
Map<String, Object> amapEvent({
  double latitude = 30.57854,
  double longitude = 104.06973,
  double accuracy = 6.0,
  double speed = 5.2,
  double bearing = 92.0,
  double altitude = 512.0,
  String locationTime = '2026-11-02 09:30:00',
}) => <String, Object>{
  'latitude': latitude,
  'longitude': longitude,
  'accuracy': accuracy,
  'speed': speed,
  'bearing': bearing,
  'altitude': altitude,
  'locationTime': locationTime,
};

void main() {
  group('positionFromAmapEvent 字段映射', () {
    test('GCJ-02 坐标在出口转成 WGS-84，且往返误差不超过 2 米', () {
      // 取一个 WGS-84 原点，正变换得到 SDK 会输出的 GCJ-02 值。
      const double wgsLat = 30.5728;
      const double wgsLon = 104.0668;
      final ({double lat, double lon}) gcj = wgs84ToGcj02(wgsLat, wgsLon);

      final Position position = positionFromAmapEvent(
        amapEvent(latitude: gcj.lat, longitude: gcj.lon),
      )!;

      expect(
        distanceMeters(wgsLat, wgsLon, position.latitude, position.longitude),
        lessThan(2.0),
      );
      // 确实做了逆变换，而不是把 GCJ-02 原样送出。
      expect(
        distanceMeters(gcj.lat, gcj.lon, position.latitude, position.longitude),
        greaterThan(100.0),
      );
    });

    test('速度 -1 原样保留，负朝向由 toLocationFix 置空', () {
      final Position position = positionFromAmapEvent(
        amapEvent(speed: -1, bearing: -1),
      )!;

      expect(position.speed, -1.0);
      expect(toLocationFix(position).speedMps, -1.0);
      expect(toLocationFix(position).headingDeg, isNull);
    });

    test('定位失败事件（带 errorCode）返回 null，不进入定位流', () {
      expect(
        positionFromAmapEvent(<String, Object>{
          'errorCode': 19,
          'errorInfo': '定位失败',
        }),
        isNull,
      );
    });

    test('缺少精度 / 经纬度的事件不可信，返回 null', () {
      expect(
        positionFromAmapEvent(<String, Object>{'latitude': 30.5, 'longitude': 104.0}),
        isNull,
      );
      expect(
        positionFromAmapEvent(<String, Object>{'longitude': 104.0, 'accuracy': 6.0}),
        isNull,
      );
    });

    test('locationTime 解析成本地时间戳', () {
      final Position position = positionFromAmapEvent(
        amapEvent(locationTime: '2026-11-02 09:30:00'),
      )!;

      expect(
        position.timestamp,
        DateTime.parse('2026-11-02 09:30:00'),
      );
    });
  });

  group('AmapLocationPlatform', () {
    late FakeAmapSdk sdk;
    late FakeFallbackPlatform fallback;
    late FakeBackgroundKeepAlive keepAlive;

    setUp(() {
      sdk = FakeAmapSdk();
      fallback = FakeFallbackPlatform();
      keepAlive = FakeBackgroundKeepAlive();
    });

    AmapLocationPlatform buildPlatform() => AmapLocationPlatform(
      apiKeyAndroid: 'android-key',
      apiKeyIos: 'ios-key',
      sdk: sdk,
      fallback: fallback,
      keepAlive: keepAlive,
      previewTimeout: const Duration(milliseconds: 50),
      // 生产值是 2 秒；测试缩短，只为把定时器等出来。
      keepAliveStopDelay: const Duration(milliseconds: 10),
    );

    test('首次订阅先设 Key 与隐私声明，再按 1 Hz 连续定位启动', () async {
      final AmapLocationPlatform platform = buildPlatform();
      final Stream<Position> stream = platform.positionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );

      final Future<Position> first = stream.first;
      sdk.controller.add(amapEvent());
      final Position position = await first;

      expect(sdk.calls.take(6), <String>[
        'setApiKey',
        'updatePrivacyShow',
        'updatePrivacyAgree',
        'listen',
        'configure',
        'start',
      ]);
      expect(sdk.lastOnceLocation, isFalse);
      expect(position.latitude, isNot(closeTo(30.57854, 1e-9)));
      // 高德没有自带前台服务：连续定位期间必须拉起应用侧服务，熄屏后才不被冻结。
      expect(keepAlive.startCalls, 1);
    });

    test('订阅取消时停止高德定位，避免后台继续耗电', () async {
      final AmapLocationPlatform platform = buildPlatform();
      final StreamSubscription<Position> subscription = platform
          .positionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
            ),
          )
          .listen((Position _) {});

      await subscription.cancel();

      expect(sdk.stopCalls, 1);
      // 前台服务延迟回收：给「取消 → 立刻重建订阅」的看门狗留出缓冲。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(keepAlive.stopCalls, 1);
      // 先停原生定位、再退订：插件在启动时才注册 sink，反过来的话停止期间
      // 仍可能有回调涌进已关闭的订阅。
      expect(
        sdk.calls.indexOf('cancel'),
        greaterThan(sdk.calls.indexOf('stop')),
      );
    });

    test('看门狗重建订阅时前台服务只拉起一次，也不被提前回收', () async {
      final AmapLocationPlatform platform = buildPlatform();
      final StreamSubscription<Position> first = platform
          .positionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
            ),
          )
          .listen((Position _) {});

      // 看门狗的真实时序是先取消再立刻重建，这里不等待取消完成。
      unawaited(first.cancel());
      final StreamSubscription<Position> second = platform
          .positionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
            ),
          )
          .listen((Position _) {});

      await Future<void>.delayed(const Duration(milliseconds: 50));
      // 从后台重新拉起前台服务会被 Android 12+ 拒绝，随后系统抛异常杀进程
      // （K40 实测闪退）。重建订阅必须复用已经在跑的服务。
      expect(keepAlive.startCalls, 1);
      expect(keepAlive.stopCalls, 0);

      await second.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(keepAlive.stopCalls, 1);
    });

    test('前台服务启动失败时定位流照常工作', () async {
      final AmapLocationPlatform platform = AmapLocationPlatform(
        apiKeyAndroid: 'android-key',
        apiKeyIos: 'ios-key',
        sdk: sdk,
        fallback: fallback,
        keepAlive: _FailingBackgroundKeepAlive(),
        previewTimeout: const Duration(milliseconds: 50),
        keepAliveStopDelay: const Duration(milliseconds: 10),
      );

      final Stream<Position> stream = platform.positionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      final Future<Position> first = stream.first;
      sdk.controller.add(amapEvent());

      final Position position = await first;
      expect(position.latitude, isNot(closeTo(30.57854, 1e-9)));
    });

    test('记录接管后，待机页一次定位超时不会停掉连续定位', () async {
      fallback.currentPosition = Position(
        latitude: 30.6,
        longitude: 104.0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        altitude: 500,
        altitudeAccuracy: 0,
        accuracy: 20,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      final AmapLocationPlatform platform = buildPlatform();

      // 待机页的粗略定位还没返回，记录就已经开始（真机上两者只差 0.1 秒）。
      final Future<Position> preview = platform.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      final StreamSubscription<Position> subscription = platform
          .positionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
            ),
          )
          .listen((Position _) {});

      final Position position = await preview;
      expect(position.latitude, 30.6);
      // 预览超时只回退系统定位，不能把记录正在用的客户端 stop 掉。
      expect(sdk.stopCalls, 0);
      expect(keepAlive.stopCalls, 0);

      await subscription.cancel();
      expect(sdk.stopCalls, 1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(keepAlive.stopCalls, 1);
    });

    test('连续定位先建立事件订阅再启动，避免原生 sink 为 null 丢掉全部回调', () async {
      final AmapLocationPlatform platform = buildPlatform();
      platform.positionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );

      expect(
        sdk.calls.indexOf('listen'),
        lessThan(sdk.calls.indexOf('configure')),
      );
      expect(
        sdk.calls.indexOf('listen'),
        lessThan(sdk.calls.indexOf('start')),
      );
    });

    test('一次定位同样先订阅后启动，超时后回退系统并释放订阅', () async {
      fallback.currentPosition = Position(
        latitude: 30.6,
        longitude: 104.0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        altitude: 500,
        altitudeAccuracy: 0,
        accuracy: 20,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      final AmapLocationPlatform platform = buildPlatform();

      final Future<Position> result = platform.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      expect(sdk.calls.indexOf('listen'), lessThan(sdk.calls.indexOf('start')));

      final Position position = await result;
      expect(position.latitude, 30.6);
      expect(fallback.currentPositionCalls, 1);
      expect(sdk.stopCalls, 1);
      expect(
        sdk.calls.indexOf('cancel'),
        greaterThan(sdk.calls.indexOf('stop')),
      );
    });

    test('一次定位成功时直接用高德，不碰系统定位', () async {
      final AmapLocationPlatform platform = buildPlatform();

      final Future<Position> result = platform.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      sdk.controller.add(amapEvent());

      final Position position = await result;
      expect(sdk.lastOnceLocation, isTrue);
      expect(position.accuracy, 6.0);
      expect(fallback.currentPositionCalls, 0);
    });

    test('一次定位失败时回退系统定位一次，不让待机页空着', () async {
      fallback.currentPosition = Position(
        latitude: 30.6,
        longitude: 104.0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        altitude: 500,
        altitudeAccuracy: 0,
        accuracy: 20,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      final AmapLocationPlatform platform = buildPlatform();

      // 只给失败事件：高德这条取不到点，超时后应回退系统。
      final Future<Position> result = platform.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      sdk.controller.add(<String, Object>{'errorCode': 19, 'errorInfo': '定位失败'});

      final Position position = await result;
      expect(position.latitude, 30.6);
      expect(fallback.currentPositionCalls, 1);
    });
  });
}
