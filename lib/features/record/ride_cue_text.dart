import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/recording/ride_cue.dart';

/// 提示条上显示的一行文案。见设计文档 10.1。
///
/// 比语音文案短：屏幕上一眼要读完，不把「第 2 公里」写成「已经骑了 2 公里」。
String rideCueBannerText(RideCue cue, DistanceUnit unit) => switch (cue) {
      LapCue c =>
        '第 ${c.lapKm} 公里 · 均速 ${formatSpeedValue(c.avgSpeedMps, unit)} ${speedUnitLabel(unit)} · 耗时 ${formatDuration(c.durationS)}',
      DistanceCue c => '已骑行 ${c.km} 公里',
      SpeedCue c =>
        '速度 ${formatSpeedValue(c.kmh / 3.6, unit)} ${speedUnitLabel(unit)}',
    };

/// 语音播报的文案。
///
/// 与提示条刻意不同：单位要念全（「km/h」会被 TTS 念成一串字母），时长要念成
/// 「2分47秒」而不是「02:47」（后者会被读成「零二四七」）。
String rideCueSpeechText(RideCue cue, DistanceUnit unit) => switch (cue) {
      LapCue c =>
        '第${c.lapKm}公里，均速${formatSpeedValue(c.avgSpeedMps, unit)}${_spokenSpeedUnit(unit)}，耗时${_spokenDuration(c.durationS)}',
      DistanceCue c => '已骑行${c.km}公里',
      SpeedCue c =>
        '速度${formatSpeedValue(c.kmh / 3.6, unit)}${_spokenSpeedUnit(unit)}',
    };

/// 速度单位的念法。
String _spokenSpeedUnit(DistanceUnit unit) =>
    unit == DistanceUnit.mile ? '英里每小时' : '公里每小时';

/// 时长的念法：`2分47秒`。整分钟时省掉「秒」，不足一分钟只念秒。
String _spokenDuration(int seconds) {
  final int safe = seconds < 0 ? 0 : seconds;
  final int minutes = safe ~/ 60;
  final int rest = safe % 60;
  if (minutes == 0) return '$rest秒';
  return rest == 0 ? '$minutes分' : '$minutes分$rest秒';
}