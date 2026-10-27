import '../../domain/models/workout.dart';

/// 历史列表里的一个月分组。见设计文档 10.2 / 11。
class HistoryMonthGroup {
  const HistoryMonthGroup({required this.month, required this.rides});

  /// 该月第一天（本地时区），用于页眉年月与分组标题。
  final DateTime month;

  /// 该月记录，按开始时间倒序。
  final List<Workout> rides;
}

/// 按「最近有记录的月份」分组，组内与组间都按时间倒序。
///
/// 历史页只在本机内存里做分组，不写 SQL 分页：记录量级小，先把筛选后的列表
/// 取回来再切月，首屏只渲染最近一个月，其余等用户点「更早的记录」。
List<HistoryMonthGroup> groupRidesByMonth(List<Workout> rides) {
  final Map<String, List<Workout>> buckets = <String, List<Workout>>{};
  for (final Workout ride in rides) {
    final DateTime t =
        DateTime.fromMillisecondsSinceEpoch(ride.startedAtMs);
    final String key = '${t.year}-${t.month}';
    (buckets[key] ??= <Workout>[]).add(ride);
  }

  final List<HistoryMonthGroup> groups = <HistoryMonthGroup>[
    for (final List<Workout> bucket in buckets.values)
      HistoryMonthGroup(
        month: DateTime(
          DateTime.fromMillisecondsSinceEpoch(bucket.first.startedAtMs).year,
          DateTime.fromMillisecondsSinceEpoch(bucket.first.startedAtMs).month,
        ),
        rides: bucket.toList()
          ..sort((Workout a, Workout b) => b.startedAtMs.compareTo(a.startedAtMs)),
      ),
  ];
  groups.sort((HistoryMonthGroup a, HistoryMonthGroup b) =>
      b.month.compareTo(a.month));
  return groups;
}
