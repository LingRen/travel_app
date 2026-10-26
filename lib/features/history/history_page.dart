import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/settings_repository.dart';
import '../../domain/models/activity_type.dart';
import '../../domain/models/workout.dart';
import '../detail/detail_page.dart';
import 'history_providers.dart';
import 'ride_card.dart';

/// 历史列表页。见设计文档 10.2。
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Workout>> rides = ref.watch(historyRidesProvider);
    final ActivityType? filter = ref.watch(historyFilterProvider);
    final DistanceUnit unit =
        ref.watch(appSettingsProvider).value?.distanceUnit ??
            DistanceUnit.kilometer;

    return Scaffold(
      appBar: AppBar(title: const Text('历史')),
      body: Column(
        children: <Widget>[
          // 类型筛选条。null = 全部。选中态读写 `historyFilterProvider`，
          // 列表 provider 跟着它重查。
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceM, kSpaceL, 0),
            child: SegmentedButton<ActivityType?>(
              segments: <ButtonSegment<ActivityType?>>[
                const ButtonSegment<ActivityType?>(
                  value: null,
                  label: Text('全部'),
                ),
                for (final ActivityType t in ActivityType.values)
                  ButtonSegment<ActivityType?>(value: t, label: Text(t.label)),
              ],
              selected: <ActivityType?>{filter},
              onSelectionChanged: (Set<ActivityType?> selected) =>
                  ref.read(historyFilterProvider.notifier).state = selected.first,
              showSelectedIcon: false,
            ),
          ),
          Expanded(
            child: rides.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace stack) =>
                  Center(child: Text('读取记录失败：$error')),
              data: (List<Workout> list) {
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      filter == null ? '还没有运动记录' : '还没有${filter.label}记录',
                    ),
                  );
                }
                // 条目之间用细线分隔：线从内容左边缘起、右侧留白，与条目左右的内边距
                // 同宽。条目内部不再画线，所以每一行只有这一道。
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const Divider(
                    height: 1,
                    indent: kSpaceL,
                    endIndent: kSpaceL,
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final Workout ride = list[index];
                    final int? id = ride.id;
                    return WorkoutCard(
                      ride: ride,
                      unit: unit,
                      onTap: id == null
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (BuildContext context) =>
                                      DetailPage(rideId: id),
                                ),
                              ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
