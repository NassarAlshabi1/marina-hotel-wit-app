import 'dart:async';

import 'package:flutter/foundation.dart';

import '../local_db.dart';
import 'enhanced_event_bus.dart';
import 'events/sync_event.dart';

typedef EntityToJson<T> = Map<String, dynamic> Function(T entity);
typedef EntityId<T> = String Function(T entity);

class DatabaseSyncHooks {
  final AppDatabase _database;
  final EnhancedEventBus _eventBus;
  final List<StreamSubscription> _subscriptions = [];
  bool _initialized = false;

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
  };

  static const Map<String, SyncPriority> _tablePriorities = {
    'payments': SyncPriority.high,
    'cash_transactions': SyncPriority.high,
    'debts': SyncPriority.high,
    'bookings': SyncPriority.normal,
    'booking_nights': SyncPriority.normal,
    'rooms': SyncPriority.normal,
    'employees': SyncPriority.normal,
    'expenses': SyncPriority.normal,
    'booking_notes': SyncPriority.low,
    'shift_notes': SyncPriority.low,
    'hotel_day_ledger': SyncPriority.low,
    'salary_cycles': SyncPriority.normal,
    'salary_payments': SyncPriority.high,
  };

  DatabaseSyncHooks({
    required AppDatabase database,
    required EnhancedEventBus eventBus,
  })  : _database = database,
        _eventBus = eventBus;

  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;

    await _setupRoomsHook();
    await _setupBookingsHook();
    await _setupBookingNotesHook();
    await _setupBookingNightsHook();
    await _setupEmployeesHook();
    await _setupExpensesHook();
    await _setupCashTransactionsHook();
    await _setupPaymentsHook();
    await _setupDebtsHook();
    await _setupHotelDayLedgerHook();
    await _setupShiftNotesHook();
    await _setupSalaryCyclesHook();
    await _setupSalaryPaymentsHook();

    _initialized = true;
    debugPrint(
      'DatabaseSyncHooks: Initialized for ${_syncTables.length} tables',
    );
  }

  Future<void> _setupRoomsHook() async {
    _setupTableHook<Room>(
      tableName: 'rooms',
      watchQuery: () => _database.select(_database.rooms).watch(),
      getId: (e) => e.localUuid,
      toJson: (e) => e.toJson(),
    );
  }

  Future<void> _setupBookingsHook() async {
    _setupTableHook<Booking>(
      tableName: 'bookings',
      watchQuery: () => _database.select(_database.bookings).watch(),
      getId: (e) => e.localUuid,
      toJson: (e) => e.toJson(),
    );
  }

  Future<void> _setupBookingNotesHook() async {
    _setupTableHook<BookingNote>(
      tableName: 'booking_notes',
      watchQuery: () => _database.select(_database.bookingNotes).watch(),
      getId: (e) => e.localUuid,
      toJson: (e) => e.toJson(),
    );
  }

  Future<void> _setupBookingNightsHook() async {
    _setupTableHook<BookingNight>(
      tableName: 'booking_nights',
      watchQuery: () => _database.select(_database.bookingNights).watch(),
      getId: (e) => e.localUuid,
      toJson: (e) => e.toJson(),
    );
  }

  Future<void> _setupEmployeesHook() async {
    _setupTableHook<Employee>(
      tableName: 'employees',
      watchQuery: () => _database.select(_database.employees).watch(),
      getId: (e) => e.localUuid,
      toJson: (e) => e.toJson(),
    );
  }

  Future<void> _setupExpensesHook() async {
    _setupTableHook<Expense>(
      tableName: 'expenses',
      watchQuery: () => _database.select(_database.expenses).watch(),
      getId: (e) => e.localUuid,
      toJson: (e) => e.toJson(),
    );
  }

  Future<void> _setupCashTransactionsHook() async {
    _setupTableHook<CashTransaction>(
      tableName: 'cash_transactions',
      watchQuery: () => _database.select(_database.cashTransactions).watch(),
      getId: (e) => e.localUuid,
      toJson: (e) => e.toJson(),
    );
  }

  Future<void> _setupPaymentsHook() async {
    _setupTableHook<Payment>(
      tableName: 'payments',
      watchQuery: () => _database.select(_database.payments).watch(),
      getId: (e) => e.localUuid,
      toJson: (e) => e.toJson(),
    );
  }

  Future<void> _setupDebtsHook() async {
    _setupTableHook<Debt>(
      tableName: 'debts',
      watchQuery: () => _database.select(_database.debts).watch(),
      getId: (e) => e.localUuid,
      toJson: (e) => e.toJson(),
    );
  }

  Future<void> _setupHotelDayLedgerHook() async {
    _setupTableHook<HotelDayLedgerEntry>(
      tableName: 'hotel_day_ledger',
      watchQuery: () => _database.select(_database.hotelDayLedger).watch(),
      getId: (e) => e.localUuid,
      toJson: (e) => e.toJson(),
    );
  }

  Future<void> _setupShiftNotesHook() async {
    _setupTableHook<ShiftNote>(
      tableName: 'shift_notes',
      watchQuery: () => _database.select(_database.shiftNotes).watch(),
      getId: (e) => e.id.toString(),
      toJson: (e) => e.toJson(),
    );
  }

  Future<void> _setupSalaryCyclesHook() async {
    _setupTableHook<SalaryCycle>(
      tableName: 'salary_cycles',
      watchQuery: () => _database.select(_database.salaryCycles).watch(),
      getId: (e) => e.localUuid,
      toJson: (e) => e.toJson(),
    );
  }

  Future<void> _setupSalaryPaymentsHook() async {
    _setupTableHook<SalaryPayment>(
      tableName: 'salary_payments',
      watchQuery: () => _database.select(_database.salaryPayments).watch(),
      getId: (e) => e.localUuid,
      toJson: (e) => e.toJson(),
    );
  }

  void _setupTableHook<T>({
    required String tableName,
    required Stream<List<T>> Function() watchQuery,
    required EntityId<T> getId,
    required EntityToJson<T> toJson,
  }) {
    final cache = <String, Map<String, dynamic>>{};
    var isFirstEmit = true;

    final subscription = watchQuery().listen((entities) {
      if (isFirstEmit) {
        for (final entity in entities) {
          cache[getId(entity)] = toJson(entity);
        }
        isFirstEmit = false;
        return;
      }

      _detectChanges(
        tableName: tableName,
        newEntities: entities,
        cache: cache,
        getId: getId,
        toJson: toJson,
      );
    });

    _subscriptions.add(subscription);
  }

  Future<void> _detectChanges<T>({
    required String tableName,
    required List<T> newEntities,
    required Map<String, Map<String, dynamic>> cache,
    required EntityId<T> getId,
    required EntityToJson<T> toJson,
  }) async {
    final newIds = <String>{};
    final priority = _tablePriorities[tableName] ?? SyncPriority.normal;

    for (final entity in newEntities) {
      final id = getId(entity);
      final json = toJson(entity);
      newIds.add(id);

      if (!cache.containsKey(id)) {
        await _eventBus.publishCreate(
          table: tableName,
          entityId: id,
          payload: json,
          priority: priority,
        );
        cache[id] = json;
      } else {
        final oldJson = cache[id]!;
        if (!_mapsEqual(oldJson, json)) {
          await _eventBus.publishUpdate(
            table: tableName,
            entityId: id,
            payload: json,
            previousPayload: oldJson,
            priority: priority,
          );
          cache[id] = json;
        }
      }
    }

    final deletedIds = cache.keys.where((id) => !newIds.contains(id)).toList();
    for (final id in deletedIds) {
      await _eventBus.publishDelete(
        table: tableName,
        entityId: id,
        previousPayload: cache[id],
        priority: priority,
      );
      cache.remove(id);
    }
  }

  bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _initialized = false;
    debugPrint('DatabaseSyncHooks: Disposed');
  }
}

