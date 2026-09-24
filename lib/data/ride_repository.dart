import '../domain/analysis/summary.dart';
import '../domain/models/ride.dart';
import '../domain/models/ride_status.dart';
import '../domain/models/ride_summary.dart';
import '../domain/models/track_point.dart';
import 'db/ride_dao.dart';
import 'db/track_point_dao.dart';
import 'settings_repository.dart';

/// 骑行数据的统一入口：组合 DAO 与 domain 分析层，供上层调用。
class RideRepository {
  RideRepository({
    required this._rides,
    required this._points,
    required this._settings,
    this.onRideDataChanged,
  });

  final RideDao _rides;
  final TrackPointDao _points;
  final SettingsRepository _settings;

  /// 「已完成骑行」集合或某条已完成记录的内容发生变化时的回调。
  ///
  /// 装配层（`app/providers.dart`）用它递增数据版本号，让历史页、统计页、
  /// 详情页那些一次性取数的 `FutureProvider` 缓存失效——否则结算保存后
  /// 切回历史页仍是旧列表，必须杀进程重启才看得到新记录。
  ///
  /// 只在结束/结算/改标题/删除时触发：记录中的追加写（`appendPoints`、
  /// `setStatus`）不影响已完成列表，不该每次落盘都把历史页重新查一遍库。
  final void Function()? onRideDataChanged;

  /// 新建一条进行中的骑行记录。
  Future<Ride> startRide({
    required int startedAtMs,
    String? hrDeviceName,
    String? cadenceDeviceName,
    String? powerDeviceName,
  }) async {
    final int id = await _rides.insert(Ride(
      startedAtMs: startedAtMs,
      status: RideStatus.recording,
      hrDeviceName: hrDeviceName,
      cadenceDeviceName: cadenceDeviceName,
      powerDeviceName: powerDeviceName,
    ));
    return Ride(
      id: id,
      startedAtMs: startedAtMs,
      status: RideStatus.recording,
      hrDeviceName: hrDeviceName,
      cadenceDeviceName: cadenceDeviceName,
      powerDeviceName: powerDeviceName,
    );
  }

  Future<void> appendPoints(int rideId, List<TrackPoint> points) =>
      _points.insertBatch(points);

  Future<void> setStatus(int rideId, RideStatus status) => _rides.updateStatus(rideId, status);

  /// 正常结束：用会话给出的时长（不含暂停）计算汇总。
  Future<RideSummary> finishRide(
    int rideId, {
    required int endedAtMs,
    required int durationS,
  }) async {
    final List<TrackPoint> points = await _points.listByRide(rideId);
    final AppSettings settings = await _settings.load();
    final RideSummary summary = computeSummary(
      points: points,
      durationS: durationS,
      maxHeartRate: settings.maxHeartRate,
      weightKg: settings.weightKg,
    );
    await _rides.markFinished(id: rideId, endedAtMs: endedAtMs, summary: summary);
    onRideDataChanged?.call();
    return summary;
  }

  /// 崩溃恢复时选择「结算」：只用已有轨迹点推算，时长取末点与首点之差。
  Future<RideSummary> settleRide(int rideId) async {
    final Ride? ride = await _rides.findById(rideId);
    if (ride == null) {
      throw ArgumentError('骑行记录不存在: $rideId');
    }
    final List<TrackPoint> points = await _points.listByRide(rideId);
    final AppSettings settings = await _settings.load();

    final int endedAtMs = points.isEmpty ? ride.startedAtMs : points.last.tMs;
    final int durationS =
        points.length < 2 ? 0 : ((points.last.tMs - points.first.tMs) / 1000).round();

    final RideSummary summary = computeSummary(
      points: points,
      durationS: durationS,
      maxHeartRate: settings.maxHeartRate,
      weightKg: settings.weightKg,
    );
    await _rides.markFinished(id: rideId, endedAtMs: endedAtMs, summary: summary);
    onRideDataChanged?.call();
    return summary;
  }

  Future<List<Ride>> findUnfinished() => _rides.findUnfinished();

  Future<List<Ride>> listFinished({int? limit, int? offset}) =>
      _rides.listFinished(limit: limit, offset: offset);

  Future<Ride?> getRide(int id) => _rides.findById(id);

  Future<List<TrackPoint>> getPoints(int rideId) => _points.listByRide(rideId);

  Future<TrackPoint?> lastPoint(int rideId) => _points.lastByRide(rideId);

  Future<void> updateTitle(int rideId, String? title) async {
    await _rides.updateTitle(rideId, title);
    onRideDataChanged?.call();
  }

  Future<void> deleteRide(int rideId) async {
    await _points.deleteByRide(rideId);
    await _rides.delete(rideId);
    onRideDataChanged?.call();
  }
}
