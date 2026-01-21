import 'dart:async';

import '../data/sync_models.dart' as models;
import 'appwrite_sync_manager.dart';
import 'smart_sync_manager.dart';
import 'local_db.dart';

class UnifiedSyncState {
  final String
      phase; // idle | pushing | pulling | snapshotting | reconciling | completing | error
  final String message;
  final DateTime timestamp;
  final String? checksum; // shared checksum after reconcile
  final int outboxCount;
  final String? lastError;
  final DateTime? lastPushAt;
  final DateTime? lastPullAt;
  final DateTime? lastSnapshotAt;

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

/// Orchestrates Appwrite delta sync with Google Drive snapshots.
class UnifiedSyncOrchestrator {
  UnifiedSyncOrchestrator({
    required this.appwrite,
    required this.smart,
    required this.database,
  });

  final AppwriteSyncManager appwrite;
  final SmartSyncManager smart;
  final AppDatabase database;

  final _stateController = StreamController<UnifiedSyncState>.broadcast();
  Stream<UnifiedSyncState> get stateStream => _stateController.stream;

  bool _initialized = false;
  StreamSubscription? _appwriteSub;
  UnifiedSyncState _state = UnifiedSyncState(
    phase: 'idle',
    message: 'جاهز',
    timestamp: DateTime.now(),
    outboxCount: 0,
  );

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _emit(_state);

    // Listen to Appwrite sync status and project higher-level phases
    _appwriteSub = appwrite.syncStatusStream.listen((status) async {
      if (status == SyncStatus.syncing) {
        _emit(_state.copyWith(
            phase: 'pushing',
            message: 'مزامنة الدلتا مع Appwrite',
            timestamp: DateTime.now()));
      } else if (status == SyncStatus.success) {
        _emit(_state.copyWith(
            phase: 'pulling',
            message: 'سحب التغييرات وإنهاء الدمج',
            timestamp: DateTime.now(),
            lastPushAt: DateTime.now()));
        // After a successful delta, consider snapshot if needed
        await _snapshotIfNeeded();
      } else if (status == SyncStatus.failed) {
        _emit(_state.copyWith(
            phase: 'error',
            message: 'فشل مزامنة Appwrite',
            timestamp: DateTime.now(),
            lastError: 'Appwrite sync failed'));
      } else if (status == SyncStatus.idle || status == SyncStatus.partial) {
        _emit(_state.copyWith(
            phase: 'idle', message: 'جاهز', timestamp: DateTime.now()));
      }
    });
  }

  Future<void> dispose() async {
    await _appwriteSub?.cancel();
    await _stateController.close();
  }

  Future<void> syncAll({bool forceSnapshot = false}) async {
    _emit(_state.copyWith(
        phase: 'pushing',
        message: 'مزامنة Appwrite (دلتا)',
        timestamp: DateTime.now()));
    await appwrite.sync();
    await _snapshotIfNeeded(force: forceSnapshot);
    _emit(_state.copyWith(
        phase: 'completing',
        message: 'اكتملت الدورة',
        timestamp: DateTime.now()));
  }

  Future<void> pushDelta() async {
    _emit(_state.copyWith(
        phase: 'pushing',
        message: 'مزامنة Appwrite (دلتا)',
        timestamp: DateTime.now()));
    await appwrite.sync();
  }

  Future<void> snapshotNow() async {
    await _takeSnapshot();
  }

  Future<void> _snapshotIfNeeded({bool force = false}) async {
    // Simple heuristic: take snapshot if forced or 20 minutes passed since last snapshot
    final now = DateTime.now();
    if (!force && _state.lastSnapshotAt != null) {
      final diff = now.difference(_state.lastSnapshotAt!);
      if (diff.inMinutes < 20) return;
    }
    await _takeSnapshot();
  }

  Future<void> _takeSnapshot() async {
    _emit(_state.copyWith(
        phase: 'snapshotting',
        message: 'إنشاء Snapshot على Google Drive',
        timestamp: DateTime.now()));
    // SmartSyncManager سيهتم بإنشاء اللقطة ورفعها
    await smart.forceSyncNow();
    // بعد الرفع، احسب checksum موحد من الجداول المحلية لتظهر في الحالة
    final checksum = await _computeUnifiedChecksum();
    _emit(_state.copyWith(
      phase: 'completing',
      message: 'تم إنشاء Snapshot',
      timestamp: DateTime.now(),
      checksum: checksum,
      lastSnapshotAt: DateTime.now(),
    ));
  }

  Future<String> _computeUnifiedChecksum() async {
    final results = await Future.wait([
      (database.select(database.rooms)).get(),
      (database.select(database.bookings)).get(),
      (database.select(database.bookingNotes)).get(),
      (database.select(database.employees)).get(),
      (database.select(database.expenses)).get(),
      (database.select(database.cashTransactions)).get(),
      (database.select(database.payments)).get(),
      (database.select(database.debts)).get(),
      (database.select(database.bookingNights)).get(),
      (database.select(database.hotelDayLedger)).get(),
      (database.select(database.shiftNotes)).get(),
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
      'hotel_day_ledger': (results[9] as List).map((e) => e.toJson()).toList(),
      'shift_notes': (results[10] as List).map((e) => e.toJson()).toList(),
    };
    return models.SyncChecksum.compute({'tables': snapshot});
  }

  void _emit(UnifiedSyncState s) {
    _state = s;
    if (!_stateController.isClosed) {
      _stateController.add(s);
    }
  }
}
