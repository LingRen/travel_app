import 'package:flutter/material.dart';

import '../theme.dart';

/// 从底部展开一张纸本面板。遮罩覆盖全屏，面板左右贴边、底部贴屏幕底边。
Future<T?> showPaperSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final AppPalette palette = context.palette;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    barrierColor: palette.ink.withValues(alpha: 0.35),
    builder: builder,
  );
}

/// 纸本底部面板本体。拖动条、衬线标题、副题、关闭与内容。
///
/// 只圆上方两角，圆角 18；内容超高时在面板内滚动，不把面板撑出屏幕。
class PaperSheet extends StatelessWidget {
  const PaperSheet({
    required this.child,
    this.title,
    this.subtitle,
    this.onClose,
    this.showHandle = true,
    super.key,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final VoidCallback? onClose;
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: const Key('paper-sheet'),
        width: double.infinity,
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(kRadiusSheet),
          ),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                kSpaceXl,
                kSpaceS,
                kSpaceXl,
                kSpaceXl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (showHandle)
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.hairline,
                          borderRadius: BorderRadius.circular(kRadiusLine),
                        ),
                      ),
                    ),
                  if (title != null) ...<Widget>[
                    const SizedBox(height: kSpaceM),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                title!,
                                style: kSerifHeadingTextStyle.copyWith(
                                  fontSize: 30,
                                  height: 1.2,
                                ),
                              ),
                              if (subtitle != null) ...<Widget>[
                                const SizedBox(height: kSpaceXs),
                                Text(subtitle!, style: kMutedTextStyle),
                              ],
                            ],
                          ),
                        ),
                        if (onClose != null)
                          IconButton(
                            onPressed: onClose,
                            tooltip: '关闭',
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                            icon: Icon(
                              Icons.close,
                              size: 24,
                              color: palette.muted,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: kSpaceL),
                  ],
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
