import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/analysis/trend.dart';

/// 个人最佳纪录。见设计文档 10.4。
///
/// **跨全部历史统计**，不受周/月/年范围切换影响：个人最佳的意义就是「历史最好」。
///
/// 排成和详情页汇总一样的规格表，但读数用强调色：按主题的用色规则，琥珀色
/// 专给「当前值」和「最佳值」——这一块几个数全是历史峰值，是强调色最该出现
/// 的地方（页面顶部的累计读数因此保持中性色，把强调让出来）。
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
        _row('最大爬升', formatElevation(bests.mostElevationGainM!.value, unit)),
      // 没配功率计时没有这一项：宁可少一行，也不摆一个「0 W」的最佳纪录。
      if (bests.highestPowerW != null)
        _row('最高功率', formatPower(bests.highestPowerW!.value)),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kSpaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: kSpaceM),
            child: Text('个人最佳', style: kSectionTextStyle),
          ),
          if (rows.isEmpty)
            const Text('还没有可统计的记录', style: kMutedTextStyle)
          else
            for (int i = 0; i < rows.length; i++) ...<Widget>[
              if (i > 0) const Divider(height: 1),
              rows[i],
            ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: kSpaceS),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Expanded(child: Text(label, style: kLabelTextStyle)),
            const SizedBox(width: kSpaceM),
            Text(value, style: _bestReadoutStyle),
          ],
        ),
      );
}

/// 峰值读数：等宽 tabular，琥珀色，比一般正文重一档。
const TextStyle _bestReadoutStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontSize: 16,
  fontWeight: FontWeight.w700,
  color: kAppAccent,
  fontFeatures: kTabularFigures,
);