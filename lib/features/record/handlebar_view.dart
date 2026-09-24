import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/ble/sensor_monitor.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/color_scale.dart';
import '../../domain/analysis/constants.dart';
import 'record_controller.dart';

/// 速度刻度尺：把当前速度换算成 0..1 的填充比例。
///
/// 公开成纯函数是给测试留的接口——[CustomPaint] 没有可断言的语义节点，
/// 光看 widget 树验证不了「超量程被钳住」「负数不反向"。参照
/// `drawnMiniCurveSegments` 的既有做法。
double speedScaleFraction(
  double speedMps, {
  double maxMps = kColorScaleMaxSpeedMps,
}) =>
    maxMps <= 0 ? 0 : (speedMps / maxMps).clamp(0.0, 1.0);

/// 车把模式。见设计文档 10.1。
///
/// 这一页的目标不是「好看」，是**在骑行中一步扫读**：骑到 30km/h 时瞄一眼
/// 屏幕只有约 200ms，还要在户外强光下。因此：
///   - 主指标 120pt 等宽数字，读数跳动时整数位不横向抖动；
///   - 刻度尺让速度有「现在处于什么位置」的参照，不必等下一帧数字；
///   - 全页只有两个可点区域，都做成 64 高，戴手套也按得中；
///   - 除数据色带外一律不上色（见 app/theme.dart 的颜色说明）。
///
/// 屏幕常亮由 RecordPage 用 wakelock 控制。
class HandlebarView extends StatelessWidget {
  const HandlebarView({
    required this.state,
    required this.unit,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.onSwitchMode,
    required this.onPickDevice,
    super.key,
  });

  /// 主指标字号。设计文档 10.1 要求不小于 72。
  static const double primaryFontSize = kInstrumentNumeralSize;

  /// 按钮高度。比 Material 默认的 40 高得多——骑行中戴手套点按。
  static const double buttonHeight = 64;

  final RecordState state;
  final DistanceUnit unit;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;
  final VoidCallback onSwitchMode;

  /// 骑行中点传感器灯时打开的配对入口。
  final void Function(SensorKind kind) onPickDevice;

  @override
  Widget build(BuildContext context) {
    final bool paused = state.isPaused;
    return SafeArea(
      child: Column(
        children: <Widget>[
          _StatusStrip(
            state: state,
            onSwitchMode: onSwitchMode,
            onPickDevice: onPickDevice,
          ),
          const Divider(height: 1),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // FittedBox 只兜极端窄高比，不参与常态布局：数字的字号始终由
                // kInstrumentTextStyle 决定，缩放的只是绘制框。
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    children: <Widget>[
                      Text(
                        formatSpeedValue(state.currentSpeedMps, unit),
                        key: const Key('handlebar-speed'),
                        style: kInstrumentTextStyle,
                      ),
                      const SizedBox(height: kSpaceXs),
                      Text(speedUnitLabel(unit), style: kLabelTextStyle),
                    ],
                  ),
                ),
                const SizedBox(height: kSpaceXl),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kSpaceXl),
                  child: _SpeedScale(speedMps: state.currentSpeedMps),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _MetricStrip(state: state, unit: unit),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceL, kSpaceL, kSpaceL),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: paused ? onResume : onPause,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(buttonHeight),
                      // 只有一个主动作，所以「继续」不再是和「暂停」并列的
                      // 另一个大按钮，而是同一个按钮换了字。
                      backgroundColor: kAppAccent,
                      foregroundColor: kAppOnAccent,
                    ),
                    child: Text(paused ? '继续' : '暂停'),
                  ),
                ),
                const SizedBox(width: kSpaceM),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onFinish,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(buttonHeight),
                      foregroundColor: kAppDanger,
                      side: const BorderSide(color: kAppDanger, width: 1),
                    ),
                    child: const Text('结束'),
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

/// 器件边框条：状态灯 + 传感器连接态 + 切模式入口。
///
/// 三个传感器灯同时是骑行中的配对入口——不用退回准备页就能补连设备。
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.state,
    required this.onSwitchMode,
    required this.onPickDevice,
  });

  final RecordState state;
  final VoidCallback onSwitchMode;
  final void Function(SensorKind kind) onPickDevice;

  @override
  Widget build(BuildContext context) {
    final bool paused = state.isPaused;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceS, kSpaceS, kSpaceS),
      child: Row(
        children: <Widget>[
          // 左半用 Expanded 兜底：窄屏上先让「GPS 信号弱」这类提示收缩，
          // 而不是把右边的传感器灯与模式按钮挤出屏幕。
          Expanded(
            child: Row(
              children: <Widget>[
                // 状态灯：实心琥珀＝采集中，空心＝已暂停。灯本身承担状态语义，
                // 「进行中」三个字只是给第一次用的人看的。
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
                  paused ? '已暂停' : '进行中',
                  style: const TextStyle(
                    fontSize: kFontBody,
                    fontWeight: FontWeight.w600,
                    color: kAppTextPrimary,
                  ),
                ),
                if (state.gpsWeak) ...<Widget>[
                  const SizedBox(width: kSpaceM),
                  const Flexible(
                    child: Text(
                      'GPS 信号弱',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: kFontBody, color: kAppWarning),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _SensorLamp(
            icon: Icons.favorite,
            connected: state.hrConnected,
            onColor: kAppDanger,
            tooltip: state.hrConnected ? '心率已连接，点击更换设备' : '点击连接心率设备',
            onTap: () => onPickDevice(SensorKind.heartRate),
          ),
          _SensorLamp(
            icon: Icons.sync,
            connected: state.cadenceConnected,
            onColor: kAppAccent,
            tooltip: state.cadenceConnected ? '踏频已连接，点击更换设备' : '点击连接踏频设备',
            onTap: () => onPickDevice(SensorKind.cadence),
          ),
          _SensorLamp(
            icon: Icons.bolt,
            connected: state.powerConnected,
            onColor: kAppAccent,
            tooltip: state.powerConnected ? '功率计已连接，点击更换设备' : '点击连接功率计',
            onTap: () => onPickDevice(SensorKind.power),
          ),
          TextButton.icon(
            onPressed: onSwitchMode,
            icon: const Icon(Icons.screen_lock_portrait, size: 16),
            label: const Text('口袋模式'),
          ),
        ],
      ),
    );
  }
}

/// 传感器连接指示灯，同时是可点的配对入口。
///
/// 图标只有 18px，直接点太难点，所以撑出 [tapSize] 的可点区域——骑行中手指
/// 本来就抖，小目标按不中。未连接时降成灰，不用红：红在这套颜色语言里是「错误」。
class _SensorLamp extends StatelessWidget {
  const _SensorLamp({
    required this.icon,
    required this.connected,
    required this.onColor,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool connected;
  final Color onColor;
  final String tooltip;
  final VoidCallback onTap;

  static const double tapSize = 40;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: tapSize,
          height: tapSize,
        ),
        icon: Icon(
          icon,
          size: 18,
          color: connected ? onColor : kAppHairline,
        ),
      );
}

/// 速度刻度尺。参照物是码表的横条速度指示：轨道 + 刻度 + 游标填充。
///
/// 填充色直接取 [speedColorArgb]，与地图轨迹、详情曲线、列表缩略图同一套
/// 映射——同一个速度在 app 里永远同一个颜色。
class _SpeedScale extends StatelessWidget {
  const _SpeedScale({required this.speedMps});

  final double speedMps;

  static const double height = 20;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _SpeedScalePainter(speedMps)),
      );
}

class _SpeedScalePainter extends CustomPainter {
  _SpeedScalePainter(this.speedMps);

  final double speedMps;

  /// 刻度条数。11 条即每 10% 一格，对应满量程的 1/10。
  static const int tickCount = 11;

  @override
  void paint(Canvas canvas, Size size) {
    final double fraction = speedScaleFraction(speedMps);
    final double trackY = size.height * 0.35;
    const double trackHeight = 4;

    final Rect track = Rect.fromLTWH(0, trackY, size.width, trackHeight);
    final RRect trackRrect =
        RRect.fromRectAndRadius(track, const Radius.circular(kRadiusLine));

    canvas.drawRRect(
      trackRrect,
      Paint()..color = kAppSurfaceRaised,
    );
    if (fraction > 0) {
      // 填充宽度至少一个圆角直径，否则低速时看不出有进度。
      final double filled = (size.width * fraction).clamp(trackHeight, size.width);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, trackY, filled, trackHeight),
          const Radius.circular(kRadiusLine),
        ),
        Paint()..color = Color(speedColorArgb(speedMps)),
      );
    }

    final Paint tickPaint = Paint()..color = kAppHairline;
    for (int i = 0; i < tickCount; i++) {
      final double x = size.width * i / (tickCount - 1);
      // 首尾与中点画长刻度，其余短刻度——读数时有三个锚点可对。
      final bool major = i == 0 || i == tickCount - 1 || i == tickCount ~/ 2;
      final double tickHeight = major ? 7 : 4;
      canvas.drawRect(
        Rect.fromLTWH(
          (x - 0.5).clamp(0.0, size.width - 1),
          size.height - tickHeight,
          1,
          tickHeight,
        ),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpeedScalePainter old) => old.speedMps != speedMps;
}

/// 次要指标条。分两行：上面是本次骑行的总量（距离、时长），下面是三个传感器
/// 的即时读数（心率、踏频、功率）。
///
/// 不再挤成一行：加上功率就是五格，411dp 宽的手机上每格只剩六十来像素，
/// 「1:00:00」这种七个字符的等宽读数会被截断（统计页的读数矩阵踩过同一个坑）。
class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.state, required this.unit});

  final RecordState state;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kSpaceL,
          vertical: kSpaceM,
        ),
        child: Column(
          children: <Widget>[
            _MetricRow(
              metrics: <(String, String)>[
                ('距离', formatDistance(state.distanceM, unit)),
                ('时长', formatDuration(state.elapsedSeconds)),
              ],
            ),
            const SizedBox(height: kSpaceM),
            _MetricRow(
              metrics: <(String, String)>[
                ('心率', state.hr?.toString() ?? '--'),
                ('踏频', state.cadence?.toString() ?? '--'),
                // 没接功率计时这一格是估算值（速度 + 坡度 + 体重），标签里直接
                // 写明：骑到一半才发现「功率」其实不是功率计读数，不是好体验。
                (
                  state.powerConnected ? '功率' : '功率（估算）',
                  state.power?.toString() ?? '--',
                ),
              ],
            ),
          ],
        ),
      );
}

/// 一行等宽格，用竖细线分隔——不用卡片、不用底色块。
class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.metrics});

  final List<(String, String)> metrics;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          for (int i = 0; i < metrics.length; i++) ...<Widget>[
            if (i > 0)
              Container(
                width: 1,
                height: 30,
                margin: const EdgeInsets.symmetric(horizontal: kSpaceM),
                color: kAppHairline,
              ),
            Expanded(
              child: Column(
                children: <Widget>[
                  Text(metrics[i].$1, style: kLabelTextStyle),
                  const SizedBox(height: kSpaceXs),
                  Text(
                    metrics[i].$2,
                    style: kMetricTextStyle.copyWith(fontSize: kFontTitle),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
}