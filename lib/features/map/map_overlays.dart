import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 指北标识。两套地图体都不旋转地图，所以永远指北。
///
/// 保留 `map-north` 测试锚点：后端切换不能改变页面可断言的结构。
class MapNorthIndicator extends StatelessWidget {
  const MapNorthIndicator({this.size = 30, this.fontSize = 11, super.key});

  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Container(
      key: const Key('map-north'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.paper.withValues(alpha: 0.88),
        border: Border.all(color: palette.hairline),
      ),
      child: Text(
        '北',
        style: kLabelTextStyle.copyWith(
          fontSize: fontSize,
          letterSpacing: 0,
          color: palette.ink,
        ),
      ),
    );
  }
}

/// 比例尺。按当前缩放与纬度把米/像素换算成一个整数距离，画一段横线。
///
/// 地图记录中不可交互，但「这段路有多长」仍需要一个参照；比例尺只做显示，
/// 调用方用 [IgnorePointer] 包住，不改变地图的手势行为。
///
/// 两套后端共用同一个公式（[metersPerPixel] 由 `MapProjection` 或
/// `MapCamera` 算出），避免原生与 legacy 的比例尺不一致。
class MapScaleBar extends StatelessWidget {
  const MapScaleBar({required this.metersPerPixel, super.key});

  final double metersPerPixel;

  /// 目标横线长度（逻辑像素）。实际会取一个不超过它的 1/2/5 整十距离。
  static const double targetWidth = 80;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final double mpp = metersPerPixel;
    final double niceMeters = _niceDistance(mpp * targetWidth);
    final double width = (niceMeters / mpp).clamp(24.0, 140.0);
    final String label = niceMeters >= 1000
        ? '${(niceMeters / 1000).toStringAsFixed(niceMeters % 1000 == 0 ? 0 : 1)} km'
        : '${niceMeters.round()} m';

    return Column(
      key: const Key('map-scale-bar'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: kLabelTextStyle.copyWith(
            fontSize: 10,
            letterSpacing: 0,
            color: palette.ink,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Container(width: 2, height: 8, color: palette.ink),
            Container(width: width, height: 2, color: palette.ink),
            Container(width: 2, height: 8, color: palette.ink),
          ],
        ),
      ],
    );
  }

  /// 取 1、2、5 乘以 10 的整数次幂中不超过 [raw] 的最大值。
  static double _niceDistance(double raw) {
    if (!raw.isFinite || raw <= 0) return 100;
    final double exponent = math
        .pow(10, (math.log(raw) / math.ln10).floor())
        .toDouble();
    final double fraction = raw / exponent;
    final double nice = fraction >= 5
        ? 5
        : fraction >= 2
        ? 2
        : 1;
    return nice * exponent;
  }
}

/// 粗略定位 / 朝向尚未建立时的位置点：12 dp 半透明墨色圆点。
///
/// 不用主题色，也不加白边：它只表示「大概在这儿」，不该和轨迹末端抢注意力。
class MapPositionDot extends StatelessWidget {
  const MapPositionDot({super.key});

  static const double size = 12;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('map-position-dot'),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: context.palette.ink.withValues(alpha: 0.55),
    ),
  );
}

/// 记录页的起点：18 dp 主题色空心环，无字。
///
/// 不带字是为了小屏地图带不挤（起点环、箭头、指北与比例尺会同时出现）。
class MapStartRing extends StatelessWidget {
  const MapStartRing({super.key});

  static const double size = 18;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('map-start-marker'),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: context.palette.accentInk, width: 2),
    ),
  );
}

/// 当前位置箭头：22 dp 实心三角，深墨填充 + 1.5 dp 纸色描边。
///
/// 用墨色而不是主题色：脚下的轨迹就是主题色，同色会融成一片。描边用纸色，
/// 让箭头在深色底图与彩色瓦片上都立得住（与轨迹的 `kRouteCasing` 同一角色）。
///
/// 形变由箭头自己承担（[AnimatedRotation]），地图保持北向上。
class MapHeadingArrow extends StatelessWidget {
  const MapHeadingArrow({required this.turns, super.key});

  /// 视觉尺寸（三角形本身）。
  static const double size = 22;

  /// 标记盒子：比三角形大一圈，旋转时不裁角。
  static const double box = 28;

  /// 连续展开的圈数。由调用方按最短弧累加。
  final double turns;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    key: const Key('map-heading-arrow'),
    turns: turns,
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOut,
    child: CustomPaint(
      size: const Size(box, box),
      painter: _HeadingArrowPainter(
        fill: context.palette.ink,
        casing: context.palette.paper,
      ),
    ),
  );
}

class _HeadingArrowPainter extends CustomPainter {
  const _HeadingArrowPainter({required this.fill, required this.casing});

  final Color fill;
  final Color casing;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double half = MapHeadingArrow.size / 2;
    // 尖端朝上（0° ＝ 正北），底边带一个内凹，像导航箭头。
    final Path path = Path()
      ..moveTo(center.dx, center.dy - half)
      ..lineTo(center.dx + half * 0.72, center.dy + half * 0.78)
      ..lineTo(center.dx, center.dy + half * 0.42)
      ..lineTo(center.dx - half * 0.72, center.dy + half * 0.78)
      ..close();

    // 先描一圈比填充宽 3 的边，再被填充盖住内侧，净剩 1.5 dp 的纸色轮廓。
    canvas.drawPath(
      path,
      Paint()
        ..color = casing
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(path, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_HeadingArrowPainter old) =>
      old.fill != fill || old.casing != casing;
}
