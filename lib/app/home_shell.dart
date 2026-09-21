import 'package:flutter/material.dart';

import '../features/history/history_page.dart';
import '../features/record/record_page.dart';
import '../features/settings/settings_page.dart';
import '../features/stats/stats_page.dart';

/// 底部四 tab 导航壳。见设计文档 10。
///
/// 四个 tab 都已是真实页面。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(
          index: _index,
          children: const <Widget>[
            RecordPage(),
            HistoryPage(),
            StatsPage(),
            SettingsPage(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (int i) => setState(() => _index = i),
          destinations: const <NavigationDestination>[
            NavigationDestination(icon: Icon(Icons.directions_bike), label: '记录'),
            NavigationDestination(icon: Icon(Icons.history), label: '历史'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: '统计'),
            NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
          ],
        ),
      );
}

/// 尚未实现的页面占位。四个 tab 都已接入真实页面，暂时没有引用者，保留备后续使用。
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Text('$title 页尚未实现')),
      );
}
