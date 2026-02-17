import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/smart_sync_provider.dart';
import '../providers/backup_provider.dart';
import '../screens/settings/smart_sync_settings_screen.dart';

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
        final isSignedIn = status['signed_in'] as bool;

        if (!isSignedIn) return const SizedBox.shrink();

        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SmartSyncSettingsScreen(),
                ),
              );
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
                        Text(
                          'المزامنة بين الأجهزة',
                          style: const TextStyle(
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
                          final manager = ref.read(smartSyncManagerProvider);
                          await manager.forceSyncNow();
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
