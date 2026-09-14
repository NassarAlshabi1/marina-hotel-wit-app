import 'dart:async';
import 'dart:isolate';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/sync_models.dart' as models;
import '../utils/debug_log.dart';
import '../utils/weak_device_optimizer.dart';
import 'analytics_service.dart';
import 'appwrite_service.dart';
import 'appwrite_sync_manager.dart' show AppwriteSyncManager, SyncStatus;
import 'google_drive_backup_service.dart';
import 'google_drive_logger.dart';
import 'google_drive_unified_sync_coordinator.dart';
import 'local_db.dart';
import 'smart_sync_manager.dart';
import 'sync_integrity_checker.dart';

class UnifiedSyncState {
  const UnifiedSyncState({
    required this.phase,
    required this.message,
    required this.timestamp,
    this.checksum,
    this.outboxCount = 0,
    this.lastError,
    this.lastPushAt,
    this.lastPullAt,
    this.lastSnapshotAt,
  });
  final String phase;
  final String message;
  final DateTime timestamp;
  final String? checksum;
  final int outboxCount;
  final String? lastError;
  final DateTime? lastPushAt;
  final DateTime? lastPullAt;
  final DateTime? lastSnapshotAt;

  UnifiedSyncState copyWith({
    String? phase,
    String? message,
    DateTime? timestamp,
    String? checksum,
    int? outboxCount,
    String? lastError,
    DateTime? lastPushAt,
    DateTime? lastPullAt,
    DateTime? lastSnapshotAt,
  }) {
    return UnifiedSyncState(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      checksum: checksum ?? this.checksum,
      outboxCount: outboxCount ?? this.outboxCount,
      lastError: lastError ?? this.lastError,
      lastPushAt: lastPushAt ?? this.lastPushAt,
      lastPullAt: lastPullAt ?? this.lastPullAt,
      lastSnapshotAt: lastSnapshotAt ?? this.lastSnapshotAt,
    );
  }
}

class UnifiedSyncOrchestrator {
  UnifiedSyncOrchestrator._();

  static final UnifiedSyncOrchestrator instance = UnifiedSyncOrchestrator._();

  AppwriteSyncManager? _appwrite;
  GoogleDriveUnifiedSyncCoordinator? _driveCoordinator;
  SmartSyncManager? _smart;
  AppDatabase? _database;

  StreamSubscription<void>? _appwriteSub;
  StreamSubscription<SyncResult>? _driveSub;
  Timer? _debounceTimer;

  bool _initialized = false;
  bool _syncing = false;

  final _stateController = StreamController<UnifiedSyncState>.broadcast();
  Stream<UnifiedSyncState> get stateStream => _stateController.stream;

  UnifiedSyncState _state = UnifiedSyncState(
    phase: 'idle',
    message: 'جاهز',
    timestamp: DateTime.now(),
  );

  Future<void> initialize({
    AppwriteSyncManager? appwrite,
    GoogleDriveUnifiedSyncCoordinator? driveCoordinator,
    SmartSyncManager? smart,
    AppDatabase? database,
  }) async {
    // ✅ P1-1 fix: idempotent — لا نُعيد التهيئة إذا تمت مسبقاً
    if (appwrite != null && _appwrite == null) {
      _appwrite = appwrite;
      await _appwrite!.initialize();
    }
    if (driveCoordinator != null) {
      _driveCoordinator = driveCoordinator;
    }
    _smart = smart ?? _smart ?? SmartSyncManager.instance;
    if (database != null) {
      _database = database;
    }
    _driveCoordinator ??= GoogleDriveUnifiedSyncCoordinator.instance;

    // ✅ P1-1 fix: عدم إعادة attachListeners إذا تمت مسبقاً
    if (!_initialized) {
      await _attachListeners();
      _initialized = true;
      _emit(_state);
    }
  }

