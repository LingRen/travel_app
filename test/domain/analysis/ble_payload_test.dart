import 'package:cycling_app/domain/analysis/ble_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseHeartRateMeasurement', () {
    test('flags 最低位为 0 时心率是 1 字节', () {
      expect(parseHeartRateMeasurement(<int>[0x00, 72]), 72);
    });

    test('flags 最低位为 1 时心率是 2 字节小端', () {
      expect(parseHeartRateMeasurement(<int>[0x01, 0x2C, 0x01]), 300);
    });

    test('带能量消耗字段时仍能正确取到心率', () {
      // flags=0x08 表示后面有能量消耗字段，心率仍在第 2 字节
      expect(parseHeartRateMeasurement(<int>[0x08, 88, 0x10, 0x00]), 88);
    });

    test('数据过短返回 null', () {
      expect(parseHeartRateMeasurement(<int>[]), isNull);
      expect(parseHeartRateMeasurement(<int>[0x01, 0x2C]), isNull);
    });
  });

  group('parseCscMeasurement', () {
    test('只有曲柄数据时解析转数与事件时间', () {
      // flags=0x02（仅曲柄），转数=1，事件时间=1024
      final CscMeasurement? m = parseCscMeasurement(<int>[0x02, 0x01, 0x00, 0x00, 0x04]);
      expect(m!.crankRevolutions, 1);
      expect(m.crankEventTime1024, 1024);
    });

    test('同时有车轮数据时跳过前 6 字节', () {
      final CscMeasurement? m = parseCscMeasurement(
        <int>[0x03, 0, 0, 0, 0, 0, 0, 0x05, 0x00, 0x00, 0x08],
      );
      expect(m!.crankRevolutions, 5);
      expect(m.crankEventTime1024, 2048);
    });

    test('没有曲柄数据返回 null', () {
      expect(parseCscMeasurement(<int>[0x01, 0, 0, 0, 0, 0, 0]), isNull);
    });

    test('数据过短返回 null', () {
      expect(parseCscMeasurement(<int>[0x02, 0x01]), isNull);
    });
  });

  group('parseCyclingPowerMeasurement', () {
    test('取紧随 flags 之后的 sint16 小端瞬时功率', () {
      // flags=0x0000，瞬时功率 210
      expect(parseCyclingPowerMeasurement(<int>[0x00, 0x00, 210, 0x00]), 210);
    });

    test('flags 置位时仍从第 3 字节开始读功率', () {
      // flags=0x001F（含平衡、累积能量等位）不影响功率字段的位置
      expect(parseCyclingPowerMeasurement(<int>[0x1F, 0x00, 0xD2, 0x00]), 210);
    });

    test('高位功率不被当成负数', () {
      // 1500 W = 0x05DC：第 3 字节 0xDC 的最高位是 1，只有按 sint16 整体判读才对
      expect(parseCyclingPowerMeasurement(<int>[0x00, 0x00, 0xDC, 0x05]), 1500);
    });

    test('负的瞬时功率夹到 0，码表上不显示负瓦数', () {
      // -50 W = 0xFFCE
      expect(parseCyclingPowerMeasurement(<int>[0x00, 0x00, 0xCE, 0xFF]), 0);
    });

    test('数据过短返回 null', () {
      expect(parseCyclingPowerMeasurement(<int>[]), isNull);
      expect(parseCyclingPowerMeasurement(<int>[0x00, 0x00]), isNull);
      expect(parseCyclingPowerMeasurement(<int>[0x00, 0x00, 0xD2]), isNull);
    });
  });

  group('cadenceRpm', () {
    test('1 秒转 1 圈等于 60 rpm', () {
      const CscMeasurement prev = CscMeasurement(crankRevolutions: 0, crankEventTime1024: 0);
      const CscMeasurement cur = CscMeasurement(crankRevolutions: 1, crankEventTime1024: 1024);
      expect(cadenceRpm(prev, cur), closeTo(60, 1e-9));
    });

    test('16 位回绕时仍能算出正确踏频', () {
      const CscMeasurement prev =
          CscMeasurement(crankRevolutions: 65535, crankEventTime1024: 65535);
      const CscMeasurement cur = CscMeasurement(crankRevolutions: 0, crankEventTime1024: 1023);
      expect(cadenceRpm(prev, cur), closeTo(60, 1e-9));
    });

    test('事件时间未前进时返回 null', () {
      const CscMeasurement m = CscMeasurement(crankRevolutions: 5, crankEventTime1024: 100);
      expect(cadenceRpm(m, m), isNull);
    });

    test('间隔超过 5 秒返回 null', () {
      const CscMeasurement prev = CscMeasurement(crankRevolutions: 0, crankEventTime1024: 0);
      const CscMeasurement cur =
          CscMeasurement(crankRevolutions: 5, crankEventTime1024: 1024 * 6);
      expect(cadenceRpm(prev, cur), isNull);
    });

    test('超出合理范围的踏频返回 null', () {
      const CscMeasurement prev = CscMeasurement(crankRevolutions: 0, crankEventTime1024: 0);
      const CscMeasurement cur = CscMeasurement(crankRevolutions: 10, crankEventTime1024: 1024);
      expect(cadenceRpm(prev, cur), isNull);
    });
  });
}
