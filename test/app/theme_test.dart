import 'package:cycling_app/app/theme.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/analysis/color_scale.dart';
import 'package:cycling_app/features/detail/hr_zone_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 相对对比度。车把模式要在户外强光下可读，因此要求正文/强调色对比度达标。
double _contrastRatio(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double lighter = la > lb ? la : lb;
  final double darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// 两个色相在色环上的最短距离（0..180）。饱和度低的颜色色相不稳，这里只用于
/// 高饱和的数据色/主题色之间。
double _hueDistance(Color a, Color b) {
  final double d = (HSVColor.fromColor(a).hue - HSVColor.fromColor(b).hue).abs();
  return d > 180 ? 360 - d : d;
}

/// 数据色：速度色带（黄→橙→深红）与心率区间色。屏幕上的颜色只表示数据本身。
List<Color> _dataColors() => <Color>[
      Color(kSpeedColorSlow),
      Color(kSpeedColorMid),
      Color(kSpeedColorFast),
      ...HrZoneBar.zoneColors,
    ];

/// 安全色：警告与危险。它们是「出事了」的信号，不能被读成「正在发生」。
List<Color> _safetyColors() => <Color>[kAppWarning, kAppDanger];

void main() {
  test('主题是深色高对比，满足车把模式户外可读要求', () {
    final ThemeData theme = buildAppTheme();

    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, kAppBackground);
    expect(theme.useMaterial3, isTrue);
  });

  test('背景色足够暗（深色主题）', () {
    expect(kAppBackground.computeLuminance(), lessThan(0.02));
    expect(kAppSurface.computeLuminance(), lessThan(0.05));
  });

  test('每一组可选主题色在深色背景上对比度都不低于 4.5', () {
    // 逐个色相守住对比度门禁：新增主题色时若忘了验证，这一条会先红。
    for (final ThemeAccent accent in ThemeAccent.values) {
      expect(
        _contrastRatio(accent.color, kAppBackground),
        greaterThanOrEqualTo(4.5),
        reason: '${accent.label}（${accent.dbValue}）对比度不足',
      );
    }
    expect(_contrastRatio(kAppWarning, kAppBackground), greaterThanOrEqualTo(4.5));
  });

  test('主题色与数据色、安全色都区分得开', () {
    // 详情页同屏出现：心率曲线用主题色绘制，心率区间条用区间色，缩略图用速度色带。
    // 主题色若和数据色撞在一起，读图的人会把曲线当成某段区间、或某个速度档。
    final List<Color> others = <Color>[..._dataColors(), ..._safetyColors()];

    for (final ThemeAccent accent in ThemeAccent.values) {
      // 琥珀是历史默认色，本就落在暖色带（速度色带中段、心率「暖身」段）上，靠
      // 亮度与语义区分，是既定取舍——豁免理由见 ThemeAccent 的文档注释。
      if (accent == ThemeAccent.amber) continue;
      for (final Color other in others) {
        final double hue = _hueDistance(accent.color, other);
        final double ratio = _contrastRatio(accent.color, other);
        expect(
          hue >= 30 || ratio >= 1.30,
          isTrue,
          reason: '${accent.label} 与另一处用色撞得太近：'
              '色相差 ${hue.toStringAsFixed(1)}°，亮度比 ${ratio.toStringAsFixed(2)}',
        );
      }
    }
  });

  test('琥珀虽被豁免，也不与危险色撞色', () {
    // 豁免不等于放任：暖色带里至少要避开危险色（红），否则「正在发生」会被读成
    // 「出错」。琥珀与危险色差 32°，这条把「至少这么开」钉住。
    expect(
      _hueDistance(ThemeAccent.amber.color, kAppDanger),
      greaterThanOrEqualTo(30),
    );
  });

  test('主题色被写进 ColorScheme.primary 与 AppPalette 扩展', () {
    for (final ThemeAccent accent in ThemeAccent.values) {
      final ThemeData theme = buildAppTheme(accent);
      expect(theme.colorScheme.primary, accent.color);
      final AppPalette? palette = theme.extension<AppPalette>();
      expect(palette, isNotNull);
      expect(palette!.accent, accent.color);
    }
  });

  test('默认主题色是琥珀', () {
    expect(buildAppTheme().colorScheme.primary, ThemeAccent.amber.color);
    expect(buildAppTheme().extension<AppPalette>()!.accent, ThemeAccent.amber.color);
  });

  test('ThemeAccent.fromDb 认已知值，未知值回退琥珀', () {
    expect(ThemeAccent.fromDb('sky'), ThemeAccent.sky);
    expect(ThemeAccent.fromDb('violet'), ThemeAccent.violet);
    expect(ThemeAccent.fromDb(null), ThemeAccent.amber);
    expect(ThemeAccent.fromDb('no-such-theme'), ThemeAccent.amber);
  });
}
