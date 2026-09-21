import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/ride_summary.dart';

/// 汇总指标网格。见设计文档 10.3 的第 2 块。
class SummaryGrid extends StatelessWidget {
  const SummaryGrid({required this.ride, required this.unit, super.key});

  final Ride ride;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) {
    final RideSummary? s = ride.summary;
    if (s == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('这条记录还没有汇总指标'),
      );
    }

    final List<_Metric> metrics = <_Metric>[
      _Metric('距离', formatDistance(s.distanceM, unit)),
      _Metric('时长', formatDuration(s.durationS)),
      _Metric('移动时长', formatDuration(s.movingS)),
      _Metric('总均速', '${formatSpeedValue(s.avgSpeedMps, unit)} ${speedUnitLabel(unit)}'),
      _Metric('移动均速', '${formatSpeedValue(s.movingAvgSpeedMps, unit)} ${speedUnitLabel(unit)}'),
      if (s.maxSpeedMps != null)
        _Metric('最高速', '${formatSpeedValue(s.maxSpeedMps!, unit)} ${speedUnitLabel(unit)}'),
      _Metric('爬升', '${s.elevationGainM.round()} m'),
      if (s.avgHr != null) _Metric('平均心率', '${s.avgHr!.round()} bpm'),
      if (s.maxHr != null) _Metric('最高心率', '${s.maxHr} bpm'),
      if (s.avgCadence != null) _Metric('平均踏频', '${s.avgCadence!.round()} rpm'),
      if (s.calories != null) _Metric('卡路里', '${s.calories!.round()} kcal（参考）'),
      _Metric('轨迹点', '${s.pointCount}'),
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: <Widget>[
          for (final _Metric m in metrics)
            SizedBox(width: 104, child: _MetricTile(metric: m)),
        ],
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value);

  final String label;
  final String value;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(metric.label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            metric.value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: kAppAccent,
            ),
          ),
        ],
      );
}
