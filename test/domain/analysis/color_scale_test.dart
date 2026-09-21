import 'package:cycling_app/domain/analysis/color_scale.dart';
import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('速度为 0 时返回色带起点', () {
    expect(speedColorArgb(0), kSpeedColorSlow);
  });

  test('速度达到上限时返回色带终点', () {
    expect(speedColorArgb(kColorScaleMaxSpeedMps), kSpeedColorFast);
  });

  test('超出上限被钳制到终点', () {
    expect(speedColorArgb(100), kSpeedColorFast);
  });

  test('中点为色带中段色', () {
    expect(speedColorArgb(kColorScaleMaxSpeedMps / 2), kSpeedColorMid);
  });

  test('速度越快颜色越深', () {
    final int slow = speedColorArgb(2);
    final int mid = speedColorArgb(7.5);
    final int fast = speedColorArgb(14);
    expect(_luminance(slow), greaterThan(_luminance(mid)));
    expect(_luminance(mid), greaterThan(_luminance(fast)));
  });

  test('输出不透明', () {
    expect(speedColorArgb(5) >> 24 & 0xFF, 0xFF);
  });

  // 任务书原有用例只在 t = 0.5（两段色带的分界点，左右两侧输出连续）上断言，
  // 因此分界点被挪动时测试仍会全绿。这里钉住分界点两侧的精确插值结果：
  //   3.75 m/s → t = 0.25，slow→mid 段的中点，各通道为两端均值；
  //   6.75 m/s → t = 0.45，仍在 slow→mid 段（factor 0.9），用于锁住分界点位置；
  //   11.25 m/s → t = 0.75，mid→fast 段的中点。
  test('色带按两段线性插值', () {
    expect(speedColorArgb(3.75), 0xFFFDBF3B);
    expect(speedColorArgb(6.75), 0xFFFB960C);
    expect(speedColorArgb(11.25), 0xFFD9540E);
  });

  // 任务书的 6 个用例完全没有覆盖 segmentColorArgb（公开 API），
  // 导致「取平均速度着色」这一行为被改坏时测试仍全绿。这里补一条最小用例。
  test('轨迹分段取两端平均速度着色', () {
    expect(segmentColorArgb(4, 8), speedColorArgb(6));
    // 两端平均为负时被钳制到色带起点。
    expect(segmentColorArgb(-5, -1), kSpeedColorSlow);
  });
}

/// 感知亮度，用于验证「越快越深」。
double _luminance(int argb) {
  final int r = (argb >> 16) & 0xFF;
  final int g = (argb >> 8) & 0xFF;
  final int b = argb & 0xFF;
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
