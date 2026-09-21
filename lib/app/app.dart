import 'package:flutter/material.dart';

import 'home_shell.dart';
import 'recovery_gate.dart';
import 'theme.dart';

/// 应用外壳。启动时先过 [RecoveryGate] 处理未结束会话，再进入四 tab 主界面。
class CyclingApp extends StatelessWidget {
  const CyclingApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '骑行记录',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const RecoveryGate(child: HomeShell()),
      );
}
