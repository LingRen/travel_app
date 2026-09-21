import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override 类型在 riverpod 3 里只从 misc 入口导出。
import 'package:flutter_riverpod/misc.dart';
import 'package:sqflite/sqflite.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/db/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 数据库在启动时打开一次，之后所有仓储都复用这个连接。
  final Database db = await openAppDatabase();
  runApp(
    ProviderScope(
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      child: const CyclingApp(),
    ),
  );
}
