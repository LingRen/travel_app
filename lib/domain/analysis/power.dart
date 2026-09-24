import 'constants.dart';

/// 没接功率计时，由速度、坡度与体重估算骑行功率（瓦）。
///
/// 用的是最经典的三项阻力模型，不含加速度项：
///
/// ```text
/// P = v · ( m·g·Crr + ½·ρ·CdA·v² + m·g·grade )
/// ```
///
/// 三项分别是滚阻、风阻、坡阻。算出来的是轮上功率，没有算传动损耗，因此系统性地
/// 偏低几个百分点——这本来就是估算，界面会写明「估算」，不值得再乘一个传动效率
/// 去假装精确。
///
/// 下坡逆推出来的负功率按 0 处理：人不蹬时功率就是 0，不是负数。
double estimatePowerW({
  required double speedMps,
  required double grade,
  required double weightKg,
}) {
  if (speedMps <= 0) return 0;
  final double forceN = weightKg * kGravity * (kRollingResistance + grade) +
      0.5 * kAirDensity * kDragArea * speedMps * speedMps;
  final double watts = speedMps * forceN;
  return watts < 0 ? 0 : watts;
}

/// 由窗口内一串「累计距离 → 高程」样点最小二乘拟合出坡度（米 / 米）。
///
/// 不能用「窗口两端高程相减 ÷ 水平距离」：高程在秒级尺度上的噪声有几米，而几十秒
/// 里真实的爬升可能还不到两米，两端相减基本是在量噪声。回归用上窗口里全部样点，
/// 白噪声按 √n 被平均掉（1Hz 采样、30 秒窗口约降到 1/5）。
///
/// 返回 null 表示样点不足或水平位移太短，调用方按平路处理。斜率按 [kMaxGrade]
/// 截断。
double? fitGrade({
  required List<double> distanceM,
  required List<double> altitudeM,
}) {
  final int n = distanceM.length;
  if (n < 2 || altitudeM.length != n) return null;
  if (distanceM.last - distanceM.first < kMinGradeRunM) return null;

  double meanDistance = 0;
  double meanAltitude = 0;
  for (int i = 0; i < n; i++) {
    meanDistance += distanceM[i];
    meanAltitude += altitudeM[i];
  }
  meanDistance /= n;
  meanAltitude /= n;

  double covariance = 0;
  double variance = 0;
  for (int i = 0; i < n; i++) {
    final double dx = distanceM[i] - meanDistance;
    covariance += dx * (altitudeM[i] - meanAltitude);
    variance += dx * dx;
  }
  if (variance <= 0) return null;
  return (covariance / variance).clamp(-kMaxGrade, kMaxGrade);
}