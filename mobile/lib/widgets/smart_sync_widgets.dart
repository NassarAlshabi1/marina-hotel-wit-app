import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/smart_sync_provider.dart';
import '../providers/backup_provider.dart';

/// Widget لعرض حالة المزامنة في الوقت الفعلي
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

        if (!isEnabled || !isSignedIn) {
          return const SizedBox.shrink();
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSyncing
                ? Colors.blue.withOpacity(0.1)
                : Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSyncing ? Colors.blue : Colors.green,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSyncing) ...[
                SizedBox(
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
class SmartSyncNotificationListener extends ConsumerStatefulWidget {
  final Widget child;

  const SmartSyncNotificationListener({super.key, required this.child});

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
      if (next.hasValue) {
        final status = next.value!;
        final lastSyncString = status['last_sync_check'] as String?;

        if (lastSyncString != null) {
          final lastSync = DateTime.parse(lastSyncString);

          // إذا كانت هناك مزامنة جديدة
          if (_lastSyncTime == null || lastSync.isAfter(_lastSyncTime!)) {
            _lastSyncTime = lastSync;

            // عرض إشعار نجاح المزامنة
            if (mounted && _lastSyncTime != null) {
              _showSyncNotification(context, 'تمت مزامنة البيانات من جهاز آخر');
            }
          }
        }
      }
    });

    return widget.child;
  }

  void _showSyncNotification(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.cloud_sync, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

/// FloatingActionButton لمزامنة يدوية سريعة
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

        if (!isEnabled || !isSignedIn) {
          return const SizedBox.shrink();
        }

        Future<void> runManualSync() async {
          try {
            final manager = ref.read(smartSyncManagerProvider);
            await manager.forceSyncNow();

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🔄 بدأت المزامنة اليدوية...'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'تعذر بدء المزامنة. تحقق من الاتصال ثم أعد المحاولة',
                  ),
                  backgroundColor: Colors.red,
                  action: SnackBarAction(
                    label: 'إعادة',
                    textColor: Colors.white,
                    onPressed: runManualSync,
                  ),
                ),
              );
            }
          }
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
/// إصلاح: تم تحويل من ConsumerWidget إلى ConsumerStatefulWidget
/// لنقل addPostFrameCallback من build() إلى initState() - يتم تنفيذه مرة واحدة فقط
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
        final syncInterval = status['sync_interval_minutes'] as int;
        final lastSync = status['last_sync_check'] as String?;
        final isSignedIn = status['signed_in'] as bool;

        if (!isSignedIn) return const SizedBox.shrink();

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isEnabled ? Colors.green : Colors.grey,
              child: Icon(
                isEnabled ? Icons.sync : Icons.sync_disabled,
                color: Colors.white,
                size: 20,
              ),
            ),
            title: Text(
              'المزامنة بين الأجهزة',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEnabled ? 'مُفعلة - فحص كل $syncInterval دقائق' : 'معطلة',
                ),
                if (isSyncing)
                  const Text(
                    '🔄 جارِ المزامنة...',
                    style: TextStyle(color: Colors.blue),
                  ),
                if (lastSync != null && !isSyncing)
                  Text('آخر فحص: ${_formatLastSync(DateTime.parse(lastSync))}'),
              ],
            ),
            trailing: isEnabled && !isSyncing
                ? IconButton(
                    icon: const Icon(Icons.sync_alt),
                    onPressed: () async {
                      final manager = ref.read(smartSyncManagerProvider);
                      await manager.forceSyncNow();
                    },
                    tooltip: 'مزامنة الآن',
                  )
                : null,
            onTap: () {
              Navigator.pushNamed(context, '/smart-sync-settings');
            },
          ),
        );
      },
    );
  }

  String _formatLastSync(DateTime lastSync) {
    final now = DateTime.now();
    final difference = now.difference(lastSync);

    if (difference.inMinutes < 1) {
      return 'الآن';
    } else if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else if (difference.inHours < 24) {
      return 'منذ ${difference.inHours} ساعة';
    } else {
      return 'منذ ${difference.inDays} يوم';
    }
  }
}
