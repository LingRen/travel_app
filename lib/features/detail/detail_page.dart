import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/curve.dart';
import '../../domain/analysis/gcj02.dart';
import '../../domain/analysis/heart_rate.dart';
import '../../domain/analysis/route_segments.dart';
import '../../domain/models/activity_type.dart';
import '../../domain/models/track_point.dart';
import '../../domain/models/workout.dart';
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
///
/// 横屏可用视口只有约 253dp（333 − 状态栏 − AppBar），固定 260dp 的地图比它还
/// 高：首屏被地图占满，而地图开了拖动会吃掉滑动手势，页面滚不动，下方的汇总与
/// 曲线就够不到了（真机横屏实测）。收窄到视口高度的一小段，让下面能露出来。
const double _kMapHeightShrink = 0.45;

/// 单次骑行详情页。见设计文档 10.3。
///
/// 地图轨迹与导出 GPX 由 Task 10 补在本页上方与下方。
class DetailPage extends ConsumerWidget {
  const DetailPage({required this.rideId, super.key});

  final int rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<WorkoutDetail> detail = ref.watch(rideDetailProvider(rideId));
    final DistanceUnit unit =
        ref.watch(appSettingsProvider).value?.distanceUnit ??
            DistanceUnit.kilometer;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          detail.value?.ride.title ??
              '${detail.value?.ride.activityType.label ?? '骑行'}详情',
        ),
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            Center(child: Text('读取记录失败：$error')),
        data: (WorkoutDetail data) => _DetailBody(detail: data, unit: unit),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.detail, required this.unit});

  final WorkoutDetail detail;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Workout ride = detail.ride;
    final List<TrackPoint> points = detail.points;
    final int maxHeartRate =
        ref.watch(appSettingsProvider).value?.maxHeartRate ??
            kDefaultMaxHeartRate;

    final List<CurveSample> speed =
        buildCurve(points, metric: CurveMetric.speed);
    final List<CurveSample> hr =
        buildCurve(points, metric: CurveMetric.heartRate);
    final List<CurveSample> cadence =
        buildCurve(points, metric: CurveMetric.cadence);
    final List<CurveSample> power =
        buildCurve(points, metric: CurveMetric.power);

    final WorkoutSummary? s = ride.summary;
    final String speedUnit = speedUnitLabel(unit);
    String speedText(double mps) => '${formatSpeedValue(mps, unit)} $speedUnit';

    final String tileUrl =
        ref.watch(appSettingsProvider).value?.mapTileUrlTemplate ??
            kDefaultMapTileUrlTemplate;
    // 只有 GCJ-02 的瓦片源（高德、腾讯）才把轨迹转过去；OSM 这类 WGS-84
    // 源上再转一次会让轨迹整体偏出几百米。
    final List<RouteSegment> route = buildRouteSegments(
      points,
      toGcj02: isGcj02TileSource(tileUrl),
    );

    // 竖屏维持 260dp；横屏等矮视口按高度收窄，见 [_kMapHeightShrink]。
    final double mapHeight = math.min(
      _kMapHeight,
      MediaQuery.sizeOf(context).height * _kMapHeightShrink,
    );

    return ListView(
      children: <Widget>[
        RouteMap(
          segments: route,
          tileUrlTemplate: tileUrl,
          subdomains: kDefaultMapTileSubdomains,
          height: mapHeight,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceL, kSpaceL, 0),
          child: Row(
            children: <Widget>[
              // 类型徽标：图标 + 标签 + 日期一排。图标与历史卡片同规格（16、
              // 不占色），混合类型的记录在详情页里一眼能看出是骑行还是跑步。
              Icon(
                _activityIcon(ride.activityType),
                size: 16,
                color: kAppTextMuted,
              ),
              const SizedBox(width: kSpaceS),
              Text(
                ride.activityType.label,
                style: const TextStyle(
                  fontSize: 13,
                  color: kAppTextMuted,
                  fontFeatures: kTabularFigures,
                ),
              ),
              const SizedBox(width: kSpaceS),
              Text(
                formatDateTime(ride.startedAtMs),
                style: const TextStyle(
                  fontSize: 13,
                  color: kAppTextMuted,
                  fontFeatures: kTabularFigures,
                ),
              ),
            ],
          ),
        ),
        SummaryGrid(ride: ride, unit: unit),
        if (points.isEmpty)
          const Padding(
            padding: EdgeInsets.all(kSpaceL),
            child: Text('这次骑行没有轨迹数据', style: kMutedTextStyle),
          ),
        // 每项指标自成一组：标题 → 该项的读数 → 该项的曲线。原来所有读数挤在
        // 顶部一张规格表里、所有曲线排在下面，读「心率多少、心率怎么变的」
        // 要在两处之间来回对；并到一组之后从上往下读一遍就够。
        if (speed.length >= 2)
          _MetricSection(
            title: '速度',
            readouts: <SpecEntry>[
              if (s != null) ('总均速', speedText(s.avgSpeedMps)),
              if (s != null) ('移动均速', speedText(s.movingAvgSpeedMps)),
              if (s?.maxSpeedMps != null) ('最高速', speedText(s!.maxSpeedMps!)),
            ],
            child: CurveChart(
              samples: speed,
              unitLabel: speedUnit,
              // 用总均速而不是移动均速：曲线是按时间铺开的，静止的时间也在
              // 里面，它的时间平均就是「总距离 / 总时长」，也就是总均速。
              averageValue: s?.avgSpeedMps,
              formatValue: (double v) => formatSpeedValue(v, unit),
              baseColorArgb: context.palette.accent.toARGB32(),
            ),
          ),
        if (hr.length >= 2)
          _MetricSection(
            title: '心率',
            readouts: <SpecEntry>[
              if (s?.avgHr != null) ('平均心率', '${s!.avgHr!.round()} bpm'),
              if (s?.maxHr != null) ('最高心率', '${s!.maxHr} bpm'),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                CurveChart(
                  samples: hr,
                  unitLabel: 'bpm',
                  averageValue: s?.avgHr?.toDouble(),
                  formatValue: _wholeNumber,
                  baseColorArgb: context.palette.accent.toARGB32(),
                ),
                const SizedBox(height: kSpaceM),
                HrZoneBar(breakdown: hrZoneBreakdown(points, maxHeartRate)),
              ],
            ),
          ),
        if (cadence.length >= 2)
          _MetricSection(
            title: '踏频',
            readouts: <SpecEntry>[
              if (s?.avgCadence != null)
                ('平均踏频', '${s!.avgCadence!.round()} rpm'),
            ],
            child: CurveChart(
              samples: cadence,
              unitLabel: 'rpm',
              averageValue: s?.avgCadence,
              formatValue: _wholeNumber,
              baseColorArgb: context.palette.accent.toARGB32(),
            ),
          ),
        if (power.length >= 2)
          _MetricSection(
            // 没接功率计的那次骑行，这里的功率是按速度、坡度与体重估出来的
            // （见 `analysis/power.dart`）。存进库里的数值与实测功率长得一模一样，
            // 只有设备名能区分，所以标题里写明。
            title: ride.powerDeviceName == null ? '功率（估算）' : '功率',
            readouts: <SpecEntry>[
              if (s?.avgPowerW != null)
                ('平均功率', '${s!.avgPowerW!.round()} W'),
              if (s?.maxPowerW != null) ('最高功率', '${s!.maxPowerW} W'),
            ],
            child: CurveChart(
              samples: power,
              unitLabel: 'W',
              averageValue: s?.avgPowerW,
              formatValue: _wholeNumber,
              baseColorArgb: context.palette.accent.toARGB32(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceXl, kSpaceL, 0),
          child: FilledButton.icon(
            onPressed: () => _exportGpx(context, ride, points),
            icon: const Icon(Icons.ios_share),
            label: const Text('导出 GPX'),
          ),
        ),
        const SizedBox(height: kSpaceXxl),
      ],
    );
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
///
/// 与上方读数同源——汇总里写着「平均心率 142」，曲线上的标注就不能是 141.7，
/// 两个地方对不上时用户会以为是算错了。
String _wholeNumber(double value) => value.round().toString();

