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

/// 距离拆成「数值 + 单位」，给历史卡片/详情大数字排版用。
///
/// 公里制保留一位小数（`42.6 km`），不足 1 公里时用米；英里制同理。
({String value, String unit}) formatDistanceParts(
  double meters,
  DistanceUnit unit,
) {
  if (unit == DistanceUnit.mile) {
    final double miles = meters / _metersPerMile;
    return miles < 0.1
        ? (value: '${(meters * _feetPerMeter).round()}', unit: 'ft')
        : (value: miles.toStringAsFixed(1), unit: 'mi');
  }
  return meters < 1000
      ? (value: '${meters.round()}', unit: 'm')
      : (value: (meters / 1000).toStringAsFixed(1), unit: 'km');
}

/// 速度数值，不含单位。
String formatSpeedValue(double mps, DistanceUnit unit) =>
    unit == DistanceUnit.mile
    ? (mps * 3600 / _metersPerMile).toStringAsFixed(1)
    : (mps * 3.6).toStringAsFixed(1);

/// 速度单位标签。
String speedUnitLabel(DistanceUnit unit) =>
    unit == DistanceUnit.mile ? 'mph' : 'km/h';

/// 配速单位尾缀。与 [speedUnitLabel] 并列；跑步/健走/徒步主读数的单位标签。
String paceUnitLabel(DistanceUnit unit) =>
    unit == DistanceUnit.mile ? '/mi' : '/km';

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

/// 记录 HUD 的时钟文本，始终 `h:mm:ss`，形如 `00:48:26`。
///
/// 与 [formatDuration] 分开：历史 / 结算用紧凑的 `48:26`，记录页的时长每
/// 秒都在跳，固定三位（时:分:秒）能避免跨过一小时时整行数字横向位移。
String formatDurationClock(int seconds) {
  final int safe = seconds < 0 ? 0 : seconds;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(safe ~/ 3600)}:${two((safe % 3600) ~/ 60)}:${two(safe % 60)}';
}

/// 功率文本。没配功率计时没有功率数据，用破折号占位。
String formatPower(double? watts) => watts == null ? '—' : '${watts.round()} W';

/// 纸本页眉的中文年月，形如 `二〇二六 · 十月`。
String formatChineseYearMonth(DateTime t) {
  const List<String> digits = <String>[
    '〇',
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '七',
    '八',
    '九',
  ];
  final String year = t.year
      .toString()
      .split('')
      .map((String d) => digits[int.parse(d)])
      .join();
  final String month = switch (t.month) {
    10 => '十',
    11 => '十一',
    12 => '十二',
    _ => digits[t.month],
  };
  return '$year · $month月';
}

/// 待机页的日期时间，形如 `10月27日 · 周二 · 06:42`。用本地时区。
String formatChineseMonthDayWeekTime(DateTime t) {
  const List<String> weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.month}月${t.day}日 · 周${weekdays[t.weekday - 1]} · '
      '${two(t.hour)}:${two(t.minute)}';
}

/// 历史条目的日期，形如 `09.21`。
String formatMonthDayDot(int epochMs) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.month)}.${two(t.day)}';
}

/// 中文星期，形如 `周一`。
String formatChineseWeekday(int epochMs) {
  const List<String> weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return '周${weekdays[t.weekday - 1]}';
}

/// 24 小时制时间，形如 `08:05`。
String formatTimeHm(int epochMs) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}

/// 中文时长摘要，形如 `4 小时 31 分`。用于历史页眉的当月摘要。
String formatChineseDuration(int seconds) {
  final int safe = seconds < 0 ? 0 : seconds;
  final int hours = safe ~/ 3600;
  final int minutes = (safe % 3600) ~/ 60;
  return hours > 0 ? '$hours 小时 $minutes 分' : '$minutes 分';
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

/// 配速文本（跑步/健走/徒步的主读数）。由速度（m/s）换算。
///
/// 公里模式为分钟每公里（mm:ss / km），英里模式为分钟每英里（mm:ss / mi）。
/// 速度无效（0、负值）时显示 `--`：起步前没有速度可言，摆 0 会像「停着」。
/// 显示格式固定 `5'30"`（分'秒"，秒数两位补齐），单位尾缀由调用方拼。
String formatPace(double speedMps, DistanceUnit unit) {
  final ({int minutes, int seconds})? parts = paceParts(speedMps, unit);
  if (parts == null) return '--';
  return "${parts.minutes}'${parts.seconds.toString().padLeft(2, '0')}\"";
}

/// 配速的分秒构成。速度无效时返回 null。
///
/// 主读数要把「分」「秒」「分隔符」分成不同字号，不能只拿拼接好的字符串。
({int minutes, int seconds})? paceParts(double speedMps, DistanceUnit unit) {
  if (speedMps <= 0) return null;
  // 秒每单位距离：公里 1000m，英里 1609.344m。
  final double metersPerUnit = unit == DistanceUnit.mile
      ? _metersPerMile
      : 1000.0;
  final double seconds = metersPerUnit / speedMps;
  final int minutes = seconds ~/ 60;
  int rest = seconds.remainder(60).round();
  // remainder 可能为 60（round 进位），归一化进位到整分。
  if (rest == 60) return (minutes: minutes + 1, seconds: 0);
  return (minutes: minutes, seconds: rest);
}

/// 由「每单位距离的秒数」直接生成配速文本，形如 `5'33"`。
///
/// 详情页的配速曲线纵轴是秒/公里（不是速度），标注不能再走 [formatPace]。
String formatPaceSeconds(double secondsPerUnit) {
  if (!secondsPerUnit.isFinite || secondsPerUnit <= 0) return '--';
  final int minutes = secondsPerUnit ~/ 60;
  int seconds = secondsPerUnit.remainder(60).round();
  if (seconds == 60) return "${minutes + 1}'00\"";
  return "$minutes'${seconds.toString().padLeft(2, '0')}\"";
}

/// 配速的口语念法，如 `5分30秒每公里`，供语音播报使用。
///
/// 不能直接把 [formatPace] 的结果扔给 TTS：`5'30"` 会被逐字符念出来。
/// 速度无效时说「暂无配速」，与界面上 `--` 的含义一致。
String formatPaceSpoken(double speedMps, DistanceUnit unit) {
  final ({int minutes, int seconds})? parts = paceParts(speedMps, unit);
  if (parts == null) return '暂无配速';
  final String where = unit == DistanceUnit.mile ? '每英里' : '每公里';
  final String minutes = parts.minutes > 0 ? '${parts.minutes}分' : '';
  final String seconds = parts.seconds > 0 ? '${parts.seconds}秒' : '';
  return '$minutes$seconds$where';
}
