import 'package:flutter/material.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({super.key, required this.title, required this.body, this.actions, this.fab});
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? fab;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.sync)),
            if (actions != null) ...actions!,
          ],
        ),
        drawer: _AppDrawer(),
        body: SafeArea(child: body),
        floatingActionButton: fab,
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF006C67)),
              child: Align(alignment: Alignment.bottomRight, child: Text('القائمة', style: TextStyle(color: Colors.white, fontSize: 20))),
            ),
            ListTile(
              leading: const Icon(Icons.group),
              title: const Text('الموظفون'),
              onTap: () => Navigator.pushNamed(context, '/employees'),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('المصروفات'),
              onTap: () => Navigator.pushNamed(context, '/expenses'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: const Text('الصندوق'),
              onTap: () => Navigator.pushNamed(context, '/finance/cash-register'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('حركة الصندوق'),
              onTap: () => Navigator.pushNamed(context, '/finance/cash-transactions'),
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('الإعدادات'),
              onTap: () => Navigator.pushNamed(context, '/settings'),
            ),
            ListTile(
              leading: const Icon(Icons.note_alt),
              title: const Text('الملاحظات'),
              onTap: () => Navigator.pushNamed(context, '/notes'),
            ),
          ],
        ),
      ),
    );
  }
}
