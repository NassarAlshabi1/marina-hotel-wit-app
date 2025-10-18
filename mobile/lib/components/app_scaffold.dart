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
        body: SafeArea(child: body),
        floatingActionButton: fab,
      ),
    );
  }
}
