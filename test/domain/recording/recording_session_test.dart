import 'package:cycling_app/domain/models/location_fix.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/recording/recording_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 纬度 0.0001 度约 11.13 米。
  LocationFix fixAt(
    int tMs, {
    double lat = 31.0,
    double? lon = 121.0,
    double? altitudeM,
    double? speedMps,
  }) =>
      LocationFix(
        tMs: tMs,
        lat: lat,
        lon: lon,
        altitudeM: altitudeM,
        speedMps: speedMps,
      );

  group('RecordingSession 时长', () {
    test('tick 累计有效时长', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.tick(1000);
      expect(s.snapshot.elapsedMs, 1000);
      s.tick(3000);
      expect(s.snapshot.elapsedMs, 3000);
    });

    test('暂停期间不累计时长', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.tick(1000);
      s.pause(1000);
      s.tick(5000);
      expect(s.snapshot.elapsedMs, 1000);
      expect(s.snapshot.phase, RecordingPhase.paused);
    });

    test('恢复后继续累计', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.tick(1000);
      s.pause(1000);
      s.tick(5000);
      s.resume(5000);
      s.tick(6000);
      expect(s.snapshot.elapsedMs, 2000);
      expect(s.snapshot.phase, RecordingPhase.recording);
    });

    test('结束之后 tick 不再累计', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.tick(1000);
      s.finish(1000);
      s.tick(9000);
      expect(s.snapshot.elapsedMs, 1000);
      expect(s.snapshot.phase, RecordingPhase.finished);
    });
  });

  group('RecordingSession 距离与速度', () {
    test('累计位移距离', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      s.ingestFix(fixAt(1000, lat: 31.0001));
      expect(s.snapshot.distanceM, closeTo(11.13, 0.2));
    });

    test('GPS 跳变不计入距离', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      s.ingestFix(fixAt(1000, lat: 31.01));
      expect(s.snapshot.distanceM, 0);
    });

    test('优先使用 GPS 上报速度', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0, speedMps: 6.0));
      expect(s.snapshot.currentSpeedMps, 6.0);
    });

    test('GPS 上报速度不合理时回退到位移推算', () {
      final RecordingSession tooFast = RecordingSession(rideId: 1, startedAtMs: 0);
      tooFast.ingestFix(fixAt(0));
      tooFast.ingestFix(fixAt(1000, lat: 31.0001, speedMps: 100.0));
      expect(tooFast.snapshot.currentSpeedMps, closeTo(11.13, 0.2));

      final RecordingSession negative = RecordingSession(rideId: 2, startedAtMs: 0);
      negative.ingestFix(fixAt(0));
      negative.ingestFix(fixAt(1000, lat: 31.0001, speedMps: -1.0));
      expect(negative.snapshot.currentSpeedMps, closeTo(11.13, 0.2));
    });

    test('GPS 长时间无更新后速度归零', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0, speedMps: 6.0));
      s.tick(11000);
      expect(s.snapshot.currentSpeedMps, 0);
    });
  });

  group('RecordingSession 落盘', () {
    test('首个定位点写入', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      expect(s.takePendingPoints().length, 1);
    });

    test('静止时按 2 秒节拍写入', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      s.ingestFix(fixAt(1000));
      s.ingestFix(fixAt(2000));
      expect(s.takePendingPoints().length, 2);
    });

    test('攒够 10 个点后 shouldFlush 为 true', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      for (int i = 0; i < 10; i++) {
        s.ingestFix(fixAt(i * 2000));
      }
      expect(s.shouldFlush, isTrue);
      expect(s.takePendingPoints().length, 10);
      expect(s.shouldFlush, isFalse);
    });

    test('暂停期间不写入轨迹点', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      s.takePendingPoints();
      s.pause(0);
      s.ingestFix(fixAt(2000));
      expect(s.takePendingPoints(), isEmpty);
    });

    test('心率、踏频与功率附加到写入的点上', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestHeartRate(120);
      s.ingestCadence(85.4);
      s.ingestPower(210);
      s.ingestFix(fixAt(0));
      final TrackPoint p = s.takePendingPoints().single;
      expect(p.hr, 120);
      expect(p.cadence, 85);
      expect(p.powerW, 210);
    });

    test('没接功率计时写入的点带估算功率，不是空值', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestHeartRate(120);
      s.ingestFix(fixAt(0, speedMps: 6.0));
      // 6 m/s、平路、70 公斤 ≈ 63 W（算法与常量见 analysis/power.dart）。
      expect(s.takePendingPoints().single.powerW, 63);
    });

    test('接了功率计时写实测值，不被估算值顶掉', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestPower(210);
      s.ingestFix(fixAt(0, speedMps: 6.0));
      expect(s.takePendingPoints().single.powerW, 210);
    });

    test('上坡时估算功率明显高于同样速度的平路', () {
      // 0.0001 度纬度约 11.13 米，6 个点爬 5 米、水平位移约 56 米（越过拟合所需的
      // 最小位移 50 米），坡度约 9%。
      int flatPower(RecordingSession s) {
        s.ingestFix(fixAt(0, speedMps: 6.0));
        return s.takePendingPoints().single.powerW!;
      }

      final RecordingSession flat = RecordingSession(rideId: 1, startedAtMs: 0);
      final int flatW = flatPower(flat);

      final RecordingSession uphill = RecordingSession(rideId: 2, startedAtMs: 0);
      int climbW = 0;
      for (int i = 0; i < 6; i++) {
        uphill.ingestFix(fixAt(
          i * 1000,
          lat: 31.0 + i * 0.0001,
          altitudeM: 100.0 + i,
          speedMps: 6.0,
        ));
        final List<TrackPoint> batch = uphill.takePendingPoints();
        if (batch.isNotEmpty) climbW = batch.last.powerW!;
      }

      expect(climbW, greaterThan(flatW * 2));
    });

    test('暂停后估算功率归零，不会停在暂停前的读数上', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0, speedMps: 6.0));
      expect(s.snapshot.power, 63);

      s.pause(1000);
      expect(s.snapshot.power, 0);
    });

    test('GPS 丢失超过 10 秒时写入纯传感器点', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestHeartRate(120);
      s.ingestFix(fixAt(0));
      s.takePendingPoints();
      s.tick(12000);
      final List<TrackPoint> batch = s.takePendingPoints();
      expect(batch.length, 1);
      expect(batch.single.hasPosition, isFalse);
      expect(batch.single.hr, 120);
      // 没有定位就没有速度，估算功率写进去只会是 0，白白拉低平均功率。
      expect(batch.single.powerW, isNull);
    });

    test('只连了功率计时也要写纯传感器点，功率曲线不能断', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestPower(210);
      s.ingestFix(fixAt(0));
      s.takePendingPoints();
      s.tick(12000);
      final List<TrackPoint> batch = s.takePendingPoints();
      expect(batch.length, 1);
      expect(batch.single.hasPosition, isFalse);
      expect(batch.single.hr, isNull);
      expect(batch.single.powerW, 210);
    });

    test('结束时返回缓冲中剩余的点', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      s.takePendingPoints();
      s.ingestFix(fixAt(1000));
      expect(s.takePendingPoints(), isEmpty);
      s.ingestFix(fixAt(2000));
      expect(s.finish(2000).length, 1);
      expect(s.takePendingPoints(), isEmpty);
    });

    test('可以用已落盘的点续写会话', () {
      const TrackPoint last = TrackPoint(rideId: 1, tMs: 5000, lat: 31.0, lon: 121.0);
      final RecordingSession s = RecordingSession(
        rideId: 1,
        startedAtMs: 0,
        initialElapsedMs: 5000,
        initialDistanceM: 120.0,
        lastWritten: last,
      );
      expect(s.snapshot.elapsedMs, 5000);
      expect(s.snapshot.distanceM, 120.0);

      // 距上一点不足 5 米且不足 2 秒：不写入
      s.ingestFix(const LocationFix(tMs: 6000, lat: 31.00001, lon: 121.0));
      expect(s.takePendingPoints(), isEmpty);

      // 距上一点超过 2 秒：写入
      s.ingestFix(const LocationFix(tMs: 8000, lat: 31.00001, lon: 121.0));
      expect(s.takePendingPoints().length, 1);
    });

    test('续写会话的时长从恢复时刻继续累计', () {
      final RecordingSession s = RecordingSession(
        rideId: 1,
        // 一小时前开始、最后落盘点在一小时前：崩溃后 5 分钟才重启 App。
        startedAtMs: -3599000,
        initialElapsedMs: 2000,
        lastWritten: const TrackPoint(rideId: 1, tMs: 0, lat: 31.0, lon: 121.0),
        resumedAtMs: 300000,
      );

      expect(s.snapshot.elapsedMs, 2000);
      s.tick(301000);
      expect(
        s.snapshot.elapsedMs,
        3000,
        reason: '只能加恢复之后的 1 秒：既不能算上开始到现在整段，'
            '也不能算上崩溃到重启之间的空档',
      );
    });
  });

  group('RecordingSession 状态机边界', () {
    test('结束后 pause 不改变状态', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.tick(1000);
      s.finish(1000);
      s.pause(5000);
      expect(s.snapshot.phase, RecordingPhase.finished);
      expect(s.snapshot.elapsedMs, 1000);
    });

    test('未暂停时 resume 是空操作', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.tick(1000);
      s.resume(5000);
      s.tick(6000);
      expect(s.snapshot.phase, RecordingPhase.recording);
      expect(s.snapshot.elapsedMs, 6000);
    });

    test('从暂停直接结束不累计暂停期间时长', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.tick(1000);
      s.pause(1000);
      final List<TrackPoint> rest = s.finish(9000);
      expect(rest, isEmpty);
      expect(s.snapshot.elapsedMs, 1000);
      expect(s.snapshot.phase, RecordingPhase.finished);
    });

    test('结束后 ingestFix 被忽略', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.finish(0);
      s.ingestFix(fixAt(1000, lat: 31.0001));
      expect(s.takePendingPoints(), isEmpty);
      expect(s.snapshot.pointCount, 0);
      expect(s.snapshot.distanceM, 0);
    });

    test('没有坐标的定位被忽略且不影响后续距离', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0, lat: 31.0, lon: 121.0));
      s.takePendingPoints();
      s.ingestFix(const LocationFix(tMs: 1000));
      s.ingestFix(fixAt(2000, lat: 31.0001));
      expect(s.snapshot.distanceM, closeTo(11.13, 0.2));
    });

    test('距离为多段累计', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      s.ingestFix(fixAt(1000, lat: 31.0001));
      s.ingestFix(fixAt(2000, lat: 31.0002));
      expect(s.snapshot.distanceM, closeTo(22.26, 0.3));
    });

    test('pointCount 统计所有写入的点且 drain 不清零', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      s.ingestFix(fixAt(2000));
      expect(s.snapshot.pointCount, 2);
      s.takePendingPoints();
      expect(s.snapshot.pointCount, 2);
    });

    test('恢复后与暂停前状态断开，暂停期间的位移不计入距离', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      s.takePendingPoints();
      s.pause(1000);
      s.resume(1000);
      s.ingestFix(fixAt(2000, lat: 31.0001));
      expect(s.snapshot.distanceM, 0);
    });

    test('finish 幂等，重复调用不再返回点', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0));
      expect(s.finish(0).length, 1);
      expect(s.finish(1000), isEmpty);
      expect(s.snapshot.elapsedMs, 0);
    });
  });
}
