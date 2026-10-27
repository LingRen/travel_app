import 'package:cycling_app/app/theme.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/features/detail/hr_zone_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 相对对比度。纸本主题要在户外强光下可读，因此要求正文与强调色达标。
double _contrastRatio(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double lighter = la > lb ? la : lb;
  final double darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// 两个色相在色环上的最短距离（0..180）。饱和度低的颜色色相不稳，这里只用于
/// 数据色 / 主题色之间。
double _hueDistance(Color a, Color b) {
  final double d = (HSVColor.fromColor(a).hue - HSVColor.fromColor(b).hue)
      .abs();
  return d > 180 ? 360 - d : d;
}

/// 数据色：心率区间色。屏幕上的颜色只表示数据本身；轨迹与各条曲线已改为
/// 跟随主题色，不再另设色带。
List<Color> _dataColors() => <Color>[...HrZoneBar.zoneColors];

/// 安全色：警告与危险。它们是「出事了」的信号，不能被读成「正在发生」。
List<Color> _safetyColors() => <Color>[kAppWarning, kAppDanger];

void main() {
  test('主题是亮色纸本，首帧背景为纸色', () {
    final ThemeData theme = buildAppTheme();

    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF5F0E5));
    expect(theme.useMaterial3, isTrue);
  });

  test('AppPalette 提供完整纸本令牌', () {
    final AppPalette palette = buildAppTheme().extension<AppPalette>()!;

    expect(palette.paper, const Color(0xFFF5F0E5));
    expect(palette.sheet, const Color(0xFFFCF9F2));
    expect(palette.ink, const Color(0xFF1D1B17));
    expect(palette.muted, const Color(0xFF746D60));
    expect(palette.hairline, const Color(0xFFD8CEBB));
    expect(palette.accent, ThemeAccent.cinnabar.color);
    expect(palette.accentInk, ThemeAccent.cinnabar.inkColor);
    expect(palette.warning, kAppWarning);
    expect(palette.danger, kAppDanger);
  });

  test('墨与次级墨在纸底、纸面上都满足正文对比度', () {
    for (final Color background in <Color>[kPaper, kSheet]) {
      expect(
        _contrastRatio(kInk, background),
        greaterThanOrEqualTo(4.5),
        reason: '墨色对 ${background.toARGB32().toRadixString(16)}',
      );
      expect(
        _contrastRatio(kMutedInk, background),
        greaterThanOrEqualTo(4.5),
        reason: '次级墨对 ${background.toARGB32().toRadixString(16)}',
      );
    }
  });

  test('四组文字安全色对纸底不低于 4.5:1', () {
    // 逐个颜料守住对比度门禁：新增主题色时若忘了验证，这一条会先红。
    for (final ThemeAccent accent in ThemeAccent.values) {
      expect(
        _contrastRatio(accent.inkColor, kPaper),
        greaterThanOrEqualTo(4.5),
        reason: '${accent.label}（${accent.dbValue}）文字安全色不足',
      );
    }
  });

  test('主题色作为非文字标记时不低于 3:1，或配有名称', () {
    // 青瓷 / 藤黄的原始颜料低于 3:1，只能在设置页色点这种同时写出颜料名的
    // 地方使用；图标、按钮、选中态、轨迹与图表线一律用 inkColor。
    for (final ThemeAccent accent in ThemeAccent.values) {
      final double ratio = _contrastRatio(accent.inkColor, kPaper);
      expect(ratio, greaterThanOrEqualTo(3.0), reason: accent.label);
      if (_contrastRatio(accent.color, kPaper) < 3.0) {
        expect(accent.label, isNotEmpty, reason: '低对比标记必须带名称');
      }
    }
  });

  test('主题文字安全色与数据色、安全色都区分得开', () {
    // 详情页同屏出现：各条曲线用主题色绘制，心率区间条用区间色，警告与危险
    // 也会在同一页出现。主题色若和它们撞在一起，读图的人会把曲线当成某段区间。
    final List<Color> others = <Color>[..._dataColors(), ..._safetyColors()];

    for (final ThemeAccent accent in ThemeAccent.values) {
      for (final Color other in others) {
        final double hue = _hueDistance(accent.inkColor, other);
        final double ratio = _contrastRatio(accent.inkColor, other);
        expect(
          hue >= 30 || ratio >= 1.30,
          isTrue,
          reason:
              '${accent.label} 与另一处用色撞得太近：'
              '色相差 ${hue.toStringAsFixed(1)}°，亮度比 ${ratio.toStringAsFixed(2)}',
        );
      }
    }
  });

  test('主题色被写进 ColorScheme.primary 与 AppPalette 扩展', () {
    for (final ThemeAccent accent in ThemeAccent.values) {
      final ThemeData theme = buildAppTheme(accent);
      expect(theme.colorScheme.primary, accent.inkColor);
      expect(theme.colorScheme.onPrimary, kPaper);
      final AppPalette? palette = theme.extension<AppPalette>();
      expect(palette, isNotNull);
      expect(palette!.accent, accent.color);
      expect(palette.accentInk, accent.inkColor);
    }
  });

  test('默认主题色是朱砂', () {
    expect(buildAppTheme().colorScheme.primary, ThemeAccent.cinnabar.inkColor);
    expect(
      buildAppTheme().extension<AppPalette>()!.accent,
      ThemeAccent.cinnabar.color,
    );
  });

  test('旧主题值映射到新颜料，未知值回退朱砂', () {
    expect(ThemeAccent.fromDb('mint'), ThemeAccent.celadon);
    expect(ThemeAccent.fromDb('sky'), ThemeAccent.indigo);
    expect(ThemeAccent.fromDb('violet'), ThemeAccent.indigo);
    expect(ThemeAccent.fromDb('amber'), ThemeAccent.gamboge);
    expect(ThemeAccent.fromDb('cinnabar'), ThemeAccent.cinnabar);
    expect(ThemeAccent.fromDb(null), ThemeAccent.cinnabar);
    expect(ThemeAccent.fromDb('no-such-theme'), ThemeAccent.cinnabar);
  });
}
