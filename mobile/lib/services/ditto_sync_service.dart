import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as d;
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';
import '../utils/time.dart';
import '../utils/ditto_config.dart';
import 'local_db.dart';
import 'daos/outbox_dao.dart';
import 'daos/rooms_dao.dart';
import 'daos/bookings_dao.dart';
import 'daos/booking_notes_dao.dart';
import 'daos/employees_dao.dart';
import 'daos/expenses_dao.dart';
import 'daos/cash_transactions_dao.dart';
import 'daos/payments_dao.dart';
import 'daos/debts_dao.dart';
import 'providers.dart';
import 'sync_performance_optimizer.dart';

enum SyncStatus { idle, syncing, error, connected, disconnected }

class DittoSyncService {
  DittoSyncService(this.db)
      : outboxDao = OutboxDao(db),
        roomsDao = RoomsDao(db, OutboxDao(db)),
        bookingsDao = BookingsDao(db, OutboxDao(db)),
        notesDao = BookingNotesDao(db, OutboxDao(db)),
        employeesDao = EmployeesDao(db, OutboxDao(db)),
        expensesDao = ExpensesDao(db, OutboxDao(db)),
        cashDao = CashTransactionsDao(db, OutboxDao(db)),
        paymentsDao = PaymentsDao(db, OutboxDao(db)),
        debtsDao = DebtsDao(db, OutboxDao(db)),
        _performanceOptimizer = SyncPerformanceOptimizer();

  final AppDatabase db;
  final OutboxDao outboxDao;
  final RoomsDao roomsDao;
  final BookingsDao bookingsDao;
  final BookingNotesDao notesDao;
  final EmployeesDao employeesDao;
  final ExpensesDao expensesDao;
  final CashTransactionsDao cashDao;
  final PaymentsDao paymentsDao;
  final DebtsDao debtsDao;
  final SyncPerformanceOptimizer _performanceOptimizer;

  final _status = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _status.stream;

  final Map<String, DittoLiveQuery> _liveQueries = {};
  final Map<String, StreamSubscription> _subscriptions = {};
  bool _isInitialized = false;
  bool _isSyncing = false;

  Ditto get _ditto => DittoConfig.instance;