class ManualSyncTrigger {
  final EnhancedEventBus _eventBus;

  ManualSyncTrigger(this._eventBus);

  Future<void> triggerCreate({
    required String table,
    required String entityId,
    required Map<String, dynamic> payload,
    SyncPriority? priority,
  }) async {
    await _eventBus.publishCreate(
      table: table,
      entityId: entityId,
      payload: payload,
      priority: priority ?? _getPriorityForTable(table),
    );
  }

  Future<void> triggerUpdate({
    required String table,
    required String entityId,
    required Map<String, dynamic> payload,
    Map<String, dynamic>? previousPayload,
    SyncPriority? priority,
  }) async {
    await _eventBus.publishUpdate(
      table: table,
      entityId: entityId,
      payload: payload,
      previousPayload: previousPayload,
      priority: priority ?? _getPriorityForTable(table),
    );
  }

  Future<void> triggerDelete({
    required String table,
    required String entityId,
    Map<String, dynamic>? previousPayload,
    SyncPriority? priority,
  }) async {
    await _eventBus.publishDelete(
      table: table,
      entityId: entityId,
      previousPayload: previousPayload,
      priority: priority ?? _getPriorityForTable(table),
    );
  }

  Future<void> triggerBatch(List<EnhancedSyncEvent> events) async {
    await _eventBus.publishBatch(events);
  }

  SyncPriority _getPriorityForTable(String table) {
    return DatabaseSyncHooks._tablePriorities[table] ?? SyncPriority.normal;
  }
}
