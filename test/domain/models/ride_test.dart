import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('进行中的骑行没有汇总指标', () {
    const Ride ride = Ride(startedAtMs: 1000, status: RideStatus.recording);
    final Map<String, Object?> row = ride.toDbMap();

    expect(row['distance_m'], isNull);
    expect(Ride.fromDbMap(<String, Object?>{...row, 'id': 1}).summary, isNull);
  });

  test('已完成的骑行汇总指标往返一致', () {
    const Ride ride = Ride(
      id: 5,
      startedAtMs: 1000,
      endedAtMs: 3601000,
      status: RideStatus.finished,
      title: '晨骑',
      summary: RideSummary(
        distanceM: 25000,
        durationS: 3600,
        movingS: 3400,
        avgSpeedMps: 6.94,
        movingAvgSpeedMps: 7.35,
        maxSpeedMps: 12.5,
        elevationGainM: 180,
        avgHr: 142,
        maxHr: 176,
        avgCadence: 84,
        calories: 720,
        pointCount: 3600,
      ),
      hrDeviceName: 'HUAWEI WATCH FIT 3',
    );

    final Ride back = Ride.fromDbMap(ride.toDbMap());

    expect(back.id, 5);
    expect(back.status, RideStatus.finished);
    expect(back.title, '晨骑');
    expect(back.summary!.distanceM, 25000);
    expect(back.summary!.maxHr, 176);
    expect(back.summary!.calories, 720);
    expect(back.hrDeviceName, 'HUAWEI WATCH FIT 3');
  });

  test('未知状态字符串直接抛错', () {
    expect(() => RideStatus.fromDb('running'), throwsArgumentError);
  });
}
