import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/analysis/power.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('由速度、坡度与体重估算功率', () {
    // 70 公斤在平路上以 6 m/s（21.6 km/h）骑：
    //   滚阻 = 70 × 9.80665 × 0.005              = 3.43 N
    //   风阻 = 0.5 × 1.225 × 0.32 × 6²           = 7.06 N
    //   合计 10.49 N × 6 m/s                     = 62.9 W
    test('平路上给出与手算一致的量级', () {
      final double watts =
          estimatePowerW(speedMps: 6, grade: 0, weightKg: 70);
      expect(watts, closeTo(62.93, 0.01));
    });

    test('速度越快功率越高，且是超线性的（风阻随速度平方增长）', () {
      final double slow = estimatePowerW(speedMps: 4, grade: 0, weightKg: 70);
      final double fast = estimatePowerW(speedMps: 8, grade: 0, weightKg: 70);
      expect(fast, greaterThan(slow));
      // 速度翻倍，功率涨到两倍以上；只算滚阻的话刚好两倍。
      expect(fast / slow, greaterThan(2.5));
    });

    test('不蹬就是 0，不会是负数', () {
      expect(estimatePowerW(speedMps: 0, grade: 0.05, weightKg: 70), 0);
      expect(estimatePowerW(speedMps: -1, grade: 0, weightKg: 70), 0);
    });

    test('陡下坡逆推出来的负功率钳到 0', () {
      // 不钳制的话这里会得到 −1600 W 上下的负数，曲线会一头扎到底。
      expect(estimatePowerW(speedMps: 5, grade: -0.5, weightKg: 70), 0);
    });

    test('上坡比平路费功率，且坡度越陡越高', () {
      final double flat = estimatePowerW(speedMps: 5, grade: 0, weightKg: 70);
      final double up = estimatePowerW(speedMps: 5, grade: 0.04, weightKg: 70);
      final double steeper =
          estimatePowerW(speedMps: 5, grade: 0.08, weightKg: 70);
      expect(up, greaterThan(flat));
      expect(steeper, greaterThan(up));
    });

    test('体重大的人同样速度同样坡更费功率', () {
      final double light = estimatePowerW(speedMps: 5, grade: 0.05, weightKg: 60);
      final double heavy = estimatePowerW(speedMps: 5, grade: 0.05, weightKg: 90);
      expect(heavy, greaterThan(light));
    });
  });

  group('窗口拟合坡度', () {
    // 真坡度 5%，120 米水平距离上爬 6 米。
    const List<double> distanceM = <double>[0, 20, 40, 60, 80, 100, 120];
    const List<double> climbM = <double>[0, 1, 2, 3, 4, 5, 6];

    test('平路拟合出 0', () {
      expect(
        fitGrade(
          distanceM: distanceM,
          altitudeM: const <double>[100, 100, 100, 100, 100, 100, 100],
        ),
        0,
      );
    });

    test('无噪声的 5% 坡精确还原成 0.05', () {
      expect(
        fitGrade(distanceM: distanceM, altitudeM: climbM),
        closeTo(0.05, 1e-9),
      );
    });

    test('逐点高程噪声不会整体搬进坡度里', () {
      // 真坡度 5%，逐点噪声都在 ±1.5 米以内——真实 GPS 在高程上的常态。
      // 两端相减只用到两个点，噪声原样搬进来，会得到 0.0442；回归用上整窗样点，
      // 白噪声按 √n 被平均掉，落回 0.0514。容差取 0.004 正是为了把这两者分开：
      // 放到 0.01 的话，退化成两端相减也能蒙混过关。
      const List<double> noisyM = <double>[1.2, 0.3, 0.6, 3.9, 2.9, 5.6, 6.5];
      expect(
        fitGrade(distanceM: distanceM, altitudeM: noisyM),
        closeTo(0.05, 0.004),
      );
    });

    test('水平位移不足时不拟合，让调用方按平路处理', () {
      // 5 个点只挪了 40 米，还不如高程噪声大。
      expect(
        fitGrade(
          distanceM: const <double>[0, 10, 20, 30, 40],
          altitudeM: const <double>[0, 3, 1, 4, 2],
        ),
        isNull,
      );
    });

    test('样点不足两个时不拟合', () {
      expect(fitGrade(distanceM: <double>[], altitudeM: <double>[]), isNull);
      expect(
        fitGrade(distanceM: const <double>[0], altitudeM: const <double>[3]),
        isNull,
      );
    });

    test('两个列表长度不一致时不拟合，不越界', () {
      expect(
        fitGrade(
          distanceM: const <double>[0, 60, 120],
          altitudeM: const <double>[0, 3],
        ),
        isNull,
      );
    });

    test('陡坡与陡下坡都按上限截断', () {
      expect(
        fitGrade(distanceM: distanceM, altitudeM: climbM.map((double m) => m * 4).toList()),
        kMaxGrade,
      );
      expect(
        fitGrade(
          distanceM: distanceM,
          altitudeM: climbM.map((double m) => -m * 4).toList(),
        ),
        -kMaxGrade,
      );
    });
  });
}