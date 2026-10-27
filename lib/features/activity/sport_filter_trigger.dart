import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/models/activity_type.dart';

/// 历史 / 统计页眉里的运动筛选入口。显示当前筛选，点击打开共用面板。
class SportFilterTrigger extends StatelessWidget {
  const SportFilterTrigger({
    required this.current,
    required this.onTap,
    super.key,
  });

  /// null 表示全部运动。
  final ActivityType? current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return TextButton(
      key: const Key('sport-filter-trigger'),
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: palette.accentInk,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: kSpaceS),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: kBodyTextStyle.copyWith(
          fontWeight: FontWeight.w600,
          color: palette.accentInk,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(current?.label ?? '全部运动'),
          const SizedBox(width: 2),
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    );
  }
}
