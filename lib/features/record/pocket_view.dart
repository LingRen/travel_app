import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/settings_repository.dart';
import 'record_controller.dart';

/// 口袋模式。见设计文档 10.1。
///
/// 屏幕不常亮（由 RecordPage 关掉 wakelock）、只保留一条状态条，
/// 采集照常进行。
class PocketView extends StatelessWidget {
  const PocketView({
    required this.state,
    required this.unit,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.onSwitchMode,
    super.key,
  });

  final RecordState state;
  final DistanceUnit unit;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;
  final VoidCallback onSwitchMode;

  @override
  Widget build(BuildContext context) {
    final bool paused = state.isPaused;
    final String status = paused ? '已暂停' : '记录中';
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (state.gpsWeak)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('GPS 信号弱', style: TextStyle(color: Colors.orange)),
            ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(status,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                Text(formatDistance(state.distanceM, unit),
                    style: const TextStyle(fontSize: 18)),
                Text(formatDuration(state.elapsedSeconds),
                    style: const TextStyle(fontSize: 18)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              OutlinedButton(
                onPressed: paused ? onResume : onPause,
                child: Text(paused ? '继续' : '暂停'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: onFinish,
                child: const Text('结束'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onSwitchMode,
                icon: const Icon(Icons.phone_android, size: 18),
                label: const Text('车把模式'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
