import 'dart:math' as math;

import '../models/track_point.dart';
import 'constants.dart';

/// 地球平均半径（米），IUGG 平均半径。
const double kEarthRadiusM = 6371008.8;

double _toRadians(double degrees) => degrees * math.pi / 180.0;

/// 两点间大圆距离（米）。
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  final double dLat = _toRadians(lat2 - lat1);
  final double dLon = _toRadians(lon2 - lon1);
  final double sinHalfLat = math.sin(dLat / 2);
  final double sinHalfLon = math.sin(dLon / 2);
  final double a = sinHalfLat * sinHalfLat +
      math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) * sinHalfLon * sinHalfLon;
  return 2 * kEarthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
}

/// 相邻两点是否构成一个可信的轨迹段。
///
/// 下列情况返回 false，即视为「不可信，不连线、不计距离，也不计入移动/静止时长」：
/// - 任一端点缺坐标（GPS 丢失）
/// - 时间不前进
/// - 时间间隔超过 [kGpsGapMs]（设计文档 9.3 的 GPS 断点）
/// - 隐含速度超过 [kMaxPlausibleSpeedMps]（GPS 跳变）
bool isTrustedSegment(TrackPoint a, TrackPoint b) {
  if (!a.hasPosition || !b.hasPosition) return false;
  final int dtMs = b.tMs - a.tMs;
  if (dtMs <= 0 || dtMs > kGpsGapMs) return false;
  final double d = haversineMeters(a.lat!, a.lon!, b.lat!, b.lon!);
  return d / (dtMs / 1000.0) <= kMaxPlausibleSpeedMps;
}

/// 相邻两个轨迹点之间的有效距离（米）。
///
/// 不可信时返回 0，判定规则见 [isTrustedSegment]。
double segmentDistanceMeters(TrackPoint a, TrackPoint b) =>
    isTrustedSegment(a, b) ? haversineMeters(a.lat!, a.lon!, b.lat!, b.lon!) : 0;
