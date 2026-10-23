import 'dart:io';

import 'package:geolocator/geolocator.dart';

import '../../domain/models/location_fix.dart';

/// 开始记录前的定位前置校验结果。见设计文档 11.1（阻断类）。
enum LocationReadiness {
  ready,

  /// 系统定位开关关闭。
  serviceDisabled,

  /// 权限被拒，可以再次申请。
  permissionDenied,

  /// 权限被永久拒绝，只能去系统设置里改。
  permissionDeniedForever,
}

/// geolocator 静态 API 的可注入抽象。
///
/// 静态方法（`Geolocator.checkPermission()` 等）会直接走平台通道，单测里既会
/// 弹系统对话框又会挂住，因此 [LocationService] 只依赖这个接口，测试注入假实现。
abstract class LocationPlatform {
  Future<bool> isLocationServiceEnabled();

  Future<LocationPermission> checkPermission();

  Future<LocationPermission> requestPermission();

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();

  Stream<Position> positionStream({required LocationSettings locationSettings});

  /// 一次性定位请求。
  Future<Position> getCurrentPosition({
    required LocationSettings locationSettings,
  });
}

/// 生产实现：转发到 geolocator 的静态 API。
class GeolocatorLocationPlatform implements LocationPlatform {
  const GeolocatorLocationPlatform();

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Stream<Position> positionStream({required LocationSettings locationSettings}) =>
      Geolocator.getPositionStream(locationSettings: locationSettings);

  @override
  Future<Position> getCurrentPosition({
    required LocationSettings locationSettings,
  }) =>
      Geolocator.getCurrentPosition(locationSettings: locationSettings);
}

/// 把 geolocator 的定位结果翻译成 domain 层的 [LocationFix]。
///
/// iOS 在速度不可用时会给 `-1`，这里原样保留，由
/// [RecordingSession] 判断是否可用。
LocationFix toLocationFix(Position position) => LocationFix(
      tMs: position.timestamp.millisecondsSinceEpoch,
      lat: position.latitude,
      lon: position.longitude,
      altitudeM: position.altitude,
      speedMps: position.speed,
      accuracyM: position.accuracy,
    );

/// 按平台构造定位设置。抽成纯函数，两端配置都能在单测里断言。
LocationSettings buildLocationSettings({required bool isAndroid}) {
  if (isAndroid) {
    return AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      // 显式要 1 Hz。真机实测（无 GMS 的 OPPO，走系统 LocationManager）不写这项时
      // 只给到约 5 秒一个点，落盘 5m/2s、曲线采样与断点判定全部建立在 1 Hz 的
      // 假设上（见 6.3），空档稍一拉长就会被当成丢信号。
      intervalDuration: const Duration(seconds: 1),
      // 前台服务通知：Android 10+ 后台持续定位必需，与 Task 2 声明的
      // com.baseflow.geolocator.GeolocatorService 配套。
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: '骑行记录中',
        notificationText: '正在记录轨迹与心率',
        notificationChannelName: '骑行记录',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }
  return AppleSettings(
    accuracy: LocationAccuracy.best,
    activityType: ActivityType.fitness,
    distanceFilter: 0,
    // 骑行中自动暂停定位会让轨迹断掉，必须关掉。
    pauseLocationUpdatesAutomatically: false,
    showBackgroundLocationIndicator: true,
    allowBackgroundLocationUpdates: true,
  );
}

/// 粗略定位（开始记录时点亮地图）用的设置。
///
/// Android 上**强制走系统 LocationManager**，不用 GMS 的 FLP：国内设备上 FLP
/// 常常等不到网络定位——K40 实测这次请求 8 秒超时，而同一环境下系统定位服务
/// 2 秒内就上报了 WiFi 位置（logcat: NetworkLocationManager 2045ms 返回）。
/// 中精度会落到 `QUALITY_BALANCED_POWER`，只求街区级，不求精准。
LocationSettings buildPreviewSettings({required bool isAndroid}) {
  if (isAndroid) {
    return AndroidSettings(
      accuracy: LocationAccuracy.medium,
      forceLocationManager: true,
      timeLimit: const Duration(seconds: 8),
    );
  }
  return const LocationSettings(
    accuracy: LocationAccuracy.medium,
    timeLimit: Duration(seconds: 8),
  );
}

/// 定位采集。只负责权限校验与字段翻译，不含任何业务判断。
class LocationService {
  const LocationService({this._platform = const GeolocatorLocationPlatform()});

  final LocationPlatform _platform;

  /// 检查定位服务与权限。不满足时返回具体原因，由 UI 引导用户处理。
  Future<LocationReadiness> checkReadiness() async {
    if (!await _platform.isLocationServiceEnabled()) {
      return LocationReadiness.serviceDisabled;
    }

    LocationPermission permission = await _platform.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _platform.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationReadiness.permissionDeniedForever;
    }
    if (permission == LocationPermission.denied) {
      return LocationReadiness.permissionDenied;
    }
    return LocationReadiness.ready;
  }

  /// 跳转系统设置页，供权限被拒时引导用户。
  Future<bool> openAppSettings() => _platform.openAppSettings();

  /// 跳转系统定位开关页，供定位服务关闭时引导用户。
  Future<bool> openLocationSettings() => _platform.openLocationSettings();

  /// 定位流。1Hz 的落盘节拍由 [RecordingSession] 的 tick 保证，
  /// 这里不做系统侧距离过滤，避免丢掉用于平滑的原始点。
  Stream<LocationFix> fixes() => _platform
      .positionStream(
        locationSettings: buildLocationSettings(isAndroid: Platform.isAndroid),
      )
      .map(toLocationFix);

  /// 开始记录时先要的一次粗略定位，用来在 GPS 锁星前把地图点亮。
  ///
  /// 高精度 GPS 冷启动或室内可能几十秒甚至几分钟都拿不到点（真机实测 K40
  /// 在室内 5 分钟无点），这段时间界面只能停在「等待定位…」。这里用中精度
  /// 一次性请求（Android 走 PRIORITY_BALANCED，主要靠 WiFi/基站），几百毫秒
  /// 到几秒就能返回大致位置；真实轨迹仍然只取 [fixes] 的高精度点，两者互不
  /// 影响。超时或失败一律返回 null：预览定位不该拖住记录开始。
  Future<LocationFix?> quickPreviewFix() async {
    try {
      final Position position = await _platform.getCurrentPosition(
        locationSettings: buildPreviewSettings(isAndroid: Platform.isAndroid),
      );
      return toLocationFix(position);
    } catch (_) {
      return null;
    }
  }
}