  static const List<String> _collections = [
    'rooms',
    'bookings',
    'booking_notes',
    'employees',
    'expenses',
    'cash_transactions',
    'payments',
    'debts',
  ];

  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('⚠️ Ditto Sync already initialized');
      return;
    }

    try {
      debugPrint('🔄 Initializing Ditto Sync Service...');

      await _performanceOptimizer.initialize();

      await _startLiveQueries();

      await _processOutbox();

      _isInitialized = true;
      _status.add(SyncStatus.connected);
      debugPrint('✅ Ditto Sync Service initialized successfully');
    } catch (e) {
      debugPrint('❌ Failed to initialize Ditto Sync: $e');
      _status.add(SyncStatus.error);
      rethrow;
    }
  }

  Future<void> _startLiveQueries() async {
    for (final collectionName in _collections) {
      await _subscribeToCollection(collectionName);
    }
  }

  Future<void> _subscribeToCollection(String collectionName) async {
    try {
      final collection = _ditto.store.collection(collectionName);
      
      final liveQuery = collection.findAll().observe(
        onDocsChanged: (docs) {
          _handleRemoteChanges(collectionName, docs);
        },
      );

      _liveQueries[collectionName] = liveQuery;
      debugPrint('✓ Subscribed to collection: $collectionName');
    } catch (e) {
      debugPrint('❌ Failed to subscribe to $collectionName: $e');
    }
  }

  Future<void> _handleRemoteChanges(
    String collectionName,
    List<DittoDocument> docs,
  ) async {
    if (_isSyncing) return;

    _isSyncing = true;
    try {
      debugPrint('📥 Received ${docs.length} docs from $collectionName');

      for (final doc in docs) {
        await _applyRemoteDocument(collectionName, doc);
      }
    } catch (e) {
      debugPrint('❌ Error handling remote changes for $collectionName: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _applyRemoteDocument(
    String collectionName,
    DittoDocument doc,
  ) async {
    try {
      final data = doc.value;
      final localUuid = data['local_uuid'] as String?;
      final serverId = data['server_id'] as int?;
      final deletedAt = data['deleted_at'] as String?;
      final lastModified = _parseTimestamp(data['last_modified']);
      
      if (localUuid == null) return;

      switch (collectionName) {
        case 'rooms':
          await _applyRoomChange(data, localUuid, deletedAt, lastModified);
          break;
        case 'bookings':
          await _applyBookingChange(data, localUuid, deletedAt, lastModified);
          break;
        case 'booking_notes':
          await _applyBookingNoteChange(data, localUuid, deletedAt, lastModified);
          break;
        case 'employees':
          await _applyEmployeeChange(data, localUuid, deletedAt, lastModified);
          break;
        case 'expenses':
          await _applyExpenseChange(data, localUuid, deletedAt, lastModified);
          break;
        case 'cash_transactions':
          await _applyCashTransactionChange(data, localUuid, deletedAt, lastModified);
          break;
        case 'payments':
          await _applyPaymentChange(data, localUuid, deletedAt, lastModified);
          break;
        case 'debts':
          await _applyDebtChange(data, localUuid, deletedAt, lastModified);
          break;
      }
    } catch (e) {
      debugPrint('❌ Error applying document from $collectionName: $e');
    }
  }

  Future<void> _applyRoomChange(
    Map<String, dynamic> data,
    String localUuid,
    String? deletedAt,
    int lastModified,
  ) async {
    final existing = await (db.select(db.rooms)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();

    if (deletedAt != null) {
      if (existing != null) {
        await roomsDao.softDelete(existing.roomNumber, originIsServer: true);
      }
      return;
    }

    if (existing != null && existing.lastModified >= lastModified) {
      return;
    }

    final roomNumber = data['room_number'] as String;
    
    if (existing == null) {
      await roomsDao.insertOne(
        RoomsCompanion(
          roomNumber: d.Value(roomNumber),
          type: d.Value(data['type'] as String? ?? ''),
          price: d.Value((data['price'] as num?)?.toDouble() ?? 0.0),
          status: d.Value(data['status'] as String? ?? 'شاغرة'),
          imageUrl: d.Value(data['image_url'] as String?),
          localUuid: d.Value(localUuid),
          serverId: d.Value(data['server_id'] as int?),
          origin: const d.Value('server'),
        ),
        originIsServer: true,
      );
    } else {
      await roomsDao.updateByNumber(
        roomNumber,
        RoomsCompanion(
          type: d.Value(data['type'] as String),
          price: d.Value((data['price'] as num).toDouble()),
          status: d.Value(data['status'] as String),
          imageUrl: d.Value(data['image_url'] as String?),
          serverId: d.Value(data['server_id'] as int?),
          origin: const d.Value('server'),
        ),
        originIsServer: true,
      );
    }
  }

  Future<void> _applyBookingChange(
    Map<String, dynamic> data,
    String localUuid,
    String? deletedAt,
    int lastModified,
  ) async {
    final existing = await (db.select(db.bookings)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();

    if (deletedAt != null) {
      if (existing != null) {
        await bookingsDao.softDeleteById(existing.id, originIsServer: true);
      }
      return;
    }

    if (existing != null && existing.lastModified >= lastModified) {
      return;
    }

    if (existing == null) {
      await bookingsDao.insertOne(
        BookingsCompanion(
          roomNumber: d.Value(data['room_number'] as String),
          guestName: d.Value(data['guest_name'] as String? ?? ''),
          guestPhone: d.Value(data['guest_phone'] as String? ?? ''),
          guestIdType: d.Value(data['guest_id_type'] as String?),
          guestIdNumber: d.Value(data['guest_id_number'] as String?),
          guestIdIssueDate: d.Value(data['guest_id_issue_date'] as String?),
          guestIdIssuePlace: d.Value(data['guest_id_issue_place'] as String?),
          guestNationality: d.Value(data['guest_nationality'] as String?),
          guestEmail: d.Value(data['guest_email'] as String?),
          guestAddress: d.Value(data['guest_address'] as String?),
          checkinDate: d.Value(data['checkin_date'] as String),
          checkoutDate: d.Value(data['checkout_date'] as String?),
          actualCheckout: d.Value(data['actual_checkout'] as String?),
          status: d.Value(data['status'] as String? ?? 'نشط'),
          notes: d.Value(data['notes'] as String?),
          expectedNights: d.Value(data['expected_nights'] as int? ?? 0),
          calculatedNights: d.Value(data['calculated_nights'] as int? ?? 0),
          localUuid: d.Value(localUuid),
          serverId: d.Value(data['server_id'] as int?),
          origin: const d.Value('server'),
        ),
        originIsServer: true,
      );
    } else {
      await bookingsDao.updateOne(
        existing.id,
        BookingsCompanion(
          roomNumber: d.Value(data['room_number'] as String),
          guestName: d.Value(data['guest_name'] as String),
          guestPhone: d.Value(data['guest_phone'] as String),
          status: d.Value(data['status'] as String),
          notes: d.Value(data['notes'] as String?),
          serverId: d.Value(data['server_id'] as int?),
          origin: const d.Value('server'),
        ),
        originIsServer: true,
      );
    }
  }

  Future<void> _applyBookingNoteChange(
    Map<String, dynamic> data,
    String localUuid,
    String? deletedAt,
    int lastModified,
  ) async {
    final existing = await (db.select(db.bookingNotes)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();

    if (deletedAt != null) {
      if (existing != null) {
        await notesDao.softDeleteById(existing.id, originIsServer: true);
      }
      return;
    }

    if (existing != null && existing.lastModified >= lastModified) {
      return;
    }

    if (existing == null) {
      await notesDao.insertOne(
        BookingNotesCompanion(
          bookingId: d.Value(data['booking_id'] as int),
          note: d.Value(data['note'] as String? ?? ''),
          createdBy: d.Value(data['created_by'] as String? ?? ''),
          localUuid: d.Value(localUuid),
          serverId: d.Value(data['server_id'] as int?),
          origin: const d.Value('server'),
        ),
        originIsServer: true,
      );
    }
  }

  Future<void> _applyEmployeeChange(
    Map<String, dynamic> data,
    String localUuid,
    String? deletedAt,
    int lastModified,
  ) async {
    final existing = await (db.select(db.employees)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();

    if (deletedAt != null) {
      if (existing != null) {
        await employeesDao.softDeleteById(existing.id, originIsServer: true);
      }
      return;
    }

    if (existing != null && existing.lastModified >= lastModified) {
      return;
    }

    if (existing == null) {
      await employeesDao.insertOne(
        EmployeesCompanion(
          name: d.Value(data['name'] as String? ?? ''),
          phone: d.Value(data['phone'] as String? ?? ''),
          salary: d.Value((data['salary'] as num?)?.toDouble() ?? 0.0),
          position: d.Value(data['position'] as String? ?? ''),
          hireDate: d.Value(data['hire_date'] as String?),
          localUuid: d.Value(localUuid),
          serverId: d.Value(data['server_id'] as int?),
          origin: const d.Value('server'),
        ),
        originIsServer: true,
      );
    } else {
      await employeesDao.updateOne(
        existing.id,
        EmployeesCompanion(
          name: d.Value(data['name'] as String),
          phone: d.Value(data['phone'] as String),
          salary: d.Value((data['salary'] as num).toDouble()),
          position: d.Value(data['position'] as String),
          serverId: d.Value(data['server_id'] as int?),
          origin: const d.Value('server'),
        ),
        originIsServer: true,
      );
    }
  }

  Future<void> _applyExpenseChange(
    Map<String, dynamic> data,
    String localUuid,
    String? deletedAt,
    int lastModified,
  ) async {
    final existing = await (db.select(db.expenses)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();

    if (deletedAt != null) {
      if (existing != null) {
        await expensesDao.softDeleteById(existing.id, originIsServer: true);
      }
      return;
    }

    if (existing != null && existing.lastModified >= lastModified) {
      return;
    }

    if (existing == null) {
      await expensesDao.insertOne(
        ExpensesCompanion(
          description: d.Value(data['description'] as String? ?? ''),
          amount: d.Value((data['amount'] as num?)?.toDouble() ?? 0.0),
          category: d.Value(data['category'] as String? ?? ''),
          expenseDate: d.Value(data['expense_date'] as String?),
          localUuid: d.Value(localUuid),
          serverId: d.Value(data['server_id'] as int?),
          origin: const d.Value('server'),
        ),
        originIsServer: true,
      );
    } else {
      await expensesDao.updateOne(
        existing.id,
        ExpensesCompanion(
          description: d.Value(data['description'] as String),
          amount: d.Value((data['amount'] as num).toDouble()),
          category: d.Value(data['category'] as String),
          serverId: d.Value(data['server_id'] as int?),
          origin: const d.Value('server'),
        ),
        originIsServer: true,
      );
    }
  }

  Future<void> _applyCashTransactionChange(
    Map<String, dynamic> data,
    String localUuid,
    String? deletedAt,
    int lastModified,
  ) async {
    final existing = await (db.select(db.cashTransactions)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();

    if (deletedAt != null) {
      if (existing != null) {
        await cashDao.softDeleteById(existing.id, originIsServer: true);
      }
      return;
    }

    if (existing != null && existing.lastModified >= lastModified) {
      return;
    }

    if (existing == null) {
      await cashDao.insertOne(
        CashTransactionsCompanion(
          transactionType: d.Value(data['transaction_type'] as String? ?? ''),
          amount: d.Value((data['amount'] as num?)?.toDouble() ?? 0.0),
          description: d.Value(data['description'] as String? ?? ''),
          transactionDate: d.Value(data['transaction_date'] as String?),
          localUuid: d.Value(localUuid),
          serverId: d.Value(data['server_id'] as int?),
          origin: const d.Value('server'),
        ),
        originIsServer: true,
      );
    }
  }

  Future<void> _applyPaymentChange(
    Map<String, dynamic> data,
    String localUuid,
    String? deletedAt,
    int lastModified,
  ) async {
    final existing = await (db.select(db.payments)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();

    if (deletedAt != null) {
      if (existing != null) {
        await paymentsDao.softDeleteById(existing.id, originIsServer: true);
      }
      return;
    }

    if (existing != null && existing.lastModified >= lastModified) {
      return;
    }

    if (existing == null) {
      await paymentsDao.insertOne(
        PaymentsCompanion(
          bookingId: d.Value(data['booking_id'] as int),
          amount: d.Value((data['amount'] as num?)?.toDouble() ?? 0.0),
          paymentMethod: d.Value(data['payment_method'] as String? ?? ''),
          notes: d.Value(data['notes'] as String?),
          localUuid: d.Value(localUuid),
          serverId: d.Value(data['server_id'] as int?),
          origin: const d.Value('server'),
        ),
        originIsServer: true,
      );
    }
  }

  Future<void> _applyDebtChange(
    Map<String, dynamic> data,
    String localUuid,
    String? deletedAt,
    int lastModified,
  ) async {
    final existing = await (db.select(db.debts)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();

    if (deletedAt != null) {
      if (existing != null) {
        await debtsDao.softDeleteById(existing.id, originIsServer: true);
      }
      return;
    }

    if (existing != null && existing.lastModified >= lastModified) {
      return;
    }

    if (existing == null) {
      await debtsDao.insertOne(
        DebtsCompanion(
          guestName: d.Value(data['guest_name'] as String? ?? ''),
          guestPhone: d.Value(data['guest_phone'] as String? ?? ''),
          totalAmount: d.Value((data['total_amount'] as num?)?.toDouble() ?? 0.0),
          paidAmount: d.Value((data['paid_amount'] as num?)?.toDouble() ?? 0.0),
          status: d.Value(data['status'] as String? ?? 'معلق'),
          localUuid: d.Value(localUuid),
          serverId: d.Value(data['server_id'] as int?),
          origin: const d.Value('server'),
        ),
        originIsServer: true,
      );
    } else {
      await debtsDao.updateOne(
        existing.id,
        DebtsCompanion(
          guestName: d.Value(data['guest_name'] as String),
          totalAmount: d.Value((data['total_amount'] as num).toDouble()),
          paidAmount: d.Value((data['paid_amount'] as num).toDouble()),
          status: d.Value(data['status'] as String),
          serverId: d.Value(data['server_id'] as int?),
          origin: const d.Value('server'),
        ),
        originIsServer: true,
      );
    }
  }

  Future<void> _processOutbox() async {
    try {
      final pendingChanges = await outboxDao.takeBatch(100);
      
      if (pendingChanges.isEmpty) return;

      debugPrint('📤 Processing ${pendingChanges.length} pending changes...');

      for (final change in pendingChanges) {
        await _pushToCollection(change);
      }
    } catch (e) {
      debugPrint('❌ Error processing outbox: $e');
    }
  }

  Future<void> _pushToCollection(OutboxData change) async {
    try {
      final collection = _ditto.store.collection(change.entity);
      final payload = jsonDecode(change.payload) as Map<String, dynamic>;

      if (change.op == 'delete') {
        await collection.findByID(change.localUuid).remove();
        await outboxDao.removeById(change.id);
        debugPrint('✓ Deleted ${change.entity}/${change.localUuid}');
        return;
      }

      final docId = DittoDocumentID.fromString(change.localUuid);
      
      await collection.upsert(payload, id: docId);

      await outboxDao.removeById(change.id);
      debugPrint('✓ Synced ${change.entity}/${change.localUuid}');
    } catch (e) {
      debugPrint('❌ Failed to push ${change.entity}: $e');
      final attempts = change.attempts + 1;
      await outboxDao.setError(change.id, e.toString(), attempts);
    }
  }

  Future<void> runSync() async {
    if (_isSyncing) {
      debugPrint('⏭️ Sync already in progress');
      return;
    }

    try {
      if (await _performanceOptimizer.shouldSkipSync()) {
        debugPrint('⏭️ Sync skipped by performance optimizer');
        return;
      }

      _isSyncing = true;
      _status.add(SyncStatus.syncing);

      await _processOutbox();

      _performanceOptimizer.recordSyncAttempt(success: true);
      _status.add(SyncStatus.connected);
      debugPrint('✅ Sync completed successfully');
    } catch (e) {
      _performanceOptimizer.recordSyncAttempt(success: false);
      _status.add(SyncStatus.error);
      debugPrint('❌ Sync failed: $e');
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> initializePerformanceOptimizer() async {
    await _performanceOptimizer.initialize();
    debugPrint('🔧 Performance optimizer initialized');
  }

  Map<String, dynamic> getPerformanceStats() {
    return _performanceOptimizer.getPerformanceStats();
  }

  Future<void> setWifiOnlyMode(bool enabled) async {
    await _performanceOptimizer.setWifiOnlyMode(enabled);
  }

  int _parseTimestamp(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) {
      try {
        final dt = DateTime.parse(value);
        return dt.millisecondsSinceEpoch ~/ 1000;
      } catch (e) {
        return 0;
      }
    }
    return 0;
  }

  Future<void> dispose() async {
    _isInitialized = false;
    
    for (final liveQuery in _liveQueries.values) {
      liveQuery.stop();
    }
    _liveQueries.clear();

    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    _performanceOptimizer.dispose();
    await _status.close();
    
    debugPrint('🔌 Ditto Sync Service disposed');
  }
}

final dittoSyncServiceProvider = Provider<DittoSyncService>((ref) {
  final db = ref.watch(databaseProvider);
  return DittoSyncService(db);
});
