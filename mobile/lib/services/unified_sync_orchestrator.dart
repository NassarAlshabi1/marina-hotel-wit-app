import 'dart:async';

import '../data/sync_models.dart' as models;
import 'appwrite_sync_manager.dart';
import 'smart_sync_manager.dart';
import 'local_db.dart';

class UnifiedSyncState {
  final String phase; // idle | pushing | pulling | snapshotting | reconciling | completing | error
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
      switch (status) {
        case SyncStatus.syncing:
          _emit(_state.copyWith(phase: 'pushing', message: 'مزامنة الدلتا مع Appwrite', timestamp: DateTime.now()));
          break;
        case SyncStatus.success:
          _emit(_state.copyWith(phase: 'pulling', message: 'سحب التغييرات وإنهاء الدمج', timestamp: DateTime.now(), lastPushAt: DateTime.now()));
          // After a successful delta, consider snapshot if needed
          await _snapshotIfNeeded();
          break;
        case SyncStatus.failed:
          _emit(_state.copyWith(phase: 'error', message: 'فشل مزامنة Appwrite', timestamp: DateTime.now(), lastError: 'Appwrite sync failed'));
          break;
        case SyncStatus.idle:
        case SyncStatus.partial:
          _emit(_state.copyWith(phase: 'idle', message: 'جاهز', timestamp: DateTime.now()));
          break;
      }
    });
  }

  Future<void> dispose() async {
    await _appwriteSub?.cancel();
    await _stateController.close();
  }

  Future<void> syncAll({bool forceSnapshot = false}) async {
    _emit(_state.copyWith(phase: 'pushing', message: 'مزامنة Appwrite (دلتا)', timestamp: DateTime.now()));
    await appwrite.sync();
    await _snapshotIfNeeded(force: forceSnapshot);
    _emit(_state.copyWith(phase: 'completing', message: 'اكتملت الدورة', timestamp: DateTime.now()));
  }

  Future<void> pushDelta() async {
    _emit(_state.copyWith(phase: 'pushing', message: 'مزامنة Appwrite (دلتا)', timestamp: DateTime.now()));
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
    _emit(_state.copyWith(phase: 'snapshotting', message: 'إنشاء Snapshot على Google Drive', timestamp: DateTime.now()));
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
    final rooms = await (database.select(database.rooms)).get();
    final bookings = await (database.select(database.bookings)).get();
    final bookingNotes = await (database.select(database.bookingNotes)).get();
    final employees = await (database.select(database.employees)).get();
    final expenses = await (database.select(database.expenses)).get();
    final cashTransactions = await (database.select(database.cashTransactions)).get();
    final payments = await (database.select(database.payments)).get();
    final debts = await (database.select(database.debts)).get();
    final bookingNights = await (database.select(database.bookingNights)).get();
    final hotelDayLedger = await (database.select(database.hotelDayLedger)).get();
    final shiftNotes = await (database.select(database.shiftNotes)).get();
    final suppliers = await (database.select(database.suppliers)).get();

    final snapshot = {
      'rooms': rooms.map((e) => e.toJson()).toList(),
      'bookings': bookings.map((e) => e.toJson()).toList(),
      'booking_notes': bookingNotes.map((e) => e.toJson()).toList(),
      'employees': employees.map((e) => e.toJson()).toList(),
      'expenses': expenses.map((e) => e.toJson()).toList(),
      'cash_transactions': cashTransactions.map((e) => e.toJson()).toList(),
      'payments': payments.map((e) => e.toJson()).toList(),
      'debts': debts.map((e) => e.toJson()).toList(),
      'booking_nights': bookingNights.map((e) => e.toJson()).toList(),
      'hotel_day_ledger': hotelDayLedger.map((e) => e.toJson()).toList(),
      'shift_notes': shiftNotes.map((e) => e.toJson()).toList(),
      'suppliers': suppliers.map((e) => e.toJson()).toList(),
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
