import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/export/gpx.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';

/// 把一次骑行导出成 GPX 文件并调起系统分享面板。见设计文档 12。
///
/// 生成逻辑（[buildGpx]）是纯函数，已单测覆盖；这里只做「写文件 + 分享」
/// 这两步 IO，因此不写自动化测试（测试环境没有分享通道）。
class GpxExporter {
  const GpxExporter();

  /// 返回生成的文件路径。分享被取消或失败时抛出的异常交给调用方处理。
  Future<String> exportAndShare({
    required Ride ride,
    required List<TrackPoint> points,
  }) async {
    final Directory dir = await getTemporaryDirectory();
    final String fileName = 'ride_${ride.id ?? 0}.gpx';
    final File file = File('${dir.path}/$fileName');
    await file.writeAsString(buildGpx(ride: ride, points: points));

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'application/gpx+xml')],
        subject: ride.title?.trim().isNotEmpty == true ? ride.title : fileName,
        text: '骑行轨迹 GPX',
      ),
    );
    return file.path;
  }
}
