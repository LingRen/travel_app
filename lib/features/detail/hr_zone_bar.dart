import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/analysis/heart_rate.dart';

/// 心率区间分布条。见设计文档 10.3 的第 4 块与 8.2 的区间定义。
///
/// 五段颜色是数据色（由冷到热就是区间本身的含义），不跟着主题的强调色走；
/// 但方块本身不带圆角修饰，底色由细线兜住，与页面的器件语言一致。
class HrZoneBar extends StatelessWidget {
  const HrZoneBar({required this.breakdown, super.key});

  final HrZoneBreakdown breakdown;

  /// 各区间在条上的颜色，由慢到快。
  ///
  /// Z5 用深墨褐而不是正红：朱砂是默认主题色，心率曲线与轨迹都用它绘制，
  /// 正红 Z5 会和朱砂线在纸底上糊成同一条；深墨褐既保留「最高区间」的
  /// 重量感，又与朱砂拉开明度。设计稿的 Z5 也是近墨色。
  static const List<Color> zoneColors = <Color>[
    Color(0xFF64B5F6),
    Color(0xFF4CAF50),
    Color(0xFFFFB300),
    Color(0xFFFB8C00),
    Color(0xFF3A2B25),
  ];

  @override
  Widget build(BuildContext context) {
    if (breakdown.totalSeconds <= 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: kSpaceL),
        child: Text('没有心率数据', style: kMutedTextStyle),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kSpaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border.fromBorderSide(kHairline),
            ),
            // 边框画在前景：色块撑满 14dp 之后会把默认画在背景里的那圈细线整个
            // 盖住，条就从「细线兜住的色块」变成一条没边框的实心条，丢掉这块
            // 本来的器件语言。
            position: DecorationPosition.foreground,
            child: SizedBox(
              height: 14,
              child: Row(
                // 必须 stretch（真机实测漏了这一条）：`ColoredBox` 没有子节点，
                // 在松高度约束下按 `constraints.smallest` 量出 0 高度，整条只剩
                // 外面那圈细线边框——图例写着 Z1 41%/Z2 29%/Z3 30%，条上却一片
                // 空白。stretch 把每段拉到 14dp 满高，宽度仍然由 flex 决定。
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final HrZone zone in kHrZones)
                    if (breakdown.ratioOf(zone.index) > 0)
                      Expanded(
                        // flex 至少为 1：占比小到 flex 取整成 0 时，`Expanded` 会被
                        // 当成非弹性子节点、量出零宽而整个区间从条上消失
                        // （已实测：0.05% 的区间宽度 0.0px，且无任何断言/异常）。
                        flex: math.max(
                          1,
                          (breakdown.ratioOf(zone.index) * 1000).round(),
                        ),
                        child: ColoredBox(color: zoneColors[zone.index - 1]),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: kSpaceS),
          Wrap(
            spacing: kSpaceM,
            runSpacing: kSpaceXs,
            children: <Widget>[
              for (final HrZone zone in kHrZones)
                Text(
                  '${zone.label} ${(breakdown.ratioOf(zone.index) * 100).round()}%'
                  ' · ${breakdown.secondsByZone[zone.index]?.round() ?? 0}s',
                  style: TextStyle(
                    fontFamily: kMonoFamily,
                    fontSize: kFontLabel,
                    color: zoneColors[zone.index - 1],
                    fontFeatures: kTabularFigures,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
