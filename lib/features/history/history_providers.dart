import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider 在 riverpod 3 里只从 legacy 入口导出。
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../app/providers.dart';
import '../../domain/models/activity_type.dart';
import '../../domain/models/track_point.dart';
import '../../domain/models/workout.dart';

/// 历史页当前选中的类型筛选。null = 全部。
final StateProvider<ActivityType?> historyFilterProvider =
    StateProvider<ActivityType?>((Ref ref) => null);

/// 已完成的运动，按开始时间倒序（排序由 `WorkoutDao.listFinished` 保证）。
final FutureProvider<List<Workout>> historyRidesProvider =
    FutureProvider<List<Workout>>((Ref ref) {
  // 依赖数据版本号：结束运动、崩溃结算、改标题、删除、恢复备份后自动重查。
  ref.watch(rideDataRevisionProvider);
  final ActivityType? filter = ref.watch(historyFilterProvider);
  return ref.watch(workoutRepositoryProvider).listFinished(activityType: filter);
});

/// 某次骑行的轨迹点，供卡片上的迷你曲线使用。
///
/// 用 family 而不是一次取全部点：列表是懒加载的，不可见的卡片不会触发查询，
/// 记录多起来之后不会一次把所有轨迹点读进内存。
final FutureProviderFamily<List<TrackPoint>, int> ridePointsProvider =
    FutureProvider.family<List<TrackPoint>, int>((Ref ref, int rideId) {
  ref.watch(rideDataRevisionProvider);
  return ref.watch(workoutRepositoryProvider).getPoints(rideId);
});
