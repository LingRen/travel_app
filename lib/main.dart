import 'package:flutter/material.dart';

import 'app/app.dart';
import 'data/db/database.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 数据库在后台打开，不阻塞 `runApp`：否则首帧要等建库/迁移跑完，Android 与
  // iOS 的原生启动图就会多停留一段，印章和封面的衔接也会变慢。连接打开前
  // [CoverGate] 已经在画封面，打开完成后再挂载恢复检查与四 tab 主界面。
  runApp(CyclingApp(opening: openAppDatabase()));
}
