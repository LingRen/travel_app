import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/models/activity_type.dart';
import '../../domain/recording/ride_cue.dart';

/// 提示条上显示的一行文案。见设计文档 10.1。
///
/// 比语音文案短：屏幕上一眼要读完，不把「第 2 公里」写成「已经骑了 2 公里」。
String rideCueBannerText(
  RideCue cue,
  DistanceUnit unit,
  ActivityType type,
) => switch (cue) {
  // 分段成绩跟着主读数走：骑行看均速，跑步/健走/徒步看配速。否则跑步时
  // 界面主读数是「5'30"/km」，横幅却报「均速 10.8 km/h」，两个数对不上。
  LapCue c =>
    type.usesPace
        ? '第 ${c.lapKm} 公里 · 配速 ${formatPace(c.avgSpeedMps, unit)} ${paceUnitLabel(unit)} · 耗时 ${formatDuration(c.durationS)}'
        : '第 ${c.lapKm} 公里 · 均速 ${formatSpeedValue(c.avgSpeedMps, unit)} ${speedUnitLabel(unit)} · 耗时 ${formatDuration(c.durationS)}',
  DistanceCue c => '${_distanceVerb(type)} ${c.km} 公里',
  SpeedCue c =>
    '速度 ${formatSpeedValue(c.kmh / 3.6, unit)} ${speedUnitLabel(unit)}',
  GpsWeakCue() => 'GPS 信号弱',
  GpsRecoveredCue() => '定位已恢复',
};

/// 语音播报的文案。
///
/// 与提示条刻意不同：单位要念全（「km/h」会被 TTS 念成一串字母），时长要念成
/// 「2分47秒」而不是「02:47」（后者会被读成「零二四七」）。「GPS」同理——
/// 字母缩写会被逐字念成「G P S」，念「卫星信号」更像人话。
String rideCueSpeechText(
  RideCue cue,
  DistanceUnit unit,
  ActivityType type,
) => switch (cue) {
  LapCue c =>
    type.usesPace
        ? '第${c.lapKm}公里，配速${formatPaceSpoken(c.avgSpeedMps, unit)}，耗时${_spokenDuration(c.durationS)}'
        : '第${c.lapKm}公里，均速${formatSpeedValue(c.avgSpeedMps, unit)}${_spokenSpeedUnit(unit)}，耗时${_spokenDuration(c.durationS)}',
  DistanceCue c => '${_distanceVerb(type)} ${c.km} 公里',
  SpeedCue c =>
    '速度${formatSpeedValue(c.kmh / 3.6, unit)}${_spokenSpeedUnit(unit)}',
  GpsWeakCue() => '卫星信号弱',
  GpsRecoveredCue() => '定位已恢复',
};

/// 距离里程碑文案里的动词，按运动类型适配。
String _distanceVerb(ActivityType type) => switch (type) {
  ActivityType.cycling => '已骑行',
  ActivityType.running => '已跑',
  ActivityType.walking => '已走',
  ActivityType.hiking => '已徒步',
  ActivityType.mountaineering => '已登山',
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
