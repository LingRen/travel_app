import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/ui/paper_sheet.dart';
import '../../core/format.dart';
import '../../data/ble/sensor_monitor.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/constants.dart';
import '../../domain/models/activity_type.dart';
import '../activity/activity_type_chip.dart';
import '../activity/activity_type_sheet.dart';
import 'live_route_map.dart';
import 'record_controller.dart';
import 'ride_cue_banner.dart';

/// 速度刻度尺：把当前速度换算成 0..1 的填充比例。
///
/// 公开成纯函数是给测试留的接口——[CustomPaint] 没有可断言的语义节点，
/// 光看 widget 树验证不了「超量程被钳住」「负数不反向」。参照
/// `drawnMiniCurveSegments` 的既有做法。
double speedScaleFraction(
  double speedMps, {
  double maxMps = kSpeedScaleMaxMps,
}) => maxMps <= 0 ? 0 : (speedMps / maxMps).clamp(0.0, 1.0);

/// 骑行界面（车把与口袋合并后的唯一一个）。见设计文档 10.1。
///
/// **记录 tab 落地就是这一页**，不再有独立的准备页：未开始态由底部那颗整宽
/// 「开始」进入记录。传感器配对入口由顶部三盏灯与未连接的指标格承担。
///
/// 整页是**一张铺满全屏的轨迹地图**，读数与按钮浮在它上面 —— 顶部是状态 +
/// 距离/时长/海拔/爬升，底部是主读数 + 刻度尺 + 心率/踏频/功率 + 动作区。
/// 纸本主题不再用深色遮罩：上下两块各压一层纸色渐变，中间地图带保持原亮度；
/// 文字改墨色，靠纸色渐变与地图滤镜保证对比度。
///
/// 这一页的目标不是「好看」，是**在骑行中一步扫读**：骑到 30km/h 时瞄一眼
/// 屏幕只有约 200ms，还要在户外强光下。因此：
///   - 主指标 120pt 等宽数字，读数跳动时整数位不横向抖动；
///   - 刻度尺让速度有「现在处于什么位置」的参照，不必等下一帧数字；
///   - 浮层不用实体面板，只有纸色渐变；地图要真的看得见；
///   - 全页可点区域都撑到 40 高以上，戴手套也按得中；
///   - 除主题色、警告色与危险色外一律不上色（见 app/theme.dart 的颜色说明）。
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
    required this.selectedActivityType,
    required this.onSelectActivityType,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.onPickDevice,
    this.now,
    this.onFixError,
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

  /// 本次运动的类型。未开始时由 chip 行选择；记录中不可切换。
  final ActivityType selectedActivityType;

  /// 未开始时点 chip 行的回调。
  final ValueChanged<ActivityType> onSelectActivityType;

  /// 未开始时的「开始」。整宽独占底部动作区——未开始态只有这一个动作。
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;

  /// 记录中的「结束」。
  final VoidCallback onFinish;

  /// 骑行中点传感器灯或未连接的指标格时打开的配对入口。
  final void Function(SensorKind kind) onPickDevice;

  /// 待机页显示当前时间。测试注入固定时间；生产由 RecordPage 从 nowProvider 取。
  final DateTime? now;

  /// 阻断类错误旁的「去设置 / 打开定位」。
  final VoidCallback? onFixError;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final bool paused = state.isPaused;
    // phase 为空＝还没开始。此时这一页就是入口页：状态条写「准备出发」，
    // 主按钮是「开始」，暂停小键不出现（没东西可暂停）。
    final bool idle = state.phase == null;
    final bool locationReady = state.previewFix?.hasPosition ?? false;
    final double? altitudeM = state.currentAltitudeM;
    // 跑步/健走/徒步/登山的主读数用配速，骑行用速度。
    final bool usePace = selectedActivityType.usesPace;
    // 配速没有「停着」可言：速度为 0 时 [formatPace] 返回 `--`，而 120dp 下两个
    // 连字符就是两条粗杠，看着像渲染坏了。改用与 `5'30"` 同构的占位符并降到
    // 次要色，一眼能认出「还没有配速」。
    final bool pacePlaceholder = usePace && state.currentSpeedMps <= 0;
    final String? error = state.errorMessage;
    final String? errorActionLabel = error == null
        ? null
        : error.contains('定位服务')
        ? '打开定位'
        : error.contains('权限')
        ? '去设置'
        : null;
    final List<Widget> bottomCells = <Widget>[
      _MetricCell(
        label: '心率',
        value: state.hr?.toString() ?? '--',
        unit: 'bpm',
        tooltip: state.hrConnected ? null : '心率未连接，点击连接',
        onTap: state.hrConnected
            ? null
            : () => onPickDevice(SensorKind.heartRate),
      ),
      if (selectedActivityType.supportsCadence)
        _MetricCell(
          label: '踏频',
          value: state.cadence?.toString() ?? '--',
          unit: 'rpm',
          tooltip: state.cadenceConnected ? null : '踏频未连接，点击连接',
          onTap: state.cadenceConnected
              ? null
              : () => onPickDevice(SensorKind.cadence),
        ),
      if (selectedActivityType.supportsPower)
        // 没接功率计时这一格是估算值（速度 + 坡度 + 体重），标签里直接写明：
        // 骑到一半才发现「功率」其实不是功率计读数，不是好体验。跑步类型没有
        // 功率概念，整格不出现。
        _MetricCell(
          label: state.powerConnected ? '功率' : '功率（估算）',
          value: state.power?.toString() ?? '--',
          unit: 'W',
          tooltip: state.powerConnected ? null : '功率计未连接，点击连接',
          onTap: state.powerConnected
              ? null
              : () => onPickDevice(SensorKind.power),
        ),
      // 配速类型没有踏频/功率，底部三格改成心率 / 海拔 / 爬升：跑步和登山时
      // 这三项才是当下真正会看的读数。
      if (usePace) ...<Widget>[
        _MetricCell(
          label: '海拔',
          value: altitudeM == null ? '--' : formatElevation(altitudeM, unit),
        ),
        _MetricCell(
          label: '爬升',
          value: formatElevation(state.elevationGainM, unit),
        ),
      ],
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 小屏 + 大字号时纵向预算不够：底部导航与状态栏吃掉一百多 dp 后，地图带会
        // 被压到 120 dp 以下。这一档把速度刻度尺收起来、纵向间距减半，把空间还给地图。
        final bool compact =
            MediaQuery.textScalerOf(context).scale(1) >= 1.2 &&
            constraints.maxHeight < 620;
        final double blockGap = compact ? kSpaceXs : kSpaceS;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 整页就是地图。读数与按钮浮在它上面（见类注释与设计文档 10.1）。
            LiveRouteMap(
              points: state.liveTrack,
              breakIndexes: state.liveTrackBreaks,
              previewFix: state.previewFix,
              tileUrlTemplate: tileUrlTemplate,
              subdomains: kDefaultMapTileSubdomains,
              placeholderAlignment: const Alignment(0, -0.35),
              // 待机页的「等待定位」由中间那张卡片说明，地图上不再重复一句。
              showPlaceholder: !idle,
            ),
            // 纸色渐变。中间 0.46–0.56 留全透明，地图带保持原亮度；上下两块靠
            // 纸色压住足够的不透明度，墨色文字在浅色瓦片上也读得出来。
            IgnorePointer(
              child: DecoratedBox(
                key: const Key('handlebar-scrim'),
                decoration: const BoxDecoration(gradient: _kPaperScrim),
                child: const SizedBox.expand(),
              ),
            ),
            SafeArea(
              child: Column(
                children: <Widget>[
                  // 顶部一块：状态 + 本次运动的总量与环境读数。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      kSpaceM,
                      kSpaceS,
                      kSpaceM,
                      0,
                    ),
                    child: Column(
                      children: <Widget>[
                        _StatusStrip(
                          state: state,
                          idle: idle,
                          paused: paused,
                          locationReady: locationReady,
                          activityType: selectedActivityType,
                          compact: compact,
                          onPickDevice: onPickDevice,
                        ),
                        const SizedBox(height: kSpaceS),
                        _MetricRow(
                          dividerMargin: kSpaceS,
                          cells: <Widget>[
                            _MetricCell(
                              label: '距离',
                              value: formatDistance(state.distanceM, unit),
                            ),
                            _MetricCell(
                              label: '时长',
                              value: formatDurationClock(state.elapsedSeconds),
                            ),
                            // 海拔与爬升：前者是「现在多高」，后者是「一共爬了多少」。
                            // 设备不给高程时海拔显示 `--`，不显示 0——0 米海拔是一个
                            // 具体读数，会和「没有数据」混起来。
                            _MetricCell(
                              label: '海拔',
                              value: altitudeM == null
                                  ? '--'
                                  : formatElevation(altitudeM, unit),
                            ),
                            _MetricCell(
                              label: '爬升',
                              value: formatElevation(
                                state.elevationGainM,
                                unit,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 中间这条是留给地图的：待机卡片与提示横幅都浮在它正中。放在
                  // Stack 里而不是直接排进 Column——横幅每闪一次都改高度的话，
                  // 上下两块会跟着跳。
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        if (idle)
                          Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  ActivityTypeChip(
                                    key: const Key('activity-type-chip'),
                                    type: selectedActivityType,
                                    onTap: () => showPaperSheet<void>(
                                      context: context,
                                      builder: (_) => ActivityTypeSheet(
                                        current: selectedActivityType,
                                        onSelected: onSelectActivityType,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: kSpaceM),
                                  _IdleCard(
                                    now: now ?? DateTime.now(),
                                    accuracyM: state.previewFix?.accuracyM,
                                    locationReady: locationReady,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        RideCueBanner(
                          cue: state.lastCue,
                          seq: state.cueSeq,
                          unit: unit,
                          activityType: selectedActivityType,
                        ),
                      ],
                    ),
                  ),
                  // 底部一块：当下读数（主读数、传感器）与动作区。拇指与视线都在这儿，
                  // 所以把「现在多少」放这一块，把「一共多少」放到上面那块。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      kSpaceM,
                      0,
                      kSpaceM,
                      kSpaceS,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          usePace ? '当前配速' : '当前速度',
                          style: kLabelTextStyle.copyWith(color: palette.muted),
                        ),
                        const SizedBox(height: kSpaceXs),
                        // 速度与单位排成一行：单位贴着基线放在右侧，省下的那十几
                        // 像素留给地图。数字仍由 FittedBox 兜底——正常尺寸下它不
                        // 参与布局，只有横向真的放不下时才缩小。
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: usePace
                              ? _PaceReadout(
                                  speedMps: state.currentSpeedMps,
                                  unit: unit,
                                  placeholder: pacePlaceholder,
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: <Widget>[
                                    Text(
                                      formatSpeedValue(
                                        state.currentSpeedMps,
                                        unit,
                                      ),
                                      key: const Key('handlebar-speed'),
                                      style: kInstrumentTextStyle,
                                    ),
                                    const SizedBox(width: kSpaceS),
                                    Text(
                                      speedUnitLabel(unit),
                                      style: kLabelTextStyle.copyWith(
                                        color: palette.muted,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        SizedBox(height: blockGap),
                        // 速度刻度尺只有骑行有意义：配速没有「现在处于什么档位」的
                        // 参照，跑步看它纯属噪音。纵向紧张的档位（见 compact）也收起来。
                        if (!usePace && !compact) ...<Widget>[
                          _SpeedScale(speedMps: state.currentSpeedMps),
                          SizedBox(height: blockGap),
                        ],
                        _MetricRow(dividerMargin: kSpaceS, cells: bottomCells),
                        // 阻断类错误（定位权限 / 定位服务）与连续写入失败都显示在
                        // 这一屏：前者让「开始」点了没反应，不说清楚就成了哑键；
                        // 后者发生在骑行中。不用 SnackBar——它自己会消失，而这两个
                        // 错误在用户处理前一直成立。
                        if (error != null) ...<Widget>[
                          const SizedBox(height: kSpaceS),
                          _InlineNotice(
                            message: error,
                            actionLabel: errorActionLabel,
                            onAction: onFixError,
                          ),
                        ],
                        SizedBox(height: blockGap),
                        // 底部动作区。未开始只有一件事可做，那颗「开始」就整宽独占；
                        // 记录中按动作频率分宽：「暂停 / 继续」占 2/3 落在右下拇指区，
                        // 「结束」占 1/3 被推到左侧并隔开一个 kSpaceL。两颗键都撑满
                        // buttonHeight 高，骑车戴手套也按得中（见 10.1）。
                        SizedBox(
                          width: double.infinity,
                          height: buttonHeight,
                          child: idle
                              ? FilledButton.icon(
                                  key: const Key('handlebar-start'),
                                  onPressed: onStart,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: palette.accentInk,
                                    foregroundColor: palette.onAccent,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(kRadiusButton),
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 22,
                                  ),
                                  label: Text(
                                    '开始${selectedActivityType.label}',
                                    style: const TextStyle(
                                      fontSize: kFontTitle,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              : Row(
                                  // stretch：两颗键都要撑满 buttonHeight，而不是各自
                                  // 取固有高度后在 64 高的槽里居中——那会让它们看起来
                                  // 比未开始态那颗「开始」小一圈。
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    Expanded(
                                      flex: finishFlex,
                                      child: OutlinedButton(
                                        key: const Key('handlebar-finish'),
                                        onPressed: onFinish,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: palette.ink,
                                          backgroundColor: palette.sheet
                                              .withValues(alpha: 0.72),
                                          side: BorderSide(
                                            color: palette.hairline,
                                          ),
                                          shape: const RoundedRectangleBorder(
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(kRadiusButton),
                                            ),
                                          ),
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: <Widget>[
                                              const Icon(
                                                Icons.stop_rounded,
                                                size: 18,
                                              ),
                                              const SizedBox(width: kSpaceS),
                                              Text(
                                                '结束',
                                                style: const TextStyle(
                                                  fontSize: kFontTitle,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: kSpaceL),
                                    Expanded(
                                      flex: toggleFlex,
                                      child: FilledButton(
                                        key: const Key('handlebar-toggle'),
                                        onPressed: paused ? onResume : onPause,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: palette.accentInk,
                                          foregroundColor: palette.onAccent,
                                          shape: const RoundedRectangleBorder(
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(kRadiusButton),
                                            ),
                                          ),
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: <Widget>[
                                              Icon(
                                                paused
                                                    ? Icons.play_arrow_rounded
                                                    : Icons.pause_rounded,
                                                size: 20,
                                              ),
                                              const SizedBox(width: kSpaceS),
                                              Text(
                                                paused ? '继续' : '暂停',
                                                style: const TextStyle(
                                                  fontSize: kFontTitle,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
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
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 上下读数区背后的纸色渐变。
///
/// 顶部 0.94 → 0、底部 0.96 → 0，中间 0.46–0.56 留全透明：地图带保持原亮度，
/// 纸色只压在本来就被字和按钮盖住的两条带上。用渐变而不是实体面板，是为了
/// 让纸色与地图之间没有一条硬边。
const LinearGradient _kPaperScrim = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: <Color>[
    Color(0xF0F5F0E5),
    Color(0xF0F5F0E5),
    Color(0x00F5F0E5),
    Color(0x00F5F0E5),
    Color(0x8CF5F0E5),
    Color(0xF5F5F0E5),
    Color(0xF5F5F0E5),
  ],
  stops: <double>[0.0, 0.28, 0.46, 0.56, 0.64, 0.78, 1.0],
);

/// 还没有配速时的主读数占位符。
///
/// 不用 `--`：那是 [formatPace] 的返回值，在 120dp 下两个连字符就是两条粗杠，
/// 看不出是「暂无读数」。这里照 `5'30"` 的形状留空，配合次要色一眼可辨。历史
/// 卡片里的「配速 --」保持原样——那里字号只有 13，两条短杠不会再像色块。
const String _kPacePlaceholder = "--'--\"";

/// 器件边框条：状态灯 + 传感器连接态 + 三盏传感器灯。
///
/// 这里刻意**不放**任何动作键。暂停在底部动作区，这一条只剩状态与配对入口。
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.state,
    required this.idle,
    required this.paused,
    required this.locationReady,
    required this.activityType,
    required this.compact,
    required this.onPickDevice,
  });

  final RecordState state;
  final bool idle;
  final bool paused;
  final bool locationReady;

  /// 本次运动的类型。传感器灯按它裁剪：跑步没有踏频/功率灯。
  final ActivityType activityType;
  final bool compact;
  final void Function(SensorKind kind) onPickDevice;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    // 状态灯：实心强调色＝采集中，空心＝准备出发或已暂停。灯本身承担状态
    // 语义，旁边几个字只是给第一次用的人看的。
    final bool collecting = !idle && !paused;
    final String status = idle
        ? '准备出发'
        : paused
        ? '已暂停'
        : '记录中';
    final String? detail = idle
        ? (locationReady ? ' · GPS 已锁定' : ' · 等待定位')
        : paused
        ? null
        : (state.gpsWeak ? ' · GPS 信号弱' : ' · 信号良好');

    return Row(
      children: <Widget>[
        // 左半用 Flexible 兜底：窄屏上先让「GPS 信号弱」这类提示收缩，
        // 而不是把右边的传感器灯挤出屏幕。
        Expanded(
          child: Row(
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: collecting ? palette.accentInk : Colors.transparent,
                  border: Border.all(
                    color: collecting ? palette.accentInk : palette.muted,
                    width: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: kSpaceS),
              Text(
                status,
                style: TextStyle(
                  fontSize: kFontBody,
                  fontWeight: FontWeight.w600,
                  color: palette.ink,
                ),
              ),
              if (detail != null)
                Flexible(
                  // 窄屏大字号时「· GPS 已锁定」会被挤成省略号；这一档把这段
                  // 辅助文字的字号锁回基准，状态词本身仍随系统字号放大。
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: compact ? 1.0 : 2.0,
                    child: Text(
                      detail,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: kFontBody,
                        color: state.gpsWeak && !idle && !paused
                            ? palette.warning
                            : palette.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _SensorLamp(
          icon: Icons.favorite,
          connected: state.hrConnected,
          tooltip: state.hrConnected ? '心率已连接，点击更换设备' : '点击连接心率设备',
          onTap: () => onPickDevice(SensorKind.heartRate),
        ),
        if (activityType.supportsCadence)
          _SensorLamp(
            icon: Icons.sync,
            connected: state.cadenceConnected,
            tooltip: state.cadenceConnected ? '踏频已连接，点击更换设备' : '点击连接踏频设备',
            onTap: () => onPickDevice(SensorKind.cadence),
          ),
        if (activityType.supportsPower)
          _SensorLamp(
            icon: Icons.bolt,
            connected: state.powerConnected,
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
/// 本来就抖，小目标按不中。未连接时降成半透明的次级墨色，不用红：红在这套
/// 颜色语言里是「错误」。
class _SensorLamp extends StatelessWidget {
  const _SensorLamp({
    required this.icon,
    required this.connected,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool connected;
  final String tooltip;
  final VoidCallback onTap;

  static const double tapSize = 40;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return IconButton(
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
        color: connected
            ? palette.accentInk
            : palette.muted.withValues(alpha: 0.55),
      ),
    );
  }
}

/// 待机页中央的出发卡片：日期时间、定位状态与精度说明。
///
/// 放在地图带里，四周仍能看见地图；卡片本身用纸面 + 发丝线，不抢主读数的
/// 位置。定位还没锁定时也显示这张卡，用「等待定位…」说明当前状态，而不是
/// 让用户对着空白地图猜。
class _IdleCard extends StatelessWidget {
  const _IdleCard({
    required this.now,
    required this.accuracyM,
    required this.locationReady,
  });

  final DateTime now;
  final double? accuracyM;
  final bool locationReady;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final String title = locationReady ? '定位已就绪' : '等待定位…';
    final String subtitle = locationReady
        ? accuracyM == null
              ? '按下开始，记录这一程。'
              : '精度 ${accuracyM!.round()} m · 按下开始，记录这一程。'
        : '正在获取当前位置，按下开始后会再次尝试。';
    return Container(
      constraints: const BoxConstraints(maxWidth: 330),
      padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceM, kSpaceL, kSpaceM),
      decoration: BoxDecoration(
        color: palette.sheet.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(kRadiusPanel),
        border: Border.all(color: palette.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            formatChineseMonthDayWeekTime(now),
            style: kLabelTextStyle.copyWith(
              color: palette.muted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: kSpaceS),
          Container(width: 28, height: 2, color: palette.accentInk),
          const SizedBox(height: kSpaceS),
          Text(title, style: kSerifHeadingTextStyle.copyWith(fontSize: 24)),
          const SizedBox(height: kSpaceXs),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: kMutedTextStyle.copyWith(fontSize: kFontMeta),
          ),
        ],
      ),
    );
  }
}

/// 配速主读数：分、秒用仪表字号，分隔符降一档。
///
/// 直接把 `5'33"` 整串塞进 120pt 等宽字体会让撇号、引号各自占满一个字宽，
/// 中间空出两大块，像渲染坏了。这里把分隔符拆成小字号，数字仍保持
/// 120pt 的扫读尺寸；单位 `/km` 贴在右侧。
class _PaceReadout extends StatelessWidget {
  const _PaceReadout({
    required this.speedMps,
    required this.unit,
    required this.placeholder,
  });

  final double speedMps;
  final DistanceUnit unit;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final ({int minutes, int seconds})? parts = placeholder
        ? null
        : paceParts(speedMps, unit);
    if (parts == null) {
      return Semantics(
        label: '暂无配速',
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                _kPacePlaceholder,
                key: const Key('handlebar-speed'),
                style: kInstrumentTextStyle.copyWith(color: palette.muted),
              ),
              const SizedBox(width: kSpaceS),
              Text(
                paceUnitLabel(unit),
                style: kLabelTextStyle.copyWith(color: palette.muted),
              ),
            ],
          ),
        ),
      );
    }

    final TextStyle numeral = kInstrumentTextStyle.copyWith(color: palette.ink);
    // 撇号 / 引号用无衬线字体、降两档字号：等宽字体在 120pt 下会把它们
    // 画成两根粗竖条，看起来像读数坏了。
    final TextStyle mark = TextStyle(
      fontFamily: kSansFamily,
      fontFamilyFallback: kSansFallback,
      fontSize: 40,
      fontWeight: FontWeight.w600,
      height: 1,
      color: palette.muted,
    );
    return Semantics(
      label: '配速 ${formatPace(speedMps, unit)} ${paceUnitLabel(unit)}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              '${parts.minutes}',
              key: const Key('handlebar-speed'),
              style: numeral,
            ),
            Text("'", style: mark),
            Text(
              parts.seconds.toString().padLeft(2, '0'),
              key: const Key('handlebar-pace-seconds'),
              style: numeral,
            ),
            Text('"', style: mark),
            const SizedBox(width: kSpaceS),
            Text(
              paceUnitLabel(unit),
              key: const Key('handlebar-pace-unit'),
              style: kLabelTextStyle.copyWith(color: palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// 速度刻度尺。参照物是码表的横条速度指示：轨道 + 刻度 + 游标填充 + 档位数字。
///
/// 填充色取主题强调色，与地图轨迹、详情曲线、列表缩略图一致。
class _SpeedScale extends StatelessWidget {
  const _SpeedScale({required this.speedMps});

  final double speedMps;

  static const double _trackHeight = 20;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Column(
      children: <Widget>[
        SizedBox(
          height: _trackHeight,
          width: double.infinity,
          child: CustomPaint(
            painter: _SpeedScalePainter(
              speedMps,
              palette.accentInk,
              palette.hairline,
              palette.muted,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            for (final int value in <int>[0, 10, 20, 30, 40, 50])
              Text(
                '$value',
                style: kLabelTextStyle.copyWith(
                  fontSize: 10,
                  letterSpacing: 0,
                  color: palette.muted,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SpeedScalePainter extends CustomPainter {
  _SpeedScalePainter(
    this.speedMps,
    this.color,
    this.trackColor,
    this.tickColor,
  );

  final double speedMps;

  /// 填充色：主题强调色。
  final Color color;
  final Color trackColor;
  final Color tickColor;

  /// 刻度条数。11 条即每 10% 一格，对应满量程的 1/10。
  static const int tickCount = 11;

  @override
  void paint(Canvas canvas, Size size) {
    final double fraction = speedScaleFraction(speedMps);
    final double trackY = size.height * 0.35;
    const double trackHeight = 4;

    final Rect track = Rect.fromLTWH(0, trackY, size.width, trackHeight);
    final RRect trackRrect = RRect.fromRectAndRadius(
      track,
      const Radius.circular(kRadiusLine),
    );

    canvas.drawRRect(trackRrect, Paint()..color = trackColor);
    if (fraction > 0) {
      // 填充宽度至少一个圆角直径，否则低速时看不出有进度。
      final double filled = (size.width * fraction).clamp(
        trackHeight,
        size.width,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, trackY, filled, trackHeight),
          const Radius.circular(kRadiusLine),
        ),
        Paint()..color = color,
      );
    }

    // 刻度画在轨道下面，用次级墨色；首尾与中点画长刻度，其余短刻度。
    final Paint tickPaint = Paint()..color = tickColor;
    for (int i = 0; i < tickCount; i++) {
      final double x = size.width * i / (tickCount - 1);
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
  bool shouldRepaint(_SpeedScalePainter old) =>
      old.speedMps != speedMps ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.tickColor != tickColor;
}

/// 一行读数格，用竖细线分隔——不用卡片、不用底色块。
///
/// [dividerMargin] 由调用方定：顶部那行是四格，分隔线两侧留 [kSpaceS] 就够，
/// 留 [kSpaceM] 的话 360dp 的机器上每格只剩六十来像素，读数会被截断。
class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.cells, this.dividerMargin = kSpaceM});

  final List<Widget> cells;
  final double dividerMargin;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Row(
      children: <Widget>[
        for (int i = 0; i < cells.length; i++) ...<Widget>[
          if (i > 0)
            Container(
              width: 1,
              height: 30,
              margin: EdgeInsets.symmetric(horizontal: dividerMargin),
              color: palette.hairline,
            ),
          Expanded(child: cells[i]),
        ],
      ],
    );
  }
}

/// 一格读数。[onTap] 非空时整格可点，并在标签右侧挂一个「+」，把
/// 「点这里能补连设备」说出来——否则「--」看起来只是个空读数。
class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
    this.unit,
    this.tooltip,
    this.onTap,
  });

  final String label;
  final String value;

  /// 传感器读数的单位，例如 bpm / rpm / W。距离、海拔这类已经在值里带单位。
  final String? unit;

  /// 可点时才给：[Tooltip] 的 message 不允许为空。
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final bool placeholder = value == '--';
    final Widget content = Column(
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: kLabelTextStyle.copyWith(color: palette.muted),
              ),
            ),
            if (onTap != null) ...<Widget>[
              const SizedBox(width: kSpaceXs),
              Icon(
                Icons.add_circle_outline,
                size: 14,
                color: palette.accentInk,
              ),
            ],
          ],
        ),
        const SizedBox(height: kSpaceXs),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: kMetricTextStyle.copyWith(
                  color: placeholder ? palette.muted : palette.ink,
                ),
              ),
              if (unit != null && !placeholder) ...<Widget>[
                const SizedBox(width: 3),
                Text(
                  unit!,
                  style: kLabelTextStyle.copyWith(
                    fontSize: 10,
                    letterSpacing: 0,
                    color: palette.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
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
/// 单行 + 省略号，不为了把整句文案排全而把这一屏撑成两行；能处理的错误
/// 在右侧给一个明确入口（去设置 / 打开定位），不让用户只看到一句话。
class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Row(
      children: <Widget>[
        Icon(Icons.error_outline, size: 18, color: palette.danger),
        const SizedBox(width: kSpaceS),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: kFontMeta, color: palette.danger),
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            key: const Key('error-action'),
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: palette.accentInk,
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: kSpaceS),
            ),
            child: Text(
              actionLabel!,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}
