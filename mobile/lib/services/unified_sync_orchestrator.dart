import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/sync_models.dart' as models;
import 'appwrite_service.dart';
import 'appwrite_sync_manager.dart' show AppwriteSyncManager, SyncStatus;
import 'google_drive_backup_service.dart';
import 'google_drive_logger.dart';
import 'google_drive_unified_sync_coordinator.dart';
import 'local_db.dart';
import 'logging/log_models.dart';
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

  StreamSubscription? _appwriteSub;
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
    outboxCount: 0,
  );

  Future<void> initialize({
    AppwriteSyncManager? appwrite,
    GoogleDriveUnifiedSyncCoordinator? driveCoordinator,
    SmartSyncManager? smart,
    AppDatabase? database,
  }) async {
    if (appwrite != null) {
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

    await _attachListeners();

    if (!_initialized) {
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
    await _stateController.close();
    _initialized = false;
  }

  Future<void> notifyLocalChange({String? table, String? operation}) async {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 10), () async {
      // رفع تلقائي إلى Appwrite فقط بعد كل تغيير
      await _autoSyncToAppwrite(
        reason: 'local_change:${table ?? 'unknown'}:${operation ?? 'unknown'}',
      );
    });
  }

  /// رفع تلقائي إلى Appwrite فقط (بدون Google Drive)
  Future<bool> _autoSyncToAppwrite({String reason = 'auto'}) async {
    if (_syncing) {
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final appwriteEnabled = prefs.getBool('appwrite_sync_enabled') ?? false;

      if (!appwriteEnabled) {
        debugPrint('ℹ️ Appwrite sync معطل - تخطي الرفع التلقائي');
        return true;
      }

      _syncing = true;
      debugPrint('🔄 رفع تلقائي إلى Appwrite: $reason');

      final success = await _syncAppwrite(push: true, pull: false);

      if (success) {
        debugPrint('✅ تم الرفع التلقائي إلى Appwrite');
      } else {
        debugPrint('❌ فشل الرفع التلقائي إلى Appwrite');
      }

      return success;
    } catch (e) {
      debugPrint('❌ خطأ في الرفع التلقائي: $e');
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
      return false;
    }

    _syncing = true;

    _emit(
      _state.copyWith(
        phase: push ? 'pushing' : 'pulling',
        message: 'تشغيل المزامنة الموحدة',
        timestamp: DateTime.now(),
      ),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final appwriteEnabled = prefs.getBool('appwrite_sync_enabled') ?? false;
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
      return false;
    } finally {
      _syncing = false;
    }
  }

  Future<void> onAppForeground() async {
    await syncNow(push: false, pull: true, reason: 'app_foreground');
  }

  Future<void> onDriveSignInChanged(bool isSignedIn) async {
    if (_driveCoordinator == null) return;
    await _driveCoordinator!.onSignInChanged(isSignedIn);
  }

  Future<void> setDebounceSeconds(int seconds) async {
    if (_driveCoordinator == null) return;
    await _driveCoordinator!.setDebounceSeconds(seconds);
  }

  Future<void> setPullInterval(int minutes) async {
    if (_driveCoordinator == null) return;
    await _driveCoordinator!.setPullInterval(minutes);
  }

  Future<void> snapshotNow() async {
    await _takeSnapshot();
  }

  Future<void> _snapshotIfNeeded({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _state.lastSnapshotAt != null) {
      final diff = now.difference(_state.lastSnapshotAt!);
      if (diff.inMinutes < 20) return;
    }
    await _takeSnapshot();
  }

  Future<void> _takeSnapshot() async {
    if (_smart == null || _database == null) return;
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
      // ❌ hotel_day_ledger - محلي فقط، لا يتم مزامنته
      db.select(db.shiftNotes).get(),
    ]);

    final snapshot = {
      'rooms': (results[0] as List).map((e) => e.toJson()).toList(),
      'bookings': (results[1] as List).map((e) => e.toJson()).toList(),
      'booking_notes': (results[2] as List).map((e) => e.toJson()).toList(),
      'employees': (results[3] as List).map((e) => e.toJson()).toList(),
      'expenses': (results[4] as List).map((e) => e.toJson()).toList(),
      'cash_transactions': (results[5] as List).map((e) => e.toJson()).toList(),
      'payments': (results[6] as List).map((e) => e.toJson()).toList(),
      'debts': (results[7] as List).map((e) => e.toJson()).toList(),
      'booking_nights': (results[8] as List).map((e) => e.toJson()).toList(),
      // ❌ hotel_day_ledger - محلي فقط
      'shift_notes': (results[9] as List).map((e) => e.toJson()).toList(),
    };
    return models.SyncChecksum.compute({'tables': snapshot});
  }

  Future<bool> _syncAppwrite({required bool push, required bool pull}) async {
    final manager = await _ensureAppwriteManager();
    if (manager == null) {
      return false;
    }

    if (push && pull) {
      final result = await manager.sync(push: true, pull: true);
      return result.isSuccess;
    }

    var success = true;
    if (push) {
      success = await manager.pushLocalChanges() && success;
    }
    if (pull) {
      success = await manager.pullRemoteChanges() && success;
    }

    return success;
  }

  Future<AppwriteSyncManager?> _ensureAppwriteManager() async {
    if (_appwrite != null) return _appwrite;
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
      await logger.initialize(
        minLevel: LogLevel.info,
        enableConsole: true,
        enableFile: false,
      );
      final db = _database ?? DatabaseManager.instance;
      _database ??= db;
      await coordinator.initialize(
        backupService: backupService,
        database: db,
        logger: logger,
      );
    }

    if (push && pull) {
      final result = await coordinator.performSync(
        trigger: SyncTrigger.manual,
        mode: SyncMode.smart,
      );
      return result.success;
    }

    if (push && !pull) {
      final result = await coordinator.performSync(
        trigger: SyncTrigger.localChange,
        mode: SyncMode.smart,
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
    if (_database == null) return;

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
