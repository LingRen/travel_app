import 'package:flutter/material.dart';

import '../theme.dart';

/// 方形印章。当前项用实心颜料底 + 纸色字，未选项用空心发丝线框。
///
/// 印章只承担「选中 / 类型标识」这类有含义的位置，不做无意义装饰。
class Seal extends StatelessWidget {
  const Seal({
    required this.label,
    this.filled = true,
    this.size = 40,
    this.semanticLabel,
    super.key,
  });

  /// 印章里的字，通常是一个汉字。
  final String label;

  /// 实心（当前项）或空心（未选项）。
  final bool filled;

  /// 边长。
  final double size;

  /// 读屏标签；缺省用印章字本身。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Semantics(
      label: semanticLabel ?? label,
      image: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled
              ? palette.accentInk
              : palette.accent.withValues(alpha: 0.06),
          border: filled ? null : Border.all(color: palette.hairline),
          borderRadius: BorderRadius.circular(kRadiusSeal),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: kSerifFamily,
            fontFamilyFallback: kSerifFallback,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w600,
            height: 1,
            color: filled ? palette.paper : palette.accentInk,
          ),
        ),
      ),
    );
  }
}
