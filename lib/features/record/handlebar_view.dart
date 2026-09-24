import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/ble/sensor_monitor.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/color_scale.dart';
import '../../domain/analysis/constants.dart';
import 'live_route_map.dart';
import 'record_controller.dart';
import 'ride_cue_banner.dart';

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
/// **记录 tab 落地就是这一页**，不再有独立的准备页：未开始态由底部那颗整宽
/// 「开始」进入记录。传感器配对入口由顶部三盏灯与未连接的指标格承担。
///
/// 整页是**一张铺满全屏的轨迹地图**，读数与按钮浮在它上面 —— 上下各一块半透明
/// 面板（顶部：状态 + 距离/时长/海拔/爬升；底部：主速度 + 刻度尺 + 心率/踏频/功率
/// + 动作区），中间留出干净的看路窗口。之前地图只是一条 120pt 的缩略图，骑行中
/// 「我在哪、前面往哪拐」是第二个高频问题，值得给它整个屏幕。
///
/// 这一页的目标不是「好看」，是**在骑行中一步扫读**：骑到 30km/h 时瞄一眼
/// 屏幕只有约 200ms，还要在户外强光下。因此：
///   - 主指标 120pt 等宽数字，读数跳动时整数位不横向抖动；
///   - 刻度尺让速度有「现在处于什么位置」的参照，不必等下一帧数字；
///   - 面板半透明而不是全黑，地图在下面若隐若现，压暗只为了让文字站得住；
///   - 全页可点区域都撑到 40 高以上，戴手套也按得中；
///   - 除数据色带外一律不上色（见 app/theme.dart 的颜色说明）。
///
/// **地图不吃手势**（`InteractiveFlag.none`，见 [LiveRouteMap]）：骑行中戴手套
/// 误触不该把视野拖走，地图只做被动跟随轨迹。
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

  /// 底部动作区里「结束」与「暂停 / 继续」的宽度配比。
  ///
  /// 1:2 是照动作频率分的：骑行中红灯、休息都要按暂停，结束一次骑行只按一次。
  /// 主键拿走 2/3 也就落在右手拇指最容易够到的右下角，而「结束」被推到左侧、
  /// 变窄——不为好看，是为误触多付一点代价。
  static const int finishFlex = 1;
  static const int toggleFlex = 2;

  final RecordState state;
  final DistanceUnit unit;

  /// 瓦片源，与详情页同一个口径（来自设置，接口失效时可换源）。
  final String tileUrlTemplate;

  /// 未开始时的「开始」。整宽独占底部动作区——未开始态只有这一个动作。
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;

  /// 记录中的「结束」。
  final VoidCallback onFinish;

  /// 骑行中点传感器灯或未连接的指标格时打开的配对入口。
  final void Function(SensorKind kind) onPickDevice;

  /// 占位文案在整页里的落点。挪到上方，避开下方那块读数面板。
  static const Alignment _kPlaceholderAlignment = Alignment(0, -0.45);

  @override
  Widget build(BuildContext context) {
    final bool paused = state.isPaused;
    // phase 为空＝还没开始。此时这一页就是入口页：状态条写「未开始」，
    // 主按钮是「开始」，暂停小键不出现（没东西可暂停）。
    final bool idle = state.phase == null;
    final double? altitudeM = state.currentAltitudeM;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 整页就是地图。读数与按钮浮在它上面（见类注释与设计文档 10.1）。
        LiveRouteMap(
          points: state.liveTrack,
          tileUrlTemplate: tileUrlTemplate,
          subdomains: kDefaultMapTileSubdomains,
          placeholderAlignment: _kPlaceholderAlignment,
        ),
        // 瓦片是浅色底，白色读数直接压上去会糊掉。上下两条渐变把读数所在区域
        // 压暗，中间留出干净的看路窗口——比给面板加更深的底色更好，阴影与
        // 大色块都不在这套视觉语言里。
        const _Scrim(alignment: Alignment.topCenter, height: _kTopScrimHeight),
        const _Scrim(alignment: Alignment.bottomCenter, height: _kBottomScrimHeight),
        SafeArea(
          child: Column(
            children: <Widget>[
              // 顶部浮层：状态 + 本次骑行的总量与环境读数。
              Padding(
                padding: const EdgeInsets.fromLTRB(kSpaceM, kSpaceM, kSpaceM, 0),
                child: _OverlayPanel(
                  child: Column(
                    children: <Widget>[
                      _StatusStrip(
                        state: state,
                        idle: idle,
                        paused: paused,
                        onPickDevice: onPickDevice,
                      ),
                      const SizedBox(height: kSpaceM),
                      _MetricRow(
                        dividerMargin: kSpaceS,
                        cells: <Widget>[
                          _MetricCell(
                            label: '距离',
                            value: formatDistance(state.distanceM, unit),
                            valueFontSize: kFontBody,
                          ),
                          _MetricCell(
                            label: '时长',
                            value: formatDuration(state.elapsedSeconds),
                            valueFontSize: kFontBody,
                          ),
                          // 海拔与爬升：前者是「现在多高」，后者是「一共爬了多少」。
                          // 设备不给高程时海拔显示 `--`，不显示 0——0 米海拔是
                          // 一个具体读数，会和「没有数据」混起来。
                          _MetricCell(
                            label: '海拔',
                            value: altitudeM == null
                                ? '--'
                                : formatElevation(altitudeM, unit),
                            valueFontSize: kFontBody,
                          ),
                          _MetricCell(
                            label: '爬升',
                            value: formatElevation(state.elevationGainM, unit),
                            valueFontSize: kFontBody,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // 中间这条是留给地图的：提示横幅浮在它正中。放在 Stack 里而不是
              // 直接排进 Column——横幅每闪一次都改高度的话，上下两块会跟着跳。
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    RideCueBanner(
                      cue: state.lastCue,
                      seq: state.cueSeq,
                      unit: unit,
                    ),
                  ],
                ),
              ),
              // 底部浮层：当下读数（速度、传感器）与动作区。拇指与视线都在这儿，
              // 所以把「现在多少」放这一块，把「一共多少」放到上面那块。
              Padding(
                padding: const EdgeInsets.fromLTRB(kSpaceM, 0, kSpaceM, kSpaceM),
                child: _OverlayPanel(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // 主数字用 FittedBox 兜底：正常尺寸下它不参与布局，字号始终
                      // 由 kInstrumentTextStyle 决定（缩放的只是绘制框）；只有横向
                      // 真的放不下时才缩小，而不是溢出。
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
                      _SpeedScale(speedMps: state.currentSpeedMps),
                      const SizedBox(height: kSpaceM),
                      _MetricRow(
                        dividerMargin: kSpaceS,
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
                          // 没接功率计时这一格是估算值（速度 + 坡度 + 体重），标签里
                          // 直接写明：骑到一半才发现「功率」其实不是功率计读数，
                          // 不是好体验。
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
                      // 阻断类错误（定位权限 / 定位服务）与连续写入失败都显示在
                      // 这一屏：前者让「开始」点了没反应，不说清楚就成了哑键；
                      // 后者发生在骑行中。不用 SnackBar——它自己会消失，而这两个
                      // 错误在用户处理前一直成立。
                      if (state.errorMessage != null) ...<Widget>[
                        const SizedBox(height: kSpaceM),
                        _InlineNotice(message: state.errorMessage!),
                      ],
                      const SizedBox(height: kSpaceM),
                      // 底部动作区。未开始只有一件事可做，那颗「开始」就整宽独占；
                      // 记录中按动作频率分宽：「暂停 / 继续」占 2/3 落在右下拇指区，
                      // 「结束」占 1/3 被推到左侧并隔开一个 kSpaceL。两颗键都撑满
                      // buttonHeight 高，骑车戴手套也按得中（见 10.1）。
                      SizedBox(
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
                            : Row(
                                // stretch：两颗键都要撑满 buttonHeight，而不是各自
                                // 取固有高度后在 64 高的槽里居中——那会让它们看起来
                                // 比未开始态那颗「开始」小一圈。
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  Expanded(
                                    flex: finishFlex,
                                    child: OutlinedButton(
                                      onPressed: onFinish,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: kAppDanger,
                                        side: const BorderSide(
                                          color: kAppDanger,
                                          width: 1,
                                        ),
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
                                  const SizedBox(width: kSpaceL),
                                  Expanded(
                                    flex: toggleFlex,
                                    child: FilledButton(
                                      onPressed: paused ? onResume : onPause,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: kAppAccent,
                                        foregroundColor: kAppOnAccent,
                                      ),
                                      child: Text(
                                        paused ? '继续' : '暂停',
                                        style: const TextStyle(
                                          fontSize: kFontTitle,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 顶部压暗渐变的覆盖高度。
const double _kTopScrimHeight = 240;

/// 底部压暗渐变的覆盖高度。要盖住整块底部浮层再往上一段，让它的上沿不至于
/// 突兀地切在地图中间。
const double _kBottomScrimHeight = 460;

/// 压暗渐变：从底色实到全透明，把浮层所在的区域压暗。
///
/// 不用阴影、也不用给面板堆更深的底色：这两样都会在浅色瓦片上形成一圈硬边，
/// 而渐变是连续的，地图在它下面还能看出走向。
class _Scrim extends StatelessWidget {
  const _Scrim({required this.alignment, required this.height});

  final AlignmentGeometry alignment;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bool atTop = alignment == Alignment.topCenter;
    return Align(
      alignment: alignment,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: atTop ? Alignment.topCenter : Alignment.bottomCenter,
            end: atTop ? Alignment.bottomCenter : Alignment.topCenter,
            colors: <Color>[
              kAppBackground.withValues(alpha: 0.92),
              kAppBackground.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// 浮在地图上的半透明面板。
///
/// 完全不透明就成了一块黑板，把「全屏地图」的意义抹掉；再透一点，浅色瓦片会
/// 吃掉文字对比度。0.86 是这两者之间的取值。
class _OverlayPanel extends StatelessWidget {
  const _OverlayPanel({required this.child});

  final Widget child;

  static const double _opacity = 0.86;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(kSpaceM),
        decoration: BoxDecoration(
          color: kAppSurface.withValues(alpha: _opacity),
          borderRadius: const BorderRadius.all(Radius.circular(kRadiusPanel)),
          border: Border.all(color: kAppHairline, width: 1),
        ),
        child: child,
      );
}

/// 器件边框条：状态灯 + 传感器连接态 + 三盏传感器灯。
///
/// 这里刻意**不放**任何动作键。它原来挂过「暂停 / 继续」那颗 40dp 小键，问题
/// 有两个：一是骑行中最频繁的动作被放在屏幕最难够到的顶部，二是它紧挨三盏
/// 传感器灯，而灯是配对入口——误触会当场弹出模态选设备面板，骑行中弹模态比
/// 按错键更糟。暂停因此下移到 [HandlebarView] 的底部动作区，这一条只剩状态。
///
/// 外层的边距由 [_OverlayPanel] 提供，这里不再自带 padding。
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.state,
    required this.idle,
    required this.paused,
    required this.onPickDevice,
  });

  final RecordState state;
  final bool idle;
  final bool paused;
  final void Function(SensorKind kind) onPickDevice;

  @override
  Widget build(BuildContext context) {
    // 状态灯：实心琥珀＝采集中，空心＝未开始或已暂停。灯本身承担状态语义，
    // 旁边三个字只是给第一次用的人看的。
    final bool collecting = !idle && !paused;
    return Row(
      children: <Widget>[
        // 左半用 Expanded 兜底：窄屏上先让「GPS 信号弱」这类提示收缩，
        // 而不是把右边的传感器灯挤出屏幕。
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

/// 一行等宽格，用竖细线分隔——不用卡片、不用底色块。
///
/// [dividerMargin] 由调用方定：顶部那行是四格，分隔线两侧留 [kSpaceS] 就够，
/// 留 [kSpaceM] 的话 360dp 的机器上每格只剩六十来像素，「1.23 km」会被截断。
class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.cells, this.dividerMargin = kSpaceM});

  final List<Widget> cells;
  final double dividerMargin;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          for (int i = 0; i < cells.length; i++) ...<Widget>[
            if (i > 0)
              Container(
                width: 1,
                height: 30,
                margin: EdgeInsets.symmetric(horizontal: dividerMargin),
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
    this.valueFontSize = kFontSubtitle,
  });

  final String label;
  final String value;

  /// 可点时才给：[Tooltip] 的 message 不允许为空。
  final String? tooltip;
  final VoidCallback? onTap;

  /// 数值字号。顶部四格比底部三格窄，用小一号。
  final double valueFontSize;

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
        Text(value, style: kMetricTextStyle.copyWith(fontSize: valueFontSize)),
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
  Widget build(BuildContext context) => Row(
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
      );
}