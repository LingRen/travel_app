import 'dart:math' as math;

import '../domain/models/ride.dart';
import '../domain/models/track_point.dart';
import 'ride_repository.dart';

/// 真机检查界面用的模拟骑行生成器。
///
/// 只在 debug 构建里、由设置页的「调试」区块手动触发。手头只有一两条真实
/// 骑行时，历史页只是一个三行列表，统计页的周/月/年三种粒度都撑不起样子，
/// 排版问题（比如月视图底下日期叠字）根本看不出来。
///
/// 生成逻辑是纯函数（[mockRidePlan] 与 [generateMockPoints]）：种子固定、
/// nowMs 给定之后输出完全确定，所以能写测试断言，而不是只能靠肉眼比对。
class MockRidePlan {
  const MockRidePlan({required this.startedAtMs, required this.durationS});

  final int startedAtMs;
  final int durationS;
}

/// 排期：跨最近两个半月，本月排密一些（月粒度是 30 个日桶，要能看出曲线
/// 形状），上个月与上上个月各留几条（年粒度才有第二、第三个非零月）。
///
/// 日期与时刻都写死，不随机：真机上生成两次应当看到同一批数据。
List<MockRidePlan> mockRidePlan({required int nowMs, int seed = 20260923}) {
  const List<int> dayOffsets = <int>[
    0, 1, 3, 5, 7, 9, 12, 14, 16, 20, 24, 30, 38, 47, 58, 70,
  ];
  const List<int> hours = <int>[
    6, 18, 7, 17, 6, 19, 8, 18, 7, 16, 6, 17, 9, 18, 7, 15,
  ];
  const List<int> minutes = <int>[
    38, 52, 27, 61, 45, 33, 58, 41, 24, 66, 36, 49, 31, 55, 43, 29,
  ];

  final DateTime today = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final List<MockRidePlan> plan = <MockRidePlan>[];
  for (int i = 0; i < dayOffsets.length; i++) {
    // 负数日号由 DateTime 自己往前推月份，不必手动算上个月有几天。
    final DateTime day = DateTime(
      today.year,
      today.month,
      today.day - dayOffsets[i],
      hours[i],
      (i * 17 + seed) % 60,
    );
    int startedAtMs = day.millisecondsSinceEpoch;
    // 今天那条排在清晨，若此刻还没到那个点，就挪到昨天，免得历史里出现未来时间。
    if (startedAtMs > nowMs) {
      startedAtMs -= const Duration(days: 1).inMilliseconds;
    }
    plan.add(MockRidePlan(
      startedAtMs: startedAtMs,
      durationS: minutes[i] * 60,
    ));
  }
  return plan;
}

/// 生成一条模拟骑行的采样点：2 秒一个点，轨迹是绕着走的往返路线，
/// 速度 / 心率 / 踏频 / 海拔都按正弦打底再叠噪声。
///
/// 噪声幅度按真实传感器**内部滤波后**的抖动取：心率 ±1.5 bpm、踏频 ±1.2 rpm、
/// 功率 ±3 W。早先按「原始未滤波读数」给（心率 ±4、踏频 ±3、功率 ±12），画到
/// 详情页里是一条毛刺线——那不是数据，是采样噪声被放大的样子。真实设备输出的
/// 已经是滤波后的值，模拟数据也应该长这样，否则看排版时会被噪声带偏。
///
/// 用自带的线性同余伪随机而不是 `Random()`：同一种子必须给出完全一样的数据，
/// 否则测试没法断言、真机上两次生成也复现不出同一条曲线。
///
/// 每三条骑行里有一条会在中途整段丢掉定位（模拟穿隧道）：那条曲线会断开、
/// 地图上也不连线，专门用来核对设计文档 9.3 的断点画法。
List<TrackPoint> generateMockPoints({
  required int rideId,
  required int startedAtMs,
  required int durationS,
  int seed = 20260923,
  int intervalS = 2,
}) {
  final int total = durationS ~/ intervalS + 1;

  // 每条骑行换个起点、换条路线，免得十几条轨迹叠在一起长得一模一样。
  double lat = 39.0850 + (seed % 7) * 0.0021;
  double lon = 117.2000 + (seed % 5) * 0.0026;
  double heading = (seed % 360) * math.pi / 180;
  // 海拔底数抬高一点，避免起伏把高度压成负数；起伏幅度按条变化，
  // 这样统计页的「爬升」既有平路也有爬坡，不是十几个一样的数。
  final double altBase = 60 + (seed % 13).toDouble();
  final double altAmp = 8 + (seed % 5) * 7.0;
  final double speedBias = 4.4 + (seed % 4) * 0.5;
  final double phase = (seed % 17) / 17 * math.pi;
  final bool hasTunnel = seed % 3 == 0;
  final int tunnelFrom = (total * 0.45).round();
  final int tunnelTo = tunnelFrom + 45; // 断 90 秒

  int state = seed | 1;
  double noise() {
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
    return state / 0x7FFFFFFF * 2 - 1;
  }

  final List<TrackPoint> points = <TrackPoint>[];
  for (int i = 0; i < total; i++) {
    // 隧道段整段不落点：时间上留出空档，曲线才会断（在轨道中间插一堆
    // 只有心率、没有经纬度的点，时间轴是连着的，曲线不会断开）。
    if (hasTunnel && i >= tunnelFrom && i < tunnelTo) continue;

    final int tMs = startedAtMs + i * intervalS * 1000;
    final double t = (i * intervalS).toDouble();

    final double speed = math.max(
      0.6,
      speedBias + 1.9 * math.sin(t / 240 + phase) + noise() * 0.45,
    );
    final double altitude =
        altBase + altAmp * math.sin(t / 120 + phase) + noise() * 0.5;
    final int hr =
        (118 + 26 * math.sin(t / 330 + phase * 3) + noise() * 1.5).round();
    final int cadence =
        (74 + 16 * math.sin(t / 260 + phase) + noise() * 1.2).round();
    // 功率跟速度挂钩：骑行功率大致随速度线性上升，再叠一点起伏与噪声。
    //
    // 挂钩用的是「趋势速度」而不是上面那条带 GPS 毛刺的瞬时速度：功率计测的是
    // 腿上踩出来的功，不会跟着定位抖。用瞬时速度的话，速度里 ±0.45 m/s 的噪声
    // 会被 28 倍放大成 ±12 W 的假起伏，盖过真实的功率曲线。
    final double trendSpeed = speedBias + 1.9 * math.sin(t / 240 + phase);
    // 速度压到最低时功率也接近 0（等红灯），不然后面算平均功率会偏高。
    final int power =
        (90 + trendSpeed * 28 + 22 * math.sin(t / 200 + phase) + noise() * 3)
            .round();

    // 航向慢慢转，画出来的路线才像一条路，而不是一圈折线。
    heading += noise() * 0.05 + 0.0015 * math.sin(t / 300);
    final double step = speed * intervalS;
    lat += step * math.cos(heading) / 111320;
    lon += step * math.sin(heading) / (111320 * math.cos(lat * math.pi / 180));

    points.add(TrackPoint(
      rideId: rideId,
      tMs: tMs,
      lat: lat,
      lon: lon,
      altitudeM: altitude,
      speedMps: speed,
      accuracyM: 5 + (noise() + 1) * 3,
      hr: hr.clamp(92, 184),
      cadence: cadence.clamp(42, 116),
      powerW: power.clamp(0, 700),
    ));
  }
  return points;
}

