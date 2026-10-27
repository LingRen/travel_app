import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';
import 'ui/seal.dart';

/// 冷启动封面。首帧后停留约 1.2 秒，点击任意位置立即跳过。
///
/// 封面结束前不构建 [child]，因此恢复提示不会在封面底下弹出来；封面期间
/// 也不会开始记录或修改会话状态。系统开启减少动态效果时停留 600ms 且不淡出。
class CoverGate extends StatefulWidget {
  const CoverGate({required this.child, super.key});

  final Widget child;

  @override
  State<CoverGate> createState() => _CoverGateState();
}

class _CoverGateState extends State<CoverGate> {
  bool _done = false;
  bool _fading = false;
  bool _reduced = false;
  Timer? _timer;
  Timer? _fadeTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timer != null || _done) return;
    _reduced = MediaQuery.disableAnimationsOf(context);
    _timer = Timer(
      Duration(milliseconds: _reduced ? 600 : 1200),
      _startExit,
    );
  }

  void _startExit() {
    _timer?.cancel();
    if (!mounted || _done || _fading) return;
    if (_reduced) {
      setState(() => _done = true);
      return;
    }
    setState(() => _fading = true);
    _fadeTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fadeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;

    final AppPalette palette = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _startExit,
      // 封面是 `MaterialApp.home` 的根，没有 Scaffold 包着。用 Material 而不
      // 是 ColoredBox：否则文字会落到 MaterialApp 的「没放进 Material」兜底
      // 样式上，纸面会多出一条黄色双下划线。
      child: Material(
        color: palette.paper,
        child: AnimatedOpacity(
          opacity: _fading ? 0 : 1,
          duration: Duration(milliseconds: _reduced ? 0 : 300),
          curve: Curves.easeOut,
          child: const _CoverBody(),
        ),
      ),
    );
  }
}

/// 封面内容按 390×760 的设计尺寸绘制，小屏用 [FittedBox] 等比缩小。
class _CoverBody extends StatelessWidget {
  const _CoverBody();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    // 文字放大时把设计高度一起放大，再交给 FittedBox 等比缩回屏幕；
    // 否则固定 760 高的 Column 会先溢出，FittedBox 来不及救。
    final double textScale = MediaQuery.textScalerOf(context).scale(1);
    return SafeArea(
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 390,
            height: 760 * (textScale < 1 ? 1 : textScale),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: kSpaceXl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 40),
                  Text('运 动 记 录 · 二〇二六', style: kLabelTextStyle),
                  const SizedBox(height: 28),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '行迹',
                              style: TextStyle(
                                fontFamily: kSerifFamily,
                                fontFamilyFallback: kSerifFallback,
                                fontSize: 96,
                                fontWeight: FontWeight.w600,
                                height: 0.95,
                                letterSpacing: 4,
                                color: palette.ink,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'X I N G J I',
                              style: kLabelTextStyle.copyWith(
                                letterSpacing: 6,
                                color: palette.muted,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              width: 48,
                              height: 3,
                              color: palette.accentInk,
                            ),
                          ],
                        ),
                      ),
                      const _VerticalMotto(),
                    ],
                  ),
                  const SizedBox(height: 44),
                  Text(
                    '把一路山河，\n收进一册薄薄的记录。',
                    style: TextStyle(
                      fontFamily: kSerifFamily,
                      fontFamilyFallback: kSerifFallback,
                      fontSize: 30,
                      height: 1.5,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '运动记录 · 单次分析 · 长期趋势',
                    style: kLabelTextStyle,
                  ),
                  const Spacer(),
                  const _RouteArtwork(),
                  const Spacer(),
                  Divider(color: palette.hairline, height: 1),
                  const SizedBox(height: kSpaceL),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '无账号 · 无云端 · 数据仅存于本机',
                          style: kMutedTextStyle.copyWith(fontSize: 12),
                        ),
                      ),
                      Seal(label: '行\n迹', size: 64, semanticLabel: '行迹印章'),
                    ],
                  ),
                  const SizedBox(height: kSpaceXl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VerticalMotto extends StatelessWidget {
  const _VerticalMotto();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Column(
      children: <Widget>[
        Container(width: 1, height: 80, color: palette.hairline),
        const SizedBox(height: kSpaceM),
        Text(
          '山\n色\n入\n轮',
          textAlign: TextAlign.center,
          style: kLabelTextStyle.copyWith(
            height: 2.2,
            letterSpacing: 2,
            color: palette.muted,
          ),
        ),
        const SizedBox(height: kSpaceM),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: palette.accentInk,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

/// 封面底部的路线装饰：一条从空心起点到实心终点的墨线。
class _RouteArtwork extends StatelessWidget {
  const _RouteArtwork();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 120,
        child: CustomPaint(
          painter: _RoutePainter(
            line: context.palette.muted,
            accent: context.palette.accentInk,
            paper: context.palette.paper,
          ),
        ),
      );
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter({
    required this.line,
    required this.accent,
    required this.paper,
  });

  final Color line;
  final Color accent;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Path path = Path()
      ..moveTo(24, h * 0.80)
      ..cubicTo(w * 0.18, h * 0.20, w * 0.30, h * 0.95, w * 0.45, h * 0.55)
      ..cubicTo(w * 0.58, h * 0.18, w * 0.66, h * 0.25, w * 0.76, h * 0.55)
      ..cubicTo(w * 0.84, h * 0.80, w * 0.90, h * 0.35, w * 0.96, h * 0.18);

    final Paint stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, stroke);

    canvas.drawCircle(
      Offset(24, h * 0.80),
      5,
      Paint()
        ..color = paper
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(24, h * 0.80),
      5,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    final double endX = w * 0.96;
    final double endY = h * 0.18;
    canvas.drawCircle(Offset(endX, endY), 5.5, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) =>
      oldDelegate.line != line ||
      oldDelegate.accent != accent ||
      oldDelegate.paper != paper;
}
