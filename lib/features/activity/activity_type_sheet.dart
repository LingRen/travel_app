import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/ui/paper_sheet.dart';
import '../../app/ui/seal.dart';
import '../../domain/models/activity_type.dart';
import 'activity_type_visuals.dart';

/// 运动类型选择面板。每行一枚印章、类型名、真实能力说明与当前标记。
class ActivityTypeSheet extends StatelessWidget {
  const ActivityTypeSheet({
    required this.current,
    required this.onSelected,
    super.key,
  });

  final ActivityType current;
  final ValueChanged<ActivityType> onSelected;

  @override
  Widget build(BuildContext context) => PaperSheet(
        title: '选择运动',
        subtitle: '选择本次记录的运动 · 开始后锁定',
        onClose: () => Navigator.of(context).maybePop(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < ActivityType.values.length; i++) ...<Widget>[
              if (i > 0) const Divider(height: 1),
              _ActivityTypeRow(
                type: ActivityType.values[i],
                selected: ActivityType.values[i] == current,
                onTap: () {
                  onSelected(ActivityType.values[i]);
                  Navigator.of(context).maybePop();
                },
              ),
            ],
          ],
        ),
      );
}

class _ActivityTypeRow extends StatelessWidget {
  const _ActivityTypeRow({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final ActivityType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: Key('activity-type-${type.dbValue}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: kSpaceM),
            child: Row(
              children: <Widget>[
                Seal(
                  label: activityTypeSeal(type),
                  filled: selected,
                  size: 44,
                ),
                const SizedBox(width: kSpaceL),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(type.label, style: kSerifHeadingTextStyle),
                      const SizedBox(height: 2),
                      Text(
                        activityTypeDescription(type),
                        style: kMutedTextStyle,
                      ),
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
