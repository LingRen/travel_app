import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/ble/ble_scanner.dart';
import '../../data/ble/sensor_monitor.dart';
import '../../data/settings_repository.dart';
import 'device_picker_sheet.dart';
import 'handlebar_view.dart';
import 'pocket_view.dart';
import 'record_controller.dart';

/// 记录页。见设计文档 10.1：两种模式共用同一个记录引擎，只切换渲染层。
class RecordPage extends ConsumerStatefulWidget {
  const RecordPage({super.key});

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<RecordPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeResumeRequest());
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
  }

  /// 崩溃恢复时用户在启动弹窗里选了「继续」，这里接着写那个会话。
  void _consumeResumeRequest() {
    final int? rideId = ref.read(resumeRideIdProvider);
    if (rideId == null) return;
    ref.read(resumeRideIdProvider.notifier).state = null;
    unawaited(ref.read(recordControllerProvider.notifier).resumeExisting(rideId));
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
    final DiscoveredDevice? device = await showModalBottomSheet<DiscoveredDevice>(
      context: context,
      builder: (BuildContext context) => DevicePickerSheet(kind: kind),
    );
    if (device == null) return;
    await ref
        .read(recordControllerProvider.notifier)
        .connectSensor(kind, device.device);
  }

  Future<void> _confirmFinish(RecordController controller) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('结束本次骑行？'),
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
    final RecordController controller = ref.read(recordControllerProvider.notifier);
    final DistanceUnit unit =
        ref.watch(appSettingsProvider).value?.distanceUnit ?? DistanceUnit.kilometer;

    // 车把模式且正在记录时屏幕常亮。见设计文档 10.1。
    ref.listen<RecordState>(recordControllerProvider,
        (RecordState? _, RecordState next) {
      unawaited(_setWakelock(
        next.isActive && !next.isPaused && next.mode == RecordViewMode.handlebar,
      ));
    });

    final Widget body;
    if (state.isFinished) {
      body = _FinishedView(state: state, unit: unit, onReset: controller.reset);
    } else if (state.isActive) {
      body = state.mode == RecordViewMode.handlebar
          ? HandlebarView(
              state: state,
              unit: unit,
              onPause: controller.pause,
              onResume: controller.resume,
              onFinish: () => _confirmFinish(controller),
              onSwitchMode: () => controller.setMode(RecordViewMode.pocket),
              onPickDevice: _pickDevice,
            )
          : PocketView(
              state: state,
              unit: unit,
              onPause: controller.pause,
              onResume: controller.resume,
              onFinish: () => _confirmFinish(controller),
              onSwitchMode: () => controller.setMode(RecordViewMode.handlebar),
            );
    } else {
      body = _IdleView(
        state: state,
        onStart: controller.start,
        onPickDevice: _pickDevice,
        onModeChanged: controller.setMode,
      );
    }

    return Scaffold(body: body);
  }
}

/// 未开始时的准备界面：选模式、连传感器、开始。见设计文档 6.1 与 10.1。
///
/// 按器件的「待机画面」来做，而不是传统的「空状态页」：顶部一条状态栏交代
/// 传感器就绪情况，中间是两组待确认的设置，底部一个开始键。没有大图标与
/// 居中大标题——那是通用空状态的写法，和这台设备的语言不一致。
class _IdleView extends StatelessWidget {
  const _IdleView({
    required this.state,
    required this.onStart,
    required this.onPickDevice,
    required this.onModeChanged,
  });

  final RecordState state;
  final Future<void> Function() onStart;
  final void Function(SensorKind kind) onPickDevice;
  final void Function(RecordViewMode mode) onModeChanged;

