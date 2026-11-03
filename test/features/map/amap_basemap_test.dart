import 'package:cycling_app/features/map/amap_basemap.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只提供给定资源的资源包；未提供的键按真实 `rootBundle` 的行为抛错。
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.assets);

  final Map<String, Uint8List> assets;

  @override
  Future<ByteData> load(String key) async {
    final Uint8List? bytes = assets[key];
    if (bytes == null) throw StateError('missing asset: $key');
    return ByteData.sublistView(bytes);
  }
}

void main() {
  test('读到样式二进制时返回字节', () async {
    final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
    final Uint8List? loaded = await loadAmapStyleBytes(
      _FakeBundle(<String, Uint8List>{'assets/amap/style.data': bytes}),
      'assets/amap/style.data',
    );

    expect(loaded, <int>[1, 2, 3]);
  });

  test('样式文件缺失时返回 null，地图退回 SDK 默认样式', () async {
    final Uint8List? loaded = await loadAmapStyleBytes(
      _FakeBundle(const <String, Uint8List>{}),
      'assets/amap/style.data',
    );

    expect(loaded, isNull);
  });
}
