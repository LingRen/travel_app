import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/settings_repository.dart';
import '../../domain/models/ride.dart';
import '../detail/detail_page.dart';
import 'history_providers.dart';
import 'ride_card.dart';

/// 历史列表页。见设计文档 10.2。
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Ride>> rides = ref.watch(historyRidesProvider);
    final DistanceUnit unit =
        ref.watch(appSettingsProvider).value?.distanceUnit ??
            DistanceUnit.kilometer;

    return Scaffold(
      appBar: AppBar(title: const Text('历史')),
      body: rides.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            Center(child: Text('读取记录失败：$error')),
        data: (List<Ride> list) {
          if (list.isEmpty) {
            return const Center(child: Text('还没有骑行记录'));
          }
          // 条目之间用细线分隔：线从内容左边缘起、右侧留白，和条目内部
          // 分隔读数与缩略曲线的那条线同宽，纵向看是一排整齐的刻度。
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (BuildContext context, int index) => const Divider(
              height: 1,
              indent: kSpaceL,
              endIndent: kSpaceL,
            ),
            itemBuilder: (BuildContext context, int index) {
              final Ride ride = list[index];
              final int? id = ride.id;
              return RideCard(
                ride: ride,
                unit: unit,
                onTap: id == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) => DetailPage(rideId: id),
                          ),
                        ),
              );
            },
          );
        },
      ),
    );
  }
}
