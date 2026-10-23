import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider 在 riverpod 3 里只从 legacy 入口导出。
import 'package:flutter_riverpod/legacy.dart';

import '../../app/providers.dart';
import '../../domain/analysis/trend.dart';
import '../../domain/models/activity_type.dart';
import '../../domain/models/workout.dart';

/// 统计页当前选中的类型筛选。null = 全部。
final StateProvider<ActivityType?> statsFilterProvider =
    StateProvider<ActivityType?>((Ref ref) => null);

/// 全部已完成的运动。统计页在内存里按范围聚合，不每次查库。
///
/// 个人记录量级（几百到几千条）下这完全够用；真到几万条再考虑下推到 SQL。
final FutureProvider<List<Workout>> finishedRidesProvider =
    FutureProvider<List<Workout>>((Ref ref) {
  // 依赖数据版本号：结束运动、崩溃结算、删除、恢复备份后自动重查。
  ref.watch(rideDataRevisionProvider);
  final ActivityType? filter = ref.watch(statsFilterProvider);
  return ref.watch(workoutRepositoryProvider).listFinished(activityType: filter);
});

/// 当前选中的统计范围。见设计文档 10.4。
final StateProvider<TrendRange> trendRangeProvider =
    StateProvider<TrendRange>((Ref ref) => TrendRange.week);
