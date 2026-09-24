import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/settings_repository.dart';
import '../../domain/recording/ride_cue.dart';
import 'ride_cue_text.dart';

/// 骑行中的提示横幅。见设计文档 10.1。
///
/// 它是一条**不改动上下两块布局**的浮层：整公里、跨速档、十公里都会在这里闪一下，
/// 如果它参与 Column 布局，每闪一次上下两块（读数、按钮）都会跳一次，骑行中瞄一眼
/// 就是「界面在动」。所以它固定展现在地图可见带里（由 [HandlebarView] 用 Stack 托住），
/// 出现与消失都不挤压邻居。
///
/// 显示时长由 [duration] 决定，到点自己收回：它是事件通知，不是常驻读数——常驻的
/// 读数在上下两块里已经有了。同一次骑行的两条提示挨得很近时，后一条会重置计时，
/// 不排队展示（排队的后果是屏幕上停着一句已经过时的话）。
class RideCueBanner extends StatefulWidget {
  const RideCueBanner({
    required this.cue,
    required this.seq,
    required this.unit,
    this.duration = const Duration(seconds: 5),
    super.key,
  });

  /// 当前要展示的提示。为 null 时不展示。
  final RideCue? cue;

  /// 提示序号。同一句提示重复出现时靠它判断「这是一条新提示」——只比 [cue]
  /// 的话，连续两次「已骑行 10 公里」在对象相等时不会重新计时。
  final int seq;

  final DistanceUnit unit;

  /// 展示多久后收回。
  final Duration duration;

  @override
  State<RideCueBanner> createState() => _RideCueBannerState();
}

class _RideCueBannerState extends State<RideCueBanner> {
  Timer? _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(RideCueBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只在「来了一条新提示」时重新计时，其余重建不动它——每秒一次的界面刷新
    // 不该把横幅的倒计时一次次清零。
    if (widget.seq != oldWidget.seq || widget.cue != oldWidget.cue) _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 重置为「展示中」，并重新开始倒计时。
  ///
  /// 不在 initState / didUpdateWidget 里调 setState：这两个时机后面紧跟一次 build，
  /// 直接改字段即可（在 initState 里调 setState 本身也是非法的）。
  void _arm() {
    _timer?.cancel();
    _shown = widget.cue != null;
    if (!_shown) return;
    _timer = Timer(widget.duration, () {
      if (mounted) setState(() => _shown = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final RideCue? cue = widget.cue;
    // 收回时直接不建这棵子树，而不是留一个透明的空壳：留着的话测试与无障碍
    // 树里都还挂着那句已经过时的文案。
    if (!_shown || cue == null) return const SizedBox.shrink();

    final bool isLap = cue is LapCue;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: kSpaceL),
      padding: const EdgeInsets.symmetric(
        horizontal: kSpaceL,
        vertical: kSpaceM,
      ),
      decoration: BoxDecoration(
        color: kAppSurfaceRaised.withValues(alpha: 0.96),
        borderRadius: BorderRadius.all(Radius.circular(kRadiusControl)),
        border: Border.all(color: kAppHairline, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isLap ? Icons.flag_outlined : Icons.campaign_outlined,
            size: 20,
            color: kAppAccent,
          ),
          const SizedBox(width: kSpaceM),
          Flexible(
            child: Text(
              rideCueBannerText(cue, widget.unit),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: kFontSubtitle,
                fontWeight: FontWeight.w600,
                color: kAppTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}