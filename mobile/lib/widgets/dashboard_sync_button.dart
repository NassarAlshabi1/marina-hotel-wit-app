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
import '../services/sync_core/conflict_resolver.dart'; // ✅ استيراد حل التعارضات

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

  final ValueNotifier<int> _pushProgress = ValueNotifier<int>(0);
  final ValueNotifier<int> _pushTotal = ValueNotifier<int>(0);

  late OutboxDao _outboxDao;
  late SyncLogDao _syncLogDao;

  static const int BATCH_SIZE = 50;

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

    final db = ref.read(databaseProvider);
    _outboxDao = OutboxDao(db);
    _syncLogDao = SyncLogDao(db);

    _loadPendingChangesCount();
    _loadAppwriteEnabled();

    _pendingChangesTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && !_isPulling && !_isPushing) {
        _loadPendingChangesCount();
        _loadAppwriteEnabled();
      }
    });
  }

  @override
  void dispose() {
    _updateStatusSmart(); // التغيير المطلوب
    _pullAnimationController.dispose();
    _pushAnimationController.dispose();
    _pushProgress.dispose();
    _pushTotal.dispose();
    super.dispose();
  }

  void _updateStatusSmart() {
    debugPrint('🔄 تحديث ذكي للحالة قبل الخروج');
  }

  Future<void> _loadPendingChangesCount() async {
    try {
      final count = await _outboxDao.count();
      if (mounted) setState(() => _pendingChangesCount = count);
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
      if (mounted) setState(() => _appwriteEnabled = enabled);
    } catch (e) {
      debugPrint('❌ خطأ في تحميل حالة Appwrite: $e');
      if (mounted) setState(() => _appwriteEnabled = true);
    }
  }

  // تحديد الوجهات المتاحة للرفع
  Future<List<String>> _getAvailableTargets() async {
    final targets = <String>[];
    if (_appwriteEnabled) {
      await ref.read(connectionStatusProvider.notifier).checkConnection();
      if (ref.read(connectionStatusProvider).isConnected) {
        targets.add('Appwrite');
      }
    }
    final isGoogleDriveSignedIn = ref.read(smartSyncGoogleDriveSignInStatusProvider);
    if (isGoogleDriveSignedIn) {
      targets.add('Google Drive');
    }
    return targets;
  }

  // رفع جميع التغييرات إلى Appwrite
  Future<int> _pushToAppwrite() async {
    try {
      final deltaSync = AppwriteDeltaSync.instance;
      if (!deltaSync.isInitialized) {
        await deltaSync.initialize(
          ref.read(appwriteServiceProvider),
          ref.read(databaseProvider),
        );
      }
      final result = await deltaSync.pushDeltaChanges();
      if (result.success && result.pushedCount > 0) {
        // تنظيف outbox بعد النجاح
        await _outboxDao.clearStale(); // أو removeAllPending إن وجدت
        return result.pushedCount;
      }
    } catch (e) {
      debugPrint('❌ فشل رفع التغييرات إلى Appwrite: $e');
    }
    return 0;
  }

  // رفع نسخة كاملة إلى Google Drive (full backup)
  Future<int> _pushToGoogleDrive() async {
    try {
      final smartSyncManager = ref.read(smartSyncManagerProvider);
      final result = await smartSyncManager.pushLocalChanges();
      if (result) {
        await _outboxDao.clearStale();
        return _pendingChangesCount;
      }
    } catch (e) {
      debugPrint('❌ فشل رفع النسخة الكاملة إلى Google Drive: $e');
    }
    return 0;
  }

  Future<void> _pushChanges(BuildContext context) async {
    if (_isPushing) return;

    await _loadPendingChangesCount();
    if (_pendingChangesCount == 0) {
      _showSnackBar(context, '✅ لا توجد تغييرات جديدة', Colors.green);
      return;
    }

    final stopwatch = Stopwatch()..start();
    final syncId = 'push_${DateTime.now().millisecondsSinceEpoch}';
    final deviceId = await _getDeviceId();

    await _syncLogDao.logSync(
      syncId: syncId,
      direction: 'push',
      deviceId: deviceId,
      target: 'Appwrite+GoogleDrive',
      status: 'in_progress',
    );

    _pushAnimationController.repeat();
    setState(() => _isPushing = true);
    _pushProgress.value = 0;
    _pushTotal.value = _pendingChangesCount;

    try {
      final targets = await _getAvailableTargets();
      if (targets.isEmpty) {
        _showSnackBar(context, 'لا توجد وجهات متاحة', Colors.orange);
        return;
      }

      _showPushProgressSnackBar(context, targets);

      final futures = <Future<int>>[];
      if (targets.contains('Appwrite')) {
        futures.add(_pushToAppwrite());
      }
      if (targets.contains('Google Drive')) {
        futures.add(_pushToGoogleDrive());
      }

      final results = await Future.wait(futures, eagerError: false);
      final totalPushed = results.fold<int>(0, (sum, val) => sum + val);
      _pushProgress.value = totalPushed;

      await _loadPendingChangesCount();

      stopwatch.stop();
      await _syncLogDao.logSync(
        syncId: syncId,
        direction: 'push',
        deviceId: deviceId,
        target: targets.join('+'),
        status: totalPushed > 0 ? 'success' : 'failed',
        recordsPushed: totalPushed,
        durationMs: stopwatch.elapsedMilliseconds,
      );

      setState(() => _lastSyncTime = DateTime.now());
      _showSuccessPushSnackBar(context, totalPushed, targets);
    } catch (e) {
      debugPrint('❌ فشل الرفع: $e');
      stopwatch.stop();
      await _syncLogDao.logSync(
        syncId: syncId,
        direction: 'push',
        deviceId: deviceId,
        target: 'Appwrite+GoogleDrive',
        status: 'failed',
        errorMessage: _sanitizeError(e.toString()),
        durationMs: stopwatch.elapsedMilliseconds,
      );
      _showErrorSnackBar(context, 'تعذر الرفع', action: SnackBarAction(
        label: 'إعادة', onPressed: () => _pushChanges(context)));
    } finally {
      _pushAnimationController.stop();
      _pushAnimationController.reset();
      _pushProgress.value = 0;
      _pushTotal.value = 0;
      if (mounted) setState(() => _isPushing = false);
    }
  }

  Future<void> _pullChanges(BuildContext context) async {
    if (_isPulling) return;

    final stopwatch = Stopwatch()..start();
    final syncId = 'pull_${DateTime.now().millisecondsSinceEpoch}';
    final deviceId = await _getDeviceId();

    await _syncLogDao.logSync(
      syncId: syncId,
      direction: 'pull',
      deviceId: deviceId,
      target: 'Appwrite',
      status: 'in_progress',
    );

    _pullAnimationController.repeat();
    setState(() => _isPulling = true);

    try {
      if (!await _isAppwriteSyncEnabled()) {
        _showSnackBar(context, 'Appwrite معطل', Colors.orange);
        return;
      }

      await ref.read(connectionStatusProvider.notifier).checkConnection();
      if (!ref.read(connectionStatusProvider).isConnected) {
        _showSnackBar(context, 'لا يوجد اتصال', Colors.red);
        return;
      }

      _showProgressSnackBar(context, '⬇️ جاري سحب التغييرات...', Colors.blue);

      final deltaSync = AppwriteDeltaSync.instance;
      if (!deltaSync.isInitialized) {
        await deltaSync.initialize(
          ref.read(appwriteServiceProvider),
          ref.read(databaseProvider),
        );
      }

      final pullResult = await deltaSync.pullDeltaChanges().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('انتهت مهلة الاتصال'),
      );

      final pulledCount = pullResult.pulledCount;

      // لا نقوم بمسح outbox هنا

      // ✅ حل التعارضات التلقائي بعد السحب
      int conflictsResolved = 0;
      if (pullResult.success && pulledCount > 0) {
        conflictsResolved = await _resolveConflicts();
      }

      AppwriteRealtimeSync().resetRemoteChangesFlag();

      stopwatch.stop();
      await _syncLogDao.logSync(
        syncId: syncId,
        direction: 'pull',
        deviceId: deviceId,
        target: 'Appwrite',
        status: 'success',
        recordsPulled: pulledCount,
        durationMs: stopwatch.elapsedMilliseconds,
      );

      setState(() => _lastSyncTime = DateTime.now());
      _showSuccessPullSnackBar(context, pulledCount, conflictsResolved);
    } catch (e) {
      debugPrint('❌ خطأ في السحب: $e');
      stopwatch.stop();
      await _syncLogDao.logSync(
        syncId: syncId,
        direction: 'pull',
        deviceId: deviceId,
        target: 'Appwrite',
        status: 'failed',
        errorMessage: _sanitizeError(e.toString()),
        durationMs: stopwatch.elapsedMilliseconds,
      );
      _showErrorSnackBar(context, 'تعذر السحب: $e');
    } finally {
      _pullAnimationController.stop();
      _pullAnimationController.reset();
      await _loadPendingChangesCount();
      if (mounted) setState(() => _isPulling = false);
    }
  }

  /// حل التعارضات التلقائي باستخدام ConflictResolver
  Future<int> _resolveConflicts() async {
    int resolvedCount = 0;
    try {
      final conflicts = await _outboxDao.getConflicts();
      if (conflicts.isEmpty) return 0;

      final resolver = ConflictResolver(
        deviceId: await _getDeviceId(),
        strategy: ConflictStrategy.newerWins, // يمكن تغيير الاستراتيجية حسب الحاجة
      );

      for (final conflict in conflicts) {
        try {
          // تحويل البيانات إلى الشكل المطلوب للمقارنة
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
              await _outboxDao.resolveConflict(
                conflict.id,
                winnerData,
                resolution: 'newer_wins',
              );
              resolvedCount++;
            }
          } else {
            // لا يوجد تعارض حقيقي (ربما نفس البيانات)
            await _outboxDao.resolveConflict(
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

  Future<String> _getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString('device_id');
      if (deviceId == null) {
        deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString('device_id', deviceId);
      }
      return deviceId;
    } catch (_) {
      return 'unknown';
    }
  }

  String _sanitizeError(String error) {
    return error
        .replaceAll(RegExp(r'Bearer\s+[a-zA-Z0-9\-\._]+'), 'Bearer [REDACTED]')
        .replaceAll(RegExp(r'key=[a-zA-Z0-9]+'), 'key=[REDACTED]')
        .replaceAll(RegExp(r'project=[a-zA-Z0-9]+'), 'project=[REDACTED]')
        .replaceAll(RegExp(r'secret=[a-zA-Z0-9]+'), 'secret=[REDACTED]');
  }

  String _formatLastSyncTime(DateTime? lastSync) {
    if (lastSync == null) return '';
    final diff = DateTime.now().difference(lastSync);
    if (diff.inSeconds < 60) return 'منذ ${diff.inSeconds} ثانية';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  // ========== دوال عرض SnackBar (كما هي) ==========

  void _showSnackBar(BuildContext context, String msg, Color color,
      {Duration duration = const Duration(seconds: 3)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: duration),
    );
  }

  void _showProgressSnackBar(BuildContext context, String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white))),
          const SizedBox(width: 12),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: color,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showPushProgressSnackBar(BuildContext context, List<String> targets) {
    if (!mounted) return;
    final snackBar = SnackBar(
      content: ValueListenableBuilder<int>(
        valueListenable: _pushProgress,
        builder: (_, progress, __) => ValueListenableBuilder<int>(
          valueListenable: _pushTotal,
          builder: (_, total, __) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(child: Text('⬆️ جاري الرفع إلى ${targets.join(' + ')}...')),
              ]),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: total > 0 ? progress / total : 0),
              const SizedBox(height: 4),
              Text('$progress / $total سجل'),
            ],
          ),
        ),
      ),
      backgroundColor: Colors.blue,
      duration: const Duration(days: 1),
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  void _showSuccessPullSnackBar(BuildContext context, int pulled, int resolved) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: const [Icon(Icons.cloud_done, color: Colors.white), SizedBox(width: 8), Text('✅ تم السحب بنجاح!')]),
          Text('⬇️ $pulled سجل' + (resolved > 0 ? ' ⚖️ $resolved تعارض' : '')),
        ]),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessPushSnackBar(BuildContext context, int pushed, List<String> targets) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: const [Icon(Icons.cloud_done, color: Colors.white), SizedBox(width: 8), Text('✅ تم الرفع بنجاح!')]),
          Text('⬆️ $pushed سجل'),
          Text('☁️ عبر ${targets.join(' + ')}'),
        ]),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String msg, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [const Icon(Icons.error_outline, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text(msg))]),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        action: action,
      ),
    );
  }

  // ========== بناء الأزرار ==========

  Widget _buildPullButton(bool hasRemoteChanges, bool isGoogleDriveSignedIn, int pendingCount) {
    final bool pullEnabled = _appwriteEnabled && !_isPulling && !_isPushing;
    Color buttonColor;
    String buttonText;
    if (_isPulling) {
      buttonColor = Colors.blue;
      buttonText = 'جاري السحب...';
    } else if (hasRemoteChanges) {
      buttonColor = Colors.blue;
      buttonText = 'سحب التغييرات';
    } else {
      buttonColor = Colors.blueGrey;
      buttonText = 'تحقق من التحديثات';
    }
    return Tooltip(
      message: hasRemoteChanges ? 'توجد تحديثات جديدة' : 'تحقق من السيرفر',
      child: Stack(clipBehavior: Clip.none, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [buttonColor.withOpacity(0.85), buttonColor]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: pullEnabled ? () => _pullChanges(context) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_isPulling)
                    RotationTransition(turns: _pullAnimationController, child: const Icon(Icons.cloud_download, size: 14, color: Colors.white))
                  else
                    const Icon(Icons.cloud_download, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(buttonText, style: const TextStyle(color: Colors.white, fontSize: 11)),
                ]),
              ),
            ),
          ),
        ),
        if (hasRemoteChanges && !_isPulling && pendingCount > 0)
          Positioned(
            top: -6, right: -6,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              child: Center(child: Text(pendingCount > 99 ? '99+' : '$pendingCount', style: const TextStyle(color: Colors.white, fontSize: 10))),
            ),
          ),
      ]),
    );
  }

  Widget _buildPushButton(bool hasChanges, bool isGoogleDriveSignedIn) {
    final bool pushEnabled = hasChanges && !_isPulling && !_isPushing;
    Color buttonColor;
    String buttonText;
    if (_isPushing) {
      buttonColor = Colors.purple;
      buttonText = 'جاري الرفع...';
    } else if (hasChanges) {
      buttonColor = Colors.purple;
      buttonText = 'رفع التغييرات';
    } else {
      buttonColor = Colors.grey;
      buttonText = 'محدّث';
    }
    return Tooltip(
      message: hasChanges ? 'رفع $_pendingChangesCount تغيير' : 'جميع التغييرات مرفوعة',
      child: Stack(clipBehavior: Clip.none, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [buttonColor.withOpacity(0.85), buttonColor]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: pushEnabled ? () => _pushChanges(context) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_isPushing)
                    RotationTransition(turns: _pushAnimationController, child: const Icon(Icons.cloud_upload, size: 14, color: Colors.white))
                  else
                    const Icon(Icons.cloud_upload, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(buttonText, style: const TextStyle(color: Colors.white, fontSize: 11)),
                ]),
              ),
            ),
          ),
        ),
        if (hasChanges && !_isPushing)
          Positioned(
            top: -6, right: -6,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              child: Center(child: Text(_pendingChangesCount > 99 ? '99+' : '$_pendingChangesCount', style: const TextStyle(color: Colors.white, fontSize: 10))),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGoogleDriveSignedIn = ref.watch(smartSyncGoogleDriveSignInStatusProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: AppwriteRealtimeSync().hasRemoteChanges,
      builder: (_, hasRemoteChanges, __) => ValueListenableBuilder<int>(
        valueListenable: AppwriteRealtimeSync().pendingRemoteChangesCount,
        builder: (_, pendingRemoteCount, __) {
          final hasLocalChanges = _pendingChangesCount > 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                _buildPullButton(hasRemoteChanges, isGoogleDriveSignedIn, pendingRemoteCount),
                const SizedBox(width: 8),
                _buildPushButton(hasLocalChanges, isGoogleDriveSignedIn),
              ]),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _isPulling || _isPushing ? Colors.blue.shade50 : (hasLocalChanges || hasRemoteChanges ? Colors.orange.shade50 : Colors.green.shade50),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isPulling || _isPushing ? Colors.blue.shade200 : (hasLocalChanges || hasRemoteChanges ? Colors.orange.shade200 : Colors.green.shade200),
                    width: 1.5,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    hasLocalChanges || hasRemoteChanges
                        ? Icons.sync_problem
                        : (_isPulling || _isPushing ? Icons.sync : Icons.check_circle),
                    size: 12,
                    color: _isPulling || _isPushing ? Colors.blue : (hasLocalChanges || hasRemoteChanges ? Colors.orange : Colors.green),
                  ),
                  const SizedBox(width: 5),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      _isPulling ? 'جاري السحب...' : _isPushing ? 'جاري الرفع...' : hasLocalChanges ? '$_pendingChangesCount تغيير محلي' : hasRemoteChanges ? '$pendingRemoteCount تحديث' : 'محدّث',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    if (!_isPulling && !_isPushing && _lastSyncTime != null)
                      Text(_formatLastSyncTime(_lastSyncTime), style: TextStyle(fontSize: 8, color: Colors.grey.shade600)),
                  ]),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}
