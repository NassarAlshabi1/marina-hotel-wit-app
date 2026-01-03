import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/appwrite_providers.dart';
import '../providers/repository_providers.dart';
import '../providers/smart_sync_provider.dart';
import '../services/daos/outbox_dao.dart';

class DashboardSyncButton extends ConsumerStatefulWidget {
  const DashboardSyncButton({super.key});

  @override
  ConsumerState<DashboardSyncButton> createState() => _DashboardSyncButtonState();
}

class _DashboardSyncButtonState extends ConsumerState<DashboardSyncButton> with SingleTickerProviderStateMixin {
  bool _isImmediateSyncing = false;
  Timer? _lastSyncUpdateTimer;
  late AnimationController _syncAnimationController;
  int _pendingChangesCount = 0;

  @override
  void initState() {
    super.initState();
    _syncAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _lastSyncUpdateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
    _loadPendingChangesCount();
  }

  @override
  void dispose() {
    _lastSyncUpdateTimer?.cancel();
    _syncAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingChangesCount() async {
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      final count = await outboxDao.count();
      if (mounted) {
        setState(() {
          _pendingChangesCount = count;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Failed to load pending changes count: $e\n$stackTrace');
    }
  }

  Future<bool> _checkLocalChanges() async {
    try {
      final manager = ref.read(smartSyncManagerProvider);
      final hasChanges = await manager.hasLocalChanges();
      return hasChanges;
    } catch (e) {
      debugPrint('❌ خطأ في فحص التغييرات المحلية: $e');
      return false;
    }
  }

  Future<bool> _isAppwriteSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('appwrite_sync_enabled') ?? true;
  }

  Future<void> _triggerImmediateSync(BuildContext context) async {
    if (_isImmediateSyncing) {
      return;
    }

    _syncAnimationController.repeat();

    try {
      await _loadPendingChangesCount();

      final smartSyncManager = ref.read(smartSyncManagerProvider);
      final smartEnabled = await smartSyncManager.isEnabled();
      final appwriteEnabled = await _isAppwriteSyncEnabled();

      if (!smartEnabled && !appwriteEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ℹ️ المزامنة معطلة')),
          );
        }
        return;
      }

      setState(() => _isImmediateSyncing = true);

      final hasLocalChanges = _pendingChangesCount > 0 || await _checkLocalChanges();

      if (hasLocalChanges) {
        await _pushThenPull(context);
      } else {
        await _pullOnly(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ فشلت المزامنة: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      _syncAnimationController.stop();
      _syncAnimationController.reset();
      if (mounted) {
        setState(() => _isImmediateSyncing = false);
      }
      await _loadPendingChangesCount();
    }
  }

  Future<String?> _showLocalChangesDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.tune, color: Colors.blue, size: 28),
            SizedBox(width: 8),
            Expanded(child: Text('خيارات المزامنة')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اختر الوضع المناسب للمزامنة.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💡 الخيارات:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• رفع ثم سحب: يرفع التغييرات المحلية ثم يسحب من السحابة (موصى به)',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• سحب فقط: يسحب من السحابة بدون رفع',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• مزامنة كاملة: رفع + سحب (قد تأخذ وقتاً أطول)',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text('إلغاء'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'pull_only'),
            icon: Icon(Icons.download, size: 18),
            label: Text('سحب فقط'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'full_sync'),
            icon: Icon(Icons.sync, size: 18),
            label: Text('مزامنة كاملة'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.blue),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'push_first'),
            icon: Icon(Icons.upload, size: 18),
            label: Text('رفع ثم سحب'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
        actionsAlignment: MainAxisAlignment.spaceBetween,
      ),
    );
  }

  Future<void> _pushThenPull(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    final smartSyncManager = ref.read(smartSyncManagerProvider);
    final appwriteSyncManager = ref.read(appwriteSyncManagerProvider);

    final smartEnabled = await smartSyncManager.isEnabled();
    final appwriteEnabled = await _isAppwriteSyncEnabled();

    messenger.showSnackBar(
      const SnackBar(
        content: Text('📤 جاري رفع التغييرات المحلية...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final futures = <Future<Object?>>[];

      if (smartEnabled) {
        futures.add(smartSyncManager.pushLocalChanges());
      }
      if (appwriteEnabled) {
        futures.add(appwriteSyncManager.pushLocalChanges());
      }

      final results = await Future.wait(futures);

      final hasAnyFailure = results.any((r) => r is bool && r == false);

      if (!mounted) return;

      if (hasAnyFailure) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('⚠️ تم رفع جزء من التغييرات فقط'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('✅ تم رفع التغييرات بنجاح'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;
      await _pullOnly(context);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في رفع التغييرات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pullOnly(BuildContext context, {bool showWarning = false}) async {
    final messenger = ScaffoldMessenger.of(context);

    final smartSyncManager = ref.read(smartSyncManagerProvider);
    final appwriteSyncManager = ref.read(appwriteSyncManagerProvider);

    final smartEnabled = await smartSyncManager.isEnabled();
    final appwriteEnabled = await _isAppwriteSyncEnabled();

    if (showWarning) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('⚠️ تحذير: سحب فقط (بدون رفع التغييرات المحلية)'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 300));
    }

    messenger.showSnackBar(
      const SnackBar(
        content: Text('📥 جاري سحب التغييرات من السحابة...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final futures = <Future<Object?>>[];

      if (smartEnabled) {
        futures.add(smartSyncManager.pullRemoteChanges());
      }
      if (appwriteEnabled) {
        futures.add(appwriteSyncManager.sync(push: false, pull: true));
      }

      await Future.wait(futures);

      ref.invalidate(smartSyncStatusProvider);

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('✅ تم السحب بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في السحب: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _performSync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    final smartSyncManager = ref.read(smartSyncManagerProvider);
    final appwriteSyncManager = ref.read(appwriteSyncManagerProvider);

    final smartEnabled = await smartSyncManager.isEnabled();
    final appwriteEnabled = await _isAppwriteSyncEnabled();

    messenger.showSnackBar(
      const SnackBar(
        content: Text('🔄 جاري المزامنة الكاملة...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final futures = <Future<Object?>>[];

      if (smartEnabled) {
        futures.add(smartSyncManager.forceSyncNow());
      }
      if (appwriteEnabled) {
        futures.add(appwriteSyncManager.sync(push: true, pull: true));
      }

      await Future.wait(futures);

      ref.invalidate(smartSyncStatusProvider);

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('✅ تمت المزامنة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في المزامنة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
    }
  }

  String _formatLastSyncTime(DateTime? lastSync) {
    if (lastSync == null) return 'لم تتم مزامنة بعد';

    final now = DateTime.now();
    final difference = now.difference(lastSync);

    if (difference.inSeconds < 60) {
      return 'منذ ${difference.inSeconds} ثانية';
    } else if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else if (difference.inHours < 24) {
      return 'منذ ${difference.inHours} ساعة';
    } else {
      final days = difference.inDays;
      return 'منذ $days ${days == 1 ? "يوم" : "أيام"}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(smartSyncStatusProvider);

    return statusAsync.when(
      data: (status) {
        final lastSyncStr = status['last_sync_check'] as String?;
        final lastSync = lastSyncStr != null ? DateTime.tryParse(lastSyncStr) : null;
        final isEnabled = status['enabled'] as bool? ?? false;
        final isSyncing = status['is_syncing'] as bool? ?? false;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: _pendingChangesCount > 0
                  ? 'لديك $_pendingChangesCount تغيير معلق - سيتم رفعها للسحابة\nضغطة طويلة لخيارات متقدمة'
                  : 'سحب آخر التحديثات من السحابة\nضغطة طويلة لخيارات متقدمة',
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isImmediateSyncing
                            ? [Colors.blue.shade400, Colors.blue.shade600]
                            : isSyncing
                                ? [Colors.orange.shade400, Colors.orange.shade600]
                                : _pendingChangesCount > 0
                                    ? [Colors.purple.shade400, Colors.purple.shade600]
                                    : isEnabled
                                        ? [Colors.green.shade400, Colors.green.shade600]
                                        : [Colors.grey.shade400, Colors.grey.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: (_isImmediateSyncing || isSyncing
                                  ? Colors.blue
                                  : _pendingChangesCount > 0
                                      ? Colors.purple
                                      : isEnabled
                                          ? Colors.green
                                          : Colors.grey)
                              .withOpacity(0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _isImmediateSyncing ? null : () => _triggerImmediateSync(context),
                        onLongPress: _isImmediateSyncing
                            ? null
                            : () async {
                                final action = await _showLocalChangesDialog(context);
                                if (!mounted || action == null) {
                                  return;
                                }

                                _syncAnimationController.repeat();

                                try {
                                  await _loadPendingChangesCount();

                                  final smartSyncManager = ref.read(smartSyncManagerProvider);
                                  final smartEnabled = await smartSyncManager.isEnabled();
                                  final appwriteEnabled = await _isAppwriteSyncEnabled();

                                  if (!smartEnabled && !appwriteEnabled) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('ℹ️ المزامنة معطلة')),
                                      );
                                    }
                                    return;
                                  }

                                  setState(() => _isImmediateSyncing = true);

                                  if (action == 'push_first') {
                                    await _pushThenPull(context);
                                  } else if (action == 'pull_only') {
                                    await _pullOnly(context, showWarning: true);
                                  } else if (action == 'full_sync') {
                                    await _performSync(context);
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('❌ فشلت المزامنة: $e'), backgroundColor: Colors.red),
                                    );
                                  }
                                } finally {
                                  _syncAnimationController.stop();
                                  _syncAnimationController.reset();
                                  if (mounted) {
                                    setState(() => _isImmediateSyncing = false);
                                  }
                                  await _loadPendingChangesCount();
                                }
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isImmediateSyncing || isSyncing)
                                RotationTransition(
                                  turns: _syncAnimationController,
                                  child: Icon(
                                    Icons.sync,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                )
                              else
                                Icon(
                                  _pendingChangesCount > 0
                                      ? Icons.cloud_upload
                                      : (isEnabled ? Icons.cloud_download : Icons.cloud_off),
                                  size: 16,
                                  color: Colors.white,
                                ),
                              const SizedBox(width: 6),
                              Text(
                                _isImmediateSyncing
                                    ? 'جاري المزامنة...'
                                    : isSyncing
                                        ? 'المزامنة نشطة'
                                        : _pendingChangesCount > 0
                                            ? 'رفع التغييرات'
                                            : 'تحديث البيانات',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_pendingChangesCount > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.5),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Center(
                          child: Text(
                            _pendingChangesCount > 99 ? '99+' : '$_pendingChangesCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isSyncing
                    ? Colors.blue.shade50
                    : _pendingChangesCount > 0
                        ? Colors.purple.shade50
                        : isEnabled
                            ? Colors.green.shade50
                            : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSyncing
                      ? Colors.blue.shade200
                      : _pendingChangesCount > 0
                          ? Colors.purple.shade200
                          : isEnabled
                              ? Colors.green.shade200
                              : Colors.grey.shade300,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isEnabled
                        ? (isSyncing ? Icons.sync : Icons.check_circle)
                        : Icons.cloud_off,
                    size: 14,
                    color: isSyncing
                        ? Colors.blue
                        : _pendingChangesCount > 0
                            ? Colors.purple
                            : isEnabled
                                ? Colors.green
                                : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isSyncing ? 'جاري المزامنة...' : _formatLastSyncTime(lastSync),
                        style: TextStyle(
                          fontSize: 11,
                          color: isSyncing
                              ? Colors.blue.shade900
                              : _pendingChangesCount > 0
                                  ? Colors.purple.shade900
                                  : isEnabled
                                      ? Colors.green.shade900
                                      : Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isEnabled && !isSyncing)
                        Text(
                          _pendingChangesCount > 0
                              ? '$_pendingChangesCount تغيير معلق'
                              : 'Smart Sync + Appwrite',
                          style: TextStyle(
                            fontSize: 7,
                            color: _pendingChangesCount > 0
                                ? Colors.purple.shade700
                                : Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 8),
                Text(
                  'تحميل...',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      ),
      error: (err, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 20, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Text(
                  'خطأ في التحميل',
                  style: TextStyle(color: Colors.red.shade900, fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
