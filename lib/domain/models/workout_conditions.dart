/// 一次运动开始时捕获的地点与天气。
///
/// 全部字段可空：没有配置 Key、没有定位、网络失败或响应缺字段时对应值为
/// null。界面据此省略缺失的部分，不用「--」「未知」之类占位冒充真实读数。
class WorkoutConditions {
  const WorkoutConditions({
    this.placeName,
    this.placeShort,
    this.weatherText,
    this.weatherTempC,
  });

  /// 详情页用的完整地名，形如「成都市 · 龙泉驿区 · 山泉镇」。
  final String? placeName;

  /// 历史列表用的短地名，通常是区县，形如「龙泉驿区」。
  final String? placeShort;

  /// 天气描述，形如「晴」「小雨」。未知天气码时为 null。
  final String? weatherText;

  /// 当前气温（摄氏度，整数）。
  final int? weatherTempC;

  static const WorkoutConditions none = WorkoutConditions();

  bool get isEmpty =>
      placeName == null &&
      placeShort == null &&
      weatherText == null &&
      weatherTempC == null;

  /// 地点行左侧文字。完整地名缺失时退回短地名，两者都没有时返回 null。
  String? get placeLabel {
    final String? name = placeName ?? placeShort;
    if (name == null || name.trim().isEmpty) return null;
    return name;
  }

  /// 历史列表用的具体地点：取完整地名的最后一段，例如
  /// 「成都市 · 龙泉驿区 · 桃花故里」→「桃花故里」。
  ///
  /// 旧记录或没有完整地名时退回 [placeShort]（通常是区县）；两者都没有时
  /// 返回 null。只从已落库的文字里取，不重新查询，也不推断当前位置。
  String? get listPlaceLabel {
    final String? full = placeName?.trim();
    if (full != null && full.isNotEmpty) {
      final String last = full.split(' · ').last.trim();
      if (last.isNotEmpty) return last;
    }
    final String? short = placeShort?.trim();
    return (short == null || short.isEmpty) ? null : short;
  }

  /// 天气行右侧文字，例如「晴 18°C」。温度缺失时只显示描述，描述也缺失时
  /// 返回 null。
  String? get weatherLabel {
    final String? text = weatherText?.trim();
    final int? temperatureC = weatherTempC;
    if (temperatureC == null) {
      return (text == null || text.isEmpty) ? null : text;
    }
    if (text == null || text.isEmpty) return '$temperatureC°C';
    return '$text $temperatureC°C';
  }
}
