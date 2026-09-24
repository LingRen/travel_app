import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
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
    required this.formatValue,
    this.averageValue,
    this.colorBySpeed = false,
    this.baseColorArgb = kAppAccentArgb,
    super.key,
  });

  final List<CurveSample> samples;

  /// y 轴单位，画在平均线的标签里。
  final String unitLabel;

  /// 把曲线上的数值格式化成标注文字的数值部分。
  ///
  /// 口径必须和上方的读数一致：速度是 `toStringAsFixed(1)`，心率 / 踏频 / 功率
  /// 取整。由 `core/format.dart` 与页面决定，画笔不自己猜一个。
  final String Function(double) formatValue;

  /// 平均线画在哪个高度（与 [samples] 同一数值口径）。为空时不画平均线。
  ///
  /// 由页面从汇总指标传入，而不是就地算曲线均值：屏幕上方就写着「平均心率
  /// 142」，参考线必须和它对得上，否则用户会以为哪里算错了。
  final double? averageValue;

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
          unitLabel: unitLabel,
          averageValue: averageValue,
          formatValue: formatValue,
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
    required this.unitLabel,
    required this.averageValue,
    required this.formatValue,
  });

  final List<CurveSample> samples;
  final bool colorBySpeed;
  final int baseColorArgb;
  final String unitLabel;
  final double? averageValue;
  final String Function(double) formatValue;

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

    // 顶部留白详见 kCurveTopHeadroom：不留的话峰顶被裁成平顶。标注与曲线必须
    // 用同一个纵轴比例，否则平均线会画在错误的标高上。
    final double scaleY = maxY * kCurveTopHeadroom;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // 控制点会略微越过极值（Catmull-Rom 的正常代价），按图表区域裁掉，
    // 免得曲线顶到相邻区块上去。
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final List<CurveArc> arcs = curveArcs(
      samples,
      drawnCurveSegments(samples),
      maxX: maxX,
      maxY: scaleY,
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
    canvas.restore();

    // 标注不跟着曲线一起裁：极值正好落在首点或末点上时，圆点有一半在图表外，
    // 裁掉就只剩半个点。图表左右各有 kSpaceL 的留白，越界这三两个像素落在
    // 留白里，看不出来。
    _paintAverageLine(canvas, size, scaleY);
    _paintExtremes(canvas, size, scaleY, maxX);
  }

  /// 归一化坐标（y 向上）换算成画布像素（y 向下）。
  Offset _px(CurvePoint p, Size size) =>
      Offset(p.x * size.width, size.height - p.y * size.height);

  /// 数值换算成画布上的纵向像素。
  double _py(double y, Size size, double scaleY) =>
      size.height - y / scaleY * size.height;

  /// 平均线：一条横穿的虚线，右端标出数值。
  ///
  /// 画虚线而不是实线：它是参考线，不是数据，不该和琥珀色的曲线抢注意力。
  void _paintAverageLine(Canvas canvas, Size size, double scaleY) {
    final double? average = averageValue;
    if (average == null) return;
    final double y = _py(average, size, scaleY);
    if (y < 0 || y > size.height) return;

    final Paint linePaint = Paint()
      ..color = kAppTextMuted
      ..strokeWidth = 1;
    const double dash = 5;
    const double gap = 4;
    for (double x = 0; x < size.width; x += dash + gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + dash, size.width), y),
        linePaint,
      );
    }

    final TextPainter label = _label(
      '平均 ${formatValue(average)} $unitLabel',
      _averageLabelStyle,
    );
    // 默认压在线上方；线贴到图表顶部时翻到下方，免得标签被裁掉。
    final double labelY =
        y - label.height - 2 < 0 ? y + 3 : y - label.height - 2;
    label.paint(
      canvas,
      Offset(
        math.max(0, size.width - label.width),
        labelY.clamp(0.0, math.max(0.0, size.height - label.height)),
      ),
    );
  }

  /// 极值：峰顶与谷底各打一个点，旁边写出数值。
  void _paintExtremes(Canvas canvas, Size size, double scaleY, double maxX) {
    final CurveExtremes? extremes = curveExtremes(samples);
    if (extremes == null) return;

    _paintExtremum(
      canvas,
      size,
      scaleY,
      maxX,
      xSeconds: samples[extremes.maxIndex].xSeconds,
      y: extremes.maxY,
      text: '最高 ${formatValue(extremes.maxY)}',
      below: false,
    );
    if (extremes.isFlat) return;
    _paintExtremum(
      canvas,
      size,
      scaleY,
      maxX,
      xSeconds: samples[extremes.minIndex].xSeconds,
      y: extremes.minY,
      text: '最低 ${formatValue(extremes.minY)}',
      below: true,
    );
  }

  void _paintExtremum(
    Canvas canvas,
    Size size,
    double scaleY,
    double maxX, {
    required double xSeconds,
    required double y,
    required String text,
    required bool below,
  }) {
    final double x = xSeconds / maxX * size.width;
    final double py = _py(y, size, scaleY);

    canvas.drawCircle(Offset(x, py), 3, Paint()..color = kAppTextPrimary);

    // 峰顶的标签朝上、谷底的朝下，反过来会压住曲线。贴到图表边上时收回界内。
    final TextPainter label = _label(text, _extremumLabelStyle);
    final double labelX = (x - label.width / 2)
        .clamp(0.0, math.max(0.0, size.width - label.width));
    final double labelY = below ? py + 5 : py - label.height - 5;
    label.paint(
      canvas,
      Offset(
        labelX,
        labelY.clamp(0.0, math.max(0.0, size.height - label.height)),
      ),
    );
  }

  TextPainter _label(String text, TextStyle style) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    return painter;
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      !identical(old.samples, samples) ||
      old.colorBySpeed != colorBySpeed ||
      old.baseColorArgb != baseColorArgb ||
      old.unitLabel != unitLabel ||
      old.averageValue != averageValue;
}

/// 极值标注：等宽 + tabular，数字位数变化时标签宽度不跳。
const TextStyle _extremumLabelStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontSize: 10,
  height: 1.1,
  color: kAppTextPrimary,
  fontFeatures: kTabularFigures,
);

/// 平均线标注：弱一档。平均值是参考，不该和极值抢注意力。
const TextStyle _averageLabelStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontSize: 10,
  height: 1.1,
  color: kAppTextMuted,
  fontFeatures: kTabularFigures,
);
