/// 骑行中的一次提示事件。见设计文档 10.1「骑行中的提示」。
///
/// 只承载数值、不带文案：文案在界面层生成（`features/record/ride_cue_text.dart`）。
/// 原因是 `core/format.dart` 依赖 `data/settings_repository.dart`，而 domain 层
/// 不允许引用它（分层铁律，见 `docs/superpowers/specs`）。分开之后 domain 的判据
/// 可以纯函数测试，文案也能独立改。
sealed class RideCue {
  const RideCue();
}

/// 每满 1 公里：播报该公里的均速与耗时。
final class LapCue extends RideCue {
  const LapCue({
    required this.lapKm,
    required this.durationS,
    required this.avgSpeedMps,
  });

  /// 第几公里（从 1 起）。
  final int lapKm;

  /// 该公里耗时（秒）。暂停时间不计入——时长本身按有效记录时长推进。
  final int durationS;

  /// 该公里均速（m/s）。
  final double avgSpeedMps;
}

/// 每满 10 公里：播报累计里程。
final class DistanceCue extends RideCue {
  const DistanceCue(this.km);

  /// 已达成的整十公里数。
  final int km;
}

/// 速度向上跨过一个 [kCueSpeedTierKmh] 档位。
///
/// 触发按整档判定，但**报的是跨档那一刻的实际速度，不是档位下沿**。真机验收时
/// 报下沿（「速度 20.0 km/h」）与屏幕上的大数字（25.9）当场打架，同一屏两个数
/// 对不上，用户只会以为哪个算错了。
final class SpeedCue extends RideCue {
  const SpeedCue(this.kmh);

  /// 跨档那一刻的实际速度（km/h）。
  final double kmh;
}