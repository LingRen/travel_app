import 'package:cycling_app/domain/models/activity_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('五种运动类型的显示名与落库值稳定', () {
    expect(
      <String, String>{
        for (final ActivityType type in ActivityType.values)
          type.dbValue: type.label,
      },
      <String, String>{
        'cycling': '骑行',
        'running': '跑步',
        'walking': '健走',
        'hiking': '徒步',
        'mountaineering': '登山',
      },
    );
  });

  test('fromDb 识别五种类型，未知值与空值回退骑行', () {
    for (final ActivityType type in ActivityType.values) {
      expect(ActivityType.fromDb(type.dbValue), type);
    }
    expect(ActivityType.fromDb('unknown'), ActivityType.cycling);
    expect(ActivityType.fromDb(null), ActivityType.cycling);
  });

  test('能力集按类型分派：骑行独有踏频与功率，其余用配速', () {
    expect(ActivityType.cycling.usesPace, isFalse);
    expect(ActivityType.cycling.supportsCadence, isTrue);
    expect(ActivityType.cycling.supportsPower, isTrue);
    expect(ActivityType.cycling.supportsSpeedTierCue, isTrue);

    for (final ActivityType type in <ActivityType>[
      ActivityType.running,
      ActivityType.walking,
      ActivityType.hiking,
      ActivityType.mountaineering,
    ]) {
      expect(type.usesPace, isTrue, reason: type.dbValue);
      expect(type.supportsCadence, isFalse, reason: type.dbValue);
      expect(type.supportsPower, isFalse, reason: type.dbValue);
      expect(type.supportsSpeedTierCue, isFalse, reason: type.dbValue);
    }
  });
}
