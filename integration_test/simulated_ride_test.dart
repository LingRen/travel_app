import 'package:cycling_app/app/app.dart';
import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/features/record/record_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';

/// 真机/模拟器上的「模拟骑行」：点开始后持续打印地图相机中心，
/// 配合 `xcrun simctl location` 喂路线，确认箭头一直留在画面里。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 真机上 `pump(时长)` 只等一帧，不推进真实时间，封面那 1.2 秒得靠真等。
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final Iterable<String> texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text t) => t.data ?? '')
        .where((String s) => s.isNotEmpty);
    fail('等不到 $finder，当前文字：${texts.join(' | ')}');
  }

  /// 上一轮跑测试留下的「未结束的骑行」会在启动时弹恢复对话框（见 RecoveryGate），
  /// 它带模态遮罩，会把「开始骑行」的点击整个吃掉——所以先把它结算掉。
  Future<void> settleStaleRides(WidgetTester tester) async {
    final Finder gate = find.textContaining('检测到未结束的');
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline) && gate.evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    for (int i = 0; i < 8 && gate.evaluate().isNotEmpty; i++) {
      debugPrint('[sim] 结算残留的未结束骑行');
      await tester.tap(find.text('结算保存'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await tester.pump();
    }
    if (gate.evaluate().isNotEmpty) fail('结算不掉残留的未结束骑行');
  }

  testWidgets('模拟骑行：地图相机跟着当前位置走', (WidgetTester tester) async {
    // 先确认 geolocator 本身在模拟器上能不能拿到点，排除是界面的问题。
    debugPrint('[sim] permission=${await Geolocator.checkPermission()}');
    try {
      final Position p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      debugPrint('[sim] probe=${p.latitude},${p.longitude} acc=${p.accuracy}');
    } catch (e) {
      debugPrint('[sim] probe failed: $e');
    }

    await tester.pumpWidget(CyclingApp(opening: openAppDatabase()));
    await settleStaleRides(tester);

    // 待机页先预热一次定位；这里由外部 `xcrun simctl location set` 喂点，
    // 等它锁上再按「开始骑行」，否则按下后还要重试一轮定位。
    await waitFor(
      tester,
      find.textContaining('GPS 已锁定'),
      timeout: const Duration(seconds: 90),
    );

    await tester.tap(find.text('开始骑行'));
    await waitFor(tester, find.byKey(const Key('live-route-map')));

    final Finder scale = find.byKey(const Key('map-scale-bar'));
    await waitFor(tester, scale);
    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(scale));

    // 让外部在这段时间里喂模拟位置（约 100 秒），每 2 秒打一行：相机中心 +
    // 轨迹点个数 + 已骑距离 + 最后一个点，三者一起看才知道相机动没动。
    for (int i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      await tester.pump();
      if (scale.evaluate().isEmpty) {
        debugPrint('[sim] t=${i * 2}s 地图已被拆掉');
        continue;
      }
      final MapCamera camera = MapCamera.of(tester.element(scale));
      final RecordState state = container.read(recordControllerProvider);
      final List<TrackPoint> track = state.liveTrack;
      final TrackPoint? last = track.isEmpty ? null : track.last;
      debugPrint(
        '[sim] t=${i * 2}s phase=${state.phase} pts=${track.length}'
        ' dist=${state.distanceM.toStringAsFixed(1)}m'
        ' pos=${last?.lat?.toStringAsFixed(5) ?? '-'},'
        '${last?.lon?.toStringAsFixed(5) ?? '-'}'
        ' center=${camera.center.latitude.toStringAsFixed(5)},'
        '${camera.center.longitude.toStringAsFixed(5)}'
        ' zoom=${camera.zoom.toStringAsFixed(2)}',
      );
    }
  });
}
