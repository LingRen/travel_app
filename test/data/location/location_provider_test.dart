import 'package:cycling_app/data/location/location_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String amapKey = 'test-amap-key';

  /// 便于把四类输入压成一行断言。
  LocationProviderSelection resolve({
    bool isDebug = true,
    String buildOverride = '',
    String? debugStoredValue,
    String key = amapKey,
  }) => resolveLocationProvider(
    isDebug: isDebug,
    buildOverride: buildOverride,
    debugStoredValue: debugStoredValue,
    amapKey: key,
  );

  group('默认与构建参数', () {
    test('未指定构建参数、也没有调试值：默认系统定位', () {
      final LocationProviderSelection selection = resolve();

      expect(selection.kind, LocationProviderKind.system);
      expect(selection.fallbackReason, isNull);
    });

    test('构建参数 LOCATION_PROVIDER=amap 且有 Key：选择高德定位', () {
      final LocationProviderSelection selection = resolve(
        buildOverride: 'amap',
      );

      expect(selection.kind, LocationProviderKind.amap);
      expect(selection.fallbackReason, isNull);
    });

    test('构建参数为 system 时选择系统定位', () {
      expect(resolve(buildOverride: 'system').kind, LocationProviderKind.system);
    });

    test('构建参数为未知值时按系统定位，不抛异常', () {
      expect(
        resolve(buildOverride: 'gps-next-gen').kind,
        LocationProviderKind.system,
      );
    });
  });

  group('调试存储值', () {
    test('debug 存储值优先于构建参数', () {
      expect(
        resolve(
          buildOverride: 'system',
          debugStoredValue: 'amap',
        ).kind,
        LocationProviderKind.amap,
      );
    });

    test('debug 存储值为 system 时覆盖构建参数的 amap，可用于回滚', () {
      final LocationProviderSelection selection = resolve(
        buildOverride: 'amap',
        debugStoredValue: 'system',
      );

      expect(selection.kind, LocationProviderKind.system);
    });

    test('release 构建忽略已存的 amap 调试值，仍用系统定位', () {
      final LocationProviderSelection selection = resolve(
        isDebug: false,
        debugStoredValue: 'amap',
      );

      expect(selection.kind, LocationProviderKind.system);
      expect(selection.fallbackReason, isNull);
    });

    test('release 构建仍尊重构建参数，便于灰度试点', () {
      expect(
        resolve(isDebug: false, buildOverride: 'amap').kind,
        LocationProviderKind.amap,
      );
    });

    test('空字符串调试值视为没有设置，继续看构建参数', () {
      expect(
        resolve(debugStoredValue: '', buildOverride: 'amap').kind,
        LocationProviderKind.amap,
      );
    });
  });

  group('高德 Key 缺失', () {
    test('选择高德但 Key 为空：回落系统并给出中文原因', () {
      final LocationProviderSelection selection = resolve(
        buildOverride: 'amap',
        key: '',
      );

      expect(selection.kind, LocationProviderKind.system);
      expect(selection.fallbackReason, isNotNull);
      expect(
        selection.fallbackReason,
        contains('系统定位'),
      );
    });

    test('debug 存储值选高德时同样按 Key 回落', () {
      expect(
        resolve(debugStoredValue: 'amap', key: '').kind,
        LocationProviderKind.system,
      );
    });

    test('选择系统定位时不校验高德 Key', () {
      expect(resolve(key: '').fallbackReason, isNull);
    });
  });
}
