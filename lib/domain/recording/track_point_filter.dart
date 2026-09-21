import '../analysis/constants.dart';
import '../analysis/geo.dart';
import '../models/location_fix.dart';
import '../models/track_point.dart';

/// 设计文档 6.3 规则 1：判断一次定位结果是否应写成轨迹点。
///
/// 距上一点 ≥ [kMinWriteDistanceM]，或距上次写入 ≥ [kMaxWriteIntervalMs]，
/// 满足其一即写入。移动时由距离触发（约 1Hz），静止时由时间触发（约 0.5Hz）。
///
/// GPS 跳变（隐含速度超过 [kMaxPlausibleSpeedMps]）不在这里拦截：跳变点照常
/// 落盘，但 [segmentDistanceMeters] 与移动/静止切分都不会把它计入距离，
/// 地图上的断线渲染由详情页负责（Plan B）。
bool shouldWriteTrackPoint({
  required TrackPoint? lastWritten,
  required LocationFix fix,
}) {
  if (!fix.hasPosition) return false;
  if (lastWritten == null) return true;
  // 上一点是 GPS 丢失期间写下的纯传感器点，定位恢复后立刻补一个轨迹点。
  if (!lastWritten.hasPosition) return true;

  final int dtMs = fix.tMs - lastWritten.tMs;
  if (dtMs <= 0) return false;
  if (dtMs >= kMaxWriteIntervalMs) return true;

  final double d =
      haversineMeters(lastWritten.lat!, lastWritten.lon!, fix.lat!, fix.lon!);
  return d >= kMinWriteDistanceM;
}
