import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/export/backup.dart';
import '../../data/export/backup_store.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';

/// 备份与恢复区块。见设计文档 10.5 与 12。
class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('备份与恢复', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _export,
                child: const Text('导出备份'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _restore,
                child: const Text('恢复备份'),
              ),
            ),
          ],
        ),
        if (_message != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _message!,
            style: TextStyle(
              fontSize: 13,
              color: _isError ? Theme.of(context).colorScheme.error : null,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final BackupStore store = ref.read(backupStoreProvider);
      final List<Ride> rides = await store.listRides();
      final List<TrackPoint> points = await store.listPoints();
      final Uint8List bytes = buildBackupArchive(
        rides: rides,
        points: points,
        exportedAtMs: ref.read(nowProvider)(),
      );
      await ref.read(backupIoProvider).exportArchive(
            bytes,
            fileName: 'cycling_backup_${DateTime.now().millisecondsSinceEpoch}.zip',
          );
      _setMessage('已导出 ${rides.length} 条记录', isError: false);
    } catch (error) {
      _setMessage('导出失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final Uint8List? bytes = await ref.read(backupIoProvider).pickArchive();
      if (bytes == null) return; // 用户取消，什么都不做

      // 先解析再确认：版本不匹配时直接说明原因，不要先弹一个会被推翻的确认框。
      final BackupPayload payload = parseBackupArchive(bytes);

      if (!mounted) return;
      final bool ok = await _confirm(payload) ?? false;
      if (!ok) return;

      await ref.read(backupStoreProvider).apply(payload, replaceExisting: true);
      // 恢复走的是 BackupStore，不经过 RideRepository，得在这里手动通知
      // 历史页与统计页重查，否则它们还显示被替换掉的旧数据。
      ref.read(rideDataRevisionProvider.notifier).markChanged();
      _setMessage(
        '恢复完成：${payload.rides.length} 条记录、${payload.points.length} 个轨迹点',
        isError: false,
      );
    } on BackupVersionException catch (error) {
      _setMessage('$error', isError: true);
    } on BackupFormatException catch (error) {
      _setMessage('$error', isError: true);
    } catch (error) {
      _setMessage('恢复失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(BackupPayload payload) => showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('确认恢复？'),
          content: Text(
            '将清空当前全部记录，替换成备份里的 '
            '${payload.rides.length} 条记录、${payload.points.length} 个轨迹点。'
            '这一步无法撤销。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('恢复'),
            ),
          ],
        ),
      );

  void _setMessage(String message, {required bool isError}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _isError = isError;
    });
  }
}
