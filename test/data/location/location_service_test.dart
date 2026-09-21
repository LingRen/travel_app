import 'dart:async';

import 'package:cycling_app/data/location/location_service.dart';
import 'package:cycling_app/domain/models/location_fix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

/// 可注入的假定位平台，让单测完全不触碰 geolocator 的静态 API。
///
/// 真实静态方法（`Geolocator.isLocationServiceEnabled()` 等）会走平台通道，
/// 在单测里既弹系统对话框又会挂住，因此定位服务必须依赖抽象接口。
class FakeLocationPlatform implements LocationPlatform {
  FakeLocationPlatform({
    this.serviceEnabled = true,
    this.permission = LocationPermission.whileInUse,
    this.permissionAfterRequest,
    this.appSettingsResult = true,
    this.locationSettingsResult = true,
  });

  bool serviceEnabled;
  LocationPermission permission;

  /// `requestPermission()` 的返回值；null 表示返回当前的 [permission]。
  LocationPermission? permissionAfterRequest;

  bool appSettingsResult;
  bool locationSettingsResult;

  int checkPermissionCalls = 0;
  int requestPermissionCalls = 0;
  int openAppSettingsCalls = 0;
  int openLocationSettingsCalls = 0;
  LocationSettings? capturedSettings;

  /// 单订阅控制器：事件会先缓冲，订阅后按序吐出，测试完全确定。
  final StreamController<Position> controller = StreamController<Position>();

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async {
    checkPermissionCalls++;
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCalls++;
    final LocationPermission next = permissionAfterRequest ?? permission;
    permission = next;
    return next;
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalls++;
    return appSettingsResult;
  }

  @override
  Future<bool> openLocationSettings() async {
    openLocationSettingsCalls++;
    return locationSettingsResult;
  }

  @override
  Stream<Position> positionStream({required LocationSettings locationSettings}) {
    capturedSettings = locationSettings;
    return controller.stream;
  }
}

/// 构造一个字段互不相同的假定位结果，便于发现映射错位。
Position fakePosition({
  double latitude = 31.2304,
  double longitude = 121.4737,
  int tMs = 1700000000000,
  double altitude = 12.5,
  double speed = 6.5,
  double accuracy = 4.0,
}) =>
    Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.fromMillisecondsSinceEpoch(tMs, isUtc: true),
      altitude: altitude,
      altitudeAccuracy: 1.5,
      accuracy: accuracy,
      heading: 87.0,
      headingAccuracy: 2.0,
      speed: speed,
      speedAccuracy: 0.5,
    );