/// 落库：每条计划新开一条记录，写入采样点，再按「正常结束」结算汇总。
///
/// 返回写入的条数。走的是与真实记录完全相同的写入路径，所以历史页、统计页、
/// 详情页看到的数据和真骑出来的没有区别。
///
/// **覆盖式**：写入前先删掉本次排期时间戳命中的既有记录。原来是纯追加，设置页
/// 上点两次「生成模拟数据」就是两份一模一样的数据，真机上曾经堆到 16 组各 4 份。
/// 判重只认 `started_at`：排期的时间戳是写死的（见 [mockRidePlan]），真实骑行的
/// 起点不可能正好撞上。
Future<int> seedMockRides(
  RideRepository repository, {
  required int nowMs,
  int seed = 20260923,
}) async {
  final List<MockRidePlan> plan = mockRidePlan(nowMs: nowMs, seed: seed);
  final Set<int> stamps = <int>{
    for (final MockRidePlan p in plan) p.startedAtMs,
  };

  final List<Ride> existing = <Ride>[
    ...await repository.listFinished(),
    ...await repository.findUnfinished(),
  ];
  for (final Ride ride in existing) {
    if (stamps.contains(ride.startedAtMs)) {
      await repository.deleteRide(ride.id!);
    }
  }

  for (int i = 0; i < plan.length; i++) {
    final MockRidePlan p = plan[i];
    // 带上功率设备名：这批数据是「模拟一个功率计记下来的骑行」，不是 app 按
    // 速度坡度估算出来的。不带的话详情页会把这些功率标成「估算」（标题按
    // `Ride.powerDeviceName` 是否为空判断），看排版时反而看不清真实样子。
    final Ride ride = await repository.startRide(
      startedAtMs: p.startedAtMs,
      powerDeviceName: '模拟功率计',
    );
    final int rideId = ride.id!;
    await repository.appendPoints(
      rideId,
      generateMockPoints(
        rideId: rideId,
        startedAtMs: p.startedAtMs,
        durationS: p.durationS,
        seed: seed + i * 977,
      ),
    );
    await repository.finishRide(
      rideId,
      endedAtMs: p.startedAtMs + p.durationS * 1000,
      durationS: p.durationS,
    );
  }
  return plan.length;
}

/// 清空全部骑行记录。模拟数据看够了之后要能一键清场，否则十几条假记录会一直
/// 混在真实记录里（真实记录也一并删除，界面上有二次确认）。
Future<int> deleteAllRides(RideRepository repository) async {
  final List<Ride> rides = <Ride>[
    ...await repository.listFinished(),
    ...await repository.findUnfinished(),
  ];
  for (final Ride ride in rides) {
    await repository.deleteRide(ride.id!);
  }
  return rides.length;
}