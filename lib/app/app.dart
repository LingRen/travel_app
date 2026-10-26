import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_repository.dart';
import 'home_shell.dart';
import 'providers.dart';
import 'recovery_gate.dart';
import 'theme.dart';

/// 应用外壳。启动时先过 [RecoveryGate] 处理未结束会话，再进入四 tab 主界面。
///
/// 主题色由设置驱动：`appSettingsProvider` 一变更就整树重着色；首帧尚未
/// 读到设置时回退天青，避免闪一下。
class CyclingApp extends ConsumerWidget {
  const CyclingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeAccent accent =
        ref.watch(appSettingsProvider).value?.accent ?? ThemeAccent.sky;
    return MaterialApp(
      title: '运动记录',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(accent),
      home: const RecoveryGate(child: HomeShell()),
    );
  }
}