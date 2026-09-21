import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/curve.dart';
import '../../domain/analysis/heart_rate.dart';
import '../../domain/analysis/route_segments.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';
import 'curve_chart.dart';
import 'detail_providers.dart';
import 'gpx_export.dart';
import 'hr_zone_bar.dart';
import 'route_map.dart';
import 'summary_grid.dart';

/// 单次骑行详情页。见设计文档 10.3。
///
/// 地图轨迹与导出 GPX 由 Task 10 补在本页上方与下方。
class DetailPage extends ConsumerWidget {
  const DetailPage({required this.rideId, super.key});

  final int rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RideDetail> detail = ref.watch(rideDetailProvider(rideId));
    final DistanceUnit unit =
        ref.watch(appSettingsProvider).value?.distanceUnit ??
            DistanceUnit.kilometer;

    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.ride.title ?? '骑行详情')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            Center(child: Text('读取记录失败：$error')),
        data: (RideDetail data) => _DetailBody(detail: data, unit: unit),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.detail, required this.unit});

  final RideDetail detail;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Ride ride = detail.ride;
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

    final List<RouteSegment> route = buildRouteSegments(points);
    final String tileUrl =
        ref.watch(appSettingsProvider).value?.mapTileUrlTemplate ??
            kDefaultMapTileUrlTemplate;

    return ListView(
      children: <Widget>[
        RouteMap(
          segments: route,
          tileUrlTemplate: tileUrl,
          subdomains: kDefaultMapTileSubdomains,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            formatDateTime(ride.startedAtMs),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        SummaryGrid(ride: ride, unit: unit),
        if (points.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('这次骑行没有轨迹数据'),
          ),
        if (speed.length >= 2) ...<Widget>[
          const _SectionTitle('速度'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CurveChart(
              samples: speed,
              unitLabel: speedUnitLabel(unit),
              colorBySpeed: true,
            ),
          ),
        ],
        if (hr.length >= 2) ...<Widget>[
          const _SectionTitle('心率'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CurveChart(samples: hr, unitLabel: 'bpm'),
          ),
          const SizedBox(height: 12),
          HrZoneBar(breakdown: hrZoneBreakdown(points, maxHeartRate)),
        ],
        if (cadence.length >= 2) ...<Widget>[
          const _SectionTitle('踏频'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CurveChart(samples: cadence, unitLabel: 'rpm'),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: FilledButton.icon(
            onPressed: () => _exportGpx(context, ride, points),
            icon: const Icon(Icons.ios_share),
            label: const Text('导出 GPX'),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  /// 导出失败时给用户一句能看懂的话，而不是把异常栈糊在界面上。
  Future<void> _exportGpx(
    BuildContext context,
    Ride ride,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      );
}
