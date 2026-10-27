import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/ui/paper_sheet.dart';
import '../../app/ui/seal.dart';
import '../../domain/models/activity_type.dart';
import 'activity_type_visuals.dart';

/// 历史与统计共用的运动筛选面板。`null` 表示全部运动。
class SportFilterSheet extends StatelessWidget {
  const SportFilterSheet({
    required this.current,
    required this.onSelected,
    super.key,
  });

  final ActivityType? current;
  final ValueChanged<ActivityType?> onSelected;

  @override
  Widget build(BuildContext context) => PaperSheet(
        title: '筛选运动类型',
        subtitle: '查看某一类运动的记录与统计',
        onClose: () => Navigator.of(context).maybePop(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _FilterRow(
              key: const Key('sport-filter-all'),
              seal: '全',
              label: '全部运动',
              description: '所有记录',
              selected: current == null,
              onTap: () {
                onSelected(null);
                Navigator.of(context).maybePop();
              },
            ),
            for (final ActivityType type in ActivityType.values) ...<Widget>[
              const Divider(height: 1),
              _FilterRow(
                key: Key('sport-filter-${type.dbValue}'),
                seal: activityTypeSeal(type),
                label: type.label,
                description: activityTypeDescription(type),
                selected: current == type,
                onTap: () {
                  onSelected(type);
                  Navigator.of(context).maybePop();
                },
              ),
            ],
            const SizedBox(height: kSpaceL),
            const Divider(height: 1),
            const SizedBox(height: kSpaceM),
            Text(
              '筛选仅改变查看范围，不修改数据',
              style: kMutedTextStyle.copyWith(fontSize: 12),
            ),
          ],
        ),
      );
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.seal,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String seal;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: kSpaceM),
            child: Row(
              children: <Widget>[
                Seal(label: seal, filled: selected, size: 44),
                const SizedBox(width: kSpaceL),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(label, style: kSerifHeadingTextStyle),
                      const SizedBox(height: 2),
                      Text(description, style: kMutedTextStyle),
                    ],
                  ),
                ),
                if (selected) ...<Widget>[
                  Text(
                    '当前',
                    style: kLabelTextStyle.copyWith(color: palette.accentInk),
                  ),
                  const SizedBox(width: kSpaceS),
                  Icon(Icons.check, size: 20, color: palette.accentInk),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
