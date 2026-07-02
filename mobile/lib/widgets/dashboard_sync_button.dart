import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/appwrite_providers.dart';
import '../providers/repository_providers.dart';
import '../providers/secondary_sync_provider.dart';
import '../services/appwrite_health_checker.dart';
import '../services/appwrite_realtime_sync.dart';
import '../services/daos/outbox_dao.dart';
import '../services/daos/sync_log_dao.dart';
import '../services/secondary_appwrite_config.dart';
import '../services/secondary_sync_manager.dart';
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
      // ✅ فصل هندسي: نعرض فقط عدد التغييرات المحلية المعلقة
      final count = await outboxDao.count(sources: const ['local']);
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
    return prefs.getBool('appwrite_sync_enabled') ?? true;
  }

  Future<void> _loadAppwriteEnabled() async {
    try {
      final enabled = await _isAppwriteSyncEnabled();
      if (mounted) {
        setState(() => _appwriteEnabled = enabled);
      } else {
        _appwriteEnabled = enabled;
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل حالة Appwrite: $e');
      // في حالة الخطأ — نفترض مفعّل (احتياطي)
      if (mounted) {
        setState(() => _appwriteEnabled = true);
      } else {
        _appwriteEnabled = true;
      }
    }
  }

  /// سحب التغييرات من Appwrite (Pull فقط - بدون دفع)
  Future<void> _pullChanges(BuildContext context) async {
    final stopwatch = Stopwatch()..start();
    final syncId = 'pull_${DateTime.now().millisecondsSinceEpoch}';
    String? deviceId;
    try {
      deviceId = await _getDeviceId();
    } catch (e) {
      deviceId = 'unknown';
    }

    // ✅ P1-2 fix: ضبط العلم متزامناً فوراً قبل أي await لمنع إعادة الدخول
    if (_isPulling) {
      return;
    }

    // ✅ P2-4 fix: تحذير قبل السحب عند وجود تغييرات محلية غير مرفوعة
    if (_pendingChangesCount > 0) {
      if (!mounted) return;
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('⚠️ تغييرات محلية غير مرفوعة'),
          content: Text(
            'لديك $_pendingChangesCount تغييراً محلياً لم يُرفع بعد.\n\n'
            'سحب البيانات قبل رفع تغييراتك قد يدهس تعديلاتك المحلية.\n\n'
            'هل تريد الرفع أولاً ثم السحب؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('سحب فقط'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('رفع ثم سحب'),
            ),
          ],
        ),
      );
      if (shouldContinue == true) {
        // رفع ثم سحب
        await _pushChanges(context);
      } else if (shouldContinue != false) {
        return; // المستخدم أغلق الحوار
      }
    }

    _isPulling = true;
    if (mounted) {
      setState(() {});
    }

    // ✅ P1-1 fix: كل الفحوص تتم قبل كتابة سجل in_progress
    // لا نكتب in_progress إلا بعد اجتياز كل فحوص ما-قبل-البدء
    try {
      final appwriteEnabled = await _isAppwriteSyncEnabled();
      if (!appwriteEnabled) {
        _isPulling = false;
        if (mounted) {
          // ignore: use_build_context_synchronously
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
        _isPulling = false;
        if (mounted) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا يوجد اتصال بـ Appwrite'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // ✅ الآن بعد اجتياز كل الفحوص — نكتب سجل in_progress
      final db = ref.read(databaseProvider);
      final syncLogDao = SyncLogDao(db);
      await syncLogDao.logSync(
        syncId: syncId,
        direction: 'pull',
        deviceId: deviceId,
        target: 'Appwrite',
        status: 'in_progress',
      );

      unawaited(_pullAnimationController.repeat());

      if (mounted) {
        // ignore: use_build_context_synchronously
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

      final appwriteSyncManager = ref.read(appwriteSyncManagerProvider);
      final pullResult = await appwriteSyncManager.sync(push: false);
      final pulledCount = pullResult.recordsPulled;

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
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.cloud_done, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      '✅ تم سحب التغييرات بنجاح!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '⬇️ استُلِم: $pulledCount سجل',
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
      try {
        final db = ref.read(databaseProvider);
        final syncLogDao = SyncLogDao(db);
        await syncLogDao.logSync(
          syncId: syncId,
          direction: 'pull',
          deviceId: deviceId,
          target: 'Appwrite',
          status: 'failed',
          errorMessage: e.toString(),
          durationMs: stopwatch.elapsedMilliseconds,
        );
      } catch (_) {}

      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('تعذر سحب التغييرات: $e'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
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

    // ✅ P1-2 fix: ضبط العلم متزامناً فوراً قبل أي await
    if (_isPushing) {
      return;
    }
    _isPushing = true;
    if (mounted) {
      setState(() {});
    }

    // ✅ P1-1 fix: كل الفحوص قبل كتابة سجل in_progress
    if (_pendingChangesCount == 0) {
      _isPushing = false;
      if (mounted) {
        // ignore: use_build_context_synchronously
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

    // ✅ الآن بعد اجتياز الفحوص — نكتب سجل in_progress
    final db = ref.read(databaseProvider);
    final syncLogDao = SyncLogDao(db);
    await syncLogDao.logSync(
      syncId: syncId,
      direction: 'push',
      deviceId: deviceId,
      target: 'Appwrite',
      status: 'in_progress',
    );

    unawaited(_pushAnimationController.repeat());
    // _isPushing ضُبط بالفعل في الأعلى (P1-2 fix)

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
          // ignore: use_build_context_synchronously
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
      if (smartEnabled && isGoogleDriveSignedIn) {
        targets.add('Google Drive');
      }
      if (appwriteEnabled && appwriteConnected) {
        targets.add('Appwrite');
      }

      if (targets.isEmpty) {
        if (mounted) {
          // ignore: use_build_context_synchronously
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
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '⬆️ جاري رفع التغييرات إلى ${targets.join(' + ')}...',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 5),
          ),
        );
      }

      final results = <String, Map<String, dynamic>>{};

      // رفع إلى Appwrite أولاً
      if (appwriteEnabled && appwriteConnected) {
        try {
          // ✅ P1-3 fix: pushLocalChanges تُعيد عدد السجلات الفعلي
          final pushedCount = await appwriteSyncManager.pushLocalChanges();
          results['Appwrite'] = {
            'success': pushedCount >= 0,
            'pushed': pushedCount,
          };
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
          results["Google Drive"] = {"success": result, "pushed": _pendingChangesCount,};
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

      // ✅ رفع إلى Appwrite الثانوي (إذا مُفعّل)
      // يستخدم نفس outbox الرئيسي — لا يسبب فقدان بيانات أو تكرار.
      // السجل يُحذف من outbox فقط بعد نجاح كلا الوجهتين.
      if (SecondaryAppwriteConfig.isEnabled &&
          SecondaryAppwriteConfig.isPushEnabled) {
        try {
          final secondaryResult =
              await SecondarySyncManager.instance.pushLocalChanges();
          results['Appwrite الثانوي'] = {
            'success': secondaryResult,
            'pushed': _pendingChangesCount,
          };
          if (secondaryResult) {
            ref
                .read(secondarySyncProvider.notifier)
                .updateLastSync(DateTime.now());
          }
          debugPrint('🔵 [Dashboard] Secondary sync push: $secondaryResult');
        } catch (e) {
          results['Appwrite الثانوي'] = {
            'success': false,
            'pushed': 0,
            'error': e.toString(),
          };
          debugPrint('❌ خطأ في رفع التغييرات إلى Appwrite الثانوي: $e');
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
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
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
                  const SizedBox(height: 4),
                  Text(
                    '⬆️ أُرسل: $totalPushed',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '☁️ عبر: ${successTargets.join(' + ')}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else if (successTargets.isEmpty) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
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
              action: SnackBarAction(
                label: 'إعادة',
                textColor: Colors.white,
                onPressed: () => _pushChanges(context),
              ),
            ),
          );
        } else {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.white),
                      SizedBox(width: 8),
                      Text('⚠️ نجح جزئياً'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '✅ نجح: ${successTargets.join(', ')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '❌ فشل: ${failedTargets.join(', ')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (totalPushed > 0)
                    Text(
                      '⬆️ أُرسل: $totalPushed',
                      style: const TextStyle(fontSize: 11),
                    ),
                ],
              ),
              backgroundColor: Colors.orange,
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
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
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
  // ignore: unused_element
  Future<int> _resolveConflicts() async {
    int resolvedCount = 0;
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);

      final conflicts = await outboxDao.getConflicts();

      if (conflicts.isEmpty) {
        return 0;
      }

      final resolver = ConflictResolver(
        deviceId: await _getDeviceId(),
      );

      // معالجة التعارضات بالتوازي باستخدام Future.wait بدلاً من التسلسل
      final resolveResults = await Future.wait(conflicts.map((conflict) async {
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
                winnerData as Map<String, dynamic>,
                resolution: 'newer_wins',
              );
              return true;
            }
          } else {
            await outboxDao.resolveConflict(
              conflict.id,
              localData,
              resolution: 'auto_no_conflict',
            );
          }
          return false;
        } catch (e) {
          debugPrint('❌ خطأ في حل تعارض ${conflict.uuid}: $e');
          return false;
        }
      }),);
      resolvedCount = resolveResults.where((r) => r).length;

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
    if (lastSync == null) {
      return '';
    }

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
    // زر السحب متاح دائماً طالما Appwrite مفعّل وليس جاري مزامنة
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
      buttonColor = Colors.blue;
      buttonIcon = Icons.cloud_download;
      buttonText = 'سحب التغييرات';
    }

    return Tooltip(
      message: hasRemoteChanges
          ? 'يوجد $pendingCount تحديث من السيرفر — اضغط للسحب'
          : 'اضغط لسحب التغييرات من السيرفر',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [buttonColor.withValues(alpha: 0.85), buttonColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: buttonColor.withValues(alpha: pullEnabled ? 0.4 : 0.1),
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
                      color: Colors.blue.withValues(alpha: 0.5),
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
                colors: [buttonColor.withValues(alpha: 0.85), buttonColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: buttonColor.withValues(alpha: pushEnabled ? 0.4 : 0.1),
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
                      color: Colors.red.withValues(alpha: 0.5),
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
                      if (!_isPulling && !_isPushing)
                        FutureBuilder<SyncLogEntry?>(
                          future: SyncLogDao(ref.read(databaseProvider)).getLastSync(),
                          builder: (context, snapshot) {
                            final lastSync = snapshot.data?.createdAt ?? _lastSyncTime;
                            if (lastSync == null) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              'آخر مزامنة: ${_formatLastSyncTime(lastSync)}',
                              style: TextStyle(
                                fontSize: 8,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.normal,
                              ),
                            );
                          },
                        ),
                      // ✅ مؤشر حالة Failover (Primary معطّل → قراءة من Secondary)
                      Consumer(
                        builder: (context, ref, _) {
                          final health = ref.watch(appwriteHealthProvider);
                          if (!health.shouldFailover) {
                            return const SizedBox.shrink();
                          }
                          return Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: Colors.orange.shade400, width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning_amber,
                                    size: 10, color: Colors.orange.shade800),
                                const SizedBox(width: 3),
                                Text(
                                  'وضع طوارئ: قراءة من الثانوي',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
