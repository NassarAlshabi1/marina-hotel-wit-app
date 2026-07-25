import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/repository_providers.dart';
import '../screens/notes/notes_screen.dart' deferred as notes;
import '../utils/performance_monitor.dart';
import 'widgets/sync_action_button.dart';

class AppScaffold extends ConsumerWidget {
  const AppScaffold({
    required this.title,
    required this.body,
    super.key,
    this.actions,
    this.fab,
    this.subtitle,
    this.appBarBackgroundColor,
    this.titleColor,
    this.subtitleColor,
    this.titleAlign,
  });
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? fab;

  /// عنوان ثانوي يظهر أسفل العنوان الرئيسي في الـ AppBar
  /// (مثال: عنوان التقرير بخط أصغر وتوسيط)
  final String? subtitle;

  /// لون خلفية الـ AppBar (إذا لم يُحدد يستخدم لون الثيم)
  final Color? appBarBackgroundColor;

  /// لون العنوان الرئيسي
  final Color? titleColor;

  /// لون العنوان الثانوي
  final Color? subtitleColor;

  /// محاذاة العنوان الرئيسي (الافتراضي: توسيط)
  /// استخدم TextAlign.end للمحاذاة اليمنى في RTL
  final TextAlign? titleAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCountAsync = ref.watch(simpleNotesUnreadCountProvider);
    final unreadCount = unreadCountAsync.maybeWhen(data: (count) => count, orElse: () => 0);
    final hasUnread = unreadCount > 0;

    final isLightBg = appBarBackgroundColor != null && appBarBackgroundColor!.computeLuminance() > 0.5;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: subtitle != null ? 64 : null,
          backgroundColor: appBarBackgroundColor,
          foregroundColor: isLightBg ? Colors.black87 : null,
          elevation: appBarBackgroundColor != null ? 1 : null,
          title: subtitle != null
              ? Column(
                  crossAxisAlignment: titleAlign == TextAlign.end ? CrossAxisAlignment.end : CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: titleAlign ?? TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: titleColor ?? (isLightBg ? Colors.black : Colors.white),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: subtitleColor ?? (isLightBg ? Colors.black54 : Colors.white70),
                      ),
                    ),
                  ],
                )
              : Text(title),
          actions: [
            IconButton(
              onPressed: () async {
                await notes.loadLibrary();
                if (context.mounted) {
                  unawaited(
                    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => notes.NotesScreen())),
                  );
                }
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
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SyncActionButton(),
            if (actions != null) ...actions!,
          ],
        ),
        body: SafeArea(
          child: PerformanceInspector(
            name: title,
            child: body,
          ),
        ),
        floatingActionButton: fab,
      ),
    );
  }
}
