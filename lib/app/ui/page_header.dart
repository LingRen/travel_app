import 'package:flutter/material.dart';

import '../theme.dart';

/// 纸本页眉：疏排栏目、年月、衬线大标题与右侧动作。
///
/// 页面不再使用 Material `AppBar`。页眉本身不负责安全区，页面在外层包
/// `SafeArea`；这样记录页这种全屏地图页面可以自己决定页眉压在什么上面。
class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.eyebrow,
    required this.date,
    required this.title,
    this.trailing,
    this.subtitle,
    this.subtitleTrailing,
    this.accentRule = true,
    super.key,
  });

  /// 疏排栏目，例如「运 动 日 志」。
  final String eyebrow;

  /// 年月，例如「二〇二六 · 十月」。
  final String date;

  /// 衬线大标题，例如「行迹」。
  final String title;

  /// 标题行右侧的动作，例如「共 42 次」。
  final Widget? trailing;

  /// 标题下方的摘要，例如「本月 4 次 · 102.0 km · 4 小时 31 分」。
  final String? subtitle;

  /// 摘要行右侧的动作，例如「全部运动 ⌄」。
  final Widget? subtitleTrailing;

  /// 标题左侧的竖排强调线。设计稿的历史 / 统计 / 设置页都有。
  final bool accentRule;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpaceXl, kSpaceL, kSpaceXl, kSpaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: Text(eyebrow, style: kLabelTextStyle)),
              const SizedBox(width: kSpaceM),
              Text(date, style: kLabelTextStyle),
            ],
          ),
          const SizedBox(height: kSpaceM),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              if (accentRule) ...<Widget>[
                Container(width: 3, height: 52, color: palette.accentInk),
                const SizedBox(width: kSpaceM),
              ],
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(title, style: kPageTitleTextStyle),
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: kSpaceM),
                trailing!,
              ],
            ],
          ),
          if (subtitle != null || subtitleTrailing != null) ...<Widget>[
            const SizedBox(height: kSpaceS),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                if (subtitle != null)
                  Expanded(child: Text(subtitle!, style: kMutedTextStyle))
                else
                  const Spacer(),
                if (subtitleTrailing != null) ...<Widget>[
                  const SizedBox(width: kSpaceM),
                  subtitleTrailing!,
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
