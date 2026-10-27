import 'package:cycling_app/domain/models/activity_type.dart';
import 'package:cycling_app/features/activity/activity_type_visuals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('五种类型与稳定标识', () {
    expect(ActivityType.values.map((ActivityType t) => t.dbValue), <String>[
      'cycling',
      'running',
      'walking',
      'hiking',
      'mountaineering',
    ]);
    expect(ActivityType.mountaineering.label, '登山');
    expect(ActivityType.mountaineering.usesPace, isTrue);
    expect(ActivityType.mountaineering.supportsPower, isFalse);
    expect(ActivityType.mountaineering.supportsCadence, isFalse);
  });

  test('未知类型回退骑行', () {
    expect(ActivityType.fromDb('swimming'), ActivityType.cycling);
  });

  test('五种类型都有说明且不承诺步频步数', () {
    for (final ActivityType type in ActivityType.values) {
      final String desc = activityTypeDescription(type);
      expect(desc, isNotEmpty);
      expect(desc.contains('步频'), isFalse);
      expect(desc.contains('步数'), isFalse);
    }
    expect(activityTypeDescription(ActivityType.cycling), '速度 · 踏频 · 功率');
    expect(
      activityTypeDescription(ActivityType.mountaineering),
      '爬升 · 海拔 · 心率',
    );
  });

  test('每种类型都有印章字与图标', () {
    for (final ActivityType type in ActivityType.values) {
      expect(activityTypeSeal(type).length, 1, reason: type.dbValue);
      expect(activityTypeIcon(type), isNotNull, reason: type.dbValue);
    }
    expect(activityTypeSeal(ActivityType.mountaineering), '登');
  });
}
