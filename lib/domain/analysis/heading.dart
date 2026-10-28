import 'dart:math' as math;

import 'constants.dart';

/// 朝向相关的纯函数。见 ADR-0002：朝向只用于实时显示，不落库、不进 GPX、
/// 不参与统计。
///
/// 角度统一用**度**，0 为正北、90 为正东，顺时针增长。记录页地图按它做
/// heading-up 旋转（行进方向朝上），见 `live_route_map.dart` 的 `_updateHeading`。

/// 把任意角度归一化到 [0, 360)。
double normalizeDegrees(double degrees) {
  if (!degrees.isFinite) return 0;
  final double wrapped = degrees % 360;
  return wrapped < 0 ? wrapped + 360 : wrapped;
}

/// 从 [fromDeg] 转到 [toDeg] 的最短弧差，落在 [-180, 180]。
///
/// 箭头补间必须用它而不是直接相减：359° → 1° 直接算出来是 -358°，动画会倒转
/// 一整圈；这里给出 +2°，箭头沿最短一侧转过去。恰好半圈时保留原始符号，让
/// 「往哪边转」在测试里可预期。
double shortestArcDelta(double fromDeg, double toDeg) {
  final double delta = normalizeDegrees(toDeg) - normalizeDegrees(fromDeg);
  if (delta > 180) return delta - 360;
  if (delta < -180) return delta + 360;
  return delta;
}

/// 两点之间的方位角（度，0 为正北，顺时针）。
double bearingDegrees(
  double fromLat,
  double fromLon,
  double toLat,
  double toLon,
) {
  final double phi1 = fromLat * math.pi / 180;
  final double phi2 = toLat * math.pi / 180;
  final double dLon = (toLon - fromLon) * math.pi / 180;
  final double y = math.sin(dLon) * math.cos(phi2);
  final double x =
      math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLon);
  return normalizeDegrees(math.atan2(y, x) * 180 / math.pi);
}

/// 本次上报的朝向该怎么处理。见设计文档里「朝向上报」的可信判定。
enum HeadingUpdate {
  /// 运动可信，采用本次上报的方向。
  adopt,

  /// 速度处在两个门槛之间，维持上一次朝向。
  hold,

  /// 近乎静止，冻结上一次朝向——不能回正北，也不能抖动。
  freeze,
}

/// 按速度判定这次上报的朝向是否可信。
HeadingUpdate headingUpdateFor(double speedMps) {
  if (speedMps >= kHeadingAdoptSpeedMps) return HeadingUpdate.adopt;
  if (speedMps < kHeadingFreezeSpeedMps) return HeadingUpdate.freeze;
  return HeadingUpdate.hold;
}

/// 算出这一拍应有的朝向。
///
/// [reportedDeg] 为空时（设备没给方向、或首个朝向还没建立）保持 [currentDeg]，
/// 不能因为一次缺字段就把箭头甩回正北。建立首个朝向的兜底由会话层按最近两个
/// 轨迹点的方位角完成。
double? resolveHeadingDeg({
  required double? currentDeg,
  required double? reportedDeg,
  required double speedMps,
}) {
  switch (headingUpdateFor(speedMps)) {
    case HeadingUpdate.adopt:
      return reportedDeg == null ? currentDeg : normalizeDegrees(reportedDeg);
    case HeadingUpdate.hold:
    case HeadingUpdate.freeze:
      return currentDeg;
  }
}
