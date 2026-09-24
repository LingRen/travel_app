import 'package:cycling_app/domain/recording/cue_detector.dart';
import 'package:cycling_app/domain/recording/ride_cue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 推进一拍。提示判据只看（距离, 时长, 速度）三元组，与时钟无关，因此测试
  // 完全确定：喂进读数，断言吐出来的提示序列。
  List<RideCue> step(
    CueDetector d, {
    double distanceM = 0,
    int elapsedMs = 0,
    double speedMps = 0,
  }) =>
      d.update(distanceM: distanceM, elapsedMs: elapsedMs, speedMps: speedMps);

  group('整公里提示', () {
    test('跨过 1 公里时报出该公里的耗时与均速', () {
      final CueDetector d = CueDetector();

      // 999 米还在这一公里里，不该报：提示是「到点了」的事件，不是逐点计算。
      expect(step(d, distanceM: 999, elapsedMs: 200000), isEmpty);

      // 1000 米跨过边界。这一公里用掉 200 秒，均速 1000 / 200 = 5 m/s。
      final List<RideCue> cues = step(d, distanceM: 1000, elapsedMs: 200000);
      expect(cues, hasLength(1));
      final LapCue lap = cues.single as LapCue;
      expect(lap.lapKm, 1);
      expect(lap.durationS, 200);
      expect(lap.avgSpeedMps, closeTo(5.0, 1e-9));
    });

    test('第 2 公里的耗时只算第 2 公里，不含前一公里', () {
      final CueDetector d = CueDetector();
      step(d, distanceM: 1000, elapsedMs: 200000);
      final LapCue lap =
          step(d, distanceM: 2000, elapsedMs: 260000).whereType<LapCue>().single;

      expect(lap.lapKm, 2);
      expect(lap.durationS, 60, reason: '是 260 − 200 秒，不是从出发算起的 260 秒');
      expect(lap.avgSpeedMps, closeTo(1000 / 60, 1e-9));
    });

    test('均速按公里边界算，不受这一拍落在哪里影响', () {
      // 这一拍已经冲到 1500 米，报的仍是「第 1 公里的 1000 米 / 200 秒」——
      // 若拿当前距离当分子，均速会被这一拍的位置带偏。
      final CueDetector d = CueDetector();
      final LapCue lap =
          step(d, distanceM: 1500, elapsedMs: 200000).whereType<LapCue>().single;
      expect(lap.avgSpeedMps, closeTo(5.0, 1e-9));
    });

    test('同一拍跨过多公里时逐条补齐，条数不能少', () {
      // GPS 断点后一口气补上 3 公里：断点期间的耗时在数据里分不出来，所以各条
      // 的耗时只能按同一段推算，但「报过几公里」这件事必须完整。
      final CueDetector d = CueDetector();
      final List<RideCue> cues = step(d, distanceM: 3000, elapsedMs: 300000);

      expect(
        cues.whereType<LapCue>().map((LapCue c) => c.lapKm),
        <int>[1, 2, 3],
      );
    });

    test('停在同一公里里反复喂不重复播报', () {
      final CueDetector d = CueDetector();
      step(d, distanceM: 1000, elapsedMs: 200000);
      expect(step(d, distanceM: 1200, elapsedMs: 210000), isEmpty);
      expect(step(d, distanceM: 1900, elapsedMs: 220000), isEmpty);
    });
  });

  group('整十公里提示', () {
    test('跨过 10 公里时报一次', () {
      final CueDetector d = CueDetector();
      final DistanceCue cue =
          step(d, distanceM: 10000, elapsedMs: 3600000).whereType<DistanceCue>().single;
      expect(cue.km, 10);
    });

    test('不到 10 公里不报', () {
      final CueDetector d = CueDetector();
      expect(
        step(d, distanceM: 9999, elapsedMs: 3600000).whereType<DistanceCue>(),
        isEmpty,
      );
    });

    test('一次骑行里每一档只报一次，20 公里接着报', () {
      final CueDetector d = CueDetector();
      expect(
        step(d, distanceM: 10000, elapsedMs: 1).whereType<DistanceCue>(),
        hasLength(1),
      );
      expect(
        step(d, distanceM: 15000, elapsedMs: 2).whereType<DistanceCue>(),
        isEmpty,
        reason: '还在 10 公里这一档里',
      );
      expect(
        step(d, distanceM: 20000, elapsedMs: 3).whereType<DistanceCue>().single.km,
        20,
      );
    });
  });

  group('速度跨档提示', () {
    test('速度跨过 10km/h 的整档时报一次，报的是实际速度', () {
      final CueDetector d = CueDetector();
      // 2.5 m/s = 9 km/h，还在 0 档里。
      expect(step(d, speedMps: 2.5).whereType<SpeedCue>(), isEmpty);
      // 2.8 m/s ≈ 10.08 km/h，跨进 10 档。报的是 10.08 这个实际速度，不是档位
      // 下沿 10——屏幕上的大数字就是实际速度，两个数对不上用户会以为算错了。
      final SpeedCue cue = step(d, speedMps: 2.8).whereType<SpeedCue>().single;
      expect(cue.kmh, closeTo(10.08, 1e-9));
    });

    test('档位只升不降：掉速后回到同一档不再播', () {
      final CueDetector d = CueDetector();
      // 6.9 m/s ≈ 24.8 km/h，跨进 20 档。
      expect(
        step(d, speedMps: 6.9).whereType<SpeedCue>().single.kmh,
        closeTo(24.84, 1e-9),
      );

      // 3.4 m/s ≈ 12.2 km/h 掉回 10 档。掉速不是「提升」，不报。
      expect(
        step(d, speedMps: 3.4).whereType<SpeedCue>(),
        isEmpty,
        reason: '掉速不报，否则丘陵路段会一路插话',
      );
      // 6.1 m/s ≈ 22 km/h 回到 20 档。这一次骑行里 20 档已经报过，不重复。
      expect(step(d, speedMps: 6.1).whereType<SpeedCue>(), isEmpty);
      // 8.4 m/s ≈ 30.2 km/h，跨进 30 档，报。
      expect(
        step(d, speedMps: 8.4).whereType<SpeedCue>().single.kmh,
        closeTo(30.24, 1e-9),
      );
    });

    test('一次跨过多个档位时只报一条', () {
      // 起步就是 34 km/h：报 10、20、30 三遍太吵，只报一条，内容是当下的 34。
      final CueDetector d = CueDetector();
      final List<SpeedCue> cues =
          step(d, speedMps: 34 / 3.6).whereType<SpeedCue>().toList();
      expect(cues, hasLength(1));
      expect(cues.single.kmh, closeTo(34, 1e-9));
    });
  });

  group('崩溃恢复时播种基线', () {
    test('对照组：不播种会把已经骑过的公里数补报一遍', () {
      // 这是「不播种」的后果，也是下面那条用例存在的理由：续写一个骑了 12.5
      // 公里的会话，第一拍就会连报 12 条整公里 + 1 条十公里。
      final CueDetector d = CueDetector();
      final List<RideCue> cues = step(d, distanceM: 12500, elapsedMs: 3600000);

      expect(cues.whereType<LapCue>(), hasLength(12));
      expect(cues.whereType<DistanceCue>().single.km, 10);
    });

    test('播种后不再补报，只从恢复那一刻继续判', () {
      final CueDetector d =
          CueDetector(initialDistanceM: 12500, initialElapsedMs: 3600000);

      // 恢复后原地推进：没有任何提示。
      expect(step(d, distanceM: 12800, elapsedMs: 3610000), isEmpty);

      // 跨过第 13 公里：报 13，耗时从恢复那一刻算起（10 秒）。
      final LapCue lap =
          step(d, distanceM: 13000, elapsedMs: 3610000).whereType<LapCue>().single;
      expect(lap.lapKm, 13);
      expect(lap.durationS, 10);
    });

    test('播种后整十公里接着数：20 公里照报', () {
      final CueDetector d =
          CueDetector(initialDistanceM: 12500, initialElapsedMs: 0);

      expect(
        step(d, distanceM: 19999, elapsedMs: 1000).whereType<DistanceCue>(),
        isEmpty,
      );
      expect(
        step(d, distanceM: 20000, elapsedMs: 2000).whereType<DistanceCue>().single.km,
        20,
      );
    });
  });
}