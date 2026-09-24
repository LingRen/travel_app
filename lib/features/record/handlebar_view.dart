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

/// 骑行界面（车把与口袋合并后的唯一一个）。见设计文档 10.1。
///
/// **记录 tab 落地就是这一页**，不再有独立的准备页：未开始态由底部那颗
/// 「开始」进入记录，记录中同一个位置的同一颗键变成「结束」——拇指只学一个
/// 位置，也就不会在骑行中把「结束」和别的大键按混。传感器配对入口由顶部
/// 三盏灯与未连接的指标格承担，因此也不需要一个专门的准备页。
///
/// 这一页的目标不是「好看」，是**在骑行中一步扫读**：骑到 30km/h 时瞄一眼
/// 屏幕只有约 200ms，还要在户外强光下。因此：
///   - 主指标 120pt 等宽数字，读数跳动时整数位不横向抖动；
///   - 刻度尺让速度有「现在处于什么位置」的参照，不必等下一帧数字；
///   - 全页可点区域都撑到 40 高以上，戴手套也按得中；
///   - 除数据色带外一律不上色（见 app/theme.dart 的颜色说明）。
///
/// 屏幕常亮由 RecordPage 用 wakelock 控制：亮屏就常亮，按电源键熄屏后
/// 随生命周期自动停。
class HandlebarView extends StatelessWidget {
  const HandlebarView({
    required this.state,
    required this.unit,
    required this.tileUrlTemplate,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.onPickDevice,
    super.key,
  });

  /// 主指标字号。设计文档 10.1 要求不小于 72。
  static const double primaryFontSize = kInstrumentNumeralSize;

  /// 主按钮高度。比 Material 默认的 40 高得多——骑行中戴手套点按。
  static const double buttonHeight = 64;

  /// 轨迹缩略图高度。见设计文档 10.1 的布局预算。
  static const double mapHeight = 120;

  /// 状态条上「暂停 / 继续」小键的高度。与传感器灯同高，状态条不因此变厚。
  static const double toggleHeight = 40;

  final RecordState state;
  final DistanceUnit unit;

  /// 瓦片源，与详情页同一个口径（来自设置，接口失效时可换源）。
  final String tileUrlTemplate;

  /// 未开始时「开始」。与 [onFinish] 是同一颗按钮的两个字。
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  /// 骑行中点传感器灯或未连接的指标格时打开的配对入口。
  final void Function(SensorKind kind) onPickDevice;

  @override
  Widget build(BuildContext context) {
    final bool paused = state.isPaused;
    // phase 为空＝还没开始。此时这一页就是入口页：状态条写「未开始」，
    // 主按钮是「开始」，暂停小键不出现（没东西可暂停）。
    final bool idle = state.phase == null;
    return SafeArea(
      child: Column(
        children: <Widget>[
          _StatusStrip(
            state: state,
            idle: idle,
            paused: paused,
            onPause: onPause,
            onResume: onResume,
            onPickDevice: onPickDevice,
          ),
          const Divider(height: 1),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // 主数字用 Flexible + FittedBox 兜底：正常尺寸下它不参与布局，
                // 字号始终由 kInstrumentTextStyle 决定（缩放的只是绘制框）；
                // 只有高度真的不够时（例如同一屏挤进了阻断类错误提示，见
                // 11.1）才缩小，而不是溢出。
                Flexible(
                  child: FittedBox(
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
          // 阻断类错误（定位权限 / 定位服务）与连续写入失败都显示在这一屏：
          // 前者让「开始」点了没反应，不说清楚就成了哑键；后者发生在骑行中。
          // 不用 SnackBar——它自己会消失，而这两个错误在用户处理前一直成立。
          if (state.errorMessage != null) _InlineNotice(message: state.errorMessage!),
          // 主按钮：未开始是「开始」，记录中是「结束」。主动作（暂停 / 继续）
          // 由状态条右侧那颗小键承担，于是这颗大键永远只意味着「开一次记录」
          // 或「收一次记录」，位置与尺寸都不变，拇指不必分辨两个几乎一样大的
          // 键哪个是哪个。
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceS, kSpaceL, kSpaceS),
            child: SizedBox(
              width: double.infinity,
              height: buttonHeight,
              child: idle
                  ? FilledButton(
                      onPressed: onStart,
                      style: FilledButton.styleFrom(
                        backgroundColor: kAppAccent,
                        foregroundColor: kAppOnAccent,
                      ),
                      child: const Text(
                        '开始',
                        style: TextStyle(
                          fontSize: kFontTitle,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : OutlinedButton(
                      onPressed: onFinish,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kAppDanger,
                        side: const BorderSide(color: kAppDanger, width: 1),
                      ),
                      child: const Text(
                        '结束',
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

/// 器件边框条：状态灯 + 传感器连接态 + 暂停 / 继续小键。
///
/// 三个传感器灯同时是骑行中的配对入口——不用切到别的页面就能补连设备。
/// 暂停 / 继续也放这里：它和「结束」曾经是并排的两颗同样大的键，骑行中要分
/// 辨哪颗是哪颗；现在主按钮只留「开始 / 结束」，暂停降级成这颗小键，两个动作
/// 在视觉上再也混不到一起。
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.state,
    required this.idle,
    required this.paused,
    required this.onPause,
    required this.onResume,
    required this.onPickDevice,
  });

  final RecordState state;
  final bool idle;
  final bool paused;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final void Function(SensorKind kind) onPickDevice;

  @override
  Widget build(BuildContext context) {
    // 状态灯：实心琥珀＝采集中，空心＝未开始或已暂停。灯本身承担状态语义，
    // 旁边三个字只是给第一次用的人看的。
    final bool collecting = !idle && !paused;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceS, kSpaceS, kSpaceS),
      child: Row(
        children: <Widget>[
          // 左半用 Expanded 兜底：窄屏上先让「GPS 信号弱」这类提示收缩，
          // 而不是把右边的键与传感器灯挤出屏幕。
          Expanded(
            child: Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: collecting ? kAppAccent : Colors.transparent,
                    border: Border.all(
                      color: collecting ? kAppAccent : kAppTextMuted,
                      width: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: kSpaceS),
                Text(
                  idle
                      ? '未开始'
                      : paused
                          ? '已暂停'
                          : '进行中',
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
          // 未开始时没有可暂停的东西，这颗键不出现——否则一个点了没反应的键
          // 比没有更糟。
          if (!idle)
            SizedBox(
              height: HandlebarView.toggleHeight,
              child: OutlinedButton(
                onPressed: paused ? onResume : onPause,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kAppAccent,
                  side: const BorderSide(color: kAppAccent, width: 1),
                  padding: const EdgeInsets.symmetric(horizontal: kSpaceM),
                  // 状态条的高度由传感器灯定（40），这颗键不能把它撑厚。
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(paused ? '继续' : '暂停'),
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

/// 行内提示：阻断类错误（定位权限 / 定位服务）与连续写入失败。
///
/// 单行 + 省略号，不为了把整句文案排全而把这一屏撑成两行——它的职责只是把
/// 「点了没反应」解释清楚，处理方式在系统设置里，这里写不下也没关系。
class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceS, kSpaceL, 0),
        child: Row(
          children: <Widget>[
            const Icon(Icons.error_outline, size: 18, color: kAppDanger),
            const SizedBox(width: kSpaceS),
            Expanded(
              child: Text(
                message,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: kFontBody,
                  color: kAppTextPrimary,
                ),
              ),
            ),
          ],
        ),
      );
}