import 'package:cycling_app/domain/analysis/trend.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试用的固定「现在」：2026-09-24（周四）12:00 本地时间。
///
/// 因此本周一是 2026-09-21，本周桶依次是 09-21 … 09-27；
/// 本月是 2026-09，共 30 天；本年共 12 个月。
int get nowMs => DateTime(2026, 9, 24, 12).millisecondsSinceEpoch;

int ms(int y, int m, int d, [int h = 12]) =>
    DateTime(y, m, d, h).millisecondsSinceEpoch;

Ride ride({
  int id = 1,
  required int startedAtMs,
  RideStatus status = RideStatus.finished,
  RideSummary? summary = const RideSummary(
    distanceM: 10000,
    durationS: 1800,
    movingS: 1700,
    avgSpeedMps: 5.56,
    movingAvgSpeedMps: 5.88,
    maxSpeedMps: 11.1,
    elevationGainM: 100,
    pointCount: 1800,
  ),
}) =>
    Ride(id: id, startedAtMs: startedAtMs, status: status, summary: summary);

void main() {
  group('buildTrend 范围与桶结构', () {
    test('week 返回 7 个日桶，首桶是本周一', () {
      final TrendSummary t = buildTrend(<Ride>[], range: TrendRange.week, nowMs: nowMs);
      expect(t.buckets.length, 7);
      expect(t.buckets.first.label, '09-21');
      expect(t.buckets.last.label, '09-27');
      expect(t.rangeStartMs, ms(2026, 9, 21, 0));
      expect(t.rangeEndMs, ms(2026, 9, 28, 0));
    });

    test('month 返回当月天数的日桶', () {
      final TrendSummary t = buildTrend(<Ride>[], range: TrendRange.month, nowMs: nowMs);
      expect(t.buckets.length, 30); // 2026-09 有 30 天
      expect(t.buckets.first.label, '09-01');
      expect(t.buckets.last.label, '09-30');
    });

    test('year 返回 12 个月桶，标签为 YYYY-MM', () {
      final TrendSummary t = buildTrend(<Ride>[], range: TrendRange.year, nowMs: nowMs);
      expect(t.buckets.length, 12);
      expect(t.buckets.first.label, '2026-01');
      expect(t.buckets.last.label, '2026-12');
    });

    test('空输入时累计值全为 0', () {
      final TrendSummary t = buildTrend(<Ride>[], range: TrendRange.week, nowMs: nowMs);
      expect(t.distanceM, 0);
      expect(t.durationS, 0);
      expect(t.elevationGainM, 0);
      expect(t.rideCount, 0);
    });
  });

  group('buildTrend 落桶', () {
    test('骑行落在 startedAtMs 所属的那一天', () {
      final TrendSummary t = buildTrend(
        <Ride>[ride(id: 1, startedAtMs: ms(2026, 9, 23, 8))],
        range: TrendRange.week,
        nowMs: nowMs,
      );
      expect(t.buckets[2].label, '09-23');
      expect(t.buckets[2].rideCount, 1);
      expect(t.buckets[2].distanceM, 10000);
      expect(t.buckets[1].rideCount, 0);
    });

    test('同一天多条骑行累加', () {
      final TrendSummary t = buildTrend(
        <Ride>[
          ride(id: 1, startedAtMs: ms(2026, 9, 22, 7)),
          ride(id: 2, startedAtMs: ms(2026, 9, 22, 19)),
        ],
        range: TrendRange.week,
        nowMs: nowMs,
      );
      expect(t.buckets[1].rideCount, 2);
      expect(t.buckets[1].distanceM, 20000);
      expect(t.buckets[1].durationS, 3600);
    });

    test('范围外的骑行不计入', () {
      final TrendSummary t = buildTrend(
        <Ride>[ride(id: 1, startedAtMs: ms(2026, 9, 20, 8))], // 上周日
        range: TrendRange.week,
        nowMs: nowMs,
      );
      expect(t.rideCount, 0);
      expect(t.buckets.every((TrendBucket b) => b.rideCount == 0), isTrue);
    });

    test('桶的右端点属于下一个桶（左闭右开）', () {
      final TrendSummary t = buildTrend(
        <Ride>[ride(id: 1, startedAtMs: ms(2026, 9, 22, 0))],
        range: TrendRange.week,
        nowMs: nowMs,
      );
      expect(t.buckets[1].rideCount, 1);
      expect(t.buckets[0].rideCount, 0);
    });

    test('未结束的骑行不计入', () {
      final TrendSummary t = buildTrend(
        <Ride>[
          ride(id: 1, startedAtMs: ms(2026, 9, 22, 8), status: RideStatus.recording, summary: null),
          ride(id: 2, startedAtMs: ms(2026, 9, 22, 9), status: RideStatus.paused, summary: null),
        ],
        range: TrendRange.week,
        nowMs: nowMs,
      );
      expect(t.rideCount, 0);
    });

    test('summary 为 null 的已结束骑行不计入', () {
      final TrendSummary t = buildTrend(
        <Ride>[ride(id: 1, startedAtMs: ms(2026, 9, 22, 8), summary: null)],
        range: TrendRange.week,
        nowMs: nowMs,
      );
      expect(t.rideCount, 0);
    });

    test('带 summary 但未结束的骑行不计入', () {
      // 记录中/暂停中的骑行理论上不该有汇总，但模型允许。这里专门覆盖
      // `status != finished` 这一条过滤：否则它会被 summary 判断掩盖而失去区分力。
      final TrendSummary t = buildTrend(
        <Ride>[
          ride(id: 1, startedAtMs: ms(2026, 9, 22, 8), status: RideStatus.recording),
          ride(id: 2, startedAtMs: ms(2026, 9, 22, 9), status: RideStatus.paused),
        ],
        range: TrendRange.week,
        nowMs: nowMs,
      );
      expect(t.rideCount, 0);
      expect(t.buckets[1].rideCount, 0);
      expect(t.distanceM, 0);
    });

    test('year 范围下按月份落桶', () {
      final TrendSummary t = buildTrend(
        <Ride>[
          ride(id: 1, startedAtMs: ms(2026, 3, 15)),
          ride(id: 2, startedAtMs: ms(2026, 3, 28)),
          ride(id: 3, startedAtMs: ms(2026, 9, 24)),
        ],
        range: TrendRange.year,
        nowMs: nowMs,
      );
      expect(t.buckets[2].label, '2026-03');
      expect(t.buckets[2].rideCount, 2);
      expect(t.buckets[8].label, '2026-09');
      expect(t.buckets[8].rideCount, 1);
    });

    test('累计值等于各桶之和', () {
      final TrendSummary t = buildTrend(
        <Ride>[
          ride(id: 1, startedAtMs: ms(2026, 9, 22, 7)),
          ride(id: 2, startedAtMs: ms(2026, 9, 24, 7)),
        ],
        range: TrendRange.week,
        nowMs: nowMs,
      );
      final double bucketDistance = t.buckets.fold(
        0,
        (double sum, TrendBucket b) => sum + b.distanceM,
      );
      final int bucketDuration = t.buckets.fold(
        0,
        (int sum, TrendBucket b) => sum + b.durationS,
      );
      expect(t.distanceM, bucketDistance);
      expect(t.durationS, bucketDuration);
      expect(t.distanceM, 20000);
      expect(t.rideCount, 2);
    });
  });

  group('personalBests', () {
    test('四项最佳各取最大的一条，并带上骑行 id 与开始时间', () {
      final PersonalBests b = personalBests(<Ride>[
        ride(
          id: 1,
          startedAtMs: ms(2026, 9, 1),
          summary: const RideSummary(
            distanceM: 30000,
            durationS: 5400,
            movingS: 5200,
            avgSpeedMps: 5.56,
            movingAvgSpeedMps: 5.77,
            elevationGainM: 200,
            pointCount: 5000,
          ),
        ),
        ride(
          id: 2,
          startedAtMs: ms(2026, 9, 2),
          summary: const RideSummary(
            distanceM: 15000,
            durationS: 9000,
            movingS: 8000,
            avgSpeedMps: 1.67,
            movingAvgSpeedMps: 8.33,
            elevationGainM: 600,
            pointCount: 9000,
          ),
        ),
      ]);

      expect(b.longestDistanceM!.rideId, 1);
      expect(b.longestDistanceM!.value, 30000);
      expect(b.longestDurationS!.rideId, 2);
      expect(b.longestDurationS!.value, 9000);
      expect(b.fastestMovingAvgMps!.rideId, 2);
      expect(b.fastestMovingAvgMps!.value, 8.33);
      expect(b.mostElevationGainM!.rideId, 2);
      expect(b.mostElevationGainM!.value, 600);
      expect(b.longestDistanceM!.startedAtMs, ms(2026, 9, 1));
    });

    test('并列时保留更早的那次', () {
      final PersonalBests b = personalBests(<Ride>[
        ride(id: 1, startedAtMs: ms(2026, 9, 1)),
        ride(id: 2, startedAtMs: ms(2026, 9, 2)),
      ]);
      expect(b.longestDistanceM!.rideId, 1);
    });

    test('没有已结束骑行时四项全为 null', () {
      final PersonalBests b = personalBests(<Ride>[
        ride(id: 1, startedAtMs: ms(2026, 9, 1), status: RideStatus.recording, summary: null),
      ]);
      expect(b.longestDistanceM, isNull);
      expect(b.longestDurationS, isNull);
      expect(b.fastestMovingAvgMps, isNull);
      expect(b.mostElevationGainM, isNull);
    });

    test('跳过没有 id 或没有 summary 的骑行', () {
      final PersonalBests b = personalBests(<Ride>[
        const Ride(startedAtMs: 1000, status: RideStatus.finished, summary: null),
        Ride(id: 9, startedAtMs: 2000, status: RideStatus.finished, summary: null),
      ]);
      expect(b.longestDistanceM, isNull);
    });

    test('带 summary 但未结束的骑行不参与最佳', () {
      // 未结束但带汇总的骑行距离更大；若丢掉 `status != finished` 过滤，
      // 它会顶掉已结束的那次，从而暴露该过滤失效。
      final PersonalBests b = personalBests(<Ride>[
        ride(
          id: 1,
          startedAtMs: ms(2026, 9, 1),
          status: RideStatus.recording,
          summary: const RideSummary(
            distanceM: 50000,
            durationS: 100,
            movingS: 100,
            avgSpeedMps: 1,
            movingAvgSpeedMps: 1,
            elevationGainM: 1,
            pointCount: 100,
          ),
        ),
        ride(id: 2, startedAtMs: ms(2026, 9, 2)),
      ]);
      expect(b.longestDistanceM!.rideId, 2);
      expect(b.longestDistanceM!.value, 10000);
    });

    test('空输入返回全 null', () {
      final PersonalBests b = personalBests(<Ride>[]);
      expect(b.longestDistanceM, isNull);
      expect(b.mostElevationGainM, isNull);
    });
  });
}
