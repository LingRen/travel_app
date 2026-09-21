import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/trend.dart';

/// 个人最佳纪录卡片。见设计文档 10.4。
///
/// **跨全部历史统计**，不受周/月/年范围切换影响：个人最佳的意义就是「历史最好」。
class PersonalBestsCard extends StatelessWidget {
  const PersonalBestsCard({required this.bests, required this.unit, super.key});

  final PersonalBests bests;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[
      if (bests.longestDistanceM != null)
        _row('最远距离', formatDistance(bests.longestDistanceM!.value, unit)),
      if (bests.longestDurationS != null)
        _row('最长时长', formatDuration(bests.longestDurationS!.value.round())),
      if (bests.fastestMovingAvgMps != null)
        _row(
          '最快移动均速',
          '${formatSpeedValue(bests.fastestMovingAvgMps!.value, unit)} '
              '${speedUnitLabel(unit)}',
        ),
      if (bests.mostElevationGainM != null)
        _row('最大爬升', '${bests.mostElevationGainM!.value.round()} m'),
    ];

    return Card(
      color: kAppSurface,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '个人最佳',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Text('还没有可统计的记录', style: TextStyle(fontSize: 13))
            else
              ...rows,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kAppAccent,
              ),
            ),
          ],
        ),
      );
}
