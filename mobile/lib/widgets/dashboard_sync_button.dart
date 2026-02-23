import 'dart:async';
import 'dart:isolate';

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
  // الحالات
  bool _isPulling = false;
  bool _isPushing = false;
  bool _appwriteEnabled = true;
  Timer? _pendingChangesTimer;
  late AnimationController _pullAnimationController;
  late AnimationController _pushAnimationController;
  int _pendingChangesCount = 0;
  DateTime? _lastSyncTime;

  // متغيرات للتقدم أثناء الرفع
  final ValueNotifier<int> _pushProgress = ValueNotifier<int>(0);
  final ValueNotifier<int> _pushTotal = ValueNotifier<int>(0);

  // حجم الدفعة (Chunk size) لتحسين الأداء
  static const int _chunkSize = 50;

  // DAOs
  late OutboxDao _outboxDao;
  late SyncLogDao _syncLogDao;

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

    // تهيئة DAOs
    final db = ref.read(databaseProvider);
    _outboxDao = OutboxDao(db);
    _syncLogDao = SyncLogDao(db);

    _loadPendingChangesCount();
    _loadAppwriteEnabled();

    // تحديث دوري للعدادات
    _pendingChangesTimer = Timer.periodic(const Duration(seconds: 2), (_) {
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
    _pushProgress.dispose();
    _pushTotal.dispose();
    super.dispose();
  }

  // تحميل عدد التغييرات المعلقة من outbox
  Future<void> _loadPendingChangesCount() async {
    try {
      final count = await _outboxDao.count();
      if (mounted) {
        setState(() {
          _pendingChangesCount = count;
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل عدد التغييرات المعلقة: $e');
    }
  }

  // التحقق من تفعيل مزامنة Appwrite
  Future<bool> _isAppwriteSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('appwrite_sync_enabled') ?? false;
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
      if (mounted) {
        setState(() => _appwriteEnabled = true);
      } else {
        _appwriteEnabled = true;
      }
    }
  }

  /// الحصول على قائمة الوجهات المتاحة للرفع (بالتوازي)
  Future<List<String>> _getAvailableTargets() async {
    final targets = <String>[];

    // التحقق من Appwrite
    if (_appwriteEnabled) {
      await ref.read(connectionStatusProvider.notifier).checkConnection();
      final appwriteConnected = ref.read(connectionStatusProvider).isConnected;
      if (appwriteConnected) {
        targets.add('Appwrite');
      }
    }

    // التحقق من Google Drive (معطل حالياً)
    final isGoogleDriveSignedIn = ref.read(
      smartSyncGoogleDriveSignInStatusProvider,
    );
    if (isGoogleDriveSignedIn) {
      targets.add('Google Drive');
    }

    return targets;
  }

  /// رفع دفعة (Chunk) إلى وجهة محددة
  Future<int> _uploadChunk(String target, List<OutboxRecord> chunk,
      int offset, int chunkSize) async {
    int successCount = 0;
    try {
      switch (target) {
        case 'Appwrite':
          final deltaSync = AppwriteDeltaSync.instance;
          if (!deltaSync.isInitialized) {
            final appwriteService = ref.read(appwriteServiceProvider);
            final db = ref.read(databaseProvider);
            await deltaSync.initialize(appwriteService, db);
          }
          // رفع الدفعة (يمكن تخصيص دالة في DeltaSync لرفع دفعة)
          final result = await deltaSync.pushChunk(chunk);
          successCount = result.successCount;
          break;
        case 'Google Drive':
          // رفع إلى Google Drive (إذا كان مفعلاً)
          // يمكن استخدام SmartSyncManager
          final smartSyncManager = ref.read(smartSyncManagerProvider);
          final result = await smartSyncManager.pushChunk(chunk);
          successCount = result.successCount;
          break;
      }

      // إذا نجحت كل السجلات، يمكن حذفها من outbox
      if (successCount == chunk.length) {
        await _outboxDao.removeByIds(chunk.map((e) => e.id).toList());
      } else {
        // تحديث حالة السجلات التي فشلت (اختياري)
        for (var record in chunk) {
          if (!record.synced) {
            // يمكن زيادة عدد المحاولات أو تسجيل الخطأ
          }
        }
      }
    } catch (e) {
      debugPrint('❌ فشل رفع الدفعة إلى $target: $e');
    }
    return successCount;
  }

  /// سحب التغييرات من Appwrite (Pull فقط - بدون دفع)
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
      // التحقق من تفعيل Appwrite
      final appwriteEnabled = await _isAppwriteSyncEnabled();
      if (!appwriteEnabled) {
        _showSnackBar(context, 'مزامنة Appwrite معطلة', Colors.orange);
        return;
      }

      // التحقق من الاتصال
      await ref.read(connectionStatusProvider.notifier).checkConnection();
      final appwriteConnected = ref.read(connectionStatusProvider).isConnected;
      if (!appwriteConnected) {
        _showSnackBar(context, 'لا يوجد اتصال بـ Appwrite', Colors.red);
        return;
      }

      // إظهار مؤقت
      _showProgressSnackBar(context, '⬇️ جاري سحب التغييرات...', Colors.blue);

      // تهيئة DeltaSync
      final deltaSync = AppwriteDeltaSync.instance;
      if (!deltaSync.isInitialized) {
        final appwriteService = ref.read(appwriteServiceProvider);
        final db = ref.read(databaseProvider);
        await deltaSync.initialize(appwriteService, db);
      }

      // سحب التغييرات مع مهلة زمنية
      final pullResult = await deltaSync.pullDeltaChanges().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('انتهت مهلة الاتصال'),
      );

      final pulledCount = pullResult.recordsPulled;

      // ❌ لا نقوم بمسح outbox هنا - هذا هو التصحيح الجوهري
      // التغييرات المحلية تبقى كما هي، ويتم دمجها مع القادمة عبر حل التعارضات

      // حل التعارضات إن وجدت
      int conflictsResolved = 0;
      if (pullResult.hasConflicts) {
        _showSnackBar(context, '⚖️ جاري حل التعارضات...', Colors.orange,
            duration: const Duration(seconds: 2));
        conflictsResolved = await _resolveConflicts();
      }

      // إعادة تعيين علامة التغييرات عن بعد
      AppwriteRealtimeSync().resetRemoteChangesFlag();

      // تسجيل النجاح
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

      setState(() {
        _lastSyncTime = DateTime.now();
      });

      _showSuccessPullSnackBar(context, pulledCount, conflictsResolved);
    } catch (e) {
      debugPrint('❌ خطأ في سحب التغييرات: $e');
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

      _showErrorSnackBar(context, 'تعذر سحب التغييرات: ${e.toString()}');
    } finally {
      _pullAnimationController.stop();
      _pullAnimationController.reset();
      await _loadPendingChangesCount();
      if (mounted) {
        setState(() => _isPulling = false);
      }
    }
  }

  /// رفع التغييرات المحلية إلى جميع الوجهات المتاحة (Push متوازي ومجزأ)
  Future<void> _pushChanges(BuildContext context) async {
    if (_isPushing) return;

    // تحديث العداد
    await _loadPendingChangesCount();
    if (_pendingChangesCount == 0) {
      _showSnackBar(context, '✅ لا توجد تغييرات جديدة للرفع', Colors.green);
      return;
    }

    final stopwatch = Stopwatch()..start();
    final syncId = 'push_${DateTime.now().millisecondsSinceEpoch}';
    final deviceId = await _getDeviceId();

    // تسجيل بداية العملية
    await _syncLogDao.logSync(
      syncId: syncId,
      direction: 'push',
      deviceId: deviceId,
      target: 'Appwrite+GoogleDrive',
      status: 'in_progress',
    );

    _pushAnimationController.repeat();
    setState(() => _isPushing = true);

    // إعادة تعيين مؤشرات التقدم
    _pushProgress.value = 0;
    _pushTotal.value = _pendingChangesCount;

    try {
      // 1. تجهيز الوجهات المتاحة (بالتوازي)
      final targets = await _getAvailableTargets();

      if (targets.isEmpty) {
        _showSnackBar(context, 'لا توجد وجهات مزامنة متاحة', Colors.orange);
        return;
      }

      // إظهار SnackBar مع progress (سيتم تحديثه لاحقاً)
      _showPushProgressSnackBar(context, targets);

      // 2. رفع البيانات بمقاطع (Chunks)
      int totalPushed = 0;
      int offset = 0;

      while (offset < _pendingChangesCount) {
        // قراءة دفعة من outbox
        final chunk = await _outboxDao.getPending(limit: _chunkSize, offset: offset);
        if (chunk.isEmpty) break;

        // رفع الدفعة إلى جميع الوجهات بالتوازي
        final uploadFutures = targets.map((target) =>
            _uploadChunk(target, chunk, offset, chunk.length));

        final results = await Future.wait(uploadFutures, eagerError: false);

        // تحديث العداد الكلي (كل future يرجع عدد النجاح)
        final chunkSuccess = results.fold<int>(0, (sum, val) => sum + val);
        totalPushed += chunkSuccess;

        // تحديث مؤشر التقدم
        _pushProgress.value = totalPushed;

        // الانتقال للدفعة التالية
        offset += _chunkSize;

        // تحديث حالة الرفع في الـ UI (اختياري)
        if (mounted) setState(() {});
      }

      // بعد الانتهاء، تحميل العدد المحدث من outbox
      await _loadPendingChangesCount();

      // تسجيل النجاح
      stopwatch.stop();
      await _syncLogDao.logSync(
        syncId: syncId,
        direction: 'push',
        deviceId: deviceId,
        target: targets.join('+'),
        status: 'success',
        recordsPushed: totalPushed,
        durationMs: stopwatch.elapsedMilliseconds,
      );

      setState(() {
        _lastSyncTime = DateTime.now();
      });

      _showSuccessPushSnackBar(context, totalPushed, targets);
    } catch (e) {
      debugPrint('❌ فشل رفع التغييرات: $e');
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

      _showErrorSnackBar(context, 'تعذر رفع التغييرات', action: SnackBarAction(
        label: 'إعادة',
        onPressed: () => _pushChanges(context),
      ));
    } finally {
      _pushAnimationController.stop();
      _pushAnimationController.reset();
      _pushProgress.value = 0;
      _pushTotal.value = 0;
      if (mounted) {
        setState(() => _isPushing = false);
      }
    }
  }

  /// حل التعارضات بين البيانات المحلية والبعيدة
  Future<int> _resolveConflicts() async {
    int resolvedCount = 0;
    try {
      final conflicts = await _outboxDao.getConflicts();

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
              await _outboxDao.resolveConflict(
                conflict.id,
                winnerData,
                resolution: 'newer_wins',
              );
              resolvedCount++;
            }
          } else {
            await _outboxDao.resolveConflict(
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

  /// تنظيف رسائل الخطأ من البيانات الحساسة
  String _sanitizeError(String error) {
    return error
        .replaceAll(RegExp(r'Bearer\s+[a-zA-Z0-9\-\._]+'), 'Bearer [REDACTED]')
        .replaceAll(RegExp(r'key=[a-zA-Z0-9]+'), 'key=[REDACTED]')
        .replaceAll(RegExp(r'project=[a-zA-Z0-9]+'), 'project=[REDACTED]')
        .replaceAll(RegExp(r'secret=[a-zA-Z0-9]+'), 'secret=[REDACTED]');
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

  // ========== دوال عرض SnackBar ==========

  void _showSnackBar(BuildContext context, String message, Color color,
      {Duration duration = const Duration(seconds: 3)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: duration,
      ),
    );
  }

  void _showProgressSnackBar(BuildContext context, String message, Color color) {
    if (!mounted) return;
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
        builder: (context, progress, child) {
          return ValueListenableBuilder<int>(
            valueListenable: _pushTotal,
            builder: (context, total, child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                          '⬆️ جاري الرفع إلى ${targets.join(' + ')}...',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: total > 0 ? progress / total : 0,
                    backgroundColor: Colors.white.withOpacity(0.3),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$progress / $total سجل',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              );
            },
          );
        },
      ),
      backgroundColor: Colors.blue,
      duration: const Duration(days: 1), // يبقى حتى ننتهي
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  void _showSuccessPullSnackBar(BuildContext context, int pulledCount, int conflictsResolved) {
    if (!mounted) return;
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

  void _showSuccessPushSnackBar(BuildContext context, int totalPushed, List<String> targets) {
    if (!mounted) return;
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
                const Expanded(
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
              '☁️ عبر: ${targets.join(' + ')}',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message,
      {SnackBarAction? action}) {
    if (!mounted) return;
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
        duration: const Duration(seconds: 4),
        action: action,
      ),
    );
  }

  // ========== بناء واجهة الأزرار ==========

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
                onTap: pullEnabled ? () => _pullChanges(context) : null,
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
          // Badge للتغييرات القادمة من السيرفر
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
                onTap: pushEnabled ? () => _pushChanges(context) : null,
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
          // Badge للتغييرات المحلية المعلقة
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
    final isGoogleDriveSignedIn = ref.watch(
      smartSyncGoogleDriveSignInStatusProvider,
    );

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
                    _buildPullButton(
                        hasRemoteChanges, isGoogleDriveSignedIn, pendingRemoteCount),
                    const SizedBox(width: 8),
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
