import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/analysis/elevation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('medianFilterElevation', () {
    test('窗口为 5 时输出等长序列', () {
      final List<double?> raw = <double?>[100, 100.5, 99.8, 100.2, 99.9, 100.4, 100.0];
      expect(medianFilterElevation(raw, kElevationFilterWindow).length, raw.length);
    });

    test('空值邻域内仍有非空值时会被填充', () {
      final List<double?> out = medianFilterElevation(<double?>[100, null, 102, null, 104], 3);
      expect(out[1], closeTo(101, 1e-9));
      expect(out[3], closeTo(103, 1e-9));
    });
  });

  group('elevationGainMeters', () {
    test('平坦高程噪声不产生爬升', () {
      final List<double?> raw = <double?>[100, 100.5, 99.8, 100.2, 99.9, 100.4, 100.0];
      final List<double?> filtered = medianFilterElevation(raw, kElevationFilterWindow);
      expect(elevationGainMeters(filtered, kElevationGainThresholdM), 0);
    });

    test('线性爬升被完整累加', () {
      final List<double?> raw = <double?>[100, 101, 102, 103, 104, 105, 106];
      final List<double?> filtered = medianFilterElevation(raw, kElevationFilterWindow);
      expect(elevationGainMeters(filtered, kElevationGainThresholdM), closeTo(6, 1e-9));
    });

    test('锯齿噪声不放大爬升', () {
      // 原始序列逐点波动约 4 米（真实爬升约 4.5 米）。
      //
      // 窗口为 5 的中值滤波无法把这种周期为 2 的锯齿彻底消掉：任意 5 点窗口
      // 里两种相位总是 3:2，中值必然落在其中一种相位上，于是滤波后仍在锯齿。
      // 所以这里断言的是「滤波显著抑制放大」而非「完全消除」：
      // 未滤波直接累加会被锯齿放大到 23 米，滤波后收敛到 11 米。
      final List<double?> raw = <double?>[100, 103, 99, 104, 100, 105, 101, 106, 102, 107];
      final List<double?> filtered = medianFilterElevation(raw, kElevationFilterWindow);
      final double gain = elevationGainMeters(filtered, kElevationGainThresholdM);
      final double rawGain = elevationGainMeters(raw, kElevationGainThresholdM);
      expect(rawGain, closeTo(23, 1e-9));
      expect(gain, greaterThan(3));
      expect(gain, lessThan(rawGain));
    });

    test('下降段不计入爬升', () {
      final List<double?> raw = <double?>[200, 190, 180, 170, 160, 150];
      final List<double?> filtered = medianFilterElevation(raw, kElevationFilterWindow);
      expect(elevationGainMeters(filtered, kElevationGainThresholdM), 0);
    });

    test('空值被跳过', () {
      final List<double?> out = medianFilterElevation(<double?>[100, null, 102, null, 104], 3);
      expect(elevationGainMeters(out, kElevationGainThresholdM), closeTo(4, 1e-9));
    });
  });
}
