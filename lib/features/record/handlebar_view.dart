import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/ble/sensor_monitor.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/color_scale.dart';
import '../../domain/analysis/constants.dart';
import 'live_route_map.dart';
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

/// 骑行界面（车把模式与口袋模式合并后的唯一一个）。见设计文档 10.1。
///
/// 这一页的目标不是「好看」，是**在骑行中一步扫读**：骑到 30km/h 时瞄一眼
/// 屏幕只有约 200ms，还要在户外强光下。因此：
///   - 主指标 120pt 等宽数字，读数跳动时整数位不横向抖动；
///   - 刻度尺让速度有「现在处于什么位置」的参照，不必等下一帧数字；
///   - 全页可点区域都撑到 40 高以上，戴手套也按得中；
///   - 除数据色带外一律不上色（见 app/theme.dart 的颜色说明）。
///
/// 原来「口袋模式」唯一独有的是不常亮 + 极简读数，而熄屏时界面根本看不见，
/// 极简读数因此没有意义：省电交给系统熄屏，界面只剩这一套（设计文档 10.1）。
///
/// 屏幕常亮由 RecordPage 用 wakelock 控制：亮屏就常亮，按电源键熄屏后
/// 随生命周期自动停。
class HandlebarView extends StatelessWidget {
  const HandlebarView({
    required this.state,
    required this.unit,
    required this.tileUrlTemplate,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.onPickDevice,
    super.key,
  });

  /// 主指标字号。设计文档 10.1 要求不小于 72。
  static const double primaryFontSize = kInstrumentNumeralSize;

  /// 按钮高度。比 Material 默认的 40 高得多——骑行中戴手套点按。
  static const double buttonHeight = 64;

  /// 轨迹缩略图高度。见设计文档 10.1 的布局预算。
  static const double mapHeight = 120;

  final RecordState state;
  final DistanceUnit unit;

  /// 瓦片源，与详情页同一个口径（来自设置，接口失效时可换源）。
  final String tileUrlTemplate;

  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  /// 骑行中点传感器灯或未连接的指标格时打开的配对入口。
  final void Function(SensorKind kind) onPickDevice;

  @override
  Widget build(BuildContext context) {
    final bool paused = state.isPaused;
    return SafeArea(
      child: Column(
        children: <Widget>[
          _StatusStrip(state: state, onPickDevice: onPickDevice),
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
                const SizedBox(height: kSpaceM),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kSpaceXl),
                  child: _SpeedScale(speedMps: state.currentSpeedMps),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _MetricStrip(state: state, unit: unit, onPickDevice: onPickDevice),
          const Divider(height: 1),
          // 缩略图放在指标条与按钮之间：抬眼读数时整页扫一遍就能看到轨迹的
          // 形状，不必切到详情页。不可交互，不吃手指。
          LiveRouteMap(
            points: state.liveTrack,
            tileUrlTemplate: tileUrlTemplate,
            subdomains: kDefaultMapTileSubdomains,
            height: mapHeight,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceS, kSpaceL, kSpaceS),
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

/// 器件边框条：状态灯 + 传感器连接态。
///
/// 三个传感器灯同时是骑行中的配对入口——不用退回准备页就能补连设备。
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.state,
    required this.onPickDevice,
  });

  final RecordState state;
  final void Function(SensorKind kind) onPickDevice;

  @override
  Widget build(BuildContext context) {
    final bool paused = state.isPaused;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceS, kSpaceS, kSpaceS),
      child: Row(
        children: <Widget>[
          // 左半用 Expanded 兜底：窄屏上先让「GPS 信号弱」这类提示收缩，
          // 而不是把右边的传感器灯挤出屏幕。
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
///
/// 下面一行的三格在**未连接**时本身可点，与顶部的传感器灯是同一个入口：
/// 骑行中看到「--」想知道怎么办，最直接的动作就是点那一格。连上了就不再吃
/// 点击——已经是对的读数，误触反而会弹出选设备面板。
class _MetricStrip extends StatelessWidget {
  const _MetricStrip({
    required this.state,
    required this.unit,
    required this.onPickDevice,
  });

  final RecordState state;
  final DistanceUnit unit;
  final void Function(SensorKind kind) onPickDevice;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kSpaceL,
          vertical: kSpaceS,
        ),
        child: Column(
          children: <Widget>[
            _MetricRow(
              cells: <Widget>[
                _MetricCell(
                  label: '距离',
                  value: formatDistance(state.distanceM, unit),
                ),
                _MetricCell(
                  label: '时长',
                  value: formatDuration(state.elapsedSeconds),
                ),
              ],
            ),
            const SizedBox(height: kSpaceS),
            _MetricRow(
              cells: <Widget>[
                _MetricCell(
                  label: '心率',
                  value: state.hr?.toString() ?? '--',
                  tooltip: state.hrConnected ? null : '心率未连接，点击连接',
                  onTap: state.hrConnected
                      ? null
                      : () => onPickDevice(SensorKind.heartRate),
                ),
                _MetricCell(
                  label: '踏频',
                  value: state.cadence?.toString() ?? '--',
                  tooltip: state.cadenceConnected ? null : '踏频未连接，点击连接',
                  onTap: state.cadenceConnected
                      ? null
                      : () => onPickDevice(SensorKind.cadence),
                ),
                // 没接功率计时这一格是估算值（速度 + 坡度 + 体重），标签里直接
                // 写明：骑到一半才发现「功率」其实不是功率计读数，不是好体验。
                _MetricCell(
                  label: state.powerConnected ? '功率' : '功率（估算）',
                  value: state.power?.toString() ?? '--',
                  tooltip: state.powerConnected ? null : '功率计未连接，点击连接',
                  onTap: state.powerConnected
                      ? null
                      : () => onPickDevice(SensorKind.power),
                ),
              ],
            ),
          ],
        ),
      );
}

/// 一行等宽格，用竖细线分隔——不用卡片、不用底色块。
class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.cells});

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          for (int i = 0; i < cells.length; i++) ...<Widget>[
            if (i > 0)
              Container(
                width: 1,
                height: 30,
                margin: const EdgeInsets.symmetric(horizontal: kSpaceM),
                color: kAppHairline,
              ),
            Expanded(child: cells[i]),
          ],
        ],
      );
}

/// 一格读数。[_onTap] 非空时整格可点，并在标签右侧挂一个「+」，把
/// 「点这里能补连设备」说出来——否则「--」看起来只是个空读数。
class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
    this.tooltip,
    this.onTap,
  });

  final String label;
  final String value;

  /// 可点时才给：[Tooltip] 的 message 不允许为空。
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = Column(
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label, style: kLabelTextStyle),
            if (onTap != null) ...<Widget>[
              const SizedBox(width: kSpaceXs),
              const Icon(Icons.add_circle_outline, size: 14, color: kAppTextMuted),
            ],
          ],
        ),
        const SizedBox(height: kSpaceXs),
        Text(value, style: kMetricTextStyle.copyWith(fontSize: kFontSubtitle)),
      ],
    );

    if (onTap == null) return content;
    return Tooltip(
      message: tooltip!,
      child: InkWell(
        onTap: onTap,
        // 整格都可点是给「骑行中手指抖」留的余量，因此不加 splash 边框，
        // 也不想让它因为圆角而与竖细线错位。
        borderRadius: BorderRadius.circular(kRadiusLine),
        child: content,
      ),
    );
  }
}