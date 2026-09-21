import 'package:flutter/material.dart';

import '../../domain/analysis/color_scale.dart';
import '../../domain/analysis/curve.dart';
import '../../domain/models/track_point.dart';

/// 卡片上的迷你速度曲线缩略图。见设计文档 10.2。
///
/// 用 [CustomPaint] 而不是图表库：列表里每张卡片一个图表，自绘便宜得多，
/// 而且能直接复用 [segmentColorArgb]，与详情页曲线、地图轨迹视觉一致。
class MiniSpeedCurve extends StatelessWidget {
  const MiniSpeedCurve({required this.points, super.key});

  final List<TrackPoint> points;

  static const double height = 32;

  /// 缩略图最多画这么多点，再多也看不出来。
  static const int maxSamples = 60;

  @override
  Widget build(BuildContext context) {
    final List<CurveSample> samples = buildCurve(
      points,
      metric: CurveMetric.speed,
      maxSamples: maxSamples,
    );
    if (samples.length < 2) return const SizedBox(height: height);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        size: Size.infinite,
        painter: _MiniSpeedPainter(samples),
      ),
    );
  }
}

/// 迷你曲线画笔真正会连出的相邻点下标对。
///
/// [CustomPaint] 没有可断言的语义节点，光靠 `find.byType(MiniSpeedCurve)`
/// 区分不出「画了几条线」——把 [CustomPaint] 的画笔掏空测试也照样通过。
/// 抽成纯函数是为了让测试能直接断言线数与跨 segment 的断开行为。
@visibleForTesting
List<(int, int)> drawnMiniCurveSegments(List<CurveSample> samples) {
  final List<(int, int)> pairs = <(int, int)>[];
  if (samples.length < 2) return pairs;

  double maxY = 0;
  for (final CurveSample s in samples) {
    if (s.y > maxY) maxY = s.y;
  }
  // y 全为零（无有效速度）或时间不前进时，纵轴/横轴范围为零，画不出线。
  if (maxY <= 0 || samples.last.xSeconds <= 0) return pairs;

  for (int i = 1; i < samples.length; i++) {
    if (samples[i - 1].segment != samples[i].segment) continue;
    pairs.add((i - 1, i));
  }
  return pairs;
}

class _MiniSpeedPainter extends CustomPainter {
  _MiniSpeedPainter(this.samples);

  final List<CurveSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final List<(int, int)> pairs = drawnMiniCurveSegments(samples);
    if (pairs.isEmpty) return;

    double maxY = 0;
    for (final CurveSample s in samples) {
      if (s.y > maxY) maxY = s.y;
    }
    final double maxX = samples.last.xSeconds;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (final (int i, int j) in pairs) {
      final CurveSample a = samples[i];
      final CurveSample b = samples[j];
      paint.color = Color(segmentColorArgb(a.y, b.y));
      canvas.drawLine(
        Offset(a.xSeconds / maxX * size.width, size.height - a.y / maxY * size.height),
        Offset(b.xSeconds / maxX * size.width, size.height - b.y / maxY * size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniSpeedPainter old) => !identical(old.samples, samples);
}
