import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/ui/page_header.dart';
import '../../app/ui/paper_sheet.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/models/activity_type.dart';
import '../../domain/models/workout.dart';
import '../activity/sport_filter_sheet.dart';
import '../activity/sport_filter_trigger.dart';
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
    final List<Workout>? list = rides.value;
    final double totalM = list == null
        ? 0
        : list.fold<double>(
            0,
            (double sum, Workout ride) => sum + (ride.summary?.distanceM ?? 0),
          );
    final DateTime now =
        DateTime.fromMillisecondsSinceEpoch(ref.read(nowProvider)());

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            PageHeader(
              eyebrow: '运 动 日 志',
              date: formatChineseYearMonth(now),
              title: '行迹',
              trailing: list == null
                  ? null
                  : Text('共 ${list.length} 次', style: kLabelTextStyle),
              subtitle: list == null
                  ? null
                  : '${filter == null ? '全部记录' : '${filter.label}记录'} · '
                      '${formatDistance(totalM, unit)}',
              subtitleTrailing: SportFilterTrigger(
                current: filter,
                onTap: () => showPaperSheet<void>(
                  context: context,
                  builder: (_) => SportFilterSheet(
                    current: filter,
                    onSelected: (ActivityType? type) =>
                        ref.read(historyFilterProvider.notifier).state = type,
                  ),
                ),
              ),
            ),
            const Divider(height: 1, indent: kSpaceXl, endIndent: kSpaceXl),
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
                        style: kMutedTextStyle,
                      ),
                    );
                  }
                  // 条目之间用细线分隔：线从内容左边缘起、右侧留白，与条目左右的内边距
                  // 同宽。条目内部不再画线，所以每一行只有这一道。
                  return ListView.separated(
                    padding: EdgeInsets.zero,
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
      ),
    );
  }
}
