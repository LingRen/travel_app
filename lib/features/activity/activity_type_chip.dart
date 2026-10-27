import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/models/activity_type.dart';
import 'activity_type_visuals.dart';

/// 记录待机页的运动类型浮标。点开 [ActivityTypeSheet] 选择类型。
///
/// 只在未开始态出现：开始后类型已经落库，记录中不允许切换。
class ActivityTypeChip extends StatelessWidget {
  const ActivityTypeChip({required this.type, required this.onTap, super.key});

  final ActivityType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Semantics(
      button: true,
      label: '运动类型：${type.label}，点击更换',
      child: Material(
        color: palette.sheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: palette.hairline),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kSpaceL,
                vertical: kSpaceS,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    activityTypeIcon(type),
                    size: 18,
                    color: palette.accentInk,
                  ),
                  const SizedBox(width: kSpaceS),
                  Text(type.label, style: kBodyTextStyle),
                  const SizedBox(width: kSpaceXs),
                  Icon(Icons.expand_more, size: 18, color: palette.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
