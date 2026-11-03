import 'dart:io';

import 'package:flutter/services.dart';

/// 记录期间的进程保活。
///
/// 系统定位由 geolocator 的前台服务负责；高德定位插件没有前台服务，熄屏后
/// 进程可能被系统冻结，定位事件随之中断。这里只在高德试点源生效时启停应用
/// 自己的前台服务（见 `android/.../RecordingForegroundService.kt`）。
abstract class BackgroundKeepAlive {
  Future<void> start();

  Future<void> stop();
}

/// iOS 与测试使用：由系统后台定位模式负责，不需要额外服务。
class NoopBackgroundKeepAlive implements BackgroundKeepAlive {
  const NoopBackgroundKeepAlive();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

/// Android：通过平台通道启停定位前台服务。
class AndroidForegroundKeepAlive implements BackgroundKeepAlive {
  const AndroidForegroundKeepAlive();

  static const MethodChannel _channel = MethodChannel(
    'com.ling.cycling_app/foreground_location',
  );

  @override
  Future<void> start() => _channel.invokeMethod<void>('start');

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}

/// 按平台取默认实现。iOS 不接入应用侧前台服务。
BackgroundKeepAlive defaultBackgroundKeepAlive() => Platform.isAndroid
    ? const AndroidForegroundKeepAlive()
    : const NoopBackgroundKeepAlive();
