import 'package:flutter/material.dart';

import '../features/history/history_page.dart';
import '../features/record/record_page.dart';
import '../features/settings/settings_page.dart';
import '../features/stats/stats_page.dart';
import 'ui/paper_nav_bar.dart';

/// 底部四 tab 导航壳。见设计文档 10。
///
/// 历史 tab 内嵌自己的 [Navigator]：详情从历史栈里推入，底部导航保持可见，
/// 返回手势也只退历史栈，不会把整个壳退掉。其余三个 tab 直接挂在根导航上。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final GlobalKey<NavigatorState> _historyNavKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(
          index: _index,
          children: <Widget>[
            const RecordPage(),
            NavigatorPopHandler<void>(
              // 只有停在历史 tab 时接管系统返回；否则返回键应该退出应用，
              // 而不是悄悄把历史栈里的详情弹掉。
              enabled: _index == 1,
              onPopWithResult: (_) => _historyNavKey.currentState?.maybePop(),
              child: Navigator(
                key: _historyNavKey,
                onGenerateRoute: (RouteSettings settings) =>
                    MaterialPageRoute<void>(
                  settings: settings,
                  builder: (BuildContext context) => const HistoryPage(),
                ),
              ),
            ),
            const StatsPage(),
            const SettingsPage(),
          ],
        ),
        bottomNavigationBar: PaperNavBar(
          selectedIndex: _index,
          onSelected: (int i) => setState(() => _index = i),
          items: const <PaperNavItem>[
            PaperNavItem(icon: Icons.route, label: '记录'),
            PaperNavItem(icon: Icons.menu_book_outlined, label: '历史'),
            PaperNavItem(icon: Icons.trending_up, label: '统计'),
            PaperNavItem(icon: Icons.tune, label: '设置'),
          ],
        ),
      );
}
