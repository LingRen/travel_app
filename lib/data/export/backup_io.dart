import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 备份文件的读写。抽成接口是为了让设置页的 widget 测试不必碰文件系统，
/// 也避免测试里去弹真实的系统分享面板与文件选择器。
abstract class BackupIo {
  /// 把归档交给系统分享面板。失败时抛异常，由调用方提示用户。
  Future<void> exportArchive(Uint8List bytes, {required String fileName});

  /// 让用户选一个归档文件并读出字节。用户取消时返回 null。
  Future<Uint8List?> pickArchive();
}

/// 生产实现：临时目录 + 系统分享 + 系统文件选择器。
class FileBackupIo implements BackupIo {
  const FileBackupIo();

  @override
  Future<void> exportArchive(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final Directory dir = await getTemporaryDirectory();
    final File file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'application/zip')],
        subject: fileName,
        text: '骑行记录备份',
      ),
    );
  }

  @override
  Future<Uint8List?> pickArchive() async {
    // file_picker 13 的 API：`FilePicker` 是 abstract final class，方法是静态的
    // （没有 `FilePicker.platform`，也没有 `withData` 参数），`pickFile` 直接返回
    // `PlatformFile?`，用户取消时是 null。
    final PlatformFile? picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['zip'],
    );
    if (picked == null) return null;
    // `readAsBytes` 由平台实现负责，本地文件、blob、data URI 都能读。
    return picked.readAsBytes();
  }
}
