import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/workout.dart';
import 'providers.dart';

/// 启动时扫描未结束的骑行，弹窗让用户选择「继续」或「结算」。见设计文档 6.4。
class RecoveryGate extends ConsumerStatefulWidget {
  const RecoveryGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<RecoveryGate> createState() => _RecoveryGateState();
}

class _RecoveryGateState extends ConsumerState<RecoveryGate> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (_checked) return;
    _checked = true;

    final List<Workout> unfinished = await ref
        .read(workoutRepositoryProvider)
        .findUnfinished();
    if (!mounted || unfinished.isEmpty) return;

    final Workout ride = unfinished.first;
    final bool? resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: Text('检测到未结束的${ride.activityType.label}'),
        content: Text('开始于 ${_formatTime(ride.startedAtMs)}，是否继续？'),
        actions: <Widget>[
          // 「继续」是主操作（强调色实心），「结算保存」是收尾操作，走中性描边，
          // 别让两个强调色按钮在同一个对话框里互相争。
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('结算保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (resume == null) return;

    if (resume) {
      ref.read(resumeRideIdProvider.notifier).state = ride.id;
    } else {
      // 结算：用已有轨迹点算出汇总指标，置为 finished。见设计文档 6.4。
      await ref.read(workoutRepositoryProvider).settleRide(ride.id!);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String _formatTime(int ms) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
