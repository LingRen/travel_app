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

/// 时长文本。不足一小时用 mm:ss，超过用 h:mm:ss。
String formatDuration(int seconds) {
  final int safe = seconds < 0 ? 0 : seconds;
  final int h = safe ~/ 3600;
  final int m = (safe % 3600) ~/ 60;
  final int s = safe % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}
