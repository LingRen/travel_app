import 'package:flutter/material.dart';

import '../theme.dart';

/// 底部导航的一项。
class PaperNavItem {
  const PaperNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// 纸本底部导航：58 高、顶部发丝线、图标 20、标签 10、选中用文字安全色。
///
/// 不再使用 Material `NavigationBar` 的选中胶囊。每项占满四分之一宽度，
/// 点击区域高度 58，满足 44×44 的触控底线。
class PaperNavBar extends StatelessWidget {
  const PaperNavBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<PaperNavItem> items;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Material(
      color: palette.paper,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: <Widget>[
                for (int i = 0; i < items.length; i++)
                  Expanded(
                    child: _PaperNavButton(
                      item: items[i],
                      selected: i == selectedIndex,
                      onTap: () => onSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperNavButton extends StatelessWidget {
  const _PaperNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final PaperNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color color = selected ? palette.accentInk : palette.muted;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 58,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(item.icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: TextStyle(
                  fontFamily: kSansFamily,
                  fontFamilyFallback: kSansFallback,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
