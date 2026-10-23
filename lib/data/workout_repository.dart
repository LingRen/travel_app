import '../domain/analysis/summary.dart';
import '../domain/models/activity_type.dart';
import '../domain/models/track_point.dart';
import '../domain/models/workout.dart';
import '../domain/models/workout_status.dart';
import '../domain/models/workout_summary.dart';
import 'db/track_point_dao.dart';
import 'db/workout_dao.dart';
import 'settings_repository.dart';

/// 运动数据的统一入口：组合 DAO 与 domain 分析层，供上层调用。
class WorkoutRepository {
  WorkoutRepository({
    required this._workouts,
    required this._points,
    required this._settings,
    this.onWorkoutDataChanged,
  });

  final WorkoutDao _workouts;
  final TrackPointDao _points;
  final SettingsRepository _settings;

  /// 「已完成运动」集合或某条已完成记录的内容发生变化时的回调。
  ///
  /// 装配层（`app/providers.dart`）用它递增数据版本号，让历史页、统计页、
  /// 详情页那些一次性取数的 `FutureProvider` 缓存失效——否则结算保存后
  /// 切回历史页仍是旧列表，必须杀进程重启才看得到新记录。
  ///
  /// 只在结束/结算/改标题/删除时触发：记录中的追加写（`appendPoints`、
  /// `setStatus`）不影响已完成列表，不该每次落盘都把历史页重新查一遍库。
  final void Function()? onWorkoutDataChanged;

  /// 新建一条进行中的运动记录。
  Future<Workout> startWorkout({
    required int startedAtMs,
    ActivityType activityType = ActivityType.cycling,
    String? hrDeviceName,
    String? cadenceDeviceName,
    String? powerDeviceName,
  }) async {
    final int id = await _workouts.insert(Workout(
      startedAtMs: startedAtMs,
      status: WorkoutStatus.recording,
      activityType: activityType,
      hrDeviceName: hrDeviceName,
      cadenceDeviceName: cadenceDeviceName,
      powerDeviceName: powerDeviceName,
    ));
    return Workout(
      id: id,
      startedAtMs: startedAtMs,
      status: WorkoutStatus.recording,
      activityType: activityType,
      hrDeviceName: hrDeviceName,
      cadenceDeviceName: cadenceDeviceName,
      powerDeviceName: powerDeviceName,
    );
  }

  Future<void> appendPoints(int rideId, List<TrackPoint> points) =>
      _points.insertBatch(points);

  Future<void> setStatus(int rideId, WorkoutStatus status) =>
      _workouts.updateStatus(rideId, status);

  /// 正常结束：用会话给出的时长（不含暂停）计算汇总。
  Future<WorkoutSummary> finishRide(
    int rideId, {
    required int endedAtMs,
    required int durationS,
  }) async {
    final List<TrackPoint> points = await _points.listByRide(rideId);
    final AppSettings settings = await _settings.load();
    final WorkoutSummary summary = computeSummary(
      points: points,
      durationS: durationS,
      maxHeartRate: settings.maxHeartRate,
      weightKg: settings.weightKg,
    );
    await _workouts.markFinished(id: rideId, endedAtMs: endedAtMs, summary: summary);
    onWorkoutDataChanged?.call();
    return summary;
  }

  /// 崩溃恢复时选择「结算」：只用已有轨迹点推算，时长取末点与首点之差。
  Future<WorkoutSummary> settleRide(int rideId) async {
    final Workout? ride = await _workouts.findById(rideId);
    if (ride == null) {
      throw ArgumentError('运动记录不存在: $rideId');
    }
    final List<TrackPoint> points = await _points.listByRide(rideId);
    final AppSettings settings = await _settings.load();

    final int endedAtMs = points.isEmpty ? ride.startedAtMs : points.last.tMs;
    final int durationS =
        points.length < 2 ? 0 : ((points.last.tMs - points.first.tMs) / 1000).round();

    final WorkoutSummary summary = computeSummary(
      points: points,
      durationS: durationS,
      maxHeartRate: settings.maxHeartRate,
      weightKg: settings.weightKg,
    );
    await _workouts.markFinished(id: rideId, endedAtMs: endedAtMs, summary: summary);
    onWorkoutDataChanged?.call();
    return summary;
  }

  Future<List<Workout>> findUnfinished() => _workouts.findUnfinished();

  Future<List<Workout>> listFinished({
    int? limit,
    int? offset,
    ActivityType? activityType,
  }) =>
      _workouts.listFinished(
        limit: limit,
        offset: offset,
        activityType: activityType,
      );

  Future<Workout?> getWorkout(int id) => _workouts.findById(id);

  Future<List<TrackPoint>> getPoints(int rideId) => _points.listByRide(rideId);

  Future<TrackPoint?> lastPoint(int rideId) => _points.lastByRide(rideId);

  Future<void> updateTitle(int rideId, String? title) async {
    await _workouts.updateTitle(rideId, title);
    onWorkoutDataChanged?.call();
  }

  Future<void> deleteRide(int rideId) async {
    await _points.deleteByRide(rideId);
    await _workouts.delete(rideId);
    onWorkoutDataChanged?.call();
  }
}
