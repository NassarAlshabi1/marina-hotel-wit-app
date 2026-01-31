import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'appwrite_delta_sync.dart';
import 'appwrite_service.dart';
import 'appwrite_sync_manager.dart';
import 'google_drive_unified_sync_coordinator.dart';
import 'local_db.dart';
import 'sync_event_bus.dart';

class SyncRouter {
  SyncRouter._();

  static final SyncRouter instance = SyncRouter._();

  static const Set<String> _syncTables = {
    'rooms',
    'bookings',
    'booking_notes',
    'booking_nights',
    'hotel_day_ledger',
    'shift_notes',
    'employees',
    'expenses',
    'cash_transactions',
    'payments',
    'debts',
    'salary_cycles',
    'salary_payments',
    'sync_log',
    'sync_logs',
  };

  static const Set<String> _localOnlyTables = {
    'outbox',
    'sync_queue',
    'sync_conflicts',
    'sync_state',
    'integrity_violations',
    'app_sessions',
    'auto_fix_runs',
    'restore_fix_log',
  };

  StreamSubscription<SyncEvent>? _subscription;
  Timer? _debounceTimer;

  AppDatabase? _database;
  GoogleDriveUnifiedSyncCoordinator? _driveCoordinator;
  AppwriteSyncManager? _appwriteManager;
  AppwriteDeltaSync? _appwriteDelta;

  bool _initialized = false;
  bool _pendingDrive = false;
  bool _pendingAppwrite = false;
  int _pendingCount = 0;
  String? _lastTable;
  String? _lastOperation;

  static const Duration _debounceWindow = Duration(seconds: 2);

  Future<void> initialize({
    AppDatabase? database,
    GoogleDriveUnifiedSyncCoordinator? driveCoordinator,
    AppwriteSyncManager? appwriteManager,
  }) async {
    _database = database ?? _database;
    _driveCoordinator = driveCoordinator ?? _driveCoordinator;
    _appwriteManager = appwriteManager ?? _appwriteManager;
    if (_initialized) {
      return;
    }
    _initialized = true;
    start();
  }

  void start() {
    _subscription ??= SyncEventBus.instance.stream.listen(_handleEvent);
  }

  void _handleEvent(SyncEvent event) {
    if (event.table != null && _localOnlyTables.contains(event.table)) {
      return;
    }

    final shouldRoute = event.table == null || _syncTables.contains(event.table);
    if (!shouldRoute) {
      return;
    }

    _pendingCount += event.count;
    _lastTable = event.table;
    _lastOperation = event.operation;
    _pendingDrive = true;
    _pendingAppwrite = true;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceWindow, () {
      _flush();
    });
  }

  Future<void> _flush() async {
    final pendingDrive = _pendingDrive;
    final pendingAppwrite = _pendingAppwrite;
    final pendingCount = _pendingCount;
    final table = _lastTable;
    final operation = _lastOperation;

    _pendingDrive = false;
    _pendingAppwrite = false;
    _pendingCount = 0;
    _lastTable = null;
    _lastOperation = null;

    final prefs = await SharedPreferences.getInstance();
    final driveEnabled = prefs.getBool('google_drive_sync_enabled') ?? false;
    final appwriteEnabled = prefs.getBool('appwrite_sync_enabled') ?? true;

    if (pendingDrive && driveEnabled) {
      final coordinator =
          _driveCoordinator ?? GoogleDriveUnifiedSyncCoordinator.instance;
      _driveCoordinator ??= coordinator;
      coordinator.notifyLocalChange(
        table: table,
        operation: operation,
        count: pendingCount,
      );
    }

    if (pendingAppwrite && appwriteEnabled) {
      final useDelta = await AppwriteDeltaSync.instance.isEnabled();
      if (useDelta) {
        final delta = await _ensureAppwriteDelta();
        await delta?.pushDeltaChanges();
      } else {
        final manager = await _ensureAppwriteManager();
        await manager?.pushLocalChanges();
      }
    }
  }

  Future<AppwriteDeltaSync?> _ensureAppwriteDelta() async {
    if (_appwriteDelta != null) return _appwriteDelta;
    final db = _database ?? DatabaseManager.instance;
    _database ??= db;
    final service = AppwriteService();
    await service.initialize();
    final delta = AppwriteDeltaSync.instance;
    await delta.initialize(service, db);
    _appwriteDelta = delta;
    return delta;
  }

  Future<AppwriteSyncManager?> _ensureAppwriteManager() async {
    if (_appwriteManager != null) return _appwriteManager;
    final db = _database ?? DatabaseManager.instance;
    _database ??= db;
    final service = AppwriteService();
    await service.initialize();
    final manager =
        AppwriteSyncManager(appwriteService: service, database: db);
    await manager.initialize();
    _appwriteManager = manager;
    return manager;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}
