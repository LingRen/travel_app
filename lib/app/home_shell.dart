import 'package:flutter/material.dart';

import '../features/record/record_page.dart';

/// 底部四 tab 导航壳。见设计文档 10。
///
/// 「记录」已是真实的 [RecordPage]；历史 / 统计 / 设置仍是占位页，由 Plan B 实现。
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
            PlaceholderPage(title: '历史'),
            PlaceholderPage(title: '统计'),
            PlaceholderPage(title: '设置'),
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

/// 尚未实现的页面占位。Plan B 会逐个替换成真实页面。
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Text('$title 页尚未实现')),
      );
}
