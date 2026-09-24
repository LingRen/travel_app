import 'package:flutter/material.dart';

import '../../domain/analysis/color_scale.dart';
import '../../domain/analysis/constants.dart';
import '../../domain/analysis/curve.dart';

/// 详情页的一条曲线。见设计文档 10.3 的第 3~5 块。
///
/// 自绘而不是用图表库：设计文档 8.2 要求速度曲线与地图轨迹共用同一套颜色映射，
/// 而 `fl_chart` 的折线只能整条一个颜色（或一个按 x 位置的渐变），
/// 做不出「按每一段的速度着色」。自绘可以直接复用 [segmentColorArgb]。
class CurveChart extends StatelessWidget {
  const CurveChart({
    required this.samples,
    required this.unitLabel,
    this.colorBySpeed = false,
    this.baseColorArgb = kAppAccentArgb,
    super.key,
  });

  final List<CurveSample> samples;

  /// y 轴单位，画在左上角。
  final String unitLabel;

  /// 为真时按每段平均速度着色（速度曲线用），否则用 [baseColorArgb]。
  final bool colorBySpeed;

  final int baseColorArgb;

  static const double chartHeight = 140;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: chartHeight,
      child: CustomPaint(
        size: Size.infinite,
        painter: _CurvePainter(
          samples: samples,
          colorBySpeed: colorBySpeed,
          baseColorArgb: baseColorArgb,
        ),
      ),
    );
  }
}

/// 主题强调色的 ARGB 整数形式，供画笔使用（画笔只认 int，不认 Color 常量表）。
/// 与 `app/theme.dart` 里的 `kAppAccent` 保持一致；两处都改才算改。
const int kAppAccentArgb = 0xFFFFA92B;

/// 画笔真正会连出的相邻点下标对。
///
/// 断点两侧不连线：GPS 断点（[CurveSample.segment] 变化）两侧连起来会画出一条
/// 横穿隧道或建筑物的假直线（设计文档 9.3）。抽成纯函数是为了让测试能直接断言
/// 「跨 segment 的两点之间不画线」，而不必去窥探私有画笔。
List<(int, int)> drawnCurveSegments(List<CurveSample> samples) {
  final List<(int, int)> pairs = <(int, int)>[];
  for (int i = 1; i < samples.length; i++) {
    if (samples[i - 1].segment != samples[i].segment) continue;
    pairs.add((i - 1, i));
  }
  return pairs;
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.samples,
    required this.colorBySpeed,
    required this.baseColorArgb,
  });

  final List<CurveSample> samples;
  final bool colorBySpeed;
  final int baseColorArgb;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    double maxY = 0;
    for (final CurveSample s in samples) {
      if (s.y > maxY) maxY = s.y;
    }
    if (maxY <= 0) maxY = 1;

    final double maxX = samples.last.xSeconds;
    if (maxX <= 0) return;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // 控制点会略微越过极值（Catmull-Rom 的正常代价），按图表区域裁掉，
    // 免得曲线顶到相邻区块上去。
    canvas.clipRect(Offset.zero & size);

    final List<CurveArc> arcs = curveArcs(
      samples,
      drawnCurveSegments(samples),
      maxX: maxX,
      // 顶部留白详见 kCurveTopHeadroom：不留的话峰顶被裁成平顶。
      maxY: maxY * kCurveTopHeadroom,
    );
    for (final CurveArc arc in arcs) {
      final CurveSample a = samples[arc.fromIndex];
      final CurveSample b = samples[arc.toIndex];
      paint.color = Color(
        colorBySpeed ? segmentColorArgb(a.y, b.y) : baseColorArgb,
      );
      canvas.drawPath(
        Path()
          ..moveTo(_px(arc.from, size).dx, _px(arc.from, size).dy)
          ..cubicTo(
            _px(arc.control1, size).dx,
            _px(arc.control1, size).dy,
            _px(arc.control2, size).dx,
            _px(arc.control2, size).dy,
            _px(arc.to, size).dx,
            _px(arc.to, size).dy,
          ),
        paint,
      );
    }
  }

  /// 归一化坐标（y 向上）换算成画布像素（y 向下）。
  Offset _px(CurvePoint p, Size size) =>
      Offset(p.x * size.width, size.height - p.y * size.height);

  @override
  bool shouldRepaint(_CurvePainter old) =>
      !identical(old.samples, samples) ||
      old.colorBySpeed != colorBySpeed ||
      old.baseColorArgb != baseColorArgb;
}
