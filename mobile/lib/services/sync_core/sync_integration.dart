import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_core.dart';
import '../local_db.dart';

final databaseSyncHooksProvider = Provider<DatabaseSyncHooks>((ref) {
  final db = ref.watch(databaseProvider);
  final eventBus = ref.watch(eventBusProvider);
  return DatabaseSyncHooks(database: db, eventBus: eventBus);
});

final syncSystemInitProvider = FutureProvider<void>((ref) async {
  final eventBus = ref.watch(eventBusProvider);
  await eventBus.initialize();

  final router = ref.watch(syncRouterProvider);
  await router.start();

  final hooks = ref.watch(databaseSyncHooksProvider);
  await hooks.initialize();

  await eventBus.replayUnacknowledged();

  debugPrint('SyncSystem: Fully initialized');
});

class SyncSystemWidget extends ConsumerWidget {
  final Widget child;

  const SyncSystemWidget({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncInit = ref.watch(syncSystemInitProvider);

    return syncInit.when(
      data: (_) => child,
      loading: () => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('جاري تهيئة نظام المزامنة...'),
              ],
            ),
          ),
        ),
      ),
      error: (error, stack) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('خطأ في تهيئة النظام: $error'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.refresh(syncSystemInitProvider),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(syncRouterStateProvider);
    final pendingAsync = ref.watch(pendingEventsCountProvider);

    return stateAsync.when(
      data: (state) {
        final pendingCount = pendingAsync.valueOrNull ?? 0;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStateIcon(state),
            if (pendingCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$pendingCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        );
      },
      loading: () => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, __) => const Icon(Icons.error, color: Colors.red, size: 20),
    );
  }

  Widget _buildStateIcon(SyncRouterState state) {
    switch (state) {
      case SyncRouterState.idle:
        return const Icon(Icons.cloud_done, color: Colors.green, size: 20);
      case SyncRouterState.syncing:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case SyncRouterState.error:
        return const Icon(Icons.cloud_off, color: Colors.red, size: 20);
      case SyncRouterState.stopped:
        return const Icon(Icons.cloud_outlined, color: Colors.grey, size: 20);
    }
  }
}

class SyncButton extends ConsumerWidget {
  const SyncButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncNotifierProvider);

    return IconButton(
      onPressed: syncState.isSyncing
          ? null
          : () => ref.read(syncNotifierProvider.notifier).syncNow(),
      icon: syncState.isSyncing
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync),
      tooltip: 'مزامنة الآن',
    );
  }
}

class AdapterStatusList extends ConsumerWidget {
  const AdapterStatusList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusesAsync = ref.watch(adapterStatusesProvider);

    return statusesAsync.when(
      data: (statuses) {
        return Column(
          children: statuses.entries.map((entry) {
            final status = entry.value;
            return ListTile(
              leading: Icon(
                _getIconForType(entry.key),
                color: status.isReady ? Colors.green : Colors.grey,
              ),
              title: Text(_getNameForType(entry.key)),
              subtitle: Text(
                status.isReady
                    ? 'متصل'
                    : status.isEnabled
                        ? 'غير متصل'
                        : 'معطل',
              ),
              trailing: Switch(
                value: status.isEnabled,
                onChanged: (value) async {
                  final adapter = ref.read(syncRouterProvider).getAdapter(entry.key);
                  await adapter?.setEnabled(value);
                  ref.refresh(adapterStatusesProvider);
                },
              ),
            );
          }).toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('خطأ: $error')),
    );
  }

  IconData _getIconForType(SyncTargetType type) {
    switch (type) {
      case SyncTargetType.appwrite:
        return Icons.cloud;
      case SyncTargetType.googleDrive:
        return Icons.add_to_drive;
      case SyncTargetType.localJson:
        return Icons.save;
    }
  }

  String _getNameForType(SyncTargetType type) {
    switch (type) {
      case SyncTargetType.appwrite:
        return 'Appwrite Cloud';
      case SyncTargetType.googleDrive:
        return 'Google Drive';
      case SyncTargetType.localJson:
        return 'نسخة محلية';
    }
  }
}
