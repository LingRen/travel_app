import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override 类型在 riverpod 3 里只从 misc 入口导出。
import 'package:flutter_riverpod/misc.dart';
import 'package:sqflite/sqflite.dart';

import '../data/settings_repository.dart';
import 'cover_gate.dart';
import 'home_shell.dart';
import 'providers.dart';
import 'recovery_gate.dart';
import 'theme.dart';

/// 应用入口。数据库在 `main()` 里发起打开但不等待，[CyclingApp] 的首帧直接
/// 画 [CoverGate] 封面：原生启动图只需等到引擎出帧，不必陪等建库与迁移。
/// 连接就绪后再挂载恢复检查与四 tab 主界面。
class CyclingApp extends StatelessWidget {
  const CyclingApp({this.opening, super.key});

  /// 正在打开的数据库连接。为空表示连接已由外层 `ProviderScope` 注入（测试）。
  final Future<Database>? opening;

  @override
  Widget build(BuildContext context) {
    final Future<Database>? opening = this.opening;
    if (opening == null) return const _Shell(booted: true);

    return FutureBuilder<Database>(
      future: opening,
      builder: (BuildContext context, AsyncSnapshot<Database> snapshot) {
        if (snapshot.hasError) return const _BootFailure();
        final Database? db = snapshot.data;
        return ProviderScope(
          // riverpod 要求 override 数量固定，所以连接到位前后用同一个 override，
          // 只在闭包里换返回值：还没打开时读到就抛，`booted` 保证这期间没人读。
          overrides: <Override>[
            databaseProvider.overrideWith(
              (Ref ref) => db ?? (throw UnimplementedError('数据库尚未打开')),
            ),
          ],
          child: _Shell(booted: db != null),
        );
      },
    );
  }
}

/// 主题与四 tab 主界面。
///
/// 主题色由设置驱动：`appSettingsProvider` 一变更就整树重着色。连接还没打开
/// 时读不到设置（[booted] 为 false），先用朱砂兜底，避免首帧闪一下错误色。
class _Shell extends ConsumerWidget {
  const _Shell({required this.booted});

  final bool booted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeAccent accent = booted
        ? ref.watch(appSettingsProvider).value?.accent ?? ThemeAccent.cinnabar
        : ThemeAccent.cinnabar;
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
        // 封面结束前不构建下面的页面，恢复提示不会在封面底下弹出来；连接
        // 万一比封面还慢，就先留一张空纸面，别让页面读到还没注入的数据库。
        home: CoverGate(
          child: booted
              ? const RecoveryGate(child: HomeShell())
              : const ColoredBox(color: kPaper, child: SizedBox.expand()),
        ),
      ),
    );
  }
}

/// 本地库打不开时的兜底页。正常路径不会有这一屏，但建库失败不该只剩黑屏。
class _BootFailure extends StatelessWidget {
  const _BootFailure();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '行迹',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(kSpaceXxl),
            child: Text(
              '本地数据打不开，关闭应用后重试一次。',
              textAlign: TextAlign.center,
              style: kMutedTextStyle,
            ),
          ),
        ),
      ),
    );
  }
}
