import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// 上次成功导出备份的时间（epoch ms），设置页「数据」分组读取。
final FutureProvider<int?> lastBackupAtProvider = FutureProvider<int?>(
  (Ref ref) => ref.watch(settingsRepositoryProvider).lastBackupAt(),
);
