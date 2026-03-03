import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _isPulling = false;
  bool _isPushing = false;
  bool _appwriteEnabled = true;
  Timer? _pendingChangesTimer;
  late AnimationController _pullAnimationController;
  late AnimationController _pushAnimationController;
  int _pendingChangesCount = 0;
  DateTime? _lastSyncTime;

  @override
  void initState() {
    super.initState();
    _pullAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pushAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _loadPendingChangesCount();
    _loadAppwriteEnabled();

    // مؤقت للتحديث الدوري
    _pendingChangesTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_isPulling && !_isPushing) {
        _loadPendingChangesCount();
        _loadAppwriteEnabled();
      }
    });
  }

  @override
  void dispose() {
    _pendingChangesTimer?.cancel();
    _pullAnimationController.dispose();
    _pushAnimationController.dispose();
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
    } catch (e) {
      debugPrint('❌ خطأ في تحميل عدد التغييرات المعلقة: $e');
    }
  }

  Future<bool> _isAppwriteSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('appwrite_sync_enabled') ?? false;
  }

  Future<void> _loadAppwriteEnabled() async {
    try {
      final enabled = await _isAppwriteSyncEnabled();
      if (mounted) {
        setState(() => _appwriteEnabled = true); // Force enabled by expert request
      } else {
        _appwriteEnabled = true; // Always true for expert functionality
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل حالة Appwrite: $e');
      if (mounted) {
        setState(() => _appwriteEnabled = true);
      } else {
        _appwriteEnabled = true;
      }
    }
  }

  /// تنظيف outbox بعد الرفع
  Future<void> _clearOutboxAfterPush() async {
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      await outboxDao.removeAllPending();
      debugPrint('✅ تم تنظيف outbox بنجاح');
    } catch (e) {
      debugPrint('⚠️ فشل تنظيف outbox: $e');
      // لا نرمي الخطأ حتى لا يؤثر على تجربة المستخدم
    }
  }

  /// سحب التغييرات من Appwrite (Pull فقط - بدون دفع)
  Future<void> _pullChanges(BuildContext context) async {
    if (_isPulling || _isPushing) return;
    
    setState(() {
      _isPulling = true;
      _pullAnimationController.repeat();
    });
    final stopwatch = Stopwatch()..start();
    final syncId = 'pull_${DateTime.now().millisecondsSinceEpoch}';
    String? deviceId;
    try {
      deviceId = await _getDeviceId();
    } catch (e) {
      deviceId = 'unknown';
    }

    // تسجيل بداية العملية
    final db = ref.read(databaseProvider);
    final syncLogDao = SyncLogDao(db);
    await syncLogDao.logSync(
      syncId: syncId,
      direction: 'pull',
      deviceId: deviceId,
      target: 'Appwrite',
      status: 'in_progress',
    );
    if (_isPulling) return;

    _pullAnimationController.repeat();
    if (mounted) {
      setState(() => _isPulling = true);
    } else {
      _isPulling = true;
    }

    try {
      final appwriteEnabled = await _isAppwriteSyncEnabled();
      if (!appwriteEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('مزامنة Appwrite معطلة - يرجى تفعيلها من الإعدادات'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      await ref.read(connectionStatusProvider.notifier).checkConnection();
      final appwriteConnected = ref.read(connectionStatusProvider).isConnected;

      if (!appwriteConnected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا يوجد اتصال بـ Appwrite'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text('⬇️ جاري سحب التغييرات من السيرفر...'),
                ),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 3),
          ),
        );
      }

      final deltaSync = AppwriteDeltaSync.instance;
      if (!deltaSync.isInitialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('خدمة المزامنة غير مهيأة'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 1️⃣ سحب التغييرات من السيرفر
      final pullResult = await deltaSync.pullDeltaChanges();
      final pulledCount = pullResult.recordsPulled;

      // 2️⃣ حل التعارضات إن وجدت
      int conflictsResolved = 0;
      if (pullResult.hasConflicts) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚖️ جاري حل التعارضات...'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        conflictsResolved = await _resolveConflicts();
      }

      // إعادة تعيين علامة "توجد تغييرات من السيرفر"
      AppwriteRealtimeSync().resetRemoteChangesFlag();

      // ✅ تسجيل نجاح العملية
      stopwatch.stop();
      await syncLogDao.logSync(
        syncId: syncId,
        direction: 'pull',
        deviceId: deviceId,
        target: 'Appwrite',
        status: 'success',
        recordsPulled: pulledCount,
        durationMs: stopwatch.elapsedMilliseconds,
      );

      if (mounted) {
        setState(() {
          _lastSyncTime = DateTime.now();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_done, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text(
                      '✅ تم سحب التغييرات بنجاح!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '⬇️ استُلِم: $pulledCount ${conflictsResolved > 0 ? '  ⚖️ تعارضات محلولة: $conflictsResolved' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في سحب التغييرات: $e');

      // ✅ تسجيل فشل العملية
      stopwatch.stop();
      await syncLogDao.logSync(
        syncId: syncId,
        direction: 'pull',
        deviceId: deviceId,
        target: 'Appwrite',
        status: 'failed',
        errorMessage: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('تعذر سحب التغييرات: ${e.toString()}'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      _pullAnimationController.stop();
      _pullAnimationController.reset();
      if (mounted) {
        setState(() => _isPulling = false);
      }
    }
  }

  /// رفع التغييرات المحلية (Push فقط)
  Future<void> _pushChanges(BuildContext context) async {
    final stopwatch = Stopwatch()..start();
    final syncId = 'push_${DateTime.now().millisecondsSinceEpoch}';
    String? deviceId;
    try {
      deviceId = await _getDeviceId();
    } catch (e) {
      deviceId = 'unknown';
    }

    // تسجيل بداية العملية
    final db = ref.read(databaseProvider);
    final syncLogDao = SyncLogDao(db);
    await syncLogDao.logSync(
      syncId: syncId,
      direction: 'push',
      deviceId: deviceId,
      target: 'Appwrite+GoogleDrive',
      status: 'in_progress',
    );
    if (_isPushing) return;

    if (_pendingChangesCount == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white),
                SizedBox(width: 8),
                Text('✅ لا توجد تغييرات جديدة للرفع'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    _pushAnimationController.repeat();
    if (mounted) {
      setState(() => _isPushing = true);
    } else {
      _isPushing = true;
    }

    try {
      final smartSyncManager = ref.read(smartSyncManagerProvider);
      final appwriteSyncManager = ref.read(appwriteSyncManagerProvider);

      final smartEnabled = await smartSyncManager.isEnabled();
      final isGoogleDriveSignedIn = ref.read(
        smartSyncGoogleDriveSignInStatusProvider,
      );
      final appwriteEnabled = await _isAppwriteSyncEnabled();

      if (!smartEnabled && !appwriteEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ℹ️ المزامنة معطلة - يرجى تفعيلها من الإعدادات',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      bool appwriteConnected = false;
      if (appwriteEnabled) {
        await ref.read(connectionStatusProvider.notifier).checkConnection();
        appwriteConnected = ref.read(connectionStatusProvider).isConnected;
      }

      final targets = <String>[];
      if (smartEnabled && isGoogleDriveSignedIn) targets.add('Google Drive');
      if (appwriteEnabled && appwriteConnected) targets.add('Appwrite');

      if (targets.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا توجد وجهات مزامنة متاحة حالياً'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '⬆️ جاري رفع التغييرات إلى ${targets.join(' + ')}...',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 5),
          ),
        );
      }

      final results = <String, Map<String, dynamic>>{};

      // رفع إلى Appwrite أولاً
      if (appwriteEnabled && appwriteConnected) {
        try {
          final deltaSync = AppwriteDeltaSync.instance;
          if (deltaSync.isInitialized) {
            final pushResult = await deltaSync.pushDeltaChanges();
            final pushedCount = pushResult.recordsPushed;

            results['Appwrite'] = {
              'success': pushResult.success,
              'pushed': pushedCount,
            };
          } else {
            final result = await appwriteSyncManager.pushLocalChanges();
            results['Appwrite'] = {
              'success': result,
              'pushed': _pendingChangesCount,
            };
          }
        } catch (e) {
          results['Appwrite'] = {
            'success': false,
            'pushed': 0,
            'error': e.toString(),
          };
          debugPrint('❌ خطأ في رفع التغييرات إلى Appwrite: $e');
        }
      }

      // رفع إلى Google Drive (بدون سحب - نسخ احتياطي فقط)
      if (smartEnabled && isGoogleDriveSignedIn) {
        try {
          final result = await smartSyncManager.pushLocalChanges();
          results['Google Drive'] = {
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

      // ✅ تنظيف outbox بعد الرفع (إذا نجح رفع إلى أي وجهة)
      if (successTargets.isNotEmpty) {
        await _clearOutboxAfterPush();
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
        errorMessage: e.toString(),
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
    // زر السحب متاح فقط إذا كان يوجد تغييرات جديدة في Appwrite
    final bool pullEnabled = _appwriteEnabled && !_isPulling && !_isPushing; // Expert: Force enabled regardless of remote change detection

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
      buttonColor = Colors.grey.shade400;
      buttonIcon = Icons.cloud_download;
      buttonText = 'لا توجد تحديثات';
    }

    return Tooltip(
      message: hasRemoteChanges
          ? 'اضغط لسحب التغييرات الجديدة من السيرفر'
          : 'لا توجد تغييرات جديدة في السحابة',
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isPulling || _isPushing
                        ? Colors.blue.shade50
                        : (hasLocalChanges || hasRemoteChanges)
                            ? Colors.orange.shade50
                            : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isPulling || _isPushing
                          ? Colors.blue.shade200
                          : (hasLocalChanges || hasRemoteChanges)
                              ? Colors.orange.shade200
                              : Colors.green.shade200,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasLocalChanges || hasRemoteChanges
                            ? Icons.sync_problem
                            : (_isPulling || _isPushing ? Icons.sync : Icons.check_circle),
                        size: 12,
                        color: _isPulling || _isPushing
                            ? Colors.blue
                            : (hasLocalChanges || hasRemoteChanges)
                                ? Colors.orange
                                : Colors.green,
                      ),
                      const SizedBox(width: 5),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isPulling
                                ? 'جاري السحب...'
                                : _isPushing
                                    ? 'جاري الرفع...'
                                    : hasLocalChanges
                                        ? '$_pendingChangesCount تغيير محلي معلق'
                                        : hasRemoteChanges
                                            ? '$pendingRemoteCount تحديث من السيرفر'
                                            : 'محدّث',
                            style: TextStyle(
                              fontSize: 11,
                              color: _isPulling || _isPushing
                                  ? Colors.blue.shade900
                                  : (hasLocalChanges || hasRemoteChanges)
                                      ? Colors.orange.shade900
                                      : Colors.green.shade900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!_isPulling && !_isPushing && _lastSyncTime != null)
                            Text(
                              _formatLastSyncTime(_lastSyncTime),
                              style: TextStyle(
                                fontSize: 8,
                                color: Colors.grey.shade600,
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
        );
      },
    );
  }
}
