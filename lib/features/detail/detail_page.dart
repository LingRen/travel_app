import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/curve.dart';
import '../../domain/analysis/gcj02.dart';
import '../../domain/analysis/heart_rate.dart';
import '../../domain/analysis/route_segments.dart';
import '../../domain/models/track_point.dart';
import '../../domain/models/workout.dart';
import '../../domain/models/workout_conditions.dart';
import '../../domain/models/workout_summary.dart';
import 'curve_chart.dart';
import 'detail_providers.dart';
import 'gpx_export.dart';
import 'hr_zone_bar.dart';
import 'route_map.dart';
import 'summary_grid.dart';

/// 竖屏下详情页地图的高度。
const double _kMapHeight = 260;

/// 矮视口（横屏）下地图最多占视口高度的比例。
const double _kMapHeightShrink = 0.45;

/// 单次运动详情页。见设计文档 10.3。
///
/// 页眉只有返回与「{类型}详情」，地图装在一张发丝线卡片里；下面是标题 / 日期、
/// 两行三列汇总、按类型命名的曲线与导出入口。
class DetailPage extends ConsumerWidget {
  const DetailPage({required this.rideId, super.key});

  final int rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<WorkoutDetail> detail = ref.watch(
      rideDetailProvider(rideId),
    );
    final DistanceUnit unit =
        ref.watch(appSettingsProvider).value?.distanceUnit ??
        DistanceUnit.kilometer;
    final String typeLabel = detail.value?.ride.activityType.label ?? '运动';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _DetailTopBar(title: '$typeLabel详情'),
            Expanded(
              child: detail.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object error, StackTrace stack) =>
                    Center(child: Text('读取记录失败：$error')),
                data: (WorkoutDetail data) =>
                    _DetailBody(detail: data, unit: unit),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return SizedBox(
      height: 52,
      child: Stack(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('detail-back'),
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(
                foregroundColor: palette.ink,
                padding: const EdgeInsets.symmetric(horizontal: kSpaceL),
                minimumSize: const Size(44, 44),
              ),
              icon: const Icon(Icons.chevron_left, size: 22),
              label: const Text('返回'),
            ),
          ),
          Center(
            child: Text(
              title,
              style: kLabelTextStyle.copyWith(
                color: palette.muted,
                letterSpacing: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 详情页标题下的地点。没有地名时返回空，让右侧天气单独靠右。
class _ConditionsPlace extends StatelessWidget {
  const _ConditionsPlace({required this.conditions});

  final WorkoutConditions conditions;

  @override
  Widget build(BuildContext context) {
    final String? place = conditions.placeLabel;
    if (place == null) return const SizedBox.shrink();
    final AppPalette palette = context.palette;
    return Row(
      children: <Widget>[
        Icon(Icons.place_outlined, size: 16, color: palette.accentInk),
        const SizedBox(width: kSpaceXs),
        Expanded(
          child: Text(
            place,
            key: const Key('detail-conditions-place'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: kFontMeta, color: palette.muted),
          ),
        ),
      ],
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.detail, required this.unit});

  final WorkoutDetail detail;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = context.palette;
    final Workout ride = detail.ride;
    final List<TrackPoint> points = detail.points;
    final int maxHeartRate =
        ref.watch(appSettingsProvider).value?.maxHeartRate ??
        kDefaultMaxHeartRate;

    final List<CurveSample> speedSamples = buildCurve(
      points,
      metric: CurveMetric.speed,
    );
    final List<CurveSample> hr = buildCurve(
      points,
      metric: CurveMetric.heartRate,
    );
    final List<CurveSample> cadence = buildCurve(
      points,
      metric: CurveMetric.cadence,
    );
    final List<CurveSample> power = buildCurve(
      points,
      metric: CurveMetric.power,
    );

    final bool usesPace = ride.activityType.usesPace;
    final double metersPerUnit = unit == DistanceUnit.mile ? 1609.344 : 1000.0;
    // 配速曲线纵轴是「秒/单位距离」，不是速度。直接把速度曲线改个标题会
    // 让纵轴含义和标注对不上，这里先换算再交给同一个画笔。
    final List<CurveSample> paceSamples = <CurveSample>[
      for (final CurveSample sample in speedSamples)
        if (sample.y > 0)
          CurveSample(
            xSeconds: sample.xSeconds,
            y: metersPerUnit / sample.y,
            segment: sample.segment,
          ),
    ];
    final List<CurveSample> mainSamples = usesPace ? paceSamples : speedSamples;

    final WorkoutSummary? s = ride.summary;
    final String speedUnit = speedUnitLabel(unit);
    final String paceUnit = paceUnitLabel(unit);
    final double? mainAverage = usesPace
        ? (s != null && s.movingAvgSpeedMps > 0
              ? metersPerUnit / s.movingAvgSpeedMps
              : null)
        : s?.avgSpeedMps;

    final String tileUrl =
        ref.watch(appSettingsProvider).value?.mapTileUrlTemplate ??
        kDefaultMapTileUrlTemplate;
    final bool toGcj02 = isGcj02TileSource(tileUrl);
    final List<RouteSegment> route = buildRouteSegments(
      points,
      toGcj02: toGcj02,
    );
    final List<RouteGap> gaps = findRouteGaps(points, toGcj02: toGcj02);
    final int gapSeconds = gaps.fold(
      0,
      (int sum, RouteGap gap) => sum + gap.durationS,
    );
    final double mapHeight = math.min(
      _kMapHeight,
      MediaQuery.sizeOf(context).height * _kMapHeightShrink,
    );
    final String? title = ride.title?.trim();
    final String displayTitle = (title == null || title.isEmpty)
        ? '${ride.activityType.label}记录'
        : title;

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceS, kSpaceL, 0),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: palette.hairline),
              borderRadius: BorderRadius.circular(kRadiusPanel),
            ),
            clipBehavior: Clip.antiAlias,
            child: RouteMap(
              segments: route,
              tileUrlTemplate: tileUrl,
              subdomains: kDefaultMapTileSubdomains,
              gapEnds: <LatLng>[
                for (final RouteGap gap in gaps) ...<LatLng>[
                  LatLng(gap.before.lat, gap.before.lon),
                  LatLng(gap.after.lat, gap.after.lon),
                ],
              ],
              height: mapHeight,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceM, kSpaceL, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Text(
                  displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: kSerifHeadingTextStyle.copyWith(
                    fontSize: 28,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: kSpaceM),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    formatMonthDayDot(ride.startedAtMs),
                    style: kSerifHeadingTextStyle.copyWith(
                      fontSize: 22,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatChineseWeekday(ride.startedAtMs)} · '
                    '${formatTimeHm(ride.startedAtMs)}',
                    style: TextStyle(
                      fontSize: kFontMeta,
                      color: palette.muted,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // 地点与天气只在记录捕获到对应字段时显示；旧记录没有这些数据，
        // 整行不渲染，不拿标题或时间冒充地点。
        if (!ride.conditions.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceS, kSpaceL, 0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _ConditionsPlace(conditions: ride.conditions),
                ),
                if (ride.conditions.weatherLabel != null) ...<Widget>[
                  const SizedBox(width: kSpaceM),
                  Text(
                    ride.conditions.weatherLabel!,
                    key: const Key('detail-conditions-weather'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: kFontMeta,
                      color: palette.muted,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                ],
              ],
            ),
          ),
        // 只在地图真的断过时解释；地点与天气已在上方单独展示，这里不重复。
        if (gaps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceS, kSpaceL, 0),
            child: Row(
              children: <Widget>[
                Icon(Icons.wifi_off, size: 16, color: palette.warning),
                const SizedBox(width: kSpaceS),
                Expanded(
                  child: Text(
                    '信号中断 ${gaps.length} 段 · 共 ${formatDuration(gapSeconds)}',
                    style: TextStyle(
                      fontSize: kFontMeta,
                      color: palette.warning,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: kSpaceS),
        Divider(
          height: 1,
          indent: kSpaceL,
          endIndent: kSpaceL,
          color: palette.hairline,
        ),
        SummaryGrid(
          key: const Key('detail-summary'),
          ride: ride,
          unit: unit,
          points: points,
        ),
        Divider(
          height: 1,
          indent: kSpaceL,
          endIndent: kSpaceL,
          color: palette.hairline,
        ),
        if (points.isEmpty)
          Padding(
            padding: const EdgeInsets.all(kSpaceL),
            child: Text(
              '这次${ride.activityType.label}没有轨迹数据',
              style: kMutedTextStyle,
            ),
          ),
        if (mainSamples.length >= 2)
          _MetricSection(
            key: const Key('detail-section-speed'),
            title: usesPace ? '配速' : '速度',
            summary: usesPace
                ? (s == null
                      ? ''
                      : '均配 ${formatPace(s.movingAvgSpeedMps, unit)} $paceUnit')
                : (s == null
                      ? ''
                      : '均速 ${formatSpeedValue(s.avgSpeedMps, unit)} $speedUnit'),
            child: CurveChart(
              samples: mainSamples,
              unitLabel: usesPace ? paceUnit : speedUnit,
              averageValue: mainAverage,
              formatValue: usesPace
                  ? formatPaceSeconds
                  : (double value) => formatSpeedValue(value, unit),
              baseColorArgb: palette.accentInk.toARGB32(),
            ),
          ),
        if (hr.length >= 2)
          _MetricSection(
            key: const Key('detail-section-hr'),
            title: '心率',
            summary: _hrSummary(s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                CurveChart(
                  samples: hr,
                  unitLabel: 'bpm',
                  averageValue: s?.avgHr?.toDouble(),
                  formatValue: _wholeNumber,
                  baseColorArgb: palette.accentInk.toARGB32(),
                ),
                const SizedBox(height: kSpaceM),
                HrZoneBar(breakdown: hrZoneBreakdown(points, maxHeartRate)),
              ],
            ),
          ),
        if (!usesPace && cadence.length >= 2)
          _MetricSection(
            key: const Key('detail-section-cadence'),
            title: '踏频',
            summary: s?.avgCadence == null
                ? ''
                : '均 ${s!.avgCadence!.round()} rpm',
            child: CurveChart(
              samples: cadence,
              unitLabel: 'rpm',
              averageValue: s?.avgCadence,
              formatValue: _wholeNumber,
              baseColorArgb: palette.accentInk.toARGB32(),
            ),
          ),
        if (!usesPace && power.length >= 2)
          _MetricSection(
            key: const Key('detail-section-power'),
            // 没接功率计时，这里的功率是按速度、坡度与体重估出来的；标题
            // 必须写明，否则会被当成功率计的实测值。
            title: ride.powerDeviceName == null ? '功率（估算）' : '功率',
            summary: _powerSummary(s),
            child: CurveChart(
              samples: power,
              unitLabel: 'W',
              averageValue: s?.avgPowerW,
              formatValue: _wholeNumber,
              baseColorArgb: palette.accentInk.toARGB32(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kSpaceL,
            kSpaceXl,
            kSpaceL,
            kSpaceXxl,
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('gpx-export'),
              onPressed: () => _exportGpx(context, ride, points),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('导出 GPX'),
            ),
          ),
        ),
      ],
    );
  }

  static String _hrSummary(WorkoutSummary? s) {
    final List<String> parts = <String>[];
    if (s?.avgHr != null) parts.add('均 ${s!.avgHr!.round()}');
    if (s?.maxHr != null) parts.add('高 ${s!.maxHr}');
    return parts.isEmpty ? '' : '${parts.join(' · ')} bpm';
  }

  static String _powerSummary(WorkoutSummary? s) {
    final List<String> parts = <String>[];
    if (s?.avgPowerW != null) parts.add('均 ${s!.avgPowerW!.round()} W');
    if (s?.maxPowerW != null) parts.add('高 ${s!.maxPowerW} W');
    return parts.join(' · ');
  }

  /// 导出失败时给用户一句能看懂的话，而不是把异常栈糊在界面上。
  Future<void> _exportGpx(
    BuildContext context,
    Workout ride,
    List<TrackPoint> points,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await const GpxExporter().exportAndShare(ride: ride, points: points);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$error')));
    }
  }
}

/// 心率 / 踏频 / 功率在曲线上的标注口径：取整。
String _wholeNumber(double value) => value.round().toString();

/// 一个指标区块：标题 + 右侧摘要 + 曲线。
class _MetricSection extends StatelessWidget {
  const _MetricSection({
    required this.title,
    required this.summary,
    required this.child,
    super.key,
  });

  final String title;
  final String summary;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Divider(
          height: 1,
          indent: kSpaceL,
          endIndent: kSpaceL,
          color: palette.hairline,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kSpaceL,
            kSpaceL,
            kSpaceL,
            kSpaceS,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: kSectionTextStyle.copyWith(
                    fontFamily: kSerifFamily,
                    fontFamilyFallback: kSerifFallback,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (summary.isNotEmpty)
                Text(
                  summary,
                  style: kLabelTextStyle.copyWith(
                    color: palette.muted,
                    letterSpacing: 0,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kSpaceL),
          child: child,
        ),
      ],
    );
  }
}
