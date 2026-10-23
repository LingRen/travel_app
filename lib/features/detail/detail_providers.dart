import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../app/providers.dart';
import '../../data/workout_repository.dart';
import '../../domain/models/track_point.dart';
import '../../domain/models/workout.dart';

/// 详情页需要的数据：运动本身 + 它的全部轨迹点。
class WorkoutDetail {
  const WorkoutDetail({required this.ride, required this.points});

  final Workout ride;
  final List<TrackPoint> points;
}

/// 按 rideId 取详情。用 family 让每个详情页各自缓存。
final FutureProviderFamily<WorkoutDetail, int> rideDetailProvider =
    FutureProvider.family<WorkoutDetail, int>((Ref ref, int rideId) async {
  // 依赖数据版本号：改标题、删除、恢复备份后详情页要反映最新内容。
  ref.watch(rideDataRevisionProvider);
  final WorkoutRepository repo = ref.watch(workoutRepositoryProvider);
  final Workout? ride = await repo.getWorkout(rideId);
  if (ride == null) {
    throw StateError('运动记录不存在：$rideId');
  }
  return WorkoutDetail(ride: ride, points: await repo.getPoints(rideId));
});
