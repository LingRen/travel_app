import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import 'record_controller.dart';

/// 口袋模式。见设计文档 10.1。
///
/// 手机在口袋里，这一页只有「特意掏出来看一眼」时才会被看到，所以刻意不放大
/// 数字：屏幕不常亮（由 RecordPage 关掉 wakelock），采集照常进行，掏出来时
/// 只要能确认「还在记」和「记了多少」就够了。快速核对读数用回车把模式切回去。
///
/// 功率是个例外：距离和时长只说明骑了多久、多远，功率才是这页唯一体现「骑得
/// 多用力」的读数，掏出口袋瞄一眼往往就是想看它，所以和距离、时长并列。心率
/// 和踏频仍然不放——车把模式才看得清，口袋里那一眼看不出趋势。
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
        children: <Widget>[
          // 状态条：与车把模式同一套边框语言，只是内容减到最少。
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceM, kSpaceL, kSpaceM),
            child: Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: paused ? Colors.transparent : kAppAccent,
                    border: Border.all(
                      color: paused ? kAppTextMuted : kAppAccent,
                      width: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: kSpaceS),
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: kFontSubtitle,
                    fontWeight: FontWeight.w600,
                    color: kAppTextPrimary,
                  ),
                ),
                if (state.gpsWeak) ...<Widget>[
                  const SizedBox(width: kSpaceM),
                  const Text(
                    'GPS 信号弱',
                    style: TextStyle(fontSize: kFontBody, color: kAppWarning),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kSpaceL,
              vertical: kSpaceXl,
            ),
            child: Row(
              children: <Widget>[
                _Readout(
                  label: '距离',
                  value: formatDistance(state.distanceM, unit),
                ),
                Container(
                  width: 1,
                  height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: kSpaceL),
                  color: kAppHairline,
                ),
                _Readout(
                  label: '时长',
                  value: formatDuration(state.elapsedSeconds),
                ),
                Container(
                  width: 1,
                  height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: kSpaceL),
                  color: kAppHairline,
                ),
                _Readout(
                  // 与车把模式同一套口径：没接功率计时这一格是 app 估出来的，
                  // 标签里就得写明，否则掏出口袋看一眼也会当成功率计读数。
                  label: state.powerConnected ? '功率' : '功率（估算）',
                  value: state.power?.toString() ?? '--',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(kSpaceL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton(
                        onPressed: paused ? onResume : onPause,
                        child: Text(paused ? '继续' : '暂停'),
                      ),
                    ),
                    const SizedBox(width: kSpaceM),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onFinish,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kAppDanger,
                          side: const BorderSide(color: kAppDanger, width: 1),
                        ),
                        child: const Text('结束'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: kSpaceS),
                // 切回车把模式是个低频动作，不该和暂停/结束抢注意力，
                // 但也不能藏进菜单——掏出口袋的那一刻往往就是想看读数。
                TextButton.icon(
                  onPressed: onSwitchMode,
                  icon: const Icon(Icons.phone_android, size: 16),
                  label: const Text('车把模式'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: kLabelTextStyle),
            const SizedBox(height: kSpaceXs),
            Text(value, style: kMetricTextStyle),
          ],
        ),
      );
}