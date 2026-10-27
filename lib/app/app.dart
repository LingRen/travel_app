import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_repository.dart';
import 'cover_gate.dart';
import 'home_shell.dart';
import 'providers.dart';
import 'recovery_gate.dart';
import 'theme.dart';

/// 应用外壳。冷启动先过 [CoverGate]，封面退场后才构建 [RecoveryGate] 与四 tab
/// 主界面；因此恢复提示不会在封面底下弹出来。
///
/// 主题色由设置驱动：`appSettingsProvider` 一变更就整树重着色；首帧尚未
/// 读到设置时回退朱砂，避免闪一下。
class CyclingApp extends ConsumerWidget {
  const CyclingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeAccent accent =
        ref.watch(appSettingsProvider).value?.accent ?? ThemeAccent.cinnabar;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: kPaper,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MaterialApp(
        title: '行迹',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(accent),
        home: const CoverGate(child: RecoveryGate(child: HomeShell())),
      ),
    );
  }
}
