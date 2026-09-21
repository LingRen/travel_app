import 'heart_rate.dart';

/// 各心率区间对应的 MET 系数（骑行，估算用）。
const Map<int, double> kZoneMet = <int, double>{
  1: 4.0, // 轻松骑行
  2: 6.0, // 中等强度
  3: 8.0, // 较大强度
  4: 10.0, // 高强度
  5: 12.0, // 极限强度
};

/// 卡路里估算：按各心率区间停留时长做 MET 加权。
///
/// `kcal = Σ(MET_i × 体重kg × 该区间小时数)`。这是参考值，不是精确测量。
/// 无心率数据或体重非正数时返回 null，UI 显示为「—」。
double? estimateCalories({required HrZoneBreakdown zones, required double weightKg}) {
  if (weightKg <= 0) return null;
  if (zones.totalSeconds <= 0) return null;
  double kcal = 0;
  kZoneMet.forEach((int zone, double met) {
    final double hours = (zones.secondsByZone[zone] ?? 0) / 3600.0;
    kcal += met * weightKg * hours;
  });
  return kcal;
}
