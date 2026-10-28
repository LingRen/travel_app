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
  final double a =
      sinHalfLat * sinHalfLat +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          sinHalfLon *
          sinHalfLon;
  return 2 * kEarthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
}

/// 一次定位空档的类别。
enum SignalGapKind {
  /// 短缺口（不超过 [kGapBridgeMaxMs]）：用虚线跨过，不当作轨迹中断。
  bridged,

  /// 长缺口：接不上了，断口两侧画标记并写进中断摘要。
  broken,
}

/// 相邻两点之间的定位空档类别。null 表示不是空档（时间没断，或根本没挪动）。
///
/// 只看时间不够：停止不动时系统常常不再送定位，十几秒的间隔只是「没动」，不是
/// 「丢信号」。这种缺口连起来也画不出横穿建筑或隧道的假直线，断开反而让轨迹和
/// 曲线看着断断续续（真机实测见 [kGapBreakMinDistanceM]）。
///
/// 缺坐标时无从判断位移，按「可能有位移」处理，保守算作空档。
SignalGapKind? signalGapKind(TrackPoint a, TrackPoint b) {
  final int dtMs = b.tMs - a.tMs;
  if (dtMs <= kGpsGapMs) return null;
  if (a.hasPosition &&
      b.hasPosition &&
      haversineMeters(a.lat!, a.lon!, b.lat!, b.lon!) <
          kGapBreakMinDistanceM) {
    return null;
  }
  return dtMs > kGapBridgeMaxMs ? SignalGapKind.broken : SignalGapKind.bridged;
}

/// 相邻两点是否构成一个**值得画出来**的断点：时间跨度超过 [kGpsGapMs]，且两点
/// 的位移超过 [kGapBreakMinDistanceM]。两种缺口都算（见 [signalGapKind]）。
///
/// 缺坐标时无从判断位移，按「可能有位移」处理，保守断开。
bool isMeaningfulGap(TrackPoint a, TrackPoint b) =>
    signalGapKind(a, b) != null;

/// 相邻两点是否构成一个可信的轨迹段。
///
/// 下列情况返回 false，即视为「不可信，不连线、不计距离，也不计入移动/静止时长」：
/// - 任一端点缺坐标（GPS 丢失）
/// - 时间不前进
/// - 时间间隔超过 [kGpsGapMs]（设计文档 9.3 的 GPS 断点）
/// - 隐含速度超过 [kMaxPlausibleSpeedMps]（GPS 跳变）
///
/// 注意这里的时间判定是**纯时间**口径，与画线用的 [isMeaningfulGap] 不同：
/// 距离统计不能把「停车时的十几秒空档」算进去。
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
    isTrustedSegment(a, b)
    ? haversineMeters(a.lat!, a.lon!, b.lat!, b.lon!)
    : 0;

/// 整条轨迹的有效里程（米），口径见 [kDistanceNoiseFloorM]。
///
/// 与实时累计同一套规则：以锚点为基准，位移够得上噪声门槛才记一笔；死区判定
/// 为静止的段直接跳过。逐段求和会把停车时的位置抖动也算成里程。
double trackDistanceMeters(List<TrackPoint> points) {
  double total = 0;
  TrackPoint? anchor;
  for (int i = 1; i < points.length; i++) {
    final TrackPoint a = points[i - 1];
    final TrackPoint b = points[i];
    final double segment = segmentDistanceMeters(a, b);
    // 只有「两端都静止」的段才是真没动。起步或刹停那一段的一端还带着速度，
    // 位移是真的，不能一起丢掉。
    final bool stationary = _isStationaryPoint(a) && _isStationaryPoint(b);
    if (segment <= 0 || stationary) {
      // 断点/跳变，或停着不动：锚点跟到当前点，这一段不记。
      anchor = b.hasPosition ? b : null;
      continue;
    }
    anchor ??= a;
    final TrackPoint from = anchor;
    final double d = haversineMeters(from.lat!, from.lon!, b.lat!, b.lon!);
    if (d < kDistanceNoiseFloorM) continue;
    total += d;
    anchor = b;
  }
  return total;
}

/// 该点是否按静止死区判定为「没在动」。速度为 0 的点（落盘前已过死区）即静止。
bool _isStationaryPoint(TrackPoint p) =>
    p.speedMps != null && p.speedMps! < kSpeedDeadbandEnterMps;
