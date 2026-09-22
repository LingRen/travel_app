import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../app/providers.dart';
import '../../data/ride_repository.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';

/// 详情页需要的数据：骑行本身 + 它的全部轨迹点。
class RideDetail {
  const RideDetail({required this.ride, required this.points});

  final Ride ride;
  final List<TrackPoint> points;
}

/// 按 rideId 取详情。用 family 让每个详情页各自缓存。
final FutureProviderFamily<RideDetail, int> rideDetailProvider =
    FutureProvider.family<RideDetail, int>((Ref ref, int rideId) async {
  // 依赖数据版本号：改标题、删除、恢复备份后详情页要反映最新内容。
  ref.watch(rideDataRevisionProvider);
  final RideRepository repo = ref.watch(rideRepositoryProvider);
  final Ride? ride = await repo.getRide(rideId);
  if (ride == null) {
    throw StateError('骑行记录不存在：$rideId');
  }
  return RideDetail(ride: ride, points: await repo.getPoints(rideId));
});
