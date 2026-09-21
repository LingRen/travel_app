import '../models/ride.dart';
import '../models/ride_status.dart';
import '../models/ride_summary.dart';

/// 统计页的时间范围。见设计文档 10.4。
enum TrendRange { week, month, year }

/// 趋势折线上的一个桶。
class TrendBucket {
  const TrendBucket({
    required this.startMs,
    required this.endMs,
    required this.label,
    required this.distanceM,
    required this.durationS,
    required this.elevationGainM,
    required this.rideCount,
  });

  /// 桶的起点（含）。本地时间的当日/当月 00:00。
  final int startMs;

  /// 桶的终点（不含）。
  final int endMs;

  /// 日桶为 `MM-DD`，月桶为 `YYYY-MM`。
  final String label;

  final double distanceM;
  final int durationS;
  final double elevationGainM;
  final int rideCount;
}

/// 一个范围内的累计值与逐桶趋势。
class TrendSummary {
  const TrendSummary({
    required this.rangeStartMs,
    required this.rangeEndMs,
    required this.distanceM,
    required this.durationS,
    required this.elevationGainM,
    required this.rideCount,
    required this.buckets,
  });

  final int rangeStartMs;
  final int rangeEndMs;
  final double distanceM;
  final int durationS;
  final double elevationGainM;
  final int rideCount;
  final List<TrendBucket> buckets;
}

/// 个人最佳纪录。
class PersonalBest {
  const PersonalBest({
    required this.rideId,
    required this.startedAtMs,
    required this.value,
  });

  final int rideId;
  final int startedAtMs;
  final double value;
}

/// 四项个人最佳。没有对应数据时为 null。
class PersonalBests {
  const PersonalBests({
    this.longestDistanceM,
    this.longestDurationS,
    this.fastestMovingAvgMps,
    this.mostElevationGainM,
  });

  final PersonalBest? longestDistanceM;
  final PersonalBest? longestDurationS;
  final PersonalBest? fastestMovingAvgMps;
  final PersonalBest? mostElevationGainM;
}

/// 按日历范围聚合骑行。
///
/// 范围是**日历对齐**的：`week` 从本周一 00:00 起 7 天，`month` 从本月 1 日
/// 00:00 起当月天数天，`year` 从本年 1 月 1 日 00:00 起 12 个月。
/// 骑行按 `startedAtMs` 落桶，左闭右开。
///
/// 只统计 `status == finished` 且带汇总的骑行：未结束的骑行没有汇总指标，
/// 计进去会让累计值凭空变小。
TrendSummary buildTrend(
  List<Ride> rides, {
  required TrendRange range,
  required int nowMs,
}) {
  final DateTime now = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final List<_Span> spans = _spansFor(range, now);

  final List<double> distances = List<double>.filled(spans.length, 0);
  final List<int> durations = List<int>.filled(spans.length, 0);
  final List<double> gains = List<double>.filled(spans.length, 0);
  final List<int> counts = List<int>.filled(spans.length, 0);

  for (final Ride ride in rides) {
    if (ride.status != RideStatus.finished) continue;
    final RideSummary? summary = ride.summary;
    if (summary == null) continue;

    final int index = spans.indexWhere(
      (_Span s) => ride.startedAtMs >= s.startMs && ride.startedAtMs < s.endMs,
    );
    if (index < 0) continue;

    distances[index] += summary.distanceM;
    durations[index] += summary.durationS;
    gains[index] += summary.elevationGainM;
    counts[index] += 1;
  }

  final List<TrendBucket> buckets = <TrendBucket>[
    for (int i = 0; i < spans.length; i++)
      TrendBucket(
        startMs: spans[i].startMs,
        endMs: spans[i].endMs,
        label: spans[i].label,
        distanceM: distances[i],
        durationS: durations[i],
        elevationGainM: gains[i],
        rideCount: counts[i],
      ),
  ];

  double totalDistance = 0;
  int totalDuration = 0;
  double totalGain = 0;
  int totalCount = 0;
  for (int i = 0; i < spans.length; i++) {
    totalDistance += distances[i];
    totalDuration += durations[i];
    totalGain += gains[i];
    totalCount += counts[i];
  }

  return TrendSummary(
    rangeStartMs: spans.first.startMs,
    rangeEndMs: spans.last.endMs,
    distanceM: totalDistance,
    durationS: totalDuration,
    elevationGainM: totalGain,
    rideCount: totalCount,
    buckets: buckets,
  );
}

/// 四项个人最佳。并列时保留**更早**的那次（先到先得），便于稳定测试。
PersonalBests personalBests(List<Ride> rides) {
  PersonalBest? distance;
  PersonalBest? duration;
  PersonalBest? speed;
  PersonalBest? gain;

  for (final Ride ride in rides) {
    final int? id = ride.id;
    final RideSummary? summary = ride.summary;
    if (ride.status != RideStatus.finished) continue;
    if (id == null || summary == null) continue;

    PersonalBest? better(PersonalBest? current, double value) =>
        current == null || value > current.value
            ? PersonalBest(
                rideId: id,
                startedAtMs: ride.startedAtMs,
                value: value,
              )
            : current;

    distance = better(distance, summary.distanceM);
    duration = better(duration, summary.durationS.toDouble());
    speed = better(speed, summary.movingAvgSpeedMps);
    gain = better(gain, summary.elevationGainM);
  }

  return PersonalBests(
    longestDistanceM: distance,
    longestDurationS: duration,
    fastestMovingAvgMps: speed,
    mostElevationGainM: gain,
  );
}

/// 一个桶的时间跨度。
class _Span {
  const _Span({
    required this.startMs,
    required this.endMs,
    required this.label,
  });

  final int startMs;
  final int endMs;
  final String label;
}

List<_Span> _spansFor(TrendRange range, DateTime now) {
  switch (range) {
    case TrendRange.week:
      final DateTime monday =
          DateTime(now.year, now.month, now.day - (now.weekday - 1));
      return <_Span>[
        for (int i = 0; i < 7; i++)
          _daySpan(DateTime(monday.year, monday.month, monday.day + i)),
      ];
    case TrendRange.month:
      // DateTime(y, m + 1, 0).day 就是当月天数，跨年由 DateTime 自己归一化。
      final int daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      return <_Span>[
        for (int i = 0; i < daysInMonth; i++)
          _daySpan(DateTime(now.year, now.month, 1 + i)),
      ];
    case TrendRange.year:
      return <_Span>[
        for (int i = 0; i < 12; i++) _monthSpan(DateTime(now.year, 1 + i, 1)),
      ];
  }
}

_Span _daySpan(DateTime start) {
  final DateTime end = DateTime(start.year, start.month, start.day + 1);
  return _Span(
    startMs: start.millisecondsSinceEpoch,
    endMs: end.millisecondsSinceEpoch,
    label: '${_two(start.month)}-${_two(start.day)}',
  );
}

_Span _monthSpan(DateTime start) {
  final DateTime end = DateTime(start.year, start.month + 1, 1);
  return _Span(
    startMs: start.millisecondsSinceEpoch,
    endMs: end.millisecondsSinceEpoch,
    label: '${start.year}-${_two(start.month)}',
  );
}

String _two(int value) => value.toString().padLeft(2, '0');
