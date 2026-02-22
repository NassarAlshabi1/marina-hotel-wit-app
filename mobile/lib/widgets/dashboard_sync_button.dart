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
  
  // ✅ تحسين: تخزين مؤقت للقيم الثابتة لتجنب القراءات المتكررة
  String? _cachedDeviceId;
  SharedPreferences? _cachedPrefs;
  // ✅ تحسين: متغير لمنع الضغط المتكرر السريع
  DateTime? _lastPushAttempt;
  static const _pushDebounceMs = 500;

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

    _initializeCache();
    _loadPendingChangesCount();

    // ✅ تحسين: تقليل الفترة إلى 5 ثوانٍ بدلاً من 2 لتقليل الضغط على قاعدة البيانات
    _pendingChangesTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_isPulling && !_isPushing) {
        _loadPendingChangesCount();
      }
    });
  }

  // ✅ تحسين: تهيئة الكاش مرة واحدة
  Future<void> _initializeCache() async {
    _cachedPrefs = await SharedPreferences.getInstance();
    _cachedDeviceId = _cachedPrefs?.getString('device_id');
    if (_cachedDeviceId == null) {
      _cachedDeviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
      await _cachedPrefs?.setString('device_id', _cachedDeviceId!);
    }
    _appwriteEnabled = _cachedPrefs?.getBool('appwrite_sync_enabled') ?? true;
    if (mounted) setState(() {});
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

  // ✅ تحسين: استخدام الكاش بدلاً من القراءة المتكررة
  bool _isAppwriteSyncEnabled() {
    return _cachedPrefs?.getBool('appwrite_sync_enabled') ?? false;
  }

  /// سحب التغييرات من Appwrite (Pull فقط - بدون دفع)
  Future<void> _pullChanges(BuildContext context) async {
    if (_isPulling) return;

    final stopwatch = Stopwatch()..start();
    final syncId = 'pull_${DateTime.now().millisecondsSinceEpoch}';
    final deviceId = _cachedDeviceId ?? 'unknown';

    final db = ref.read(databaseProvider);
    final syncLogDao = SyncLogDao(db);
    
    // ✅ تحسين: تنفيذ التسجيل بشكل غير متزامن بدون انتظار
    unawaited(syncLogDao.logSync(
      syncId: syncId,
      direction: 'pull',
      deviceId: deviceId,
      target: 'Appwrite',
      status: 'in_progress',
    ));

    _pullAnimationController.repeat();
    if (mounted) setState(() => _isPulling = true);

    try {
      final appwriteEnabled = _isAppwriteSyncEnabled();
      if (!appwriteEnabled) {
        if (mounted) {
          _showSnackBar(
            'مزامنة Appwrite معطلة - يرجى تفعيلها من الإعدادات',
            Colors.orange,
          );
        }
        return;
      }

      // ✅ تحسين: التحقق من الاتصال بشكل أسرع باستخدام القيمة المخزنة أولاً
      final connectionStatus = ref.read(connectionStatusProvider);
      if (!connectionStatus.isConnected) {
        await ref.read(connectionStatusProvider.notifier).checkConnection();
        if (!ref.read(connectionStatusProvider).isConnected) {
          if (mounted) _showSnackBar('لا يوجد اتصال بـ Appwrite', Colors.red);
          return;
        }
      }

      if (mounted) {
        _showLoadingSnackBar('⬇️ جاري سحب التغييرات من السيرفر...');
      }

      final deltaSync = AppwriteDeltaSync.instance;
      if (!deltaSync.isInitialized) {
        final appwriteService = ref.read(appwriteServiceProvider);
        final db = ref.read(databaseProvider);
        await deltaSync.initialize(appwriteService, db);
      }

      // ✅ تحسين: تنفيذ السحب وحل التعارضات بشكل متوازي حيثما أمكن
      final pullResult = await deltaSync.pullDeltaChanges();
      final pulledCount = pullResult.recordsPulled;

      // ✅ تحسين: تنظيف Outbox بشكل غير متزامن إذا وجدت بيانات
      if (pulledCount > 0) {
        unawaited(OutboxDao(db).removeAllPending());
      }

      // ✅ تحسين: حل التعارضات فوراً بدون رسالة منفصلة
      int conflictsResolved = 0;
      if (pullResult.hasConflicts) {
        conflictsResolved = await _resolveConflicts();
      }

      AppwriteRealtimeSync().resetRemoteChangesFlag();

      stopwatch.stop();
      unawaited(syncLogDao.logSync(
        syncId: syncId,
        direction: 'pull',
        deviceId: deviceId,
        target: 'Appwrite',
        status: 'success',
        recordsPulled: pulledCount,
        durationMs: stopwatch.elapsedMilliseconds,
      ));

      if (mounted) {
        setState(() => _lastSyncTime = DateTime.now());
        _showSuccessSnackBar(
          '✅ تم سحب التغييرات بنجاح!',
          '⬇️ استُلِم: $pulledCount ${conflictsResolved > 0 ? '  ⚖️ تعارضات محلولة: $conflictsResolved' : ''}',
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في سحب التغييرات: $e');
      stopwatch.stop();
      unawaited(syncLogDao.logSync(
        syncId: syncId,
        direction: 'pull',
        deviceId: deviceId,
        target: 'Appwrite',
        status: 'failed',
        errorMessage: _sanitizeError(e.toString()),
        durationMs: stopwatch.elapsedMilliseconds,
      ));
      if (mounted) _showErrorSnackBar('تعذر سحب التغييرات: ${e.toString()}');
    } finally {
      _pullAnimationController.stop();
      _pullAnimationController.reset();
      await _loadPendingChangesCount();
      if (mounted) setState(() => _isPulling = false);
    }
  }

  /// رفع التغييرات المحلية (Push فقط) - ✅ نسخة محسّنة للسرعة
  Future<void> _pushChanges(BuildContext context) async {
    // ✅ تحسين: منع الضغط المتكرر السريع (Debounce)
    final now = DateTime.now();
    if (_lastPushAttempt != null && 
        now.difference(_lastPushAttempt!).inMilliseconds < _pushDebounceMs) {
      return;
    }
    _lastPushAttempt = now;

    if (_isPushing) return;

    // ✅ تحسين: قراءة العدد مباشرة من الكاش بدلاً من قاعدة البيانات
    if (_pendingChangesCount == 0) {
      // تحديث سريع للتأكد
      await _loadPendingChangesCount();
      if (_pendingChangesCount == 0) {
        if (mounted) {
          _showSnackBar('✅ لا توجد تغييرات جديدة للرفع', Colors.green);
        }
        return;
      }
    }

    final stopwatch = Stopwatch()..start();
    final syncId = 'push_${now.millisecondsSinceEpoch}';
    final deviceId = _cachedDeviceId ?? 'unknown';

    final db = ref.read(databaseProvider);
    final syncLogDao = SyncLogDao(db);
    
    // ✅ تحسين: بدء التسجيل بشكل غير متزامن
    unawaited(syncLogDao.logSync(
      syncId: syncId,
      direction: 'push',
      deviceId: deviceId,
      target: 'Appwrite',
      status: 'in_progress',
    ));

    _pushAnimationController.repeat();
    if (mounted) setState(() => _isPushing = true);

    try {
      // ✅ تحسين: قراءة جميع الإعدادات مرة واحدة من الكاش
      final appwriteEnabled = _isAppwriteSyncEnabled();
      
      // ✅ تحسين: التحقق من الاتصال مباشرة بدون قراءة إضافية
      bool appwriteConnected = false;
      if (appwriteEnabled) {
        appwriteConnected = ref.read(connectionStatusProvider).isConnected;
      }

      if (!appwriteEnabled || !appwriteConnected) {
        if (mounted) {
          _showSnackBar(
            !appwriteEnabled 
              ? 'ℹ️ المزامنة معطلة - يرجى تفعيلها من الإعدادات'
              : 'لا يوجد اتصال بـ Appwrite',
            Colors.orange,
          );
        }
        return;
      }

      if (mounted) {
        _showLoadingSnackBar('⬆️ جاري الرفع السريع...');
      }

      // ✅ تحسين: تهيئة DeltaSync مباشرة بدون فحوصات مكررة
      final deltaSync = AppwriteDeltaSync.instance;
      if (!deltaSync.isInitialized) {
        final appwriteService = ref.read(appwriteServiceProvider);
        await deltaSync.initialize(appwriteService, db);
      }

      // ✅ تحسين: تنفيذ الرفع مباشرة
      final pushResult = await deltaSync.pushDeltaChanges();
      final pushedCount = pushResult.recordsPushed;

      // ✅ تحسين: تحديث العدد بشكل فوري
      await _loadPendingChangesCount();

      stopwatch.stop();
      
      // ✅ تحسين: تسجيل النتيجة بشكل غير متزامن
      unawaited(syncLogDao.logSync(
        syncId: syncId,
        direction: 'push',
        deviceId: deviceId,
        target: 'Appwrite',
        status: pushResult.success ? 'success' : 'failed',
        recordsPushed: pushedCount,
        durationMs: stopwatch.elapsedMilliseconds,
      ));

      if (mounted) {
        setState(() => _lastSyncTime = DateTime.now());
        if (pushResult.success) {
          _showSuccessSnackBar(
            '✅ تم الرفع بنجاح!',
            '⬆️ أُرسل: $pushedCount في ${stopwatch.elapsedMilliseconds}ms',
          );
        } else {
          _showErrorSnackBar('فشل الرفع', onRetry: () => _pushChanges(context));
        }
      }

      ref.invalidate(smartSyncStatusProvider);
    } catch (e) {
      debugPrint('❌ فشل رفع التغييرات: $e');
      stopwatch.stop();
      unawaited(syncLogDao.logSync(
        syncId: syncId,
        direction: 'push',
        deviceId: deviceId,
        target: 'Appwrite',
        status: 'failed',
        errorMessage: _sanitizeError(e.toString()),
        durationMs: stopwatch.elapsedMilliseconds,
      ));
      if (mounted) _showErrorSnackBar('تعذر الرفع', onRetry: () => _pushChanges(context));
    } finally {
      _pushAnimationController.stop();
      _pushAnimationController.reset();
      if (mounted) setState(() => _isPushing = false);
    }
  }

  // ✅ تحسين: دوال مساعدة مختصرة لعرض الرسائل بشكل أسرع
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showLoadingSnackBar(String message) {
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
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showSuccessSnackBar(String title, String subtitle) {
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
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message, {VoidCallback? onRetry}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
        action: onRetry != null
            ? SnackBarAction(
                label: 'إعادة',
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  String _sanitizeError(String error) {
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
        deviceId: _cachedDeviceId ?? 'unknown',
        strategy: ConflictStrategy.newerWins,
      );

      for (final conflict in conflicts) {
        try {
          final localMap = <String, Map<String, dynamic>>{
            conflict.targetTable: {conflict.uuid: conflict.localPayload},
          };
          final remoteMap = <String, Map<String, dynamic>>{
            conflict.targetTable: {conflict.uuid: conflict.remotePayload},
          };

          final dataConflicts = await resolver.detectConflicts(localMap, remoteMap);

          if (dataConflicts.isNotEmpty) {
            final resolved = await resolver.resolveConflicts(dataConflicts);
            final winnerData = resolved[conflict.targetTable]?[conflict.uuid];
            if (winnerData != null) {
              await outboxDao.resolveConflict(conflict.id, winnerData, resolution: 'newer_wins');
              resolvedCount++;
            }
          } else {
            await outboxDao.resolveConflict(conflict.id, conflict.localPayload, resolution: 'auto_no_conflict');
          }
        } catch (e) {
          debugPrint('❌ خطأ في حل تعارض ${conflict.uuid}: $e');
        }
      }
      return resolvedCount;
    } catch (e) {
      debugPrint('❌ خطأ في حل التعارضات: $e');
      return 0;
    }
  }

  String _formatLastSyncTime(DateTime? lastSync) {
    if (lastSync == null) return '';
    final difference = DateTime.now().difference(lastSync);

    if (difference.inSeconds < 60) return 'منذ ${difference.inSeconds} ثانية';
    if (difference.inMinutes < 60) return 'منذ ${difference.inMinutes} دقيقة';
    if (difference.inHours < 24) return 'منذ ${difference.inHours} ساعة';
    return 'منذ ${difference.inDays} يوم';
  }

  Widget _buildPullButton(bool hasRemoteChanges, int pendingCount) {
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
            duration: const Duration(milliseconds: 200), // ✅ أسرع
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
                onTap: pullEnabled ? () => _pullChanges(context) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isPulling)
                        RotationTransition(
                          turns: _pullAnimationController,
                          child: Icon(buttonIcon, size: 14, color: Colors.white),
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
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
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

  Widget _buildPushButton(bool hasChanges) {
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
            duration: const Duration(milliseconds: 200), // ✅ أسرع
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
                onTap: pushEnabled ? () => _pushChanges(context) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isPushing)
                        RotationTransition(
                          turns: _pushAnimationController,
                          child: Icon(buttonIcon, size: 14, color: Colors.white),
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
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                child: Center(
                  child: Text(
                    _pendingChangesCount > 99 ? '99+' : '$_pendingChangesCount',
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPullButton(hasRemoteChanges, pendingRemoteCount),
                    const SizedBox(width: 8),
                    _buildPushButton(hasLocalChanges),
                  ],
                ),
                const SizedBox(height: 6),
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
  ‌‍
