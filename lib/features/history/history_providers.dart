import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../app/providers.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';

/// 已完成的骑行，按开始时间倒序（排序由 `RideDao.listFinished` 保证）。
final FutureProvider<List<Ride>> historyRidesProvider =
    FutureProvider<List<Ride>>(
  (Ref ref) => ref.watch(rideRepositoryProvider).listFinished(),
);

/// 某次骑行的轨迹点，供卡片上的迷你曲线使用。
///
/// 用 family 而不是一次取全部点：列表是懒加载的，不可见的卡片不会触发查询，
/// 记录多起来之后不会一次把所有轨迹点读进内存。
final FutureProviderFamily<List<TrackPoint>, int> ridePointsProvider =
    FutureProvider.family<List<TrackPoint>, int>(
  (Ref ref, int rideId) => ref.watch(rideRepositoryProvider).getPoints(rideId),
);
