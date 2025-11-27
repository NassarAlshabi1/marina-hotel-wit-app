import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/notes/notes_screen.dart';
import '../providers/repository_providers.dart';
import '../services/sync_service.dart';


class AppScaffold extends ConsumerWidget {
  const AppScaffold({super.key, required this.title, required this.body, this.actions, this.fab});
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? fab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCountAsync = ref.watch(simpleNotesUnreadCountProvider);
    final unreadCount = unreadCountAsync.maybeWhen(data: (count) => count, orElse: () => 0);
    final hasUnread = unreadCount > 0;

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
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: () async {
                await ref.read(syncServiceProvider).runSync();
              },
              tooltip: 'مزامنة يدوية (احتياطية)',
              icon: const Icon(Icons.sync),
            ),
            if (actions != null) ...actions!,
          ],
        ),
        body: SafeArea(
          child: body,
        ),
        floatingActionButton: fab,
      ),
    );
  }
}
