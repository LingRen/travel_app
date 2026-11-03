import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x_amap_base/x_amap_base.dart';

import '../../app/theme.dart';
import '../../config/app_config.dart';

/// 读取高德自定义样式二进制。文件不存在时返回 null，地图退回 SDK 默认样式。
///
/// 单独导出是为了让「资源缺失」这条分支可单测，不必创建平台视图。
Future<Uint8List?> loadAmapStyleBytes(
  AssetBundle bundle,
  String assetPath,
) async {
  try {
    final ByteData data = await bundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    // 尚未提供 style.data / style_extra.data 属于正常状态：用默认样式。
    return null;
  }
}

/// 高德原生底图。
///
/// 封装插件的一次性初始化、隐私声明、样式二进制、相机回调与失败占位；
/// 上层只看到「一块底图」，不依赖插件的具体 API。
///
/// 轨迹、标记、指北与比例尺仍由 Flutter 覆盖层绘制（见 `LiveRouteMap` /
/// `RouteMap`），因此这里不传任何 `Marker` / `Polyline`。
class AmapBasemap extends StatefulWidget {
  const AmapBasemap({
    required this.initialCamera,
    required this.onMapCreated,
    this.onCameraMove,
    this.onCameraMoveEnd,
    this.interactive = false,
    this.unavailableAfter = const Duration(seconds: 10),
    this.assetBundle,
    super.key,
  });

  /// 首帧相机。之后由上层用 [AMapController.moveCamera] 驱动。
  final CameraPosition initialCamera;

  final ValueChanged<AMapController> onMapCreated;
  final ValueChanged<CameraPosition>? onCameraMove;
  final ValueChanged<CameraPosition>? onCameraMoveEnd;

  /// 是否允许拖动 / 缩放。记录页必须为 false，详情页为 true。
  final bool interactive;

  /// 平台视图迟迟没有创建时，显示「地图暂时不可用」的等待上限。
  final Duration unavailableAfter;

  /// 测试可注入的资源包；生产用 `rootBundle`。
  final AssetBundle? assetBundle;

  @override
  State<AmapBasemap> createState() => _AmapBasemapState();
}

class _AmapBasemapState extends State<AmapBasemap> {
  CustomStyleOptions? _styleOptions;
  bool _stylesLoaded = false;
  bool _started = false;
  bool _created = false;
  bool _unavailable = false;
  Timer? _creationTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery 在 initState 阶段还不可用，插件的 AMapUtil.init(context)
    // 要读 devicePixelRatio，放到依赖就绪后再跑一次。
    if (_started) return;
    _started = true;
    _initializeSdk();
    unawaited(_loadStyles());
    _creationTimer = Timer(widget.unavailableAfter, () {
      if (!_created && mounted) setState(() => _unavailable = true);
    });
  }

  /// 插件初始化是静态的、进程内只生效一次；隐私声明三项必须全为 true，
  /// 否则 Android 上平台视图会白屏。同意与否由 `AmapPrivacyGate` 把关，
  /// 走到这里就代表用户已经同意。
  void _initializeSdk() {
    AMapInitializer.init(
      context,
      apiKey: const AMapApiKey(
        androidKey: kAmapMapKeyAndroid,
        iosKey: kAmapMapKeyIos,
      ),
    );
    AMapInitializer.updatePrivacyAgree(
      const AMapPrivacyStatement(
        hasContains: true,
        hasShow: true,
        hasAgree: true,
      ),
    );
  }

  Future<void> _loadStyles() async {
    final AssetBundle bundle = widget.assetBundle ?? rootBundle;
    final Uint8List? style = await loadAmapStyleBytes(
      bundle,
      kAmapMapStyleAsset,
    );
    final Uint8List? extra = await loadAmapStyleBytes(
      bundle,
      kAmapMapStyleExtraAsset,
    );
    if (!mounted) return;
    setState(() {
      _stylesLoaded = true;
      _styleOptions = style == null
          ? null
          : CustomStyleOptions(
              true,
              styleData: style,
              styleExtraData: extra,
            );
    });
  }

  @override
  void dispose() {
    _creationTimer?.cancel();
    // 平台视图的销毁由插件自身的 dispose 处理；这里不再重复调用，
    // 避免同一次 mapId 收到两次 dispose。
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_stylesLoaded || _unavailable) {
      return _AmapFallback(
        unavailable: _unavailable,
        paper: context.palette.paper,
      );
    }
    return AMapWidget(
      initialCameraPosition: widget.initialCamera,
      customStyleOptions: _styleOptions,
      // 比例尺、指北与纸色滤镜都由 Flutter 覆盖层承担。
      scaleEnabled: false,
      compassEnabled: false,
      buildingsEnabled: false,
      touchPoiEnabled: false,
      trafficEnabled: false,
      labelsEnabled: true,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      zoomGesturesEnabled: widget.interactive,
      scrollGesturesEnabled: widget.interactive,
      mapLanguage: MapLanguage.chinese,
      onMapCreated: (AMapController controller) {
        _creationTimer?.cancel();
        if (mounted) setState(() => _created = true);
        widget.onMapCreated(controller);
      },
      onCameraMove: widget.onCameraMove,
      onCameraMoveEnd: widget.onCameraMoveEnd,
    );
  }
}

/// 样式加载中 / 平台视图创建失败的纸色占位。
///
/// 只用纸色，不套颜色矩阵：原生平台视图不接受客户端滤镜，失败时也没有底图
/// 可滤。轨迹覆盖层仍画在它上面。
class _AmapFallback extends StatelessWidget {
  const _AmapFallback({required this.unavailable, required this.paper});

  final bool unavailable;
  final Color paper;

  @override
  Widget build(BuildContext context) {
    if (!unavailable) return ColoredBox(color: paper);
    return ColoredBox(
      color: paper,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '地图暂时不可用',
              key: const Key('amap-map-unavailable'),
              style: kLabelTextStyle.copyWith(color: context.palette.muted),
            ),
            const SizedBox(height: kSpaceXs),
            Text(
              '轨迹仍在记录，稍后会自动重试',
              style: kLabelTextStyle.copyWith(color: context.palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}