/// 各运动类型的图标。图标只做类型区分，与历史卡片同源（见 ride_card.dart），
/// 四个值都要能映射到，缺一个详情页就崩。
IconData _activityIcon(ActivityType t) => switch (t) {
      ActivityType.cycling => Icons.directions_bike,
      ActivityType.running => Icons.directions_run,
      ActivityType.walking => Icons.directions_walk,
      ActivityType.hiking => Icons.terrain,
    };

/// 一个指标区块：标题 → 该项读数 → 该项曲线。
///
/// 上方一条从边到边的细线把它和前一组分开——曲线区块之间原本只靠留白分隔，
/// 一屏里三段曲线连在一起，容易误读成同一块内容。
///
/// [readouts] 为空时（没有汇总指标，或该项本身没有读数）只画曲线，不留下
/// 一段空白。
class _MetricSection extends StatelessWidget {
  const _MetricSection({
    required this.title,
    required this.readouts,
    required this.child,
  });

  final String title;
  final List<SpecEntry> readouts;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kSpaceL,
              kSpaceL,
              kSpaceL,
              kSpaceS,
            ),
            child: Text(title, style: kSectionTextStyle),
          ),
          if (readouts.isNotEmpty) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kSpaceL),
              child: SpecList(entries: readouts),
            ),
            const SizedBox(height: kSpaceM),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSpaceL),
            child: child,
          ),
        ],
      );
}
