import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/sync_service.dart';
import '../../services/appwrite_delta_sync.dart';
import '../../providers/appwrite_providers.dart';

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
            : 'مزامنة يدوية (احتياطية) - Field-Level Delta Sync';

    return PopupMenuButton<String>(
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
      enabled: !isSyncing,
      onSelected: (value) async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          switch (value) {
            case 'sync':
              await ref.read(syncServiceProvider).runSync();
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('تمت المزامنة بنجاح'),
                  duration: Duration(seconds: 2),
                ),
              );
              break;
            case 'push':
              final deltaSync = ref.read(appwriteDeltaSyncProvider);
              final result = await deltaSync.pushDeltaChanges();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(result.success
                      ? 'تم رفع ${result.pushedCount} سجل بنجاح'
                      : 'فشل الرفع: ${result.message}'),
                  duration: const Duration(seconds: 3),
                ),
              );
              break;
            case 'pull':
              final deltaSync = ref.read(appwriteDeltaSyncProvider);
              final result = await deltaSync.pullDeltaChanges();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(result.success
                      ? 'تم سحب ${result.pulledCount} سجل بنجاح'
                      : 'فشل السحب: ${result.message}'),
                  duration: const Duration(seconds: 3),
                ),
              );
              break;
          }
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('خطأ: $e'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'sync',
          child: ListTile(
            leading: Icon(Icons.sync),
            title: Text('مزامنة'),
            subtitle: Text('مزامنة التغييرات'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'push',
          child: ListTile(
            leading: Icon(Icons.cloud_upload, color: Colors.blue),
            title: Text('رفع'),
            subtitle: Text('رفع التغييرات للسحابة'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'pull',
          child: ListTile(
            leading: Icon(Icons.cloud_download, color: Colors.green),
            title: Text('سحب'),
            subtitle: Text('سحب التغييرات من السحابة'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

final appwriteDeltaSyncProvider = Provider<AppwriteDeltaSync>((ref) {
  return AppwriteDeltaSync.instance;
});
