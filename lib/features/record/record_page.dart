import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/ble/ble_scanner.dart';
import '../../data/ble/sensor_monitor.dart';
import '../../data/location/location_service.dart';
import '../../data/settings_repository.dart';
import 'device_picker_sheet.dart';
import 'handlebar_view.dart';
import 'idle_conditions.dart';
import 'record_controller.dart';

/// 记录页。见设计文档 10.1：落地就是骑行界面，底部那颗键在「开始」与
/// 「结束」之间切换，没有单独的准备屏。
class RecordPage extends ConsumerStatefulWidget {
  const RecordPage({super.key});

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<RecordPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _consumeResumeRequest(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_setWakelock(false));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 退到后台时强制落盘一次，缩小崩溃丢数据的窗口。
    ref.read(recordControllerProvider.notifier).handleLifecycle(state);
    // 常亮不能只靠上面的 listen 兜：暂停中息屏、或 listen 还没收到通知，
    // 都会让屏幕在黑屏状态下继续耗电。离开前台一律先关掉。
    if (state != AppLifecycleState.resumed) unawaited(_setWakelock(false));
  }

  /// 崩溃恢复时用户在启动弹窗里选了「继续」，这里接着写那个会话。
  ///
  /// 没有待恢复的会话时预热一次定位：待机页要显示「GPS 已锁定 / 精度 N m」，
  /// 不能等用户按下开始才第一次问位置。
  void _consumeResumeRequest() {
    final RecordState state = ref.read(recordControllerProvider);
    _syncIdleConditions(state);
    final int? rideId = ref.read(resumeRideIdProvider);
    if (rideId == null) {
      unawaited(ref.read(recordControllerProvider.notifier).loadIdlePreview());
      return;
    }
    ref.read(resumeRideIdProvider.notifier).state = null;
    unawaited(
      ref.read(recordControllerProvider.notifier).resumeExisting(rideId),
    );
  }

  /// 只在待机时查地名与天气。开始记录、结束或定位丢失后控制器会清空状态，
  /// 并丢弃仍在途的响应。
  void _syncIdleConditions(RecordState state) {
    ref
        .read(idleConditionsProvider.notifier)
        .update(
          idle: !state.isActive && !state.isFinished,
          fix: state.previewFix,
        );
  }

  Future<void> _setWakelock(bool enable) async {
    try {
      if (enable) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // 没有 wakelock 通道的环境（测试、桌面）忽略即可。
    }
  }

  Future<void> _pickDevice(SensorKind kind) async {
    final DiscoveredDevice? device =
        await showModalBottomSheet<DiscoveredDevice>(
          context: context,
          builder: (BuildContext context) => DevicePickerSheet(kind: kind),
        );
    if (device == null) return;
    await ref
        .read(recordControllerProvider.notifier)
        .connectSensor(kind, device.device);
  }

  /// 阻断类错误旁的「去设置 / 打开定位」。按错误文案选目标页。
  Future<void> _openLocationHelp() async {
    final String message =
        ref.read(recordControllerProvider).errorMessage ?? '';
    final LocationService service = ref.read(locationServiceProvider);
    if (message.contains('定位服务')) {
      await service.openLocationSettings();
    } else {
      await service.openAppSettings();
    }
  }

  /// 「始终允许」提示旁的「去设置」：只认定位权限，不受同时存在的错误文案影响。
  Future<void> _openPermissionSettings() =>
      ref.read(locationServiceProvider).openAppSettings();

  Future<void> _confirmFinish(RecordController controller) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(
          '结束本次${ref.read(recordControllerProvider).selectedActivityType.label}？',
        ),
        content: const Text('结束后会保存记录并结算指标，无法再继续记录。'),
        actions: <Widget>[
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('结束'),
          ),
        ],
      ),
    );
    if (ok ?? false) await controller.finish();
  }

  @override
  Widget build(BuildContext context) {
    final RecordState state = ref.watch(recordControllerProvider);
    final IdleConditions idleConditions = ref.watch(idleConditionsProvider);
    final RecordController controller = ref.read(
      recordControllerProvider.notifier,
    );
    final AppSettings? settings = ref.watch(appSettingsProvider).value;
    final DistanceUnit unit = settings?.distanceUnit ?? DistanceUnit.kilometer;
    final String tileUrl =
        settings?.mapTileUrlTemplate ?? kDefaultMapTileUrlTemplate;

    // 正在记录且 App 在前台时屏幕常亮。见设计文档 10.1 的「熄屏与常亮」：
    // 亮着就常亮，用户按电源键熄屏后随生命周期自动停。
    ref.listen<RecordState>(recordControllerProvider, (
      RecordState? _,
      RecordState next,
    ) {
      unawaited(
        _setWakelock(next.isActive && !next.isPaused && next.foreground),
      );
      _syncIdleConditions(next);
    });

    final Widget body;
    if (state.isFinished) {
      body = _FinishedView(state: state, unit: unit, onReset: controller.reset);
    } else {
      // 未开始态也是这一页：底部那颗键是「开始」，按下即记录（见设计文档
      // 10.1——原来的准备页已并进来，不再有单独一屏）。
      body = HandlebarView(
        state: state,
        unit: unit,
        idleConditions: idleConditions,
        tileUrlTemplate: tileUrl,
        selectedActivityType: state.selectedActivityType,
        now: DateTime.fromMillisecondsSinceEpoch(ref.read(nowProvider)()),
        onSelectActivityType: controller.selectActivityType,
        onStart: controller.start,
        onPause: controller.pause,
        onResume: controller.resume,
        onFinish: () => _confirmFinish(controller),
        onPickDevice: _pickDevice,
        onFixError: _openLocationHelp,
        onFixAlwaysPermission: _openPermissionSettings,
      );
    }

    return Scaffold(body: body);
  }
}

