import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/sync_service.dart';

class SyncActionButton extends ConsumerWidget {
  const SyncActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(syncStatusProvider);
    final status = statusAsync.asData?.value;
    final isSyncing =
        status == SyncStatus.pushing || status == SyncStatus.pulling;
    final hasError = status == SyncStatus.error;

    final tooltip = isSyncing
        ? 'جاري المزامنة...'
        : hasError
        ? 'حدث خطأ في آخر مزامنة، اضغط لإعادة المحاولة'
        : 'مزامنة يدوية (احتياطية)';

    return IconButton(
      onPressed: isSyncing
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(syncServiceProvider).runSync();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('تمت المزامنة بنجاح'),
                    duration: Duration(seconds: 2),
                  ),
                );
              } catch (Object e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('فشل في المزامنة: $e'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
      tooltip: tooltip,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: isSyncing
            ? const SizedBox(
                key: ValueKey('syncing'),
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.sync,
                key: ValueKey(hasError ? 'error' : 'idle'),
                color: hasError ? Colors.redAccent : null,
              ),
      ),
    );
  }
}
