import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/analysis/curve.dart';
import 'package:cycling_app/domain/models/track_point.dart';
// 连接规则（哪两个相邻点会连起来）定义在画笔那一侧，平滑测试直接复用，
// 免得在两处各写一遍 segment 判断。
import 'package:cycling_app/features/detail/curve_chart.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一串等间隔的轨迹点。`hr`/`cadence` 与序号绑定，便于断言取到的是哪个点。
List<TrackPoint> buildPoints(int count, {int stepMs = 1000, int? gapAfter}) {
  return <TrackPoint>[
    for (int i = 0; i < count; i++)
      TrackPoint(
        rideId: 1,
        tMs: (gapAfter != null && i > gapAfter)
            ? i * stepMs + kGpsGapMs + 1
            : i * stepMs,
        lat: 31.0 + i * 0.0001,
        lon: 121.0,
        speedMps: i.toDouble(),
        hr: 100 + i,
        cadence: 60 + i,
      ),
  ];
}

void main() {
  group('buildCurve 基本行为', () {
    test('速度曲线取平滑后的速度，x 是相对首点的秒数', () {
      final List<TrackPoint> points = buildPoints(5);
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.speed);

      expect(curve.length, 5);
      expect(curve.first.xSeconds, 0);
      expect(curve.last.xSeconds, 4);
      // 速度 0,1,2,3,4 经过 5 点滑动平均，中点附近应落在区间内。
      expect(curve[2].y, inInclusiveRange(1.0, 3.0));
    });

    test('心率曲线做滑动平均，不是逐点原始值', () {
      // 窗口 9 覆盖全部 3 个点（边界裁剪），三点均值都是 101。
      // 若实现漏掉平滑，这里会读回原始的 100 / 101 / 102。
      final List<CurveSample> curve = buildCurve(
        buildPoints(3),
        metric: CurveMetric.heartRate,
      );
      expect(curve.map((CurveSample s) => s.y).toList(), <double>[101, 101, 101]);
    });

    test('踏频曲线做滑动平均，不是逐点原始值', () {
      final List<CurveSample> curve = buildCurve(
        buildPoints(3),
        metric: CurveMetric.cadence,
      );
      expect(curve.map((CurveSample s) => s.y).toList(), <double>[61, 61, 61]);
    });

    test('功率曲线做滑动平均，不是逐点原始值', () {
      final List<TrackPoint> points = <TrackPoint>[
        for (int i = 0; i < 3; i++)
          TrackPoint(rideId: 1, tMs: i * 1000, powerW: 200 + i * 10),
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.power);
      expect(curve.map((CurveSample s) => s.y).toList(), <double>[210, 210, 210]);
    });

    test('速度曲线对尖峰做滑动平均，毛刺被削弱', () {
      // 静止中夹一个 10 m/s 的 GPS 毛刺。绘制窗口（kSpeedCurveFilterWindow）
      // 比这 7 个点还宽，窗口覆盖全部点，中点应取全体均值 10/7。
      // 若实现漏掉 movingAverage，中点仍是原始的 10.0。
      final List<TrackPoint> points = <TrackPoint>[
        for (int i = 0; i < 7; i++)
          TrackPoint(rideId: 1, tMs: i * 1000, speedMps: i == 3 ? 10.0 : 0.0),
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.speed);
      expect(curve.length, 7);
      expect(curve[3].y, closeTo(10 / 7, 1e-6));
    });

    test('速度曲线的平滑窗口远大于读数窗口，逐点抖动被抹平', () {
      // 40 个点在 4 与 6 之间逐点跳。真实速度不可能这样抖，这是 GPS 噪声的
      // 形状：读数窗口（kSpeedFilterWindow = 5）只能把它削弱到 ±0.2，
      // 画出来仍是一条两三个像素的细齿。绘制窗口要大到把它压成平线——
      // 详情页「有锯齿」抱怨的就是这个抖动。
      final List<TrackPoint> points = <TrackPoint>[
        for (int i = 0; i < 40; i++)
          TrackPoint(rideId: 1, tMs: i * 1000, speedMps: i.isEven ? 4.0 : 6.0),
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.speed);

      // 窗口内 4 与 6 各占一半，中点落回真实的 5 m/s。
      expect(curve[20].y, closeTo(5.0, 0.3));
      // 相邻两点之间不再一上一下：差值远小于原始的 2.0。
      // 换成 kSpeedFilterWindow 时这里是 0.4，会红。
      expect((curve[20].y - curve[19].y).abs(), lessThan(0.2));
    });

    test('缺该指标的轨迹点被跳过，且平滑不填补空缺', () {
      final List<TrackPoint> points = <TrackPoint>[
        const TrackPoint(rideId: 1, tMs: 0, hr: 100),
        const TrackPoint(rideId: 1, tMs: 1000), // 没有心率
        const TrackPoint(rideId: 1, tMs: 2000, hr: 120),
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.heartRate);
      expect(curve.length, 2, reason: '中间没有心率的点不该被平滑补出一个值');
      // 两个有点的位置被同一个窗口覆盖，都取两点均值 110。
      expect(curve.map((CurveSample s) => s.y).toList(), <double>[110, 110]);
    });

    test('中途才连上的传感器不会凭空多出前半段曲线', () {
      // 前 5 个点没有踏频（传感器还没连上），第 6 个点起才有。
      // 若平滑填补空缺，升采样后踏频曲线会从第一秒就存在。
      final List<TrackPoint> points = <TrackPoint>[
        for (int i = 0; i < 10; i++)
          TrackPoint(rideId: 1, tMs: i * 1000, cadence: i < 5 ? null : 80 + i),
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.cadence);
      expect(curve.length, 5, reason: '只有后 5 个点有踏频，前 5 个点不能凭空补出值');
      // x 是相对首个有效点的秒数，所以首个采样点仍是 0。
      expect(curve.first.xSeconds, 0);
      expect(curve.last.xSeconds, 4);
    });

    test('空输入返回空曲线', () {
      expect(buildCurve(<TrackPoint>[], metric: CurveMetric.speed), isEmpty);
    });
  });

  group('buildCurve 断点分段', () {
    test('时间间隔超过 kGpsGapMs 时 segment 递增', () {
      final List<TrackPoint> points = buildPoints(6, gapAfter: 2);
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.heartRate);

      // 前 3 个点（下标 0,1,2）同段；下标 3 起时间跳变，进入新段。
      expect(curve[0].segment, 0);
      expect(curve[2].segment, 0);
      expect(curve[3].segment, 1);
      expect(curve[5].segment, 1);
    });

    test('时间不前进时也递增 segment', () {
      final List<TrackPoint> points = <TrackPoint>[
        const TrackPoint(rideId: 1, tMs: 1000, hr: 100),
        const TrackPoint(rideId: 1, tMs: 500, hr: 110), // 时间倒流
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.heartRate);
      expect(curve[0].segment, 0);
      expect(curve[1].segment, 1);
    });

    test('时间相同（dt 为 0）时也递增 segment', () {
      final List<TrackPoint> points = <TrackPoint>[
        const TrackPoint(rideId: 1, tMs: 1000, hr: 100),
        const TrackPoint(rideId: 1, tMs: 1000, hr: 110), // 时间没前进
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.heartRate);
      expect(curve[0].segment, 0);
      expect(curve[1].segment, 1);
    });

    test('恰好等于 kGpsGapMs 不算断点', () {
      final List<TrackPoint> points = <TrackPoint>[
        const TrackPoint(rideId: 1, tMs: 0, hr: 100),
        const TrackPoint(rideId: 1, tMs: kGpsGapMs, hr: 110),
      ];
      final List<CurveSample> curve =
          buildCurve(points, metric: CurveMetric.heartRate);
      expect(curve[1].segment, 0);
    });
  });

  group('buildCurve 降采样', () {
    test('点数超过 maxSamples 时抽稀到不超过上限', () {
      final List<TrackPoint> points = buildPoints(1000);
      final List<CurveSample> curve = buildCurve(
        points,
        metric: CurveMetric.heartRate,
        maxSamples: 100,
      );
      expect(curve.length, lessThanOrEqualTo(100));
      expect(curve.length, greaterThan(50));
    });

    test('降采样保留首点与末点：x 覆盖完整时间轴', () {
      final List<TrackPoint> points = buildPoints(1000);
      final List<CurveSample> curve = buildCurve(
        points,
        metric: CurveMetric.heartRate,
        maxSamples: 100,
      );
      // 抓 x 而不是 y：平滑会改数值（首末点是窗口均值），但首末两秒必须还在，
      // 否则曲线两头会被抽掉一段。
      expect(curve.first.xSeconds, 0);
      expect(curve.last.xSeconds, 999);
    });

    test('点数不超上限时原样返回，不抽稀', () {
      final List<CurveSample> curve = buildCurve(
        buildPoints(10),
        metric: CurveMetric.heartRate,
        maxSamples: 100,
      );
      expect(curve.length, 10);
    });

    test('降采样后 x 仍单调不减', () {
      final List<CurveSample> curve = buildCurve(
        buildPoints(1000),
        metric: CurveMetric.heartRate,
        maxSamples: 50,
      );
      for (int i = 1; i < curve.length; i++) {
        expect(curve[i].xSeconds, greaterThanOrEqualTo(curve[i - 1].xSeconds));
      }
    });
  });

  group('平滑曲线段', () {
    // 相邻点直连在数据密集时看着是锯齿，改用 Catmull-Rom 转贝塞尔。这几个
    // 断言盯的是「平滑不能改数据」：曲线必须仍然严格穿过每一个采样点。
    const double maxX = 10;
    const double maxY = 100;

    List<CurveArc> arcsOf(List<CurveSample> samples) => curveArcs(
          samples,
          drawnCurveSegments(samples),
          maxX: maxX,
          maxY: maxY,
        );

    test('每个连接点对生成一段，弧数与折线段数一致', () {
      final List<CurveSample> samples = buildCurve(
        buildPoints(30),
        metric: CurveMetric.heartRate,
      );
      expect(arcsOf(samples).length, drawnCurveSegments(samples).length);
    });

    test('曲线严格穿过每个采样点：起点终点就是归一化后的采样点', () {
      final List<CurveSample> samples = <CurveSample>[
        const CurveSample(xSeconds: 0, y: 10, segment: 0),
        const CurveSample(xSeconds: 5, y: 40, segment: 0),
        const CurveSample(xSeconds: 10, y: 20, segment: 0),
      ];

      final List<CurveArc> arcs = arcsOf(samples);
      expect(arcs.length, 2);
      expect(arcs.first.from, const CurvePoint(0, 0.1));
      expect(arcs.first.to, const CurvePoint(0.5, 0.4));
      expect(arcs.last.from, const CurvePoint(0.5, 0.4));
      expect(arcs.last.to, const CurvePoint(1, 0.2));

      // 中间那个点是控制点，不是端点：这是它「被抹圆」的原因，也是
      // 「曲线仍然穿过它所在高度」这句话的边界——它作为控制点时，曲线
      // 在 x=0.5 处的高度由三个点共同决定，不再等于 0.4。
      expect(arcs.first.control1, const CurvePoint(0 + (0.5 - 0) / kCurveTensionDivisor, 0.1 + (0.4 - 0.1) / kCurveTensionDivisor));
      expect(arcs.last.control1, const CurvePoint(0.5 + (1 - 0) / kCurveTensionDivisor, 0.4 + (0.2 - 0.1) / kCurveTensionDivisor));
    });

    test('相邻两段的切线连续：前一段的末控制点与后一段的首控制点共线于采样点', () {
      // 三个点的高度必须互不相等：若两端都是 0，`(next.y - p0.y)` 恒为 0，
      // 切线方向写反也照样满足「首末控制点关于中点对称」，这条就白写了。
      final List<CurveSample> samples = <CurveSample>[
        const CurveSample(xSeconds: 0, y: 0, segment: 0),
        const CurveSample(xSeconds: 5, y: 60, segment: 0),
        const CurveSample(xSeconds: 10, y: 30, segment: 0),
      ];
      final List<CurveArc> arcs = arcsOf(samples);
      final CurvePoint middle = arcs.first.to;
      // 两侧控制点关于中间的采样点对称（Catmull-Rom 的性质），这就是「没有折角」。
      expect(
        arcs.last.control1.x + arcs.first.control2.x,
        closeTo(middle.x * 2, 1e-9),
      );
      expect(
        arcs.last.control1.y + arcs.first.control2.y,
        closeTo(middle.y * 2, 1e-9),
      );
    });

    test('断口处不生成弧，且切线不借用断口另一侧的点', () {
      final List<CurveSample> samples = <CurveSample>[
        const CurveSample(xSeconds: 0, y: 90, segment: 0),
        const CurveSample(xSeconds: 5, y: 10, segment: 0),
        const CurveSample(xSeconds: 6, y: 80, segment: 1),
        const CurveSample(xSeconds: 10, y: 20, segment: 1),
      ];
      // 只有 0-1 与 2-3 两个连接，跨断口的 1-2 不连。
      expect(drawnCurveSegments(samples), <(int, int)>[(0, 1), (2, 3)]);

      final List<CurveArc> arcs = arcsOf(samples);
      expect(arcs.length, 2);
      expect(arcs.first.toIndex, 1);
      expect(arcs.last.fromIndex, 2);

      // 第 2 段的切线邻居是它自己那一侧的第 3 点，而不是断口另一侧的第 1 点。
      final CurvePoint p2 = const CurvePoint(6 / maxX, 80 / maxY);
      final CurvePoint p3 = const CurvePoint(1, 0.2);
      expect(arcs.last.control1, CurvePoint(p2.x + (p3.x - p2.x) / kCurveTensionDivisor, p2.y + (p3.y - p2.y) / kCurveTensionDivisor));

      // 对照组：若真的借用了断口另一侧的第 1 点，控制点会落在别处。
      final CurvePoint p1 = const CurvePoint(0.5, 0.1);
      expect(
        CurvePoint(p2.x + (p3.x - p1.x) / kCurveTensionDivisor, p2.y + (p3.y - p1.y) / kCurveTensionDivisor),
        isNot(arcs.last.control1),
      );
    });

    test('只有一个点时不生成任何弧', () {
      final List<CurveSample> samples = <CurveSample>[
        const CurveSample(xSeconds: 0, y: 10, segment: 0),
      ];
      expect(arcsOf(samples), isEmpty);
    });
  });
}