/// 结束后的结算界面。
///
/// 这一屏只出现一次、看一眼就走，所以把两个数字放到最大（display 字号），
/// 其余全部撤掉。原来的版本在 28pt 数字下面留了一大片空白。
class _FinishedView extends StatelessWidget {
  const _FinishedView({
    required this.state,
    required this.unit,
    required this.onReset,
  });

  final RecordState state;
  final DistanceUnit unit;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return SafeArea(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kSpaceL,
              kSpaceM,
              kSpaceL,
              kSpaceM,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.check_circle_outline,
                  size: 20,
                  color: palette.accentInk,
                ),
                const SizedBox(width: kSpaceS),
                Text(
                  '记录已保存',
                  style: kSerifHeadingTextStyle.copyWith(fontSize: 22),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.hairline),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: kSpaceL),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _FinishedReadout(
                      label: '距离',
                      value: formatDistance(state.distanceM, unit),
                    ),
                    const SizedBox(height: kSpaceXl),
                    _FinishedReadout(
                      label: '时长',
                      value: formatDuration(state.elapsedSeconds),
                    ),
                    const SizedBox(height: kSpaceXl),
                    Text(
                      '记录已写入历史，详情页可以看轨迹与曲线。',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(height: 1, color: palette.hairline),
          Padding(
            padding: const EdgeInsets.all(kSpaceL),
            child: SizedBox(
              width: double.infinity,
              height: HandlebarView.buttonHeight,
              child: FilledButton(
                onPressed: onReset,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accentInk,
                  foregroundColor: palette.onAccent,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(kRadiusButton),
                    ),
                  ),
                ),
                child: const Text(
                  '完成',
                  style: TextStyle(
                    fontSize: kFontTitle,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinishedReadout extends StatelessWidget {
  const _FinishedReadout({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      // 结算是一次性静态读数，按设计文档用衬线大数字，不用仪表等宽字体。
      Text(value, style: kSerifDisplayTextStyle),
      const SizedBox(height: kSpaceXs),
      Text(
        label,
        style: kLabelTextStyle.copyWith(color: context.palette.muted),
      ),
    ],
  );
}
