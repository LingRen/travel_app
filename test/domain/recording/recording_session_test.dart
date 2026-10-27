import 'package:cycling_app/domain/analysis/elevation.dart';
import 'package:cycling_app/domain/models/activity_type.dart';
import 'package:cycling_app/domain/models/location_fix.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/recording/recording_session.dart';
import 'package:cycling_app/domain/recording/ride_cue.dart';
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

    test('原地不动时芯片报出的低速被压成 0', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      // 停在原地，位置在一两米内抖动，GPS 仍会解算出 0.3 m/s 的残差速度。
      for (int i = 0; i < 5; i++) {
        s.ingestFix(fixAt(i * 1000, lat: 31.0 + i * 0.00001, speedMps: 0.3));
        expect(s.snapshot.currentSpeedMps, 0,
            reason: '第 ${i + 1} 秒：静止时的幻影速度不能显示');
      }
    });

    test('死区带滞回，门槛附近不闪烁', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0, speedMps: 0.3));
      expect(s.snapshot.currentSpeedMps, 0);
      // 高于入场阈值（0.5）但低于出场阈值（1.0）：保持 0，避免 0↔2 km/h 跳变。
      s.ingestFix(fixAt(1000, speedMps: 0.7));
      expect(s.snapshot.currentSpeedMps, 0);
      // 真的动起来了才恢复读数。
      s.ingestFix(fixAt(2000, speedMps: 1.2));
      expect(s.snapshot.currentSpeedMps, 1.2);
      // 减速时低于出场阈值仍照常显示，跌破入场阈值才归零。
      s.ingestFix(fixAt(3000, speedMps: 0.6));
      expect(s.snapshot.currentSpeedMps, 0.6);
      s.ingestFix(fixAt(4000, speedMps: 0.4));
      expect(s.snapshot.currentSpeedMps, 0);
    });

    test('落盘点写的是死区后的速度，停车不会被算成移动时间', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0, speedMps: 0.3));
      expect(s.takePendingPoints().single.speedMps, 0);
    });

    test('停在原地时位置抖动不涨里程', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      // 停车 10 秒，位置在一两米内来回抖，芯片一直报 0.3 m/s。
      for (int i = 0; i < 10; i++) {
        s.ingestFix(fixAt(
          i * 1000,
          lat: 31.0 + (i.isEven ? 0.00001 : -0.00001),
          speedMps: 0.3,
        ));
      }
      expect(s.snapshot.distanceM, 0,
          reason: '静止时的位置漂移不是里程');
    });

    test('慢速移动的里程按锚点累计，总量不丢', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      // 步行 1.4 m/s，每秒 1.39 米；门槛 4 米，读数几米一跳但总量基本不变。
      for (int i = 0; i < 11; i++) {
        s.ingestFix(fixAt(i * 1000, lat: 31.0 + i * 0.0000125, speedMps: 1.4));
      }
      // 实际走了 13.9 米，最后一次记账停在 4 米的整数倍上。
      expect(s.snapshot.distanceM, closeTo(13.9, 4.0));
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

  group('RecordingSession 实时海拔与爬升', () {
    test('实时海拔取最近一次可信定位的高程', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      expect(s.snapshot.currentAltitudeM, isNull, reason: '还没有定位点');

      s.ingestFix(fixAt(0, altitudeM: 100));
      expect(s.snapshot.currentAltitudeM, 100);

      // 约 11 米水平位移配 3 米上升，坡度 0.27，是缓坡。
      s.ingestFix(fixAt(1000, lat: 31.0001, altitudeM: 103));
      expect(s.snapshot.currentAltitudeM, 103);
    });

    test('设备不给高程时不把读数抹成 null', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0, altitudeM: 100));
      s.ingestFix(fixAt(1000, lat: 31.0001));

      expect(s.snapshot.currentAltitudeM, 100);
      expect(s.snapshot.elevationGainM, 0);
    });

    test('沉降期只校准基准，之后的爬升才累加', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      // 前 60 秒稳定在 100 米：冷启动高程已收敛，这一段不该产生任何爬升。
      for (int i = 0; i <= 60; i++) {
        s.ingestFix(fixAt(i * 1000, lat: 31.0 + i * 0.00009, altitudeM: 100));
      }
      expect(s.snapshot.elevationGainM, 0);

      // 之后每秒升 0.1 米、共 100 秒：真实爬升 10 米。中值窗口有约 7 秒滞后，
      // 所以最后读数比理论值略小。
      for (int i = 61; i <= 160; i++) {
        s.ingestFix(fixAt(
          i * 1000,
          lat: 31.0 + i * 0.00009,
          altitudeM: 100 + (i - 60) * 0.1,
        ));
      }
      expect(s.snapshot.elevationGainM, closeTo(9.2, 1.0));
    });

    test('下降不增加爬升，下降超过阈值后基准随之下移', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      for (int i = 0; i <= 60; i++) {
        s.ingestFix(fixAt(i * 1000, lat: 31.0 + i * 0.00009, altitudeM: 100));
      }
      // 40 秒下降 8 米：下降本身不计爬升。
      for (int i = 61; i <= 100; i++) {
        s.ingestFix(fixAt(
          i * 1000,
          lat: 31.0 + i * 0.00009,
          altitudeM: 100 - (i - 60) * 0.2,
        ));
      }
      expect(s.snapshot.elevationGainM, 0, reason: '下降不计入爬升');

      // 再爬回来 12 米：基准已经随下降下移，这一段是真实爬升，不是「回到
      // 原点」。滞回只在跨过 3 米阈值时结算，下降段最后不足 3 米的尾巴没有
      // 推进基准，所以累计值是 6 而不是 9。
      for (int i = 101; i <= 160; i++) {
        s.ingestFix(fixAt(
          i * 1000,
          lat: 31.0 + i * 0.00009,
          altitudeM: 92 + (i - 100) * 0.2,
        ));
      }
      expect(s.snapshot.elevationGainM, closeTo(6, 1));
    });

    test('高程跳变不计入爬升，也不污染基准', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0, altitudeM: 100));
      // 只挪了约 11 米却「升高」60 米，坡度 5.4 物理上不成立。
      s.ingestFix(fixAt(1000, lat: 31.0001, altitudeM: 160));

      expect(s.snapshot.currentAltitudeM, 100, reason: '不可信的高程不进读数');
      expect(s.snapshot.elevationGainM, 0);

      // 关键：跳变点没有推进基准。若推进了，后面的真实高程会以 160 为起点，
      // 整段都会被判成下降。
      s.ingestFix(fixAt(2000, lat: 31.0002, altitudeM: 102));
      expect(s.snapshot.currentAltitudeM, 102);
      for (int i = 3; i <= 60; i++) {
        s.ingestFix(fixAt(i * 1000, lat: 31.0 + i * 0.00009, altitudeM: 102));
      }
      expect(s.snapshot.elevationGainM, 0, reason: '沉降期内不累计');

      // 之后升 12 米：以 102 为基准，而不是跳变值 160。跨过 3 / 6 / 9 三档，
      // 累计 9 米，剩下不到 3 米的尾巴不计。
      for (int i = 61; i <= 120; i++) {
        s.ingestFix(fixAt(
          i * 1000,
          lat: 31.0 + i * 0.00009,
          altitudeM: 102 + (i - 60) * 0.2,
        ));
      }
      expect(s.snapshot.elevationGainM, closeTo(9, 1));
    });

    test('与结算口径一致：一条缓坡在实时读数与结算值上给出同一个爬升', () {
      // 实时用尾部中值窗口、结算用居中窗口，两者窗口长度一致，对一条单调缓坡
      // 只差窗口边缘的几个点。这一条守的是「同一趟骑行在结算前后不能出现两个
      // 爬升数」。
      const int steps = 200;
      final List<TrackPoint> points = <TrackPoint>[];
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);

      for (int i = 0; i < steps; i++) {
        final double alt = i < 60 ? 100.0 : 100 + (i - 60) * 0.1;
        final double lat = 31.0 + i * 0.00009;
        s.ingestFix(fixAt(i * 1000, lat: lat, altitudeM: alt));
        points.add(TrackPoint(
          rideId: 1,
          tMs: i * 1000,
          lat: lat,
          lon: 121.0,
          altitudeM: alt,
        ));
      }

      expect(s.snapshot.elevationGainM, greaterThan(8));
      expect(
        s.snapshot.elevationGainM,
        closeTo(elevationGainOf(points), 1.0),
      );
    });
  });

  group('RecordingSession 骑行中的提示', () {
    test('tick 产出提示，takeCues 取走后不再重复', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      // 12 m/s = 43.2 km/h，跨进 40 档。报的是实际速度。
      s.ingestFix(fixAt(0, speedMps: 12.0));

      s.tick(1000);
      final List<RideCue> cues = s.takeCues();
      expect(cues.whereType<SpeedCue>().single.kmh, closeTo(43.2, 1e-9));

      s.tick(2000);
      expect(s.takeCues(), isEmpty, reason: '取走后不能重放，同一档也只报一次');
    });

    test('暂停期间不产生提示', () {
      final RecordingSession s = RecordingSession(rideId: 1, startedAtMs: 0);
      s.ingestFix(fixAt(0, speedMps: 12.0));
      s.pause(1000);
      s.tick(2000);

      expect(s.takeCues(), isEmpty);
    });

    test('崩溃恢复后不补报已经骑过的整公里', () {
      final RecordingSession s = RecordingSession(
        rideId: 1,
        startedAtMs: 0,
        resumedAtMs: 0,
        initialDistanceM: 12500,
        initialElapsedMs: 3600000,
      );
      s.tick(1000);

      expect(s.takeCues(), isEmpty);
    });
  });

  group('RecordingSession 按运动类型开关', () {
    test('跑步会话不估算功率、忽略踏频与功率采样', () {
      final RecordingSession s = RecordingSession(
        rideId: 1,
        startedAtMs: 0,
        activityType: ActivityType.running,
        weightKg: 70,
      );
      s.ingestCadence(90);
      s.ingestPower(250);
      s.ingestFix(LocationFix(
        tMs: 1000,
        lat: 31.2304,
        lon: 121.4737,
        speedMps: 2.78,
        altitudeM: 10,
      ));
      s.tick(1000);
      expect(s.snapshot.power, isNull);
      expect(s.snapshot.cadence, isNull);
    });
  });
}
