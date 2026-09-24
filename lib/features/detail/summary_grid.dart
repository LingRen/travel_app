import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/ride_summary.dart';

/// 规格表的一行：量名与读数。
typedef SpecEntry = (String label, String value);

/// 基础信息规格表。见设计文档 10.3 的第 2 块。
///
/// 原来是 104px 的方块网格：十二个指标铺成几行方块，左对齐的标签配上大号
/// 绿色数字，读起来像一堆并列的仪表盘贴纸，但方块宽度固定、数值长短不一，
/// 数字既对不齐也排不成列。改成规格表后标签在左、数值在右，数值是等宽
/// tabular 数字，纵向自然成列——想比两次骑行的均速时，扫同一列就行。
/// 行与行之间用细线分开，而不是靠间距，这是仪表说明书的读法。
///
/// 这里只放**没有曲线可配**的那些量（距离、时长、爬升……）。速度、心率、
/// 踏频、功率的读数跟着各自的曲线走，见 [SpecList] 与详情页的曲线区块。
class SummaryGrid extends StatelessWidget {
  const SummaryGrid({required this.ride, required this.unit, super.key});

  final Ride ride;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) {
    final RideSummary? s = ride.summary;
    if (s == null) {
      return const Padding(
        padding: EdgeInsets.all(kSpaceL),
        child: Text('这条记录还没有汇总指标', style: kMutedTextStyle),
      );
    }

    final List<SpecEntry> entries = <SpecEntry>[
      ('距离', formatDistance(s.distanceM, unit)),
      ('时长', formatDuration(s.durationS)),
      ('移动时长', formatDuration(s.movingS)),
      ('爬升', formatElevation(s.elevationGainM, unit)),
      if (s.calories != null) ('卡路里', '${s.calories!.round()} kcal（参考）'),
      ('轨迹点', '${s.pointCount}'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceL, kSpaceL, 0),
      child: SpecList(entries: entries),
    );
  }
}

/// 细线分隔的规格表。
///
/// 详情页的基础信息块与每条曲线的读数块共用同一套排版：量名在左、读数在右，
/// 行间一条细线。抽出来是为了让「一屏里六处读数」长得完全一样，不必各自
/// 复制一遍 Row + Divider。
class SpecList extends StatelessWidget {
  const SpecList({required this.entries, super.key});

  final List<SpecEntry> entries;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          for (int i = 0; i < entries.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 1),
            _SpecRow(entry: entries[i]),
          ],
        ],
      );
}

/// 一行规格：左边是量名，右边是读数。行高由读数决定，标签不参与撑高，
/// 这样即便标签换行也不会把某一行顶得比别人胖。
class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.entry});

  final SpecEntry entry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: kSpaceS),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Expanded(child: Text(entry.$1, style: kLabelTextStyle)),
            const SizedBox(width: kSpaceM),
            Text(entry.$2, style: _readoutStyle),
          ],
        ),
      );
}

/// 规格表里读数比仪表主数字收一档，一屏能容下十几行而不显得吵。
const TextStyle _readoutStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontSize: 18,
  fontWeight: FontWeight.w600,
  height: 1.1,
  color: kAppTextPrimary,
  fontFeatures: kTabularFigures,
);