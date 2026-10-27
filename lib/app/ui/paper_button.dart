import 'package:flutter/material.dart';

import '../theme.dart';

/// 纸本按钮的两种语气。
enum PaperButtonVariant {
  /// 主动作：颜料底、纸色字。
  filled,

  /// 次动作：透明底、颜料字。
  ghost,
}

/// 纸本按钮。高度 52，圆角 3，主按钮整宽。
class PaperButton extends StatelessWidget {
  const PaperButton({
    required this.label,
    this.onPressed,
    this.variant = PaperButtonVariant.filled,
    this.icon,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final PaperButtonVariant variant;
  final IconData? icon;

  /// 是否占满可用宽度。底部主动作默认整宽。
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Widget child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 18),
          const SizedBox(width: kSpaceS),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    final Widget button = switch (variant) {
      PaperButtonVariant.filled => FilledButton(
        onPressed: onPressed,
        child: child,
      ),
      PaperButtonVariant.ghost => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: palette.accentInk,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: kSpaceL),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(kRadiusButton)),
          ),
        ),
        child: child,
      ),
    };

    return SizedBox(
      width: expand ? double.infinity : null,
      height: 52,
      child: button,
    );
  }
}
