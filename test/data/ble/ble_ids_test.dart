import 'package:cycling_app/data/ble/ble_ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shortUuid', () {
    test('短形式原样返回', () {
      expect(shortUuid('180d'), '180d');
      expect(shortUuid('2A37'), '2a37');
    });

    test('128 位长形式归一化为短形式', () {
      expect(shortUuid('0000180D-0000-1000-8000-00805F9B34FB'), '180d');
      expect(shortUuid('00002a2b-0000-1000-8000-00805f9b34fb'), '2a2b');
    });

    test('32 位形式归一化为短形式', () {
      expect(shortUuid('00001816'), '1816');
    });

    test('非标准 UUID 不会被归一化成标准短 UUID', () {
      // 相邻的 0x180E 与 0x2A38 归一化后必须与标准值不同，
      // 否则订阅时会误匹配到错误的特征值。
      expect(shortUuid('0000180e-0000-1000-8000-00805f9b34fb'),
          isNot(kHeartRateServiceShort));
      expect(shortUuid('00002a38-0000-1000-8000-00805f9b34fb'),
          isNot(kHeartRateMeasurementShort));
      expect(shortUuid('00010203-0405-0607-0809-0a0b0c0d0e0f'), '10203');
    });
  });

  group('标准 GATT 短 UUID', () {
    test('心率用 HRS 0x180D / 0x2A37，踏频用 CSC 0x1816 / 0x2A2B', () {
      expect(kHeartRateServiceShort, '180d');
      expect(kHeartRateMeasurementShort, '2a37');
      expect(kCscServiceShort, '1816');
      expect(kCscMeasurementShort, '2a2b');
    });
  });
}
