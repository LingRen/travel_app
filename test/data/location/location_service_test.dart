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
  Stream<Position> positionStream({
    required LocationSettings locationSettings,
  }) {
    capturedSettings = locationSettings;
    return controller.stream;
  }

  /// 一次性定位的结果；null 表示抛错（模拟超时/无可用位置）。
  Position? currentPosition;
  LocationSettings? capturedCurrentSettings;
  int getCurrentPositionCalls = 0;

  @override
  Future<Position> getCurrentPosition({
    required LocationSettings locationSettings,
  }) async {
    getCurrentPositionCalls++;
    capturedCurrentSettings = locationSettings;
    final Position? position = currentPosition;
    if (position == null) throw TimeoutException('定位超时');
    return position;
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
  double heading = 87.0,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.fromMillisecondsSinceEpoch(tMs, isUtc: true),
  altitude: altitude,
  altitudeAccuracy: 1.5,
  accuracy: accuracy,
  heading: heading,
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

    test('朝向原样映射，只落在内存字段 headingDeg', () {
      final LocationFix fix = toLocationFix(fakePosition(heading: 87));

      expect(fix.headingDeg, 87.0);
    });

    test('负朝向表示没有方向，置空而不是取绝对值', () {
      expect(toLocationFix(fakePosition(heading: -1)).headingDeg, isNull);
    });

    test('安卓静止时报的 0 度保留，由会话层的速度门槛挡掉', () {
      expect(toLocationFix(fakePosition(heading: 0)).headingDeg, 0.0);
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

  group('hasPermission', () {
    test('已授权时返回 true，且不申请权限', () async {
      for (final LocationPermission permission in <LocationPermission>[
        LocationPermission.whileInUse,
        LocationPermission.always,
      ]) {
        final FakeLocationPlatform platform = FakeLocationPlatform(
          permission: permission,
        );
        expect(
          await LocationService(platform: platform).hasPermission(),
          isTrue,
          reason: permission.name,
        );
        expect(platform.requestPermissionCalls, 0);
      }
    });

    test('未授权时返回 false，且不弹系统申请框', () async {
      for (final LocationPermission permission in <LocationPermission>[
        LocationPermission.denied,
        LocationPermission.deniedForever,
      ]) {
        final FakeLocationPlatform platform = FakeLocationPlatform(
          permission: permission,
        );
        expect(
          await LocationService(platform: platform).hasPermission(),
          isFalse,
          reason: permission.name,
        );
        expect(platform.requestPermissionCalls, 0);
      }
    });
  });

  group('checkReadiness', () {
    test('定位服务关闭时返回 serviceDisabled，且不申请权限', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform(
        serviceEnabled: false,
        permission: LocationPermission.denied,
      );

      final LocationReadiness readiness = await LocationService(
        platform: platform,
      ).checkReadiness();

      expect(readiness, LocationReadiness.serviceDisabled);
      expect(platform.checkPermissionCalls, 0);
      expect(platform.requestPermissionCalls, 0);
    });

    test('权限为 whileInUse 时返回 ready，不再申请', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform(
        permission: LocationPermission.whileInUse,
      );

      expect(
        await LocationService(platform: platform).checkReadiness(),
        LocationReadiness.ready,
      );
      expect(platform.requestPermissionCalls, 0);
    });

    test('权限为 always 时返回 ready', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform(
        permission: LocationPermission.always,
      );

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
      final FakeLocationPlatform platform = FakeLocationPlatform(
        permission: LocationPermission.deniedForever,
      );

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

  group('shouldSuggestAlwaysPermission', () {
    test('iOS 只有「使用期间」权限时返回 true', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform(
        permission: LocationPermission.whileInUse,
      );

      expect(
        await LocationService(
          platform: platform,
          isIOS: true,
        ).shouldSuggestAlwaysPermission(),
        isTrue,
      );
    });

    test('iOS 已是「始终允许」时返回 false', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform(
        permission: LocationPermission.always,
      );

      expect(
        await LocationService(
          platform: platform,
          isIOS: true,
        ).shouldSuggestAlwaysPermission(),
        isFalse,
      );
    });

    test('Android 即使用「使用期间」也不提示，且不读权限', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform(
        permission: LocationPermission.whileInUse,
      );

      expect(
        await LocationService(
          platform: platform,
          isIOS: false,
        ).shouldSuggestAlwaysPermission(),
        isFalse,
      );
      expect(platform.checkPermissionCalls, 0);
    });
  });

  group('系统设置跳转', () {
    test('openAppSettings 委托给平台并返回其结果', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform(
        appSettingsResult: false,
      );

      expect(
        await LocationService(platform: platform).openAppSettings(),
        isFalse,
      );
      expect(platform.openAppSettingsCalls, 1);
    });

    test('openLocationSettings 委托给平台并返回其结果', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform(
        locationSettingsResult: true,
      );

      expect(
        await LocationService(platform: platform).openLocationSettings(),
        isTrue,
      );
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
      expect(settings!.accuracy, LocationAccuracy.bestForNavigation);
      expect(settings.distanceFilter, 0);
    });
  });

  group('quickPreviewFix', () {
    test('用中精度一次性请求，并把 Position 翻译成 LocationFix', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform()
        ..currentPosition = fakePosition(
          latitude: 30.6,
          longitude: 104.0,
          tMs: 5000,
        );
      final LocationService service = LocationService(platform: platform);

      final LocationFix? fix = await service.quickPreviewFix();

      expect(fix, isNotNull);
      expect(fix!.lat, 30.6);
      expect(fix.lon, 104.0);
      expect(fix.tMs, 5000);

      final LocationSettings? settings = platform.capturedCurrentSettings;
      expect(settings!.accuracy, LocationAccuracy.medium);
      expect(settings.timeLimit, const Duration(seconds: 8));
    });

    test('Android 的粗略定位强制走系统 LocationManager，绕开 GMS FLP', () {
      final LocationSettings settings = buildPreviewSettings(isAndroid: true);

      expect(settings, isA<AndroidSettings>());
      expect(settings.accuracy, LocationAccuracy.medium);
      expect(settings.timeLimit, const Duration(seconds: 8));
      expect((settings as AndroidSettings).forceLocationManager, isTrue);
    });

    test('拿不到位置（超时）时返回 null，不向外抛', () async {
      final FakeLocationPlatform platform = FakeLocationPlatform();
      final LocationService service = LocationService(platform: platform);

      expect(await service.quickPreviewFix(), isNull);
      expect(platform.getCurrentPositionCalls, 1);
    });
  });

  group('buildLocationSettings', () {
    test('Android：不做系统侧距离过滤，并配置前台服务通知', () {
      final LocationSettings settings = buildLocationSettings(isAndroid: true);

      expect(settings, isA<AndroidSettings>());
      expect(settings.accuracy, LocationAccuracy.best);
      expect(settings.distanceFilter, 0);

      final AndroidSettings android = settings as AndroidSettings;
      // 真机实测无 GMS 的机器不写这项只有约 5 秒一个点；落盘与曲线口径都按
      // 1 Hz 设计的，必须显式要。
      expect(android.intervalDuration, const Duration(seconds: 1));

      final ForegroundNotificationConfig? config =
          android.foregroundNotificationConfig;
      expect(config, isNotNull);
      expect(config!.notificationTitle, '运动记录中');
      expect(config.setOngoing, isTrue);
      expect(config.enableWakeLock, isTrue);
    });

    test('iOS：健身活动类型、后台持续更新、不自动暂停', () {
      final LocationSettings settings = buildLocationSettings(isAndroid: false);

      expect(settings, isA<AppleSettings>());
      // bestForNavigation 会允许陀螺仪/加速度计参与解算：楼群与高架下短暂遮挡
      // 后能更快接回定位，减少十几秒的空档。
      expect(settings.accuracy, LocationAccuracy.bestForNavigation);
      expect(settings.distanceFilter, 0);

      final AppleSettings apple = settings as AppleSettings;
      expect(apple.activityType, ActivityType.fitness);
      expect(apple.pauseLocationUpdatesAutomatically, isFalse);
      expect(apple.allowBackgroundLocationUpdates, isTrue);
      expect(apple.showBackgroundLocationIndicator, isTrue);
    });
  });
}