  Future<void> _attachListeners() async {
    await _appwriteSub?.cancel();
    await _driveSub?.cancel();

    if (_appwrite != null) {
      _appwriteSub = _appwrite!.syncStatusStream.listen((status) async {
        switch (status) {
          case SyncStatus.syncing:
            _emit(
              _state.copyWith(
                phase: 'pushing',
                message: 'مزامنة الدلتا مع Appwrite',
                timestamp: DateTime.now(),
              ),
            );
          case SyncStatus.success:
            _emit(
              _state.copyWith(
                phase: 'pulling',
                message: 'سحب التغييرات وإنهاء الدمج',
                timestamp: DateTime.now(),
                lastPushAt: DateTime.now(),
              ),
            );
            await _snapshotIfNeeded();
          case SyncStatus.failed:
            _emit(
              _state.copyWith(
                phase: 'error',
                message: 'فشل مزامنة Appwrite',
                timestamp: DateTime.now(),
                lastError: 'Appwrite sync failed',
              ),
            );
          case SyncStatus.idle:
          case SyncStatus.partial:
            _emit(
              _state.copyWith(
                phase: 'idle',
                message: 'جاهز',
                timestamp: DateTime.now(),
              ),
            );
        }
      });
    }

    if (_driveCoordinator != null) {
      _driveSub = _driveCoordinator!.syncResults.listen((result) {
        if (result.success) {
          _emit(
            _state.copyWith(
              phase: 'completing',
              message: result.message,
              timestamp: DateTime.now(),
              lastPushAt:
                  result.pushedChanges != null && result.pushedChanges! > 0
                  ? DateTime.now()
                  : _state.lastPushAt,
              lastPullAt:
                  result.pulledChanges != null && result.pulledChanges! > 0
                  ? DateTime.now()
                  : _state.lastPullAt,
            ),
          );
        } else {
          _emit(
            _state.copyWith(
              phase: 'error',
              message: result.message,
              timestamp: DateTime.now(),
              lastError: result.error,
            ),
          );
        }
      });
    }
  }

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    await _appwriteSub?.cancel();
    await _driveSub?.cancel();
    unawaited(_stateController.close());
    _initialized = false;
  }

  /// تنظيف الموارد الثابتة للـ singleton (يُستدعى عند إغلاق التطبيق)
  static void disposeInstance() {
    instance.dispose();
  }

  Future<void> notifyLocalChange({String? table, String? operation}) async {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 10), () async {
      // ✅ إصلاح جذري: Timer callback async بدون try-catch يُسبب
      // unhandled async error → Crashlytics Fatal عند أي استثناء شبكي.
      try {
        await _autoSyncToAppwrite(
          reason:
              'local_change:${table ?? 'unknown'}:${operation ?? 'unknown'}',
        );
      } catch (e, stackTrace) {
        dwarn(() => '❌ UnifiedSyncOrchestrator: خطأ في debounce auto sync: $e');
        dwarn(() => 'Stack trace: $stackTrace');
        // لا rethrow — نمنع fatal crash
      }
    });
  }

  /// رفع تلقائي إلى Appwrite فقط (بدون Google Drive)
  /// ✅ P1-2 fix: تمييز "مشغول" (true) عن "فشل" (false)
  Future<bool> _autoSyncToAppwrite({String reason = 'auto'}) async {
    if (_syncing) {
      dlog(() => '⏸️ _autoSyncToAppwrite: مشغول — تخطي (ليس فشل)');
      return true; // مشغول ≠ فشل — لا نُعيد جدولة إعادة محاولة
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final appwriteEnabled = prefs.getBool('appwrite_sync_enabled') ?? true;

      if (!appwriteEnabled) {
        dlog(() => 'ℹ️ Appwrite sync معطل - تخطي الرفع التلقائي');
        return true;
      }

      _syncing = true;
      dlog(() => '🔄 رفع تلقائي إلى Appwrite: $reason');

      final success = await _syncAppwrite(push: true, pull: false);

      if (success) {
        dlog(() => '✅ تم الرفع التلقائي إلى Appwrite');
      } else {
        dwarn(() => '❌ فشل الرفع التلقائي إلى Appwrite');
      }

      return success;
    } catch (e) {
      dwarn(() => '❌ خطأ في الرفع التلقائي: $e');
      return false;
    } finally {
      _syncing = false;
    }
  }

  Future<bool> syncNow({
    bool push = true,
    bool pull = true,
    String reason = 'manual',
    bool forceSnapshot = false,
  }) async {
    if (_syncing) {
      dlog(() => '⏸️ syncNow: مشغول — تخطي (ليس فشل)');
      return true; // ✅ P1-2: مشغول ≠ فشل
    }

    _syncing = true;
    // ✅ Analytics: تتبّع بدء المزامنة مع سببها (manual/foreground/periodic)
    final syncStartTime = DateTime.now();
    unawaited(AnalyticsService().logSyncStart(trigger: reason));

    _emit(
      _state.copyWith(
        phase: push ? 'pushing' : 'pulling',
        message: 'تشغيل المزامنة الموحدة',
        timestamp: DateTime.now(),
      ),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final appwriteEnabled = prefs.getBool('appwrite_sync_enabled') ?? true;
      final googleDriveEnabled =
          prefs.getBool('google_drive_sync_enabled') ?? false;

      var success = true;

      if (appwriteEnabled) {
        success = await _syncAppwrite(push: push, pull: pull) && success;
      }

      if (googleDriveEnabled) {
        success =
            await _syncGoogleDrive(push: push, pull: pull, reason: reason) &&
            success;
      }

      if (forceSnapshot) {
        await snapshotNow();
      }

      if (success) {
        await _verifySyncIntegrity();
      }

      _emit(
        _state.copyWith(
          phase: success ? 'completing' : 'error',
          message: success ? 'اكتملت الدورة' : 'فشل في مزامنة واحدة أو أكثر',
          timestamp: DateTime.now(),
        ),
      );

      // ✅ Analytics: تسجيل اكتمال المزامنة مع المدة وعدد العناصر
      final syncDuration = DateTime.now().difference(syncStartTime);
      unawaited(
        AnalyticsService().logSyncComplete(
          itemsProcessed: 0, // ملاحظة: عدد العناصر الفعلي غير متاح هنا
          duration: syncDuration,
        ),
      );

      return success;
    } catch (e) {
      _emit(
        _state.copyWith(
          phase: 'error',
          message: 'فشل تشغيل المزامنة',
          timestamp: DateTime.now(),
          lastError: e.toString(),
        ),
      );
      // ✅ Analytics: تسجيل فشل المزامنة
      final syncDuration = DateTime.now().difference(syncStartTime);
      unawaited(
        AnalyticsService().logSyncFailure(
          error: e.toString(),
          operation: 'syncNow',
          attempt: 1,
        ),
      );
      dlog(
        () =>
            '📊 Analytics: sync failed after ${syncDuration.inMilliseconds}ms',
      );
      return false;
    } finally {
      _syncing = false;
    }
  }

  Future<void> onAppForeground() async {
    await syncNow(push: false, reason: 'app_foreground');
  }

  Future<void> onDriveSignInChanged(bool isSignedIn) async {
    if (_driveCoordinator == null) {
      return;
    }
    await _driveCoordinator!.onSignInChanged(isSignedIn);
  }

  Future<void> setDebounceSeconds(int seconds) async {
    if (_driveCoordinator == null) {
      return;
    }
    await _driveCoordinator!.setDebounceSeconds(seconds);
  }

  Future<void> setPullInterval(int minutes) async {
    if (_driveCoordinator == null) {
      return;
    }
    await _driveCoordinator!.setPullInterval(minutes);
  }

  Future<void> snapshotNow() async {
    await _takeSnapshot();
  }

  Future<void> _snapshotIfNeeded({bool force = false}) async {
    // الـ snapshot التلقائي يقرأ جداول كاملة ويبني عدة نسخ JSON في الذاكرة.
    // على جهاز 1GB نحتفظ بالمزامنة التفاضلية ونؤجل الـ snapshot إلى طلب يدوي.
    if (!force && WeakDeviceOptimizer.instance.isWeakDevice) {
      dlog('🧠 Low-RAM policy: skipped automatic full snapshot');
      return;
    }

    final now = DateTime.now();
    if (!force && _state.lastSnapshotAt != null) {
      final diff = now.difference(_state.lastSnapshotAt!);
      if (diff.inMinutes < 20) {
        return;
      }
    }
    await _takeSnapshot();
  }

  Future<void> _takeSnapshot() async {
    if (_smart == null || _database == null) {
      return;
    }
    _emit(
      _state.copyWith(
        phase: 'snapshotting',
        message: 'إنشاء Snapshot على Google Drive',
        timestamp: DateTime.now(),
      ),
    );
    await _smart!.forceSyncNow();
    final checksum = await _computeUnifiedChecksum();
    _emit(
      _state.copyWith(
        phase: 'completing',
        message: 'تم إنشاء Snapshot',
        timestamp: DateTime.now(),
        checksum: checksum,
        lastSnapshotAt: DateTime.now(),
      ),
    );
  }

  Future<String> _computeUnifiedChecksum() async {
    final db = _database!;
    final results = await Future.wait([
      db.select(db.rooms).get(),
      db.select(db.bookings).get(),
      db.select(db.bookingNotes).get(),
      db.select(db.employees).get(),
      db.select(db.expenses).get(),
      db.select(db.cashTransactions).get(),
      db.select(db.payments).get(),
      db.select(db.debts).get(),
      db.select(db.bookingNights).get(),
      db.select(db.hotelDayLedger).get(),
      db.select(db.shiftNotes).get(),
    ]);

    final tablesPayload = <String, List<Map<String, dynamic>>>{
      'rooms': (results[0] as List)
          .map((e) => e.toJson() as Map<String, dynamic>)
          .toList(),
      'bookings': (results[1] as List)
          .map((e) => e.toJson() as Map<String, dynamic>)
          .toList(),
      'booking_notes': (results[2] as List)
          .map((e) => e.toJson() as Map<String, dynamic>)
          .toList(),
      'employees': (results[3] as List)
          .map((e) => e.toJson() as Map<String, dynamic>)
          .toList(),
      'expenses': (results[4] as List)
          .map((e) => e.toJson() as Map<String, dynamic>)
          .toList(),
      'cash_transactions': (results[5] as List)
          .map((e) => e.toJson() as Map<String, dynamic>)
          .toList(),
      'payments': (results[6] as List)
          .map((e) => e.toJson() as Map<String, dynamic>)
          .toList(),
      'debts': (results[7] as List)
          .map((e) => e.toJson() as Map<String, dynamic>)
          .toList(),
      'booking_nights': (results[8] as List)
          .map((e) => e.toJson() as Map<String, dynamic>)
          .toList(),
      'hotel_day_ledger': (results[9] as List)
          .map((e) => e.toJson() as Map<String, dynamic>)
          .toList(),
      'shift_notes': (results[10] as List)
          .map((e) => e.toJson() as Map<String, dynamic>)
          .toList(),
    };
    return Isolate.run(
      () => models.SyncChecksum.compute({'tables': tablesPayload}),
    );
  }

  Future<bool> _syncAppwrite({required bool push, required bool pull}) async {
    final manager = await _ensureAppwriteManager();
    if (manager == null) {
      return false;
    }

    if (push && pull) {
      final result = await manager.sync();
      return result.isSuccess;
    }

    var success = true;
    if (push) {
      final pushed = await manager.pushLocalChanges();
      success = (pushed >= 0) && success;
    }
    if (pull) {
      // تفويض السحب للمسار الموحد: pull خلفي/تلقائي = دلتا عبر
      // checkpoints لكل مجموعة — لا Full Sync من الخلفية أبداً
      // (Bootstrap الصريح وحده يبدأ السحب الكامل). اليدوي يمر عبر فرع
      // push&&pull أعلاه حيث يبقى السحب الكامل قراراً مرئياً.
      final result = await manager.sync(push: false, pull: true);
      success = result.isSuccess && success;
    }

    return success;
  }

  Future<AppwriteSyncManager?> _ensureAppwriteManager() async {
    if (_appwrite != null) {
      return _appwrite;
    }
    final db = _database ?? DatabaseManager.instance;
    _database ??= db;
    final service = AppwriteService();
    final manager = AppwriteSyncManager(appwriteService: service, database: db);
    await manager.initialize();
    _appwrite = manager;
    return manager;
  }

  Future<bool> _syncGoogleDrive({
    required bool push,
    required bool pull,
    required String reason,
  }) async {
    final coordinator =
        _driveCoordinator ?? GoogleDriveUnifiedSyncCoordinator.instance;
    _driveCoordinator ??= coordinator;

    if (!coordinator.isInitialized) {
      final backupService = GoogleDriveBackupService();
      final account = await backupService.attemptSilentSignIn();
      if (account == null) {
        return false;
      }
      final logger = GoogleDriveLogger();
      await logger.initialize();
      final db = _database ?? DatabaseManager.instance;
      _database ??= db;
      await coordinator.initialize(
        backupService: backupService,
        database: db,
        logger: logger,
      );
    }

    if (push && pull) {
      final result = await coordinator.performSync(trigger: SyncTrigger.manual);
      return result.success;
    }

    if (push && !pull) {
      final result = await coordinator.performSync(
        trigger: SyncTrigger.localChange,
      );
      return result.success;
    }

    if (!push && pull) {
      final result = await coordinator.performSync(
        trigger: SyncTrigger.periodic,
        mode: SyncMode.deltaOnly,
      );
      return result.success;
    }

    return true;
  }

  Future<void> _verifySyncIntegrity() async {
    if (_database == null) {
      return;
    }

    try {
      _emit(
        _state.copyWith(
          phase: 'verifying',
          message: 'التحقق من سلامة البيانات',
          timestamp: DateTime.now(),
        ),
      );

      final report = await SyncIntegrityChecker.instance.verify(_database!);

      if (report.hasCriticalIssues) {
        _emit(
          _state.copyWith(
            phase: 'completing',
            message: 'تم اكتشاف ${report.criticalIssueCount} مشاكل حرجة',
            timestamp: DateTime.now(),
            lastError:
                'Found ${report.criticalIssueCount} critical integrity issues',
          ),
        );
      } else if (report.hasIssues) {
        _emit(
          _state.copyWith(
            phase: 'completing',
            message: 'تم اكتشاف ${report.issueCount} مشاكل غير حرجة',
            timestamp: DateTime.now(),
          ),
        );
      } else {
        _emit(
          _state.copyWith(
            phase: 'completing',
            message: 'سلامة البيانات جيدة',
            timestamp: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      _emit(
        _state.copyWith(
          phase: 'error',
          message: 'فشل التحقق من سلامة البيانات',
          timestamp: DateTime.now(),
          lastError: e.toString(),
        ),
      );
    }
  }

  void _emit(UnifiedSyncState s) {
    _state = s;
    if (!_stateController.isClosed) {
      _stateController.add(s);
    }
  }
}
