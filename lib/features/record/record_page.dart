import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
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
          TextButton(
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
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Spacer(),
              const Icon(Icons.directions_bike, size: 64),
              const SizedBox(height: 16),
              Text(
                '准备骑行',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 32),
              SegmentedButton<RecordViewMode>(
                segments: const <ButtonSegment<RecordViewMode>>[
                  ButtonSegment<RecordViewMode>(
                    value: RecordViewMode.handlebar,
                    label: Text('车把'),
                    icon: Icon(Icons.phone_android),
                  ),
                  ButtonSegment<RecordViewMode>(
                    value: RecordViewMode.pocket,
                    label: Text('口袋'),
                    icon: Icon(Icons.screen_lock_portrait),
                  ),
                ],
                selected: <RecordViewMode>{state.mode},
                onSelectionChanged: (Set<RecordViewMode> selected) =>
                    onModeChanged(selected.first),
              ),
              const SizedBox(height: 24),
              // 传感器连不上不阻断开始记录。见设计文档 6.1。
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onPickDevice(SensorKind.heartRate),
                      icon: Icon(state.hrConnected ? Icons.favorite : Icons.favorite_border),
                      label: Text(state.hrConnected ? '心率已连接' : '连接心率'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onPickDevice(SensorKind.cadence),
                      icon: Icon(state.cadenceConnected ? Icons.sync : Icons.sync_disabled),
                      label: Text(state.cadenceConnected ? '踏频已连接' : '连接踏频'),
                    ),
                  ),
                ],
              ),
              if (state.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    state.errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),
              const Spacer(),
              FilledButton(
                onPressed: onStart,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                child: const Text('开始骑行', style: TextStyle(fontSize: 22)),
              ),
            ],
          ),
        ),
      );
}

/// 结束后的结算界面。
class _FinishedView extends StatelessWidget {
  const _FinishedView({required this.state, required this.unit, required this.onReset});

  final RecordState state;
  final DistanceUnit unit;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Spacer(),
              const Icon(Icons.check_circle, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              Text(
                '记录已保存',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _FinishedMetric(label: '距离', value: formatDistance(state.distanceM, unit)),
                  _FinishedMetric(label: '时长', value: formatDuration(state.elapsedSeconds)),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: onReset,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                child: const Text('完成', style: TextStyle(fontSize: 22)),
              ),
            ],
          ),
        ),
      );
}

class _FinishedMetric extends StatelessWidget {
  const _FinishedMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
