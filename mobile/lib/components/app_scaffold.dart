import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/notes/notes_screen.dart';
import '../services/providers.dart';

class AppScaffold extends ConsumerWidget {
  const AppScaffold({super.key, required this.title, required this.body, this.actions, this.fab});
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? fab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(activeNotesProvider);
    final hasUnread = notesAsync.maybeWhen(data: (notes) => notes.isNotEmpty, orElse: () => false);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotesScreen()));
              },
              tooltip: 'التنبيهات',
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(hasUnread ? Icons.notifications_active : Icons.notifications_none),
                  if (hasUnread)
                    const Positioned(
                      right: -2,
                      top: -2,
                      child: CircleAvatar(radius: 4, backgroundColor: Colors.red),
                    ),
                ],
              ),
            ),
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
