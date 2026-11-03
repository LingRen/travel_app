import 'package:cycling_app/features/map/map_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveMapBackend', () {
    test('配置了 Key 时使用高德原生底图', () {
      expect(
        resolveMapBackend(key: 'native-key', override: ''),
        MapBackend.amap,
      );
    });

    test('没有 Key 时回落到 legacy 栅格底图', () {
      expect(resolveMapBackend(key: '', override: ''), MapBackend.legacy);
    });

    test('强制 legacy 时即使有 Key 也回落', () {
      expect(
        resolveMapBackend(key: 'native-key', override: 'legacy'),
        MapBackend.legacy,
      );
    });

    test('显式要求高德但没有 Key 时回落', () {
      expect(resolveMapBackend(key: '  ', override: 'amap'), MapBackend.legacy);
    });

    test('未知覆盖值按自动规则处理', () {
      expect(
        resolveMapBackend(key: 'native-key', override: 'unknown'),
        MapBackend.amap,
      );
      expect(
        resolveMapBackend(key: '', override: 'unknown'),
        MapBackend.legacy,
      );
    });
  });
}
