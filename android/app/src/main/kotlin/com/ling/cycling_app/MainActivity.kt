package com.ling.cycling_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 高德定位试点源在 Dart 侧按记录开始 / 结束启停记录前台服务。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ling.cycling_app/foreground_location",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    RecordingForegroundService.start(this)
                    result.success(null)
                }
                "stop" -> {
                    RecordingForegroundService.stop(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
