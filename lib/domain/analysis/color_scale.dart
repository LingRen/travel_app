import 'dart:math' as math;

import 'constants.dart';

/// 色带起点：慢（浅黄）。
const int kSpeedColorSlow = 0xFFFFF176;

/// 色带中段：中速（橙）。
const int kSpeedColorMid = 0xFFFB8C00;

/// 色带终点：快（深红）。
const int kSpeedColorFast = 0xFFB71C1C;

/// 速度到颜色的映射，返回 0xAARRGGBB 整数。
///
/// 返回 int 而不是 `Color`，是为了让 domain 层不依赖 Flutter。
/// UI 层用 `Color(speedColorArgb(v))` 转换即可。
/// 速度越快颜色越深；超出 [maxSpeedMps] 的部分被钳制。
int speedColorArgb(double speedMps, {double maxSpeedMps = kColorScaleMaxSpeedMps}) {
  final double t = (speedMps / maxSpeedMps).clamp(0.0, 1.0);
  if (t <= 0.5) {
    return _lerpArgb(kSpeedColorSlow, kSpeedColorMid, t * 2);
  }
  return _lerpArgb(kSpeedColorMid, kSpeedColorFast, (t - 0.5) * 2);
}

int _lerpArgb(int from, int to, double t) {
  final int a = _lerpChannel((from >> 24) & 0xFF, (to >> 24) & 0xFF, t);
  final int r = _lerpChannel((from >> 16) & 0xFF, (to >> 16) & 0xFF, t);
  final int g = _lerpChannel((from >> 8) & 0xFF, (to >> 8) & 0xFF, t);
  final int b = _lerpChannel(from & 0xFF, to & 0xFF, t);
  return (a << 24) | (r << 16) | (g << 8) | b;
}

int _lerpChannel(int from, int to, double t) =>
    (from + (to - from) * t).round().clamp(0, 255).toInt();

/// 两个速度之间的线段颜色，取平均速度着色。供地图轨迹分段使用。
int segmentColorArgb(
  double speedA,
  double speedB, {
  double maxSpeedMps = kColorScaleMaxSpeedMps,
}) =>
    speedColorArgb(math.max(0, (speedA + speedB) / 2), maxSpeedMps: maxSpeedMps);