  @override
  Widget build(BuildContext context) {
    final bool sensorsReady =
        state.hrConnected || state.cadenceConnected || state.powerConnected;

    return SafeArea(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceM, kSpaceL, kSpaceM),
            child: Row(
              children: <Widget>[
                const Icon(Icons.directions_bike, size: 18, color: kAppTextMuted),
                const SizedBox(width: kSpaceS),
                const Text('准备骑行', style: kSectionTextStyle),
                const Spacer(),
                Text(
                  sensorsReady ? '传感器就绪' : '未接传感器',
                  style: kLabelTextStyle.copyWith(
                    color: sensorsReady ? kAppAccent : kAppTextMuted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(kSpaceL),
              children: <Widget>[
                const _GroupLabel('骑行方式'),
                const SizedBox(height: kSpaceS),
                // 车把模式在骑行中看，口袋模式不用看。两者的取舍是「屏幕常亮
                // 耗电」换「读数方便」，用一句话说清楚，别让人去猜。
                SegmentedButton<RecordViewMode>(
                  segments: const <ButtonSegment<RecordViewMode>>[
                    ButtonSegment<RecordViewMode>(
                      value: RecordViewMode.handlebar,
                      label: Text('车把'),
                      icon: Icon(Icons.phone_android, size: 16),
                    ),
                    ButtonSegment<RecordViewMode>(
                      value: RecordViewMode.pocket,
                      label: Text('口袋'),
                      icon: Icon(Icons.screen_lock_portrait, size: 16),
                    ),
                  ],
                  selected: <RecordViewMode>{state.mode},
                  onSelectionChanged: (Set<RecordViewMode> selected) =>
                      onModeChanged(selected.first),
                ),
                const SizedBox(height: kSpaceS),
                Text(
                  state.mode == RecordViewMode.handlebar
                      ? '车把模式：屏幕常亮，骑行中可随时看读数。'
                      : '口袋模式：屏幕不常亮，省电，采集照常进行。',
                  style: const TextStyle(fontSize: 12, color: kAppTextMuted),
                ),
                const SizedBox(height: kSpaceXl),
                const _GroupLabel('传感器'),
                const SizedBox(height: kSpaceS),
                // 传感器连不上不阻断开始记录。见设计文档 6.1。
                // 三个并排而不是两个：多出的功率计挤在同一行，所以按钮里的
                // 文字收短（「已连接」＋传感器图标），否则窄屏上会被裁掉。
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _SensorButton(
                        connected: state.hrConnected,
                        icon: state.hrConnected
                            ? Icons.favorite
                            : Icons.favorite_border,
                        label: state.hrConnected ? '已连接' : '连接心率',
                        onPressed: () => onPickDevice(SensorKind.heartRate),
                      ),
                    ),
                    const SizedBox(width: kSpaceM),
                    Expanded(
                      child: _SensorButton(
                        connected: state.cadenceConnected,
                        icon: state.cadenceConnected
                            ? Icons.sync
                            : Icons.sync_disabled,
                        label: state.cadenceConnected ? '已连接' : '连接踏频',
                        onPressed: () => onPickDevice(SensorKind.cadence),
                      ),
                    ),
                    const SizedBox(width: kSpaceM),
                    Expanded(
                      child: _SensorButton(
                        connected: state.powerConnected,
                        icon: state.powerConnected
                            ? Icons.bolt
                            : Icons.bolt_outlined,
                        label: state.powerConnected ? '已连接' : '连接功率',
                        onPressed: () => onPickDevice(SensorKind.power),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: kSpaceS),
                const Text(
                  '不连也能记录。没接心率与踏频就没有对应数据，功率按速度与坡度估算。',
                  style: TextStyle(fontSize: 12, color: kAppTextMuted),
                ),
                if (state.errorMessage != null) ...<Widget>[
                  const SizedBox(height: kSpaceXl),
                  _InlineNotice(message: state.errorMessage!),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(kSpaceL),
            child: FilledButton(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(HandlebarView.buttonHeight),
              ),
              child: const Text(
                '开始骑行',
                style: TextStyle(fontSize: kFontTitle, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: kLabelTextStyle);
}

/// 传感器连接按钮。已连接时边框与文字转琥珀，一眼能扫出「哪些已就绪」。
class _SensorButton extends StatelessWidget {
  const _SensorButton({
    required this.connected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool connected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: connected ? kAppAccent : kAppTextPrimary,
          side: BorderSide(
            color: connected ? kAppAccent : kAppHairline,
            width: 1,
          ),
          // 三个并排后每格只有一百来像素，左右各留 8 而不是主题的 16。
          padding: const EdgeInsets.symmetric(horizontal: kSpaceS),
        ),
      );
}

/// 行内提示。用于「定位权限被拒」这类阻断类错误——不用 SnackBar，
/// 因为 SnackBar 会自己消失，而这个错误在用户处理前一直成立。
class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(kSpaceM),
        decoration: const BoxDecoration(
          color: kAppSurface,
          border: Border(left: BorderSide(color: kAppDanger, width: 3)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.error_outline, size: 18, color: kAppDanger),
            const SizedBox(width: kSpaceS),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: kFontBody, color: kAppTextPrimary),
              ),
            ),
          ],
        ),
      );
}

/// 结束后的结算界面。
///
/// 这一屏只出现一次、看一眼就走，所以把两个数字放到最大（display 字号），
/// 其余全部撤掉。原来的版本在 28pt 数字下面留了一大片空白。
class _FinishedView extends StatelessWidget {
  const _FinishedView({required this.state, required this.unit, required this.onReset});

  final RecordState state;
  final DistanceUnit unit;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceM, kSpaceL, kSpaceM),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.check_circle, size: 18, color: kAppAccent),
                  const SizedBox(width: kSpaceS),
                  const Text('记录已保存', style: kSectionTextStyle),
                ],
              ),
            ),
            const Divider(height: 1),
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
                      const Text(
                        '记录已写入历史，详情页可以看轨迹与曲线。',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: kAppTextMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(kSpaceL),
              child: FilledButton(
                onPressed: onReset,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(HandlebarView.buttonHeight),
                ),
                child: const Text(
                  '完成',
                  style: TextStyle(fontSize: kFontTitle, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      );
}

class _FinishedReadout extends StatelessWidget {
  const _FinishedReadout({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Text(value, style: kDisplayTextStyle),
          const SizedBox(height: kSpaceXs),
          Text(label, style: kLabelTextStyle),
        ],
      );
}