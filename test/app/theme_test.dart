import 'package:cycling_app/app/theme.dart';
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

  test('强调色与警告色在深色背景上对比度不低于 4.5', () {
    expect(_contrastRatio(kAppAccent, kAppBackground), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(kAppWarning, kAppBackground), greaterThanOrEqualTo(4.5));
  });
}
