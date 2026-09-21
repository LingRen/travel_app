import 'package:cycling_app/data/ble/reconnect_backoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('backoffDelayMs', () {
    test('按 1s → 2s → 4s → 8s → 16s 递增并封顶 30s', () {
      expect(backoffDelayMs(0), 1000);
      expect(backoffDelayMs(1), 2000);
      expect(backoffDelayMs(2), 4000);
      expect(backoffDelayMs(3), 8000);
      expect(backoffDelayMs(4), 16000);
      expect(backoffDelayMs(5), 30000);
      expect(backoffDelayMs(10), 30000);
    });

    test('负数次数按首次处理', () {
      expect(backoffDelayMs(-1), 1000);
    });
  });
}
