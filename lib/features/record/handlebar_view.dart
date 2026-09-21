import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/settings_repository.dart';
import 'record_controller.dart';

/// 车把模式。见设计文档 10.1。
///
/// 主指标字号 ≥72pt、深色高对比；屏幕常亮由 RecordPage 用 wakelock 控制。
class HandlebarView extends StatelessWidget {
  const HandlebarView({
    required this.state,
    required this.unit,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.onSwitchMode,
    super.key,
  });

  /// 主指标字号。设计文档 10.1 要求不小于 72。
  static const double primaryFontSize = 76;

  final RecordState state;
  final DistanceUnit unit;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;
  final VoidCallback onSwitchMode;

  @override
  Widget build(BuildContext context) {
    final bool paused = state.isPaused;
    return SafeArea(
      child: Column(
        children: <Widget>[
          _StatusBar(state: state, onSwitchMode: onSwitchMode),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    formatSpeedValue(state.currentSpeedMps, unit),
                    key: const Key('handlebar-speed'),
                    style: const TextStyle(
                      fontSize: primaryFontSize,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    speedUnitLabel(unit),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _Metric(label: '距离', value: formatDistance(state.distanceM, unit)),
                _Metric(label: '时长', value: formatDuration(state.elapsedSeconds)),
                _Metric(label: '心率', value: state.hr?.toString() ?? '--'),
                _Metric(label: '踏频', value: state.cadence?.toString() ?? '--'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: paused ? onResume : onPause,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      backgroundColor: paused ? Colors.green : Colors.orange,
                    ),
                    child: Text(paused ? '继续' : '暂停',
                        style: const TextStyle(fontSize: 22)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onFinish,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('结束', style: TextStyle(fontSize: 22)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state, required this.onSwitchMode});

  final RecordState state;
  final VoidCallback onSwitchMode;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            if (state.gpsWeak)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text('GPS 信号弱', style: TextStyle(color: Colors.orange)),
              ),
            Icon(
              Icons.favorite,
              size: 16,
              color: state.hrConnected ? Colors.red : Colors.grey,
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.sync,
              size: 16,
              color: state.cadenceConnected ? Colors.blue : Colors.grey,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onSwitchMode,
              icon: const Icon(Icons.screen_lock_portrait, size: 18),
              label: const Text('口袋模式'),
            ),
          ],
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Text(value,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
