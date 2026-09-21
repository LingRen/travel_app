import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toDbMap / fromDbMap 往返保持一致', () {
    const TrackPoint p = TrackPoint(
      id: 7,
      rideId: 3,
      tMs: 1000,
      lat: 31.23,
      lon: 121.47,
      altitudeM: 12.5,
      speedMps: 5.5,
      accuracyM: 4.0,
      hr: 132,
      cadence: 85,
    );

    final TrackPoint back = TrackPoint.fromDbMap(p.toDbMap());

    expect(back.id, 7);
    expect(back.rideId, 3);
    expect(back.tMs, 1000);
    expect(back.lat, 31.23);
    expect(back.lon, 121.47);
    expect(back.altitudeM, 12.5);
    expect(back.speedMps, 5.5);
    expect(back.accuracyM, 4.0);
    expect(back.hr, 132);
    expect(back.cadence, 85);
  });

  test('GPS 丢失的点没有坐标但有传感器数据', () {
    const TrackPoint p = TrackPoint(rideId: 3, tMs: 2000, hr: 140, cadence: 90);

    expect(p.hasPosition, isFalse);
    expect(TrackPoint.fromDbMap(p.toDbMap()).hr, 140);
  });
}
