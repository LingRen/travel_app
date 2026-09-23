import '../data/settings_repository.dart';

/// 1 英里 = 1609.344 米（国际英尺定义，精确值）。
const double _metersPerMile = 1609.344;

/// 1 米 = 3.28084 英尺（1 / 0.3048 的常用近似）。
const double _feetPerMeter = 3.28084;

/// 距离文本。不足 1 公里（英里）时换用更小的单位，短距离也能看清。
String formatDistance(double meters, DistanceUnit unit) {
  if (unit == DistanceUnit.mile) {
    final double miles = meters / _metersPerMile;
    return miles < 0.1
        ? '${(meters * _feetPerMeter).round()} ft'
        : '${miles.toStringAsFixed(2)} mi';
  }
  return meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(2)} km';
}

/// 速度数值，不含单位。
String formatSpeedValue(double mps, DistanceUnit unit) => unit == DistanceUnit.mile
    ? (mps * 3600 / _metersPerMile).toStringAsFixed(1)
    : (mps * 3.6).toStringAsFixed(1);

/// 速度单位标签。
String speedUnitLabel(DistanceUnit unit) =>
    unit == DistanceUnit.mile ? 'mph' : 'km/h';

/// 距离单位标签，用于图表标题这类不跟具体数值走的地方。
String distanceUnitLabel(DistanceUnit unit) =>
    unit == DistanceUnit.mile ? 'mi' : 'km';

/// 距离换算到当前单位下的数值，供图表的坐标轴使用。
double distanceInUnit(double meters, DistanceUnit unit) =>
    unit == DistanceUnit.mile ? meters / _metersPerMile : meters / 1000;

/// 爬升文本。跟随距离单位：公里模式用米，英里模式用英尺。
///
/// 不像 [formatDistance] 那样在小数值时换小单位：爬升几十米是常态，换来换去
/// 反而难比较。
String formatElevation(double meters, DistanceUnit unit) =>
    unit == DistanceUnit.mile
        ? '${(meters * _feetPerMeter).round()} ft'
        : '${meters.round()} m';

/// 时长文本。不足一小时用 mm:ss，超过用 h:mm:ss。
String formatDuration(int seconds) {
  final int safe = seconds < 0 ? 0 : seconds;
  final int h = safe ~/ 3600;
  final int m = (safe % 3600) ~/ 60;
  final int s = safe % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// 日期时间文本，形如 `2026-09-21 08:05`。用本地时区。
///
/// 不做「今年省略年份」的压缩：列表里跨年的记录混在一起时，省略年份会看不出
/// 是哪一年，得不偿失。
String formatDateTime(int epochMs) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