void main() {
  group('toLocationFix', () {
    test('经纬度、高程、精度与时间戳原样映射，不互换不错位', () {
      final LocationFix fix = toLocationFix(
        fakePosition(
          latitude: 31.2304,
          longitude: 121.4737,
          tMs: 1700000000000,
          altitude: 12.5,
          accuracy: 4.0,
        ),
      );

      expect(fix.lat, 31.2304);
      expect(fix.lon, 121.4737);
      expect(fix.altitudeM, 12.5);
      expect(fix.accuracyM, 4.0);
      expect(fix.tMs, 1700000000000);
      expect(fix.hasPosition, isTrue);
    });

    test('速度按 m/s 原样保留，不做 km/h 换算', () {
      final LocationFix fix = toLocationFix(fakePosition(speed: 10.0));

      expect(fix.speedMps, 10.0);
    });

    test('iOS 速度不可用时的 -1 原样保留，交给 RecordingSession 判断', () {
      final LocationFix fix = toLocationFix(fakePosition(speed: -1));

      expect(fix.speedMps, -1.0);
    });

    test('时间戳取自 Position.timestamp 而不是当前时间', () {
      const int oldMs = 1000000000000; // 2001-09-09，远早于测试运行时刻
      final LocationFix fix = toLocationFix(fakePosition(tMs: oldMs));

      expect(fix.tMs, oldMs);
    });

    test('南半球与西经的负值不被取绝对值', () {
      final LocationFix fix = toLocationFix(
        fakePosition(latitude: -33.8688, longitude: -70.6693),
      );

      expect(fix.lat, -33.8688);
      expect(fix.lon, -70.6693);
    });
  });

  group('checkReadiness', () {
    test('定位服务关闭时返回 serviceDisabled，且不申请权限', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform(
        serviceEnabled: false,
        permission: LocationPermission.denied,
      );

      final LocationReadiness readiness =
          await LocationService(platform: platform).checkReadiness();

      expect(readiness, LocationReadiness.serviceDisabled);
      expect(platform.checkPermissionCalls, 0);
      expect(platform.requestPermissionCalls, 0);
    });

    test('权限为 whileInUse 时返回 ready，不再申请', () async {
      final FakeLocationPlatform platform =
          FakeLocationPlatform(permission: LocationPermission.whileInUse);

      expect(
        await LocationService(platform: platform).checkReadiness(),
        LocationReadiness.ready,
      );
      expect(platform.requestPermissionCalls, 0);
    });

    test('权限为 always 时返回 ready', () async {
      final FakeLocationPlatform platform =
          FakeLocationPlatform(permission: LocationPermission.always);

      expect(
        await LocationService(platform: platform).checkReadiness(),
        LocationReadiness.ready,
      );
    });

    test('权限被拒时可再次申请，申请后授予则 ready', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform(
        permission: LocationPermission.denied,
        permissionAfterRequest: LocationPermission.whileInUse,
      );

      expect(
        await LocationService(platform: platform).checkReadiness(),
        LocationReadiness.ready,
      );
      expect(platform.requestPermissionCalls, 1);
    });

    test('权限被拒且申请后仍被拒返回 permissionDenied', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform(
        permission: LocationPermission.denied,
        permissionAfterRequest: LocationPermission.denied,
      );

      expect(
        await LocationService(platform: platform).checkReadiness(),
        LocationReadiness.permissionDenied,
      );
      expect(platform.requestPermissionCalls, 1);
    });

    test('权限被永久拒绝时返回 permissionDeniedForever，且不再弹窗申请', () async {
      final FakeLocationPlatform platform =
          FakeLocationPlatform(permission: LocationPermission.deniedForever);

      expect(
        await LocationService(platform: platform).checkReadiness(),
        LocationReadiness.permissionDeniedForever,
      );
      expect(platform.requestPermissionCalls, 0);
    });

    test('权限被拒但申请后被永久拒绝返回 permissionDeniedForever', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform(
        permission: LocationPermission.denied,
        permissionAfterRequest: LocationPermission.deniedForever,
      );

      expect(
        await LocationService(platform: platform).checkReadiness(),
        LocationReadiness.permissionDeniedForever,
      );
      expect(platform.requestPermissionCalls, 1);
    });
  });

  group('系统设置跳转', () {
    test('openAppSettings 委托给平台并返回其结果', () async {
      final FakeLocationPlatform platform =
          FakeLocationPlatform(appSettingsResult: false);

      expect(await LocationService(platform: platform).openAppSettings(),
          isFalse);
      expect(platform.openAppSettingsCalls, 1);
    });

    test('openLocationSettings 委托给平台并返回其结果', () async {
      final FakeLocationPlatform platform =
          FakeLocationPlatform(locationSettingsResult: true);

      expect(
          await LocationService(platform: platform).openLocationSettings(),
          isTrue);
      expect(platform.openLocationSettingsCalls, 1);
    });
  });

  group('fixes', () {
    test('定位流逐条把 Position 翻译成 LocationFix', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform();
      final LocationService service = LocationService(platform: platform);

      platform.controller.add(fakePosition(tMs: 1000, latitude: 31.1));
      platform.controller.add(fakePosition(tMs: 2000, latitude: 31.2));

      // 单订阅控制器会缓冲订阅前的事件；取满 2 条即完成，不 await close()
      // （close 的 future 要等 done 事件送达监听者，此时订阅已被取消）。
      final List<LocationFix> fixes = await service.fixes().take(2).toList();
      platform.controller.close();

      expect(fixes.length, 2);
      expect(fixes[0].tMs, 1000);
      expect(fixes[0].lat, 31.1);
      expect(fixes[1].tMs, 2000);
      expect(fixes[1].lat, 31.2);
    });

    test('定位流把构造好的定位设置传给平台', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform();

      LocationService(platform: platform).fixes();

      final LocationSettings? settings = platform.capturedSettings;
      expect(settings, isNotNull);
      expect(settings!.accuracy, LocationAccuracy.best);
      expect(settings.distanceFilter, 0);
    });
  });

  group('buildLocationSettings', () {
    test('Android：不做系统侧距离过滤，并配置前台服务通知', () {
      final LocationSettings settings = buildLocationSettings(isAndroid: true);

      expect(settings, isA<AndroidSettings>());
      expect(settings.accuracy, LocationAccuracy.best);
      expect(settings.distanceFilter, 0);

      final ForegroundNotificationConfig? config =
          (settings as AndroidSettings).foregroundNotificationConfig;
      expect(config, isNotNull);
      expect(config!.notificationTitle, '骑行记录中');
      expect(config.setOngoing, isTrue);
      expect(config.enableWakeLock, isTrue);
    });

    test('iOS：健身活动类型、后台持续更新、不自动暂停', () {
      final LocationSettings settings = buildLocationSettings(isAndroid: false);

      expect(settings, isA<AppleSettings>());
      expect(settings.accuracy, LocationAccuracy.best);
      expect(settings.distanceFilter, 0);

      final AppleSettings apple = settings as AppleSettings;
      expect(apple.activityType, ActivityType.fitness);
      expect(apple.pauseLocationUpdatesAutomatically, isFalse);
      expect(apple.allowBackgroundLocationUpdates, isTrue);
      expect(apple.showBackgroundLocationIndicator, isTrue);
    });
  });
}
