import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider 在 riverpod 3 里只从 legacy 入口导出。
import 'package:flutter_riverpod/legacy.dart';

import '../../app/providers.dart';
import '../../domain/analysis/trend.dart';
import '../../domain/models/ride.dart';

/// 全部已完成的骑行。统计页在内存里按范围聚合，不每次查库。
///
/// 个人记录量级（几百到几千条）下这完全够用；真到几万条再考虑下推到 SQL。
final FutureProvider<List<Ride>> finishedRidesProvider =
    FutureProvider<List<Ride>>(
  (Ref ref) => ref.watch(rideRepositoryProvider).listFinished(),
);

/// 当前选中的统计范围。见设计文档 10.4。
final StateProvider<TrendRange> trendRangeProvider =
    StateProvider<TrendRange>((Ref ref) => TrendRange.week);
