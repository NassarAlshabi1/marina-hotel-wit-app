import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/backup_provider.dart';
import '../providers/smart_sync_provider.dart';

// ═══════════════════════════════════════════════════════════════════
// ⚠️ Smart Sync widgets are DISABLED
// With smartSyncStatusProvider always returning enabled: false,
// all widgets below will render as SizedBox.shrink() automatically.
// Kept for compilation compatibility — they won't appear in the UI.
// ═══════════════════════════════════════════════════════════════════

/// Widget لعرض حالة المزامنة في الوقت الفعلي
/// [DISABLED] Always renders invisible — smart sync is off.
class SmartSyncStatusWidget extends ConsumerWidget {
  const SmartSyncStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(smartSyncStatusProvider);

    return statusAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (status) {
        final isEnabled = status['enabled'] as bool;
        final isSyncing = status['is_syncing'] as bool;
        final isSignedIn = status['signed_in'] as bool;

        // [DISABLED] Always hides — isEnabled and isSignedIn are both false.
        if (!isEnabled || !isSignedIn) {
          return const SizedBox.shrink();
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSyncing
                ? Colors.blue.withValues(alpha: 0.1)
                : Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSyncing ? Colors.blue : Colors.green,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSyncing) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'مزامنة...',
                  style: TextStyle(fontSize: 11, color: Colors.blue),
                ),
              ] else ...[
                const Icon(Icons.cloud_done, size: 12, color: Colors.green),
                const SizedBox(width: 4),
                const Text(
                  'مُزامن',
                  style: TextStyle(fontSize: 11, color: Colors.green),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Widget لإشعارات المزامنة التفاعلية
/// [DISABLED] No notifications will be shown — smart sync is off.
class SmartSyncNotificationListener extends ConsumerStatefulWidget {

  const SmartSyncNotificationListener({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SmartSyncNotificationListener> createState() =>
      _SmartSyncNotificationListenerState();
}

class _SmartSyncNotificationListenerState
    extends ConsumerState<SmartSyncNotificationListener> {
  DateTime? _lastSyncTime;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Map<String, dynamic>>>(smartSyncStatusProvider, (
      previous,
      next,
    ) {
      // [DISABLED] No notifications — smart sync status never reports sync events.
      // Keeping the listener structure for compilation compatibility.
    });

    return widget.child;
  }
}

/// FloatingActionButton لمزامنة يدوية سريعة
/// [DISABLED] Always renders invisible — smart sync is off.
class SmartSyncFloatingButton extends ConsumerWidget {
  const SmartSyncFloatingButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(smartSyncStatusProvider);

    return statusAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (status) {
        final isEnabled = status['enabled'] as bool;
        final isSyncing = status['is_syncing'] as bool;
        final isSignedIn = status['signed_in'] as bool;

        // [DISABLED] Always hides — isEnabled and isSignedIn are both false.
        if (!isEnabled || !isSignedIn) {
          return const SizedBox.shrink();
        }

        Future<void> runManualSync() async {
          // [DISABLED] Smart sync forceSyncNow is a no-op.
        }

        return FloatingActionButton.small(
          onPressed: isSyncing ? null : runManualSync,
          backgroundColor: isSyncing ? Colors.grey : Colors.blue,
          tooltip: isSyncing ? 'مزامنة جارية...' : 'مزامنة يدوية',
          child: isSyncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.sync, size: 20),
        );
      },
    );
  }
}

/// Card مختصر لحالة المزامنة (للـ dashboard)
/// [DISABLED] Always renders invisible — smart sync is off.
/// Navigation to SmartSyncSettingsScreen has been removed.
class SmartSyncDashboardCard extends ConsumerStatefulWidget {
  const SmartSyncDashboardCard({super.key});

  @override
  ConsumerState<SmartSyncDashboardCard> createState() =>
      _SmartSyncDashboardCardState();
}

class _SmartSyncDashboardCardState
    extends ConsumerState<SmartSyncDashboardCard> {
  @override
  void initState() {
    super.initState();
    // التحقق من حالة تسجيل الدخول الفعلية مرة واحدة عند إنشاء الويدجت
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(backupStatusProvider.notifier).refreshSignInStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(smartSyncStatusProvider);

    return statusAsync.when(
      loading: () =>
          const Card(child: ListTile(title: Text('تحميل حالة المزامنة...'))),
      error: (error, stack) => const SizedBox.shrink(),
      data: (status) {
        final isEnabled = status['enabled'] as bool;
        final isSyncing = status['is_syncing'] as bool;
        final isSignedIn = status['signed_in'] as bool;

        // [DISABLED] Always hides — signed_in is always false.
        if (!isSignedIn) {
          return const SizedBox.shrink();
        }

        // [DISABLED] The code below is unreachable since isSignedIn is always false.
        // Kept for compilation compatibility. Navigation to SmartSyncSettingsScreen
        // has been removed — tapping the card does nothing.
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () {
              // ⚠️ Navigation to SmartSyncSettingsScreen DISABLED.
              // That screen controls a disabled feature.
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isEnabled ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isEnabled ? Icons.sync : Icons.sync_disabled,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'المزامنة بين الأجهزة',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          isSyncing
                              ? 'جارِ المزامنة...'
                              : isEnabled
                              ? 'مُفعلة'
                              : 'معطلة',
                          style: TextStyle(
                            fontSize: 10,
                            color: isSyncing ? Colors.blue : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isEnabled && !isSyncing)
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.sync_alt, size: 18),
                        onPressed: () async {
                          // [DISABLED] Smart sync forceSyncNow is a no-op.
                        },
                        tooltip: 'مزامنة الآن',
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
