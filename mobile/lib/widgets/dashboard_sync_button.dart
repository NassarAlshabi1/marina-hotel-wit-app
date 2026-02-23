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

/// زر المزامنة المحسن للوحة التحكم
/// يدعم الرفع والسحب مع Appwrite وGoogle Drive
class DashboardSyncButton extends ConsumerStatefulWidget {
  const DashboardSyncButton({super.key});

  @override
  ConsumerState<DashboardSyncButton> createState() => _DashboardSyncButtonState();
}

class _DashboardSyncButtonState extends ConsumerState<DashboardSyncButton>
    with SingleTickerProviderStateMixin {
  // حالات التحميل
  bool _isPulling = false;
  bool _isPushing = false;
  
  // الإعدادات
  bool _appwriteEnabled = true;
  bool _smartSyncEnabled = false;
  bool _googleDriveSignedIn = false;
  
  // المؤقتات والتحكم
  Timer? _pendingChangesTimer;
  late AnimationController _pullAnimationController;
  late AnimationController _pushAnimationController;
  
  // البيانات
  int _pendingChangesCount = 0;
  DateTime? _lastSyncTime;
  
  // الكاش
  String? _cachedDeviceId;
  SharedPreferences? _prefs;
  DateTime? _lastPushClick;
  
  // الثوابت
  static const _debounceMs = 300;
  static const _animationDuration = Duration(milliseconds: 800);
  static const _uiUpdateDuration = Duration(milliseconds: 150);
  static const _timerInterval = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeCache();
    _startPeriodicUpdates();
  }

  void _initializeAnimations() {
    _pullAnimationController = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );
    _pushAnimationController = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );
  }

  Future<void> _initializeCache() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // قراءة deviceId أو إنشاؤه
      _cachedDeviceId = _prefs?.getString('device_id');
      if (_cachedDeviceId == null) {
        _cachedDeviceId = 'device_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
        await _prefs?.setString('device_id', _cachedDeviceId!);
      }
      
      // قراءة الإعدادات
      _appwriteEnabled = _prefs?.getBool('appwrite_sync_enabled') ?? true;
      
      if (mounted) setState(() {});
      
      // تحميل العداد
      await _loadPendingChangesCount();
      
      // مراقبة حالة Google Drive
      _watchGoogleDriveStatus();
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة الكاش: $e');
    }
  }

  void _watchGoogleDriveStatus() {
    // الاستماع لتغييرات حالة Google Drive
    ref.listenManual(
      smartSyncGoogleDriveSignInStatusProvider,
      (previous, next) {
        if (mounted) {
          setState(() => _googleDriveSignedIn = next);
        }
      },
    );
  }

  void _startPeriodicUpdates() {
    _pendingChangesTimer = Timer.periodic(_timerInterval, (_) {
      if (mounted && !_isPulling && !_isPushing) {
        _loadPendingChangesCount();
        _refreshSettings();
      }
    });
  }

  Future<void> _refreshSettings() async {
    if (_prefs == null) return;
    final newEnabled = _prefs!.getBool('appwrite_sync_enabled') ?? true;
    if (newEnabled != _appwriteEnabled && mounted) {
      setState(() => _appwriteEnabled = newEnabled);
    }
  }

  @override
  void dispose() {
    _pendingChangesTimer?.cancel();
    _pullAnimationController.dispose();
    _pushAnimationController.dispose();
    super.dispose();
  }

  // ==================== دوال مساعدة ====================

  Future<void> _loadPendingChangesCount() async {
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      final count = await outboxDao.count();
      
      if (mounted && count != _pendingChangesCount) {
        setState(() => _pendingChangesCount = count);
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل عدد التغييرات: $e');
    }
  }

  bool get _isAppwriteSyncEnabled => 
    _prefs?.getBool('appwrite_sync_enabled') ?? false;

  String get _deviceId => _cachedDeviceId ?? 'unknown_device';

  /// التحقق من الضغط المزدوج
  bool _isDebounced() {
    final now = DateTime.now();
    if (_lastPushClick != null && 
        now.difference(_lastPushClick!).inMilliseconds < _debounceMs) {
      return true;
    }
    _lastPushClick = now;
    return false;
  }

  // ==================== عرض الرسائل ====================

  void _showSnackBar(String message, Color backgroundColor, {Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: duration ?? const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showLoadingSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.9)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.blue.shade600,
        duration: const Duration(seconds: 30),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showSuccessSnackBar(String title, String subtitle) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(subtitle, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.green.shade600,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showErrorSnackBar(String message, {VoidCallback? onRetry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        action: onRetry != null
            ? SnackBarAction(
                label: 'إعادة المحاولة',
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  void _showPartialSuccessSnackBar(
    String title,
    List<String> successTargets,
    List<String> failedTargets,
    int totalPushed,
  ) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.warning_amber, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('نجاح جزئي', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Text('✅ نجح: ${successTargets.join(', ')}', style: const TextStyle(fontSize: 12)),
            Text('❌ فشل: ${failedTargets.join(', ')}', style: const TextStyle(fontSize: 12)),
            if (totalPushed > 0)
              Text('⬆️ إجمالي: $totalPushed سجل', style: const TextStyle(fontSize: 11)),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ==================== تسجيل السجلات ====================

  Future<void> _logSyncEvent({
    required String syncId,
    required String direction,
    required String deviceId,
    required String target,
    required String status,
    int? recordsPulled,
    int? recordsPushed,
    String? errorMessage,
    required int durationMs,
  }) async {
    try {
      final db = ref.read(databaseProvider);
      final syncLogDao = SyncLogDao(db);
      
      await syncLogDao.logSync(
        syncId: syncId,
        direction: direction,
        deviceId: deviceId,
        target: target,
        status: status,
        recordsPulled: recordsPulled,
        recordsPushed: recordsPushed,
        errorMessage: errorMessage,
        durationMs: durationMs,
      );
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل السجل: $e');
    }
  }

  // ==================== حل التعارضات ====================

  Future<int> _resolveConflicts() async {
    int resolvedCount = 0;
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      final conflicts = await outboxDao.getConflicts();

      if (conflicts.isEmpty) return 0;

      final resolver = ConflictResolver(
        deviceId: _deviceId,
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
              conflict.localPayload,
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

  // ==================== السحب (Pull) ====================

  /// سحب التغييرات من السيرفر
  /// ❌ لا يتم تنظيف Outbox - يحتوي على تغييرات محلية غير مرفوعة
  Future<void> _pullChanges(BuildContext context) async {
    if (_isPulling || _isPushing) return;

    final stopwatch = Stopwatch()..start();
    final syncId = 'pull_${DateTime.now().millisecondsSinceEpoch}';
    final deviceId = _deviceId;
    final db = ref.read(databaseProvider);

    // تسجيل البداية (غير متزامن)
    unawaited(_logSyncEvent(
      syncId: syncId,
      direction: 'pull',
      deviceId: deviceId,
      target: 'Appwrite',
      status: 'in_progress',
      durationMs: 0,
    ));

    _pullAnimationController.repeat();
    if (mounted) setState(() => _isPulling = true);

    try {
      // التحقق من الإعدادات
      if (!_isAppwriteSyncEnabled) {
        _showSnackBar('مزامنة Appwrite معطلة - فعّلها من الإعدادات', Colors.orange);
        return;
      }

      // التحقق من الاتصال
      var connState = ref.read(connectionStatusProvider);
      if (!connState.isConnected) {
        await ref.read(connectionStatusProvider.notifier).checkConnection();
        connState = ref.read(connectionStatusProvider);
        if (!connState.isConnected) {
          _showSnackBar('لا يوجد اتصال بالإنترنت', Colors.red);
          return;
        }
      }

      _showLoadingSnackBar('⬇️ جاري سحب التغييرات من السيرفر...');

      // تهيئة الخدمة
      final deltaSync = AppwriteDeltaSync.instance;
      if (!deltaSync.isInitialized) {
        final appwriteService = ref.read(appwriteServiceProvider);
        await deltaSync.initialize(appwriteService, db);
      }

      // تنفيذ السحب
      final pullResult = await deltaSync.pullDeltaChanges();
      final pulledCount = pullResult.recordsPulled;

      // حل التعارضات إن وجدت
      int conflictsResolved = 0;
      if (pullResult.hasConflicts) {
        conflictsResolved = await _resolveConflicts();
      }

      // إعادة تعيين علامة التغييرات البعيدة
      AppwriteRealtimeSync().resetRemoteChangesFlag();

      stopwatch.stop();

      // تسجيل النجاح (غير متزامن)
      unawaited(_logSyncEvent(
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
          '✅ تم سحب التغييرات بنجاح',
          '⬇️ استُلِم: $pulledCount سجل${conflictsResolved > 0 ? '  ⚖️ تعارضات محلولة: $conflictsResolved' : ''}',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ خطأ في السحب: $e\n$stackTrace');
      stopwatch.stop();

      unawaited(_logSyncEvent(
        syncId: syncId,
        direction: 'pull',
        deviceId: deviceId,
        target: 'Appwrite',
        status: 'failed',
        errorMessage: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      ));

      _showErrorSnackBar('فشل سحب التغييرات: ${_sanitizeError(e.toString())}');
    } finally {
      _pullAnimationController.stop();
      _pullAnimationController.reset();
      await _loadPendingChangesCount();
      if (mounted) setState(() => _isPulling = false);
    }
  }

  // ==================== الرفع (Push) ====================

  /// رفع التغييرات المحلية مع تنظيف Outbox
  /// ✅ يدعم Appwrite (أساسي) وGoogle Drive (احتياطي)
  Future<void> _pushChanges(BuildContext context) async {
    if (_isDebounced()) return;
    if (_isPulling || _isPushing) return;
    if (_pendingChangesCount == 0) {
      _showSnackBar('✅ لا توجد تغييرات للرفع', Colors.green);
      return;
    }

    final stopwatch = Stopwatch()..start();
    final syncId = 'push_${DateTime.now().millisecondsSinceEpoch}';
    final deviceId = _deviceId;
    final db = ref.read(databaseProvider);

    _pushAnimationController.repeat();
    if (mounted) setState(() => _isPushing = true);

    try {
      // قراءة حالات المزامنة
      final smartSyncManager = ref.read(smartSyncManagerProvider);
      final appwriteSyncManager = ref.read(appwriteSyncManagerProvider);
      
      final smartEnabled = await smartSyncManager.isEnabled();
      final isGoogleDriveSignedIn = ref.read(smartSyncGoogleDriveSignInStatusProvider);
      final appwriteEnabled = _isAppwriteSyncEnabled;

      if (!smartEnabled && !appwriteEnabled) {
        _showSnackBar('⚠️ المزامنة معطلة - فعّلها من الإعدادات', Colors.orange);
        return;
      }

      // فحص الاتصالات المتاحة
      bool appwriteConnected = false;
      if (appwriteEnabled) {
        final connState = ref.read(connectionStatusProvider);
        appwriteConnected = connState.isConnected;
        if (!appwriteConnected) {
          await ref.read(connectionStatusProvider.notifier).checkConnection();
          appwriteConnected = ref.read(connectionStatusProvider).isConnected;
        }
      }

      // تحديد الأهداف المتاحة
      final targets = <String>[];
      if (smartEnabled && isGoogleDriveSignedIn) targets.add('Google Drive');
      if (appwriteEnabled && appwriteConnected) targets.add('Appwrite');

      if (targets.isEmpty) {
        _showSnackBar('❌ لا توجد وجهات مزامنة متاحة', Colors.red);
        return;
      }

      _showLoadingSnackBar('⬆️ جاري الرفع إلى ${targets.join(' + ')}...');

      final results = <String, Map<String, dynamic>>{};
      int totalPushed = 0;
      bool appwriteSuccess = false;
      int appwritePushed = 0;

      // ========== رفع إلى Appwrite (الأساسي) ==========
      if (appwriteEnabled && appwriteConnected) {
        try {
          final deltaSync = AppwriteDeltaSync.instance;
          
          if (!deltaSync.isInitialized) {
            final appwriteService = ref.read(appwriteServiceProvider);
            await deltaSync.initialize(appwriteService, db);
          }

          final pushResult = await deltaSync.pushDeltaChanges();
          appwriteSuccess = pushResult.success;
          appwritePushed = pushResult.recordsPushed;

          results['Appwrite'] = {
            'success': appwriteSuccess,
            'pushed': appwritePushed,
          };

          if (appwriteSuccess && appwritePushed > 0) {
            totalPushed += appwritePushed;
            
            // ✅ تنظيف Outbox بعد نجاح الرفع إلى Appwrite
            final outboxDao = OutboxDao(db);
            final cleanedCount = await outboxDao.removeAllPending();
            debugPrint('🧹 تم تنظيف Outbox: $cleanedCount سجل');
            
            // تحديث العداد فوراً
            if (mounted) {
              setState(() => _pendingChangesCount = 0);
            }
          }
        } catch (e) {
          results['Appwrite'] = {'success': false, 'pushed': 0, 'error': e.toString()};
          debugPrint('❌ خطأ في رفع Appwrite: $e');
        }
      }

      // ========== رفع إلى Google Drive (الاحتياطي) ==========
      if (smartEnabled && isGoogleDriveSignedIn) {
        try {
          // لا نرفع إلى Google Drive إذا نجح Appwrite (البيانات متطابقة)
          // أو نرفع كنسخة احتياطية إذا فشل Appwrite
          final result = await smartSyncManager.pushLocalChanges();
          
          results['Google Drive'] = {
            'success': result,
            'pushed': result ? _pendingChangesCount : 0,
          };

          if (result && !appwriteSuccess) {
            // نضيف للمجموع فقط إذا فشل Appwrite
            totalPushed += _pendingChangesCount;
          }
        } catch (e) {
          results['Google Drive'] = {'success': false, 'pushed': 0, 'error': e.toString()};
          debugPrint('❌ خطأ في رفع Google Drive: $e');
        }
      }

      // تحديد النتيجة النهائية
      final successTargets = results.entries
          .where((e) => e.value['success'] == true)
          .map((e) => e.key)
          .toList();
      
      final failedTargets = results.entries
          .where((e) => e.value['success'] == false)
          .map((e) => e.key)
          .toList();

      final overallStatus = failedTargets.isEmpty
          ? 'success'
          : (successTargets.isNotEmpty ? 'partial' : 'failed');

      stopwatch.stop();

      // تسجيل النتيجة (غير متزامن)
      unawaited(_logSyncEvent(
        syncId: syncId,
        direction: 'push',
        deviceId: deviceId,
        target: successTargets.join('+'),
        status: overallStatus,
        recordsPushed: totalPushed,
        durationMs: stopwatch.elapsedMilliseconds,
      ));

      if (mounted) {
        setState(() => _lastSyncTime = DateTime.now());

        if (failedTargets.isEmpty) {
          _showSuccessSnackBar(
            '✅ تم الرفع بنجاح',
            '⬆️ $totalPushed سجل إلى ${successTargets.join(' + ')}',
          );
        } else if (successTargets.isEmpty) {
          _showErrorSnackBar(
            '❌ فشل الرفع إلى جميع الوجهات',
            onRetry: () => _pushChanges(context),
          );
        } else {
          _showPartialSuccessSnackBar(
            '⚠️ نجاح جزئي',
            successTargets,
            failedTargets,
            totalPushed,
          );
        }
      }

      // تحديث المزودات
      ref.invalidate(smartSyncStatusProvider);
      ref.invalidate(connectionStatusProvider);
    } catch (e, stackTrace) {
      debugPrint('❌ خطأ عام في الرفع: $e\n$stackTrace');
      stopwatch.stop();

      unawaited(_logSyncEvent(
        syncId: syncId,
        direction: 'push',
        deviceId: deviceId,
        target: 'Appwrite+GoogleDrive',
        status: 'failed',
        errorMessage: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      ));

      _showErrorSnackBar(
        'فشل الرفع: ${_sanitizeError(e.toString())}',
        onRetry: () => _pushChanges(context),
      );
    } finally {
      _pushAnimationController.stop();
      _pushAnimationController.reset();
      await _loadPendingChangesCount();
      if (mounted) setState(() => _isPushing = false);
    }
  }

  // ==================== أدوات مساعدة ====================

  String _sanitizeError(String error) {
    return error
        .replaceAll(RegExp(r'Bearer\s+[a-zA-Z0-9\-\._]+'), 'Bearer ***')
        .replaceAll(RegExp(r'key=[a-zA-Z0-9]+'), 'key=***')
        .replaceAll(RegExp(r'project=[a-zA-Z0-9]+'), 'project=***')
        .replaceAll(RegExp(r'secret=[a-zA-Z0-9]+'), 'secret=***')
        .replaceAll(RegExp(r'password=[^\s&]+'), 'password=***');
  }

  String _formatLastSyncTime(DateTime? lastSync) {
    if (lastSync == null) return 'لم تتم المزامنة بعد';
    final diff = DateTime.now().difference(lastSync);
    
    if (diff.inSeconds < 10) return 'الآن';
    if (diff.inSeconds < 60) return 'منذ ${diff.inSeconds} ثانية';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays < 30) return 'منذ ${diff.inDays} يوم';
    return '${lastSync.day}/${lastSync.month}/${lastSync.year}';
  }

  // ==================== بناء الواجهة ====================

  Widget _buildPullButton(bool hasRemoteChanges, int pendingCount) {
    final enabled = hasRemoteChanges && _appwriteEnabled && !_isPulling && !_isPushing;

    return Tooltip(
      message: hasRemoteChanges 
        ? 'سحب $pendingCount تغيير من السيرفر' 
        : 'لا توجد تحديثات جديدة',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: _uiUpdateDuration,
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: enabled 
                  ? [Colors.blue.shade400, Colors.blue.shade600]
                  : [Colors.grey.shade400, Colors.grey.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: enabled
                ? [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: enabled ? () => _pullChanges(context) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isPulling)
                        RotationTransition(
                          turns: _pullAnimationController,
                          child: const Icon(Icons.cloud_download, size: 18, color: Colors.white),
                        )
                      else
                        Icon(
                          hasRemoteChanges ? Icons.cloud_download : Icons.cloud_done,
                          size: 18,
                          color: Colors.white,
                        ),
                      const SizedBox(width: 8),
                      Text(
                        _isPulling ? 'جاري السحب...' : (hasRemoteChanges ? 'سحب' : 'لا جديد'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
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
              top: -8,
              right: -8,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 300),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.4),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
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
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPushButton(bool hasChanges) {
    final enabled = hasChanges && !_isPulling && !_isPushing;

    return Tooltip(
      message: hasChanges 
        ? 'رفع $_pendingChangesCount تغيير إلى السحابة' 
        : 'جميع التغييرات مرفوعة',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: _uiUpdateDuration,
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: enabled 
                  ? [Colors.purple.shade400, Colors.purple.shade600]
                  : [Colors.grey.shade400, Colors.grey.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: enabled
                ? [
                    BoxShadow(
                      color: Colors.purple.withOpacity(0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: enabled ? () => _pushChanges(context) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isPushing)
                        RotationTransition(
                          turns: _pushAnimationController,
                          child: const Icon(Icons.cloud_upload, size: 18, color: Colors.white),
                        )
                      else
                        Icon(
                          hasChanges ? Icons.cloud_upload : Icons.cloud_done,
                          size: 18,
                          color: Colors.white,
                        ),
                      const SizedBox(width: 8),
                      Text(
                        _isPushing ? 'جاري الرفع...' : (hasChanges ? 'رفع' : 'محدّث'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
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
              top: -8,
              right: -8,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 300),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.red.shade500,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.4),
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
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(bool hasLocalChanges, bool hasRemoteChanges, int remoteCount) {
    final isSyncing = _isPulling || _isPushing;
    final hasAnyChanges = hasLocalChanges || hasRemoteChanges;

    Color backgroundColor;
    Color borderColor;
    Color textColor;
    IconData icon;
    String statusText;

    if (isSyncing) {
      backgroundColor = Colors.blue.shade50;
      borderColor = Colors.blue.shade200;
      textColor = Colors.blue.shade800;
      icon = Icons.sync;
      statusText = _isPulling ? 'جاري السحب...' : 'جاري الرفع...';
    } else if (hasAnyChanges) {
      backgroundColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade200;
      textColor = Colors.orange.shade800;
      icon = Icons.sync_problem;
      statusText = hasLocalChanges 
        ? '$_pendingChangesCount تغيير محلي معلق'
        : '$remoteCount تحديث من السيرفر';
    } else {
      backgroundColor = Colors.green.shade50;
      borderColor = Colors.green.shade200;
      textColor = Colors.green.shade800;
      icon = Icons.check_circle;
      statusText = 'محدّث';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 12,
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!isSyncing && _lastSyncTime != null)
                Text(
                  _formatLastSyncTime(_lastSyncTime),
                  style: TextStyle(
                    fontSize: 9,
                    color: textColor.withOpacity(0.7),
                  ),
                ),
            ],
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
                    const SizedBox(width: 10),
                    _buildPushButton(hasLocalChanges),
                  ],
                ),
                const SizedBox(height: 8),
                _buildStatusBar(hasLocalChanges, hasRemoteChanges, pendingRemoteCount),
              ],
            );
          },
        );
      },
    );
  }
}
