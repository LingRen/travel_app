import 'dart:math' as math;

import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/analysis/geo.dart';
import 'package:cycling_app/domain/models/location_fix.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/recording/track_point_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 纬度 1 度约 111320 米，故 0.0001 度约 11.13 米、0.00001 度约 1.11 米。
  TrackPoint pointAt(int tMs, double lat, double lon) =>
      TrackPoint(rideId: 1, tMs: tMs, lat: lat, lon: lon);

  /// 同经度时 haversine 退化为 `2R·asin(|sin(Δφ/2)|)`，这里按解析式反解出
  /// 对应 [meters] 米的纬度偏移（度）。
  ///
  /// 注意：只有从赤道纬度 0.0 出发时，`0.0 + 偏移` 的浮点舍入才恰好让
  /// haversine 得到与 [kMinWriteDistanceM] 完全相等的值（见下方边界用例的
  /// 精确断言），因此边界用例一律以纬度 0.0 为起点。
  double latOffsetDeg(double meters) =>
      2 * math.asin(math.sin(meters / (2 * kEarthRadiusM))) * 180.0 / math.pi;

  /// 在纬度 [lat0] 处、沿经度方向相距约 [meters] 米的经度偏移（度）。
  ///
  /// 用于验证距离计算按纬度收缩：纬度 [lat0] 处同样的经度差对应更短的地面
  /// 距离，若把 lat/lon 传反，算出的距离会偏大 [1/cos(lat0)] 倍。
  double lonOffsetDeg(double lat0, double meters) =>
      meters / (kEarthRadiusM * math.cos(lat0 * math.pi / 180)) * 180.0 / math.pi;

  group('shouldWriteTrackPoint', () {
    test('没有上一点时写入', () {
      const LocationFix fix = LocationFix(tMs: 1000, lat: 31.0, lon: 121.0);
      expect(shouldWriteTrackPoint(lastWritten: null, fix: fix), isTrue);
    });

    test('距离达到 5 米时写入', () {
      final TrackPoint last = pointAt(0, 31.0, 121.0);
      const LocationFix fix = LocationFix(tMs: 1000, lat: 31.0001, lon: 121.0);
      expect(shouldWriteTrackPoint(lastWritten: last, fix: fix), isTrue);
    });

    test('距离恰为阈值时写入（边界含等号）', () {
      final TrackPoint last = pointAt(0, 0.0, 0.0);
      final LocationFix fix = LocationFix(
        tMs: 1000,
        lat: latOffsetDeg(kMinWriteDistanceM),
        lon: 0.0,
      );
      final double d =
          haversineMeters(last.lat!, last.lon!, fix.lat!, fix.lon!);
      expect(d, kMinWriteDistanceM, reason: '构造出的距离应恰在阈值上，实测 $d 米');
      expect(shouldWriteTrackPoint(lastWritten: last, fix: fix), isTrue);
    });

    test('距离与时间都不足时不写入', () {
      final TrackPoint last = pointAt(0, 31.0, 121.0);
      const LocationFix fix = LocationFix(tMs: 1000, lat: 31.00001, lon: 121.0);
      expect(shouldWriteTrackPoint(lastWritten: last, fix: fix), isFalse);
    });

    test('距离略小于阈值且时间不足时不写入', () {
      final TrackPoint last = pointAt(0, 0.0, 0.0);
      final LocationFix fix = LocationFix(
        tMs: 1000,
        lat: latOffsetDeg(kMinWriteDistanceM - 0.1),
        lon: 0.0,
      );
      final double d =
          haversineMeters(last.lat!, last.lon!, fix.lat!, fix.lon!);
      expect(d, lessThan(kMinWriteDistanceM), reason: '实测 $d 米');
      expect(shouldWriteTrackPoint(lastWritten: last, fix: fix), isFalse);
    });

    test('高纬度下经度距离按纬度收缩（lat/lon 不能传反）', () {
      // 60°N 处同样的经度差对应约一半的地面距离：真实距离约 4 米（不足阈值），
      // 若把 lat/lon 传反则按赤道尺度算出约 8 米而误判为「该写入」。
      const double lat0 = 60.0;
      final TrackPoint last = pointAt(0, lat0, 0.0);
      final LocationFix fix = LocationFix(
        tMs: 1000,
        lat: lat0,
        lon: lonOffsetDeg(lat0, 4.0),
      );
      final double d =
          haversineMeters(last.lat!, last.lon!, fix.lat!, fix.lon!);
      expect(d, closeTo(4.0, 0.05), reason: '实测 $d 米');
      expect(d, lessThan(kMinWriteDistanceM));
      expect(shouldWriteTrackPoint(lastWritten: last, fix: fix), isFalse);
    });

    test('距离不足但间隔达到 2 秒时写入', () {
      final TrackPoint last = pointAt(0, 31.0, 121.0);
      const LocationFix fix = LocationFix(tMs: 2000, lat: 31.0, lon: 121.0);
      expect(shouldWriteTrackPoint(lastWritten: last, fix: fix), isTrue);
    });

    test('没有定位的点不写入', () {
      const LocationFix fix = LocationFix(tMs: 2000);
      expect(shouldWriteTrackPoint(lastWritten: null, fix: fix), isFalse);
    });

    test('时间倒退不写入', () {
      final TrackPoint last = pointAt(5000, 31.0, 121.0);
      const LocationFix fix = LocationFix(tMs: 4000, lat: 31.0, lon: 121.0);
      expect(shouldWriteTrackPoint(lastWritten: last, fix: fix), isFalse);
    });

    test('时间未前进（同一时间戳）不写入', () {
      // 同一时间戳却位移 11 米，等价于无穷大速度，属无效采样，不应落盘。
      final TrackPoint last = pointAt(0, 31.0, 121.0);
      const LocationFix fix = LocationFix(tMs: 0, lat: 31.0001, lon: 121.0);
      expect(shouldWriteTrackPoint(lastWritten: last, fix: fix), isFalse);
    });

    test('上一点没有坐标时写入', () {
      const TrackPoint last = TrackPoint(rideId: 1, tMs: 0);
      const LocationFix fix = LocationFix(tMs: 1000, lat: 31.0, lon: 121.0);
      expect(shouldWriteTrackPoint(lastWritten: last, fix: fix), isTrue);
    });
  });
}
