import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rxdart/rxdart.dart'; // For debouncing
import '../sync/orchestrator/sync_orchestrator.dart'; // Import SyncOrchestrator
import '../sync/models/sync_models.dart'; // Import SyncStatus

import '../providers/appwrite_providers.dart';
import '../providers/repository_providers.dart';
import '../services/daos/outbox_dao.dart';
import '../services/daos/sync_log_dao.dart';
import '../services/appwrite_delta_sync.dart';
import '../services/appwrite_realtime_sync.dart';
import '../services/sync_core/conflict_resolver.dart';

class DashboardSyncButton extends ConsumerStatefulWidget {
  const DashboardSyncButton({super.key});

  @override
  ConsumerState<DashboardSyncButton> createState() =>
      _DashboardSyncButtonState();
}

class _DashboardSyncButtonState extends ConsumerState<DashboardSyncButton>
    with SingleTickerProviderStateMixin {
  late final SyncOrchestrator _syncOrchestrator; // Added for direct access
  StreamSubscription? _pendingChangesSubscription;
  StreamSubscription? _syncStateSubscription;
  bool _isPulling = false;
  bool _isPushing = false;
  bool _appwriteEnabled = true;
  // Timer? _pendingChangesTimer; // Removed: Replaced by stream subscription
  late AnimationController _pullAnimationController;
  late AnimationController _pushAnimationController;
  int _pendingChangesCount = 0;
  DateTime? _lastSyncTime;

  @override
  void initState() {
    super.initState();
    _syncOrchestrator = ref.read(unifiedSyncOrchestratorProvider);

    _pullAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pushAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _loadAppwriteEnabled(); // This can still be loaded once or less frequently

    // ✅ ADDED: الاستماع لعدد التغييرات المعلقة من OutboxProcessor
    // ISSUE: P0 Critical Bug: استخدام Timer.periodic للاستعلام المتكرر يستهلك البطارية والموارد بشكل كبير.
    // PRIORITY: P0
    _pendingChangesSubscription = _syncOrchestrator.outbox.pendingCountStream.listen((count) {
      if (mounted) {
        setState(() {
          _pendingChangesCount = count;
        });
      }
    });

    // ✅ ADDED: الاستماع لحالة المزامنة من SyncOrchestrator
    // ISSUE: P1 Performance: تحسين مؤشرات التقدم لتكون أكثر دقة وتفاعلية.
    // PRIORITY: P1
    _syncStateSubscription = _syncOrchestrator.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPulling = state.status == SyncStatus.pull;
          _isPushing = state.status == SyncStatus.push;
          _lastSyncTime = state.lastSyncAt;
        });
      }
    });

    // تحميل العدد الأولي عند التهيئة
    _syncOrchestrator.outbox.pendingCount.then((count) {
      if (mounted) {
        setState(() {
          _pendingChangesCount = count;
        });
      }
    });
  }

  @override
  void dispose() {
    _pendingChangesSubscription?.cancel();
    _syncStateSubscription?.cancel();
    _pullAnimationController.dispose();
    _pushAnimationController.dispose();
    super.dispose();
  }

  // Future<void> _loadPendingChangesCount() async { // Removed: Replaced by stream subscription
  //   try {
  //     final db = ref.read(databaseProvider);
  //     final outboxDao = OutboxDao(db);
  //     final count = await outboxDao.count();
  //     if (mounted) {
  //       setState(() {
  //         _pendingChangesCount = count;
  //       });
  //     }
  //   } catch (e) {
  //     debugPrint('❌ خطأ في تحميل عدد التغييرات المعلقة: $e');
  //   }
  // }

  Future<bool> _isAppwriteSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('appwrite_sync_enabled') ?? false;
  }

  Future<void> _loadAppwriteEnabled() async {
    try {
      final enabled = await _isAppwriteSyncEnabled();
      // ✅ ADDED: mounted check
      // ISSUE: P0 Critical Bug: عدم وجود تحقق mounted قبل setState.
      // PRIORITY: P0
      if (mounted) {
        setState(() => _appwriteEnabled = enabled);
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل حالة Appwrite: $e');
      // ✅ ADDED: mounted check
      // ISSUE: P0 Critical Bug: عدم وجود تحقق mounted قبل setState.
      // PRIORITY: P0
      if (mounted) {
        setState(() => _appwriteEnabled = true);
      }
    }
  }

  /// سحب التغييرات من Appwrite (Pull فقط - بدون دفع)
  Future<void> _pullChanges(BuildContext context) async {
    if (_isPulling) return;

    // ✅ ADDED: mounted check
    // ISSUE: P0 Critical Bug: عدم وجود تحقق mounted قبل setState.
    // PRIORITY: P0
    if (!mounted) return;

    setState(() {
      _isPulling = true;
    });
    try {
      // 🔄 CHANGED: استخدام SyncOrchestrator بدلاً من AppwriteSyncManager مباشرة
      // ISSUE: P1 Performance: تحسين مؤشرات التقدم لتكون أكثر دقة وتفاعلية.
      // PRIORITY: P1
      await _syncOrchestrator.pullOnly();
      // ✅ ADDED: mounted check
      // ISSUE: P0 Critical Bug: عدم وجود تحقق mounted قبل setState.
      // PRIORITY: P0
      if (mounted) {
        setState(() {
          _lastSyncTime = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ في سحب التغييرات: $e');
      // TODO: عرض رسالة خطأ للمستخدم
    } finally {
      // ✅ ADDED: mounted check
      // ISSUE: P0 Critical Bug: عدم وجود تحقق mounted قبل setState.
      // PRIORITY: P0
      if (mounted) {
        setState(() {
          _isPulling = false;
        });
      }
    }
  }

  /// رفع التغييرات المحلية (Push فقط)
  Future<void> _pushChanges(BuildContext context) async {
    if (_isPushing) return;

    // ✅ ADDED: mounted check
    // ISSUE: P0 Critical Bug: عدم وجود تحقق mounted قبل setState.
    // PRIORITY: P0
    if (!mounted) return;

    setState(() {
      _isPushing = true;
    });
    try {
      // 🔄 CHANGED: استخدام SyncOrchestrator بدلاً من AppwriteSyncManager مباشرة
      // ISSUE: P1 Performance: تحسين مؤشرات التقدم لتكون أكثر دقة وتفاعلية.
      // PRIORITY: P1
      await _syncOrchestrator.pushOnly();
      // ✅ ADDED: mounted check
      // ISSUE: P0 Critical Bug: عدم وجود تحقق mounted قبل setState.
      // PRIORITY: P0
      if (mounted) {
        setState(() {
          _lastSyncTime = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ في دفع التغييرات: $e');
      // TODO: عرض رسالة خطأ للمستخدم
    } finally {
      // ✅ ADDED: mounted check
      // ISSUE: P0 Critical Bug: عدم وجود تحقق mounted قبل setState.
      // PRIORITY: P0
      if (mounted) {
        setState(() {
          _isPushing = false;
        });
      }
    }
  }          results['Google Drive'] = {
            'success': result,
            'pushed': _pendingChangesCount,
          };
        } catch (e) {
          results['Google Drive'] = {
            'success': false,
            'pushed': 0,
            'error': e.toString(),
          };
          debugPrint('❌ خطأ في رفع التغييرات إلى Google Drive: $e');
        }
      }

      await _loadPendingChangesCount();

      // حساب الإحصائيات
      int totalPushed = 0;
      final successTargets = <String>[];
      final failedTargets = <String>[];

      for (final entry in results.entries) {
        final data = entry.value;
        if (data['success'] == true) {
          successTargets.add(entry.key);
          totalPushed += (data['pushed'] as int?) ?? 0;
        } else {
          failedTargets.add(entry.key);
        }
      }

      // ✅ تسجيل نجاح العملية
      stopwatch.stop();
      await syncLogDao.logSync(
        syncId: syncId,
        direction: 'push',
        deviceId: deviceId,
        target: successTargets.join('+'),
        status: failedTargets.isEmpty ? 'success' : (successTargets.isNotEmpty ? 'partial' : 'failed'),
        recordsPushed: totalPushed,
        durationMs: stopwatch.elapsedMilliseconds,
      );

      if (mounted) {
        setState(() {
          _lastSyncTime = DateTime.now();
        });

        if (failedTargets.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud_done, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '✅ تم رفع التغييرات بنجاح!',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    '⬆️ أُرسل: $totalPushed',
                    style: TextStyle(fontSize: 12),
                  ),
                  Text(
                    '☁️ عبر: ${successTargets.join(' + ')}',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        } else if (successTargets.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '❌ فشل رفع التغييرات',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
              action: SnackBarAction(
                label: 'إعادة',
                textColor: Colors.white,
                onPressed: () => _pushChanges(context),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.warning, color: Colors.white),
                      SizedBox(width: 8),
                      Text('⚠️ نجح جزئياً'),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    '✅ نجح: ${successTargets.join(', ')}',
                    style: TextStyle(fontSize: 12),
                  ),
                  Text(
                    '❌ فشل: ${failedTargets.join(', ')}',
                    style: TextStyle(fontSize: 12),
                  ),
                  if (totalPushed > 0)
                    Text(
                      '⬆️ أُرسل: $totalPushed',
                      style: TextStyle(fontSize: 11),
                    ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }

      ref.invalidate(smartSyncStatusProvider);
    } catch (e) {
      debugPrint('❌ فشل رفع التغييرات: $e');

      // ✅ تسجيل فشل العملية
      stopwatch.stop();
      await syncLogDao.logSync(
        syncId: syncId,
        direction: 'push',
        deviceId: deviceId,
        target: 'Appwrite+GoogleDrive',
        status: 'failed',
        errorMessage: _sanitizeError(e.toString()),
        durationMs: stopwatch.elapsedMilliseconds,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تعذر رفع التغييرات. تحقق من الاتصال وبيانات الدخول',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
            action: SnackBarAction(
              label: 'إعادة',
              textColor: Colors.white,
              onPressed: () => _pushChanges(context),
            ),
          ),
        );
      }
    } finally {
      _pushAnimationController.stop();
      _pushAnimationController.reset();
      if (mounted) {
        setState(() => _isPushing = false);
      }
    }
  }

  String _sanitizeError(String error) {
    // إزالة المعلومات الحساسة من رسائل الخطأ
    // مثل رموز التوكن والروابط التي قد تحتوي مفاتيح
    return error
        .replaceAll(RegExp(r'Bearer\s+[a-zA-Z0-9\-\._]+'), 'Bearer [REDACTED]')
        .replaceAll(RegExp(r'key=[a-zA-Z0-9]+'), 'key=[REDACTED]')
        .replaceAll(RegExp(r'project=[a-zA-Z0-9]+'), 'project=[REDACTED]')
        .replaceAll(RegExp(r'secret=[a-zA-Z0-9]+'), 'secret=[REDACTED]');
  }

  /// حل التعارضات بين البيانات المحلية والبعيدة
  Future<int> _resolveConflicts() async {
    int resolvedCount = 0;
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);

      final conflicts = await outboxDao.getConflicts();

      if (conflicts.isEmpty) return 0;

      final resolver = ConflictResolver(
        deviceId: await _getDeviceId(),
        strategy: ConflictStrategy.newerWins,
      );

      for (final conflict in conflicts) {
        try {
          final localData = conflict.localPayload;
          final remoteData = conflict.remotePayload;

          final localMap = <String, Map<String, dynamic>>{
            conflict.targetTable: {conflict.uuid: localData},
          };
          final remoteMap = <String, Map<String, dynamic>>{
            conflict.targetTable: {conflict.uuid: remoteData},
          };

          final dataConflicts = await resolver.detectConflicts(localMap, remoteMap);

          if (dataConflicts.isNotEmpty) {
            final resolved = await resolver.resolveConflicts(dataConflicts);

            final winnerData = resolved[conflict.targetTable]?[conflict.uuid];
            if (winnerData != null) {
              await outboxDao.resolveConflict(
                conflict.id,
                winnerData,
                resolution: 'newer_wins',
              );
              resolvedCount++;
            }
          } else {
            await outboxDao.resolveConflict(
              conflict.id,
              localData,
              resolution: 'auto_no_conflict',
            );
          }
        } catch (e) {
          debugPrint('❌ خطأ في حل تعارض ${conflict.uuid}: $e');
        }
      }

      debugPrint('✅ تم حل $resolvedCount تعارض');
      return resolvedCount;
    } catch (e) {
      debugPrint('❌ خطأ في حل التعارضات: $e');
      return 0;
    }
  }

  /// الحصول على معرف الجهاز
  Future<String> _getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString('device_id');
      if (deviceId == null) {
        deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString('device_id', deviceId);
      }
      return deviceId;
    } catch (e) {
      return 'unknown_device';
    }
  }

  String _formatLastSyncTime(DateTime? lastSync) {
    if (lastSync == null) return '';

    final now = DateTime.now();
    final difference = now.difference(lastSync);

    if (difference.inSeconds < 60) {
      return 'منذ ${difference.inSeconds} ثانية';
    } else if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else if (difference.inHours < 24) {
      return 'منذ ${difference.inHours} ساعة';
    } else {
      return 'منذ ${difference.inDays} يوم';
    }
  }

  // ✅ تحسين: إضافة معامل pendingCount لعرض عدد التغييرات
  Widget _buildPullButton(bool hasRemoteChanges, bool isGoogleDriveSignedIn, int pendingCount) {
    final bool pullEnabled = _appwriteEnabled && !_isPulling && !_isPushing;

    Color buttonColor;
    IconData buttonIcon;
    String buttonText;

    if (_isPulling) {
      buttonColor = Colors.blue;
      buttonIcon = Icons.cloud_download;
      buttonText = 'جاري السحب...';
    } else if (hasRemoteChanges) {
      buttonColor = Colors.blue;
      buttonIcon = Icons.cloud_download;
      buttonText = 'سحب التغييرات';
    } else {
      buttonColor = Colors.blueGrey;
      buttonIcon = Icons.cloud_download;
      buttonText = 'تحقق من التحديثات';
    }

    return Tooltip(
      message: hasRemoteChanges
          ? 'اضغط لسحب التغييرات الجديدة من السيرفر'
          : 'تحقق من وجود تحديثات جديدة في السحابة',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [buttonColor.withOpacity(0.85), buttonColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: buttonColor.withOpacity(pullEnabled ? 0.4 : 0.1),
                  blurRadius: pullEnabled ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: pullEnabled
                    ? () => _pullChanges(context)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isPulling)
                        RotationTransition(
                          turns: _pullAnimationController,
                          child: Icon(
                            buttonIcon,
                            size: 14,
                            color: Colors.white,
                          ),
                        )
                      else
                        Icon(buttonIcon, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        buttonText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // ✅ تحسين: Badge يعرض عدد التغييرات المعلقة من السيرفر
          if (hasRemoteChanges && !_isPulling && pendingCount > 0)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                constraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 24,
                ),
                child: Center(
                  child: Text(
                    pendingCount > 99 ? '99+' : '$pendingCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPushButton(bool hasChanges, bool isGoogleDriveSignedIn) {
    // زر الدفع متاح فقط إذا كان يوجد تغييرات محلية
    // تم تعطيل التحقق من تسجيل دخول Google Drive في زر الدفع
    final bool pushEnabled = hasChanges && !_isPulling && !_isPushing;

    Color buttonColor;
    IconData buttonIcon;
    String buttonText;

    if (_isPushing) {
      buttonColor = Colors.purple;
      buttonIcon = Icons.cloud_upload;
      buttonText = 'جاري الرفع...';
    } else if (hasChanges) {
      buttonColor = Colors.purple;
      buttonIcon = Icons.cloud_upload;
      buttonText = 'رفع التغييرات';
    } else {
      buttonColor = Colors.grey.shade400;
      buttonIcon = Icons.cloud_done;
      buttonText = 'محدّث';
    }

    return Tooltip(
      message: hasChanges
          ? 'اضغط لرفع $_pendingChangesCount تغيير إلى السحابة'
          : 'جميع التغييرات مرفوعة',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [buttonColor.withOpacity(0.85), buttonColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: buttonColor.withOpacity(pushEnabled ? 0.4 : 0.1),
                  blurRadius: pushEnabled ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: pushEnabled
                    ? () => _pushChanges(context)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isPushing)
                        RotationTransition(
                          turns: _pushAnimationController,
                          child: Icon(
                            buttonIcon,
                            size: 14,
                            color: Colors.white,
                          ),
                        )
                      else
                        Icon(buttonIcon, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        buttonText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Badge يظهر عدد التغييرات المعلقة
          if (hasChanges && !_isPushing)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                constraints: const BoxConstraints(
                  minWidth: 22,
                  minHeight: 22,
                ),
                child: Center(
                  child: Text(
                    _pendingChangesCount > 99
                        ? '99+'
                        : '$_pendingChangesCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGoogleDriveSignedIn = ref.watch(
      smartSyncGoogleDriveSignInStatusProvider,
    );

    // ✅ تحسين: استخدام ValueListenableBuilder المدمج لكل من hasRemoteChanges و pendingRemoteChangesCount
    return ValueListenableBuilder<bool>(
      valueListenable: AppwriteRealtimeSync().hasRemoteChanges,
      builder: (context, hasRemoteChanges, child) {
        return ValueListenableBuilder<int>(
          valueListenable: AppwriteRealtimeSync().pendingRemoteChangesCount,
          builder: (context, pendingRemoteCount, child) {
            final hasLocalChanges = _pendingChangesCount > 0;

            return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // صف الأزرار: زر السحب + زر الدفع
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // زر السحب من السيرفر - ✅ تحديث: تمرير عداد التغييرات
                _buildPullButton(hasRemoteChanges, isGoogleDriveSignedIn, pendingRemoteCount),
                const SizedBox(width: 8),
                // زر الدفع إلى السيرفر
                _buildPushButton(hasLocalChanges, isGoogleDriveSignedIn),
              ],
            ),
            const SizedBox(height: 6),
            // شريط الحالة
            // 🔄 CHANGED: استخدام StreamBuilder للاستماع لحالة المزامنة بشكل تفاعلي
            // ISSUE: P1 Performance: تحسين مؤشرات التقدم لتكون أكثر دقة وتفاعلية.
            // PRIORITY: P1
            StreamBuilder<SyncState>(
              stream: _syncOrchestrator.stateStream,
              initialData: _syncOrchestrator.currentState,
              builder: (context, snapshot) {
                final syncState = snapshot.data!;
                final hasLocalChanges = _pendingChangesCount > 0;
                final isSyncing = syncState.isSyncing;
                final isSynced = syncState.isSynced;
                final hasError = syncState.hasError;

                Color statusColor = Colors.green.shade50;
                Color borderColor = Colors.green.shade200;
                IconData statusIcon = Icons.check_circle;
                String statusText = 'محدّث';
                Color textColor = Colors.green.shade900;

                if (isSyncing) {
                  statusColor = Colors.blue.shade50;
                  borderColor = Colors.blue.shade200;
                  statusIcon = Icons.sync;
                  statusText = syncState.status == SyncStatus.pull ? 'جاري السحب...' : 'جاري الرفع...';
                  textColor = Colors.blue.shade900;
                } else if (hasError) {
                  statusColor = Colors.red.shade50;
                  borderColor = Colors.red.shade200;
                  statusIcon = Icons.error;
                  statusText = 'خطأ في المزامنة';
                  textColor = Colors.red.shade900;
                } else if (hasLocalChanges || hasRemoteChanges) {
                  statusColor = Colors.orange.shade50;
                  borderColor = Colors.orange.shade200;
                  statusIcon = Icons.sync_problem;
                  statusText = hasLocalChanges
                      ? '$_pendingChangesCount تغيير محلي معلق'
                      : '$pendingRemoteCount تحديث من السيرفر';
                  textColor = Colors.orange.shade900;
                }

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: borderColor,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        statusIcon,
                        size: 12,
                        color: textColor,
                      ),
                      const SizedBox(width: 5),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 11,
                              color: textColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!isSyncing && syncState.lastSyncAt != null)
                            Text(
                              _formatLastSyncTime(syncState.lastSyncAt!),
                              style: TextStyle(
                                fontSize: 8,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
          },
        );
      },
    );
  }
}
