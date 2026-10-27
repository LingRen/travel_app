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
import 'history_grouping.dart';
import 'history_providers.dart';
import 'ride_card.dart';

/// 历史列表页。见设计文档 10.2。
///
/// 首屏只渲染最近有记录的月份，底部「更早的记录 · N 次」在内存里展开；
/// 筛选变化时收起展开状态，避免在另一个筛选下看到上一个筛选的旧月份。
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // 筛选一变，展开状态归零；否则用户切到跑步后还停留在「已展开全部」。
    ref.listen<ActivityType?>(historyFilterProvider,
        (ActivityType? _, ActivityType? _) {
      if (mounted && _expanded) setState(() => _expanded = false);
    });

    final AsyncValue<List<Workout>> rides = ref.watch(historyRidesProvider);
    final ActivityType? filter = ref.watch(historyFilterProvider);
    final DistanceUnit unit =
        ref.watch(appSettingsProvider).value?.distanceUnit ??
            DistanceUnit.kilometer;
    final List<Workout>? list = rides.value;
    final List<HistoryMonthGroup> groups =
        list == null ? const <HistoryMonthGroup>[] : groupRidesByMonth(list);
    final DateTime now =
        DateTime.fromMillisecondsSinceEpoch(ref.read(nowProvider)());
    final DateTime displayedMonth =
        groups.isEmpty ? now : groups.first.month;
    final HistoryMonthGroup? latest = groups.isEmpty ? null : groups.first;
    final double monthDistance = latest == null
        ? 0
        : latest.rides.fold<double>(
            0,
            (double sum, Workout ride) => sum + (ride.summary?.distanceM ?? 0),
          );
    final int monthSeconds = latest == null
        ? 0
        : latest.rides.fold<int>(
            0,
            (int sum, Workout ride) => sum + (ride.summary?.durationS ?? 0),
          );
    final ({String value, String unit}) monthDistanceParts =
        formatDistanceParts(monthDistance, unit);
    // 360dp 上「本月」会把最后两个字挤到第二行；日期已经在页眉上，窄屏省略。
    final bool narrow = MediaQuery.sizeOf(context).width < 380;
    final String? subtitle = latest == null
        ? null
        : '${narrow ? '' : '本月 '}${latest.rides.length} 次 · '
            '${monthDistanceParts.value} ${monthDistanceParts.unit} · '
            '${formatChineseDuration(monthSeconds)}';
    final int earlierCount = groups.length <= 1
        ? 0
        : groups.skip(1).fold<int>(
            0,
            (int sum, HistoryMonthGroup group) => sum + group.rides.length,
          );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            PageHeader(
              eyebrow: '运 动 日 志',
              date: formatChineseYearMonth(displayedMonth),
              title: '行迹',
              trailing: list == null
                  ? null
                  : Text('共 ${list.length} 次', style: kLabelTextStyle),
              subtitle: subtitle,
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
            Divider(height: 1, color: context.palette.hairline),
            Expanded(
              child: rides.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object error, StackTrace stack) =>
                    Center(child: Text('读取记录失败：$error')),
                data: (List<Workout> list) {
                  if (list.isEmpty) {
                    return _EmptyHistory(filter: filter);
                  }
                  final List<HistoryMonthGroup> visible =
                      _expanded ? groups : <HistoryMonthGroup>[groups.first];
                  return ListView(
                    padding: EdgeInsets.zero,
                    children: <Widget>[
                      for (int g = 0; g < visible.length; g++) ...<Widget>[
                        if (g > 0) _MonthLabel(group: visible[g]),
                        for (int i = 0; i < visible[g].rides.length; i++) ...<Widget>[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: kSpaceL,
                              endIndent: kSpaceL,
                              color: context.palette.hairline,
                            ),
                          _RideEntry(
                            ride: visible[g].rides[i],
                            unit: unit,
                            highlight: g == 0 && i == 0,
                            onTap: visible[g].rides[i].id == null
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (BuildContext context) =>
                                            DetailPage(
                                          rideId: visible[g].rides[i].id!,
                                        ),
                                      ),
                                    ),
                          ),
                        ],
                      ],
                      if (!_expanded && earlierCount > 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            kSpaceL,
                            kSpaceS,
                            kSpaceL,
                            kSpaceXl,
                          ),
                          child: Center(
                            child: TextButton.icon(
                              key: const Key('history-older'),
                              onPressed: () => setState(() => _expanded = true),
                              icon: const Icon(Icons.expand_more, size: 18),
                              label: Text('更早的记录 · $earlierCount 次'),
                            ),
                          ),
                        ),
                    ],
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

/// 更早月份的标题。最近那个月由页眉承担年月，这里只给展开后的更早分组用。
class _MonthLabel extends StatelessWidget {
  const _MonthLabel({required this.group});

  final HistoryMonthGroup group;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceM, kSpaceL, kSpaceS),
        child: Text(
          formatChineseYearMonth(group.month),
          style: kLabelTextStyle.copyWith(color: context.palette.muted),
        ),
      );
}

class _RideEntry extends StatelessWidget {
  const _RideEntry({
    required this.ride,
    required this.unit,
    required this.highlight,
    this.onTap,
  });

  final Workout ride;
  final DistanceUnit unit;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => WorkoutCard(
        ride: ride,
        unit: unit,
        onTap: onTap,
        highlight: highlight,
      );
}

/// 历史空态。筛选下没有记录时给出「查看全部运动」的回退入口。
class _EmptyHistory extends ConsumerWidget {
  const _EmptyHistory({required this.filter});

  final ActivityType? filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              filter == null ? '还没有运动记录' : '还没有${filter!.label}记录',
              style: kMutedTextStyle,
            ),
            if (filter != null) ...<Widget>[
              const SizedBox(height: kSpaceS),
              TextButton(
                key: const Key('history-show-all'),
                onPressed: () =>
                    ref.read(historyFilterProvider.notifier).state = null,
                child: const Text('查看全部运动'),
              ),
            ],
          ],
        ),
      );
}
