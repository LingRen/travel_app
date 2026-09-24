import '../analysis/constants.dart';
import 'ride_cue.dart';

/// 从每秒的实时读数里判定「该提示了」的纯逻辑。见设计文档 10.1。
///
/// 三个提示各有各的判据，但共用一条原则：**只在跨过整档的那一刻触发一次**。
/// 每拍都判的话，1Hz 的节拍会把同一件事播报几十遍——「已骑行 10 公里」会变成
/// 连播一分钟。
///
///   - 每整公里（[kCueLapM]）：距离跨过 1000m 的整数倍，给出该公里的耗时与均速；
///   - 每 10 公里（[kCueDistanceTierM]）：距离跨过 10000m 的整数倍；
///   - 速度跨档（[kCueSpeedTierKmh]）：速度(km/h) 跨过 10 的整数倍。
///
/// **速度档只升不降**。掉速之后再回到同一档不再播报：否则丘陵路段上反复经过
/// 20km/h 会一直插话，把真正有用的整公里播报淹掉。代价是「同一档一次骑行只报
/// 一次」，这正是「每次提升 10km/h 提示一次」的字面口径。
///
/// 本对象是有状态的，但状态只跟「已经报过什么」有关，与时钟无关，因此测试完全
/// 确定：喂进（距离, 时长, 速度）三元组，断言吐出来的提示序列即可。
class CueDetector {
  /// [initialDistanceM] / [initialElapsedMs] 供崩溃恢复时播种基线。
  ///
  /// 不播种的话，续写一个已经骑了 12 公里的会话，第一拍就会把 1~12 公里逐条补报
  /// 一遍。播种后把「恢复这一刻」当作当前这一公里的起点：已经跨过的整公里与整十
  /// 公里不再补报，正在进行的这一公里按恢复后的耗时计算——精确的断点已随崩溃丢失，
  /// 这是能取到的最接近的口径。
  ///
  /// 速度档不播种（速度是瞬时量，本来就没有「历史最高档」可以落盘）。
  CueDetector({double initialDistanceM = 0, int initialElapsedMs = 0})
      : _lapKm = initialDistanceM ~/ kCueLapM,
        _tensKm = initialDistanceM ~/ kCueDistanceTierM,
        _lapStartElapsedMs = initialElapsedMs;

  /// 已播报过的整公里数。
  int _lapKm;

  /// 已播报过的整十公里档位。
  int _tensKm;

  /// 已播报过的最高速度档（档位下沿，km/h）。
  int _speedTierKmh = 0;

  /// 上一公里结束时的有效时长（毫秒），用于算这一公里的耗时。
  int _lapStartElapsedMs;

  /// 推进一次，返回这一拍新产生的提示。可能为空，也可能一次多条（例如长距离
  /// 断点后一口气跨过多公里、或同时跨过 10 公里与 10km/h 档）。
  List<RideCue> update({
    required double distanceM,
    required int elapsedMs,
    required double speedMps,
  }) {
    final List<RideCue> cues = <RideCue>[];

    // 整公里：跨过一公里的边界就报一次。距离跳变（GPS 断点后补上）可能一次跨
    // 过多公里，用循环补齐，每条都带上自己那一段的耗时。
    while (_lapKm < distanceM ~/ kCueLapM) {
      _lapKm++;
      final double lapSeconds = (elapsedMs - _lapStartElapsedMs) / 1000.0;
      cues.add(LapCue(
        lapKm: _lapKm,
        durationS: lapSeconds.round(),
        // 一公里的边界到边界就是整 1000m，均速直接由它除以耗时得到；耗时非正
        // （同一拍里跨过多公里）时按 0 处理，不做除零。
        avgSpeedMps: lapSeconds > 0 ? kCueLapM / lapSeconds : 0,
      ));
      _lapStartElapsedMs = elapsedMs;
    }

    // 每 10 公里。
    final int tens = distanceM ~/ kCueDistanceTierM;
    if (tens > _tensKm) {
      _tensKm = tens;
      cues.add(DistanceCue(tens * (kCueDistanceTierM ~/ 1000)));
    }

    // 速度跨档：只认向上的新高档。报的是这一拍的实际速度，不是档位下沿（见
    // [SpeedCue]）——屏幕上的大数字就是实际速度，两个数必须对得上。
    final int tier = (speedMps * 3.6) ~/ kCueSpeedTierKmh;
    if (tier > _speedTierKmh) {
      _speedTierKmh = tier;
      cues.add(SpeedCue(speedMps * 3.6));
    }

    return cues;
  }
}