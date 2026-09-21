import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/recording/write_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TrackPoint pointAt(int tMs) => TrackPoint(rideId: 1, tMs: tMs, lat: 31.0, lon: 121.0);

  group('WriteBuffer', () {
    test('初始为空', () {
      final WriteBuffer buffer = WriteBuffer();
      expect(buffer.length, 0);
      expect(buffer.isEmpty, isTrue);
      expect(buffer.isFull, isFalse);
    });

    test('未达容量时 isFull 为 false', () {
      final WriteBuffer buffer = WriteBuffer();
      for (int i = 0; i < 9; i++) {
        buffer.add(pointAt(i));
      }
      expect(buffer.length, 9);
      expect(buffer.isFull, isFalse);
    });

    test('达到容量时 isFull 为 true', () {
      final WriteBuffer buffer = WriteBuffer();
      for (int i = 0; i < 10; i++) {
        buffer.add(pointAt(i));
      }
      expect(buffer.isFull, isTrue);
    });

    test('drain 返回全部待写点并清空', () {
      final WriteBuffer buffer = WriteBuffer();
      buffer.add(pointAt(1));
      buffer.add(pointAt(2));
      final List<TrackPoint> batch = buffer.drain();
      expect(batch.length, 2);
      expect(batch.first.tMs, 1);
      expect(batch.last.tMs, 2);
      expect(buffer.isEmpty, isTrue);
      expect(buffer.isFull, isFalse);
    });

    test('空缓冲 drain 返回空列表', () {
      final WriteBuffer buffer = WriteBuffer();
      expect(buffer.drain(), isEmpty);
    });

    test('容量可自定义', () {
      final WriteBuffer buffer = WriteBuffer(capacity: 2);
      buffer.add(pointAt(1));
      expect(buffer.isFull, isFalse);
      buffer.add(pointAt(2));
      expect(buffer.isFull, isTrue);
    });
  });
}
