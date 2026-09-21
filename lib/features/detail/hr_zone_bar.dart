import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/analysis/heart_rate.dart';

/// 心率区间分布条。见设计文档 10.3 的第 4 块与 8.2 的区间定义。
class HrZoneBar extends StatelessWidget {
  const HrZoneBar({required this.breakdown, super.key});

  final HrZoneBreakdown breakdown;

  /// 各区间在条上的颜色，由慢到快。
  static const List<Color> zoneColors = <Color>[
    Color(0xFF64B5F6),
    Color(0xFF4CAF50),
    Color(0xFFFFB300),
    Color(0xFFFB8C00),
    Color(0xFFB71C1C),
  ];

  @override
  Widget build(BuildContext context) {
    if (breakdown.totalSeconds <= 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('这次骑行没有心率数据'),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 14,
              child: Row(
                children: <Widget>[
                  for (final HrZone zone in kHrZones)
                    if (breakdown.ratioOf(zone.index) > 0)
                      Expanded(
                        // flex 至少为 1：占比小到 flex 取整成 0 时，`Expanded` 会被
                        // 当成非弹性子节点、量出零宽而整个区间从条上消失
                        // （已实测：0.05% 的区间宽度 0.0px，且无任何断言/异常）。
                        flex: math.max(1, (breakdown.ratioOf(zone.index) * 1000).round()),
                        child: ColoredBox(color: zoneColors[zone.index - 1]),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: <Widget>[
              for (final HrZone zone in kHrZones)
                Text(
                  '${zone.label} ${(breakdown.ratioOf(zone.index) * 100).round()}%'
                  ' · ${breakdown.secondsByZone[zone.index]?.round() ?? 0}s',
                  style: TextStyle(
                    fontSize: 12,
                    color: zoneColors[zone.index - 1],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
