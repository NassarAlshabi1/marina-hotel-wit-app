import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_sqflite/drift_sqflite.dart';

part 'local_db.g.dart';

mixin SyncFields on Table {
  TextColumn get localUuid => text().unique()();
  IntColumn get serverId => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get lastModified => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get origin => text().withDefault(const Constant('local'))();
}

class Rooms extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get roomNumber => text().unique()();
  TextColumn get type => text()();
  RealColumn get price => real()();
  TextColumn get status => text()();
  TextColumn get imageUrl => text().nullable()();
}

class Bookings extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get serverBookingId => integer().nullable()();
  TextColumn get roomNumber => text().references(Rooms, #roomNumber)();
  TextColumn get guestName => text()();
  TextColumn get guestPhone => text()();
  TextColumn get guestIdType => text().withDefault(const Constant('بطاقة شخصية'))();
  TextColumn get guestIdNumber => text().withDefault(const Constant(''))();
  TextColumn get guestIdIssueDate => text().nullable()();
  TextColumn get guestIdIssuePlace => text().nullable()();
  TextColumn get guestNationality => text()();
  TextColumn get guestEmail => text().nullable()();
  TextColumn get guestAddress => text().nullable()();
  TextColumn get checkinDate => text()();
  TextColumn get checkoutDate => text().nullable()();
  TextColumn get actualCheckout => text().nullable()();
  TextColumn get status => text()();
  TextColumn get notes => text().nullable()();
  IntColumn get expectedNights => integer().withDefault(const Constant(1))();
  IntColumn get calculatedNights => integer().withDefault(const Constant(1))();

  @override
  List<Index> get indexes => [];
}

class BookingNotes extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookingId => integer().references(Bookings, #id)();
  TextColumn get noteText => text()();
  TextColumn get alertType => text()();
  TextColumn get alertUntil => text().nullable()();
  IntColumn get isActive => integer().withDefault(const Constant(1))();
}

class Employees extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  RealColumn get basicSalary => real()();
  TextColumn get position => text().withDefault(const Constant('موظف'))();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get hireDate => text().withDefault(const Constant(''))();
  TextColumn get status => text()();
}

class Expenses extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get expenseType => text()();
  IntColumn get relatedId => integer().nullable()();
  TextColumn get description => text()();
  RealColumn get amount => real()();
  TextColumn get date => text()();
  IntColumn get cashTransactionId => integer().nullable()();
}

class CashTransactions extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get registerId => integer().nullable()();
  TextColumn get transactionType => text()();
  RealColumn get amount => real()();
  TextColumn get referenceType => text().nullable()();
  IntColumn get referenceId => integer().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get transactionTime => text()();
  IntColumn get createdBy => integer().nullable()();
}

class Payments extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get serverPaymentId => integer().nullable()();
  IntColumn get bookingLocalId => integer().nullable().references(Bookings, #id)();
  IntColumn get serverBookingId => integer().nullable()();
  TextColumn get roomNumber => text().nullable()();
  RealColumn get amount => real()();
  TextColumn get paymentDate => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get paymentMethod => text()();
  TextColumn get revenueType => text()();
  IntColumn get cashTransactionLocalId => integer().nullable().references(CashTransactions, #id)();
  IntColumn get cashTransactionServerId => integer().nullable()();
  TextColumn get referenceNumber => text().nullable()();

  @override
  List<Index> get indexes => [];
}

class Debts extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookingLocalId => integer().nullable().references(Bookings, #id)();
  TextColumn get guestName => text()();
  TextColumn get checkinDate => text()();
  TextColumn get checkoutDate => text()();
  TextColumn get dateRecorded => text().withDefault(const Constant(''))();
  TextColumn get debtReason => text().withDefault(const Constant(''))();
  RealColumn get totalAmount => real()();
  RealColumn get paidAmount => real()();
  RealColumn get remainingAmount => real()();
  TextColumn get paymentDate => text()();
  IntColumn get isSettled => integer().withDefault(const Constant(0))();
  TextColumn get pledge => text().nullable()();
  TextColumn get pledgeType => text().nullable()();
  TextColumn get note => text().nullable()();
}

// جدول الملاحظات البسيط
class ShiftNotes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get content => text()();
  TextColumn get priority => text().withDefault(const Constant('medium'))(); // high, medium, low
  TextColumn get shiftType => text().withDefault(const Constant('all'))(); // morning, evening, night, all
  IntColumn get isRead => integer().withDefault(const Constant(0))(); // 0 = غير مقروء، 1 = مقروء
  TextColumn get createdAt => text()();
  TextColumn get expiresAt => text().nullable()();
  TextColumn get createdBy => text().withDefault(const Constant('user'))();
}

class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get op => text()();
  TextColumn get localUuid => text()();
  IntColumn get serverId => integer().nullable()();
  TextColumn get payload => text()();
  IntColumn get clientTs => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

class SyncState extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get lastServerTs => integer().withDefault(const Constant(0))();
  IntColumn get lastPullTs => integer().withDefault(const Constant(0))();
  IntColumn get lastPushTs => integer().withDefault(const Constant(0))();
  IntColumn get isSyncing => integer().withDefault(const Constant(0))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  @override
  Set<Column> get primaryKey => {id};
}

class RestoreFixLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get fixId => text().unique()();
  IntColumn get executedAt => integer()();
  TextColumn get targetTable => text()();
  IntColumn get targetRecordId => integer()();
  TextColumn get fieldName => text()();
  TextColumn get oldValue => text().nullable()();
  TextColumn get newValue => text().nullable()();
  TextColumn get reason => text()();
  TextColumn get fixType => text()();
}

class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get tableName => text()();
  TextColumn get operation => text()();
  TextColumn get payload => text()();
  TextColumn get updatedAt => text()();
  TextColumn get deviceId => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get createdAt => text()();
}

class SyncLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get syncId => text()();
  TextColumn get direction => text()();
  TextColumn get deviceId => text()();
  TextColumn get metadata => text()();
  TextColumn get operations => text()();
  IntColumn get checksumMatched => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('success'))();
  TextColumn get createdAt => text()();
  TextColumn get completedAt => text().nullable()();
}

class SyncConflicts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get logId => integer().references(SyncLog, #id)();
  TextColumn get tableName => text()();
  TextColumn get uuid => text()();
  TextColumn get resolution => text()();
  TextColumn get localPayload => text()();
  TextColumn get remotePayload => text()();
  TextColumn get createdAt => text()();
}

@DriftDatabase(tables: [
  Rooms,
  Bookings,
  BookingNotes,
  ShiftNotes,
  Employees,
  Expenses,
  CashTransactions,
  Payments,
  Debts,
  Outbox,
  SyncState,
  RestoreFixLog,
  SyncQueue,
  SyncLog,
  SyncConflicts,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  AppDatabase._internal(QueryExecutor executor) : super(executor);

  static AppDatabase forTesting(QueryExecutor executor) => AppDatabase._internal(executor);

  @override
  int get schemaVersion => 12;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(bookings, bookings.guestIdType);
            await m.addColumn(bookings, bookings.guestIdNumber);
            await m.addColumn(bookings, bookings.guestIdIssueDate);
            await m.addColumn(bookings, bookings.guestIdIssuePlace);
            await m.addColumn(bookings, bookings.actualCheckout);
            await m.addColumn(bookings, bookings.expectedNights);
            await m.database.customStatement('UPDATE bookings SET expected_nights = calculated_nights');
          }
          if (from < 3) {
            await m.database.customStatement('ALTER TABLE rooms RENAME TO rooms_old');
            await m.createTable(rooms);
            await m.database.customStatement('INSERT INTO rooms (room_number, type, price, status, image_url, local_uuid, server_id, created_at, updated_at, deleted_at, last_modified, version, origin) '
                'SELECT room_number, type, price, status, image_url, local_uuid, server_id, created_at, updated_at, deleted_at, last_modified, version, origin FROM rooms_old');
            await m.database.customStatement('DROP TABLE rooms_old');
          }
          if (from < 4) {
            await m.createTable(debts);
          }
          if (from < 5 && from >= 4) {
            await m.addColumn(debts, debts.dateRecorded);
            await m.addColumn(debts, debts.debtReason);
            await m.addColumn(debts, debts.isSettled);
          }
          if (from < 6) {
            await m.createTable(shiftNotes);
          }
          if (from < 7) {
            await m.addColumn(payments, payments.referenceNumber);
          }
          if (from < 10) {
            await m.createTable(restoreFixLog);
          }
          if (from < 11) {
            await m.createTable(syncQueue);
          }
          if (from < 12) {
            await m.createTable(syncLog);
            await m.createTable(syncConflicts);
          }
        },
      );

  /// تجميع جميع الجداول المطلوب مزامنتها في خريطة JSON
  Future<Map<String, dynamic>> getAllTablesAsJson() async {
    final roomsData = await select(rooms).get();
    final bookingsData = await select(bookings).get();
    final bookingNotesData = await select(bookingNotes).get();
    final employeesData = await select(employees).get();
    final expensesData = await select(expenses).get();
    final cashTransactionsData = await select(cashTransactions).get();
    final paymentsData = await select(payments).get();
    final debtsData = await select(debts).get();

    return {
      'rooms': roomsData.map((e) => e.toJson()).toList(),
      'bookings': bookingsData.map((e) => e.toJson()).toList(),
      'booking_notes': bookingNotesData.map((e) => e.toJson()).toList(),
      'employees': employeesData.map((e) => e.toJson()).toList(),
      'expenses': expensesData.map((e) => e.toJson()).toList(),
      'cash_transactions': cashTransactionsData.map((e) => e.toJson()).toList(),
      'payments': paymentsData.map((e) => e.toJson()).toList(),
      'debts': debtsData.map((e) => e.toJson()).toList(),
      'guests': <Map<String, dynamic>>[],
      'services': <Map<String, dynamic>>[],
      'settings': <Map<String, dynamic>>[],
    };
  }

  /// تطبيق البيانات المدمجة على قاعدة البيانات المحلية داخل معاملة واحدة
  Future<void> applyMergedData(Map<String, dynamic> merged) async {
    await transaction(() async {
      Future<void> replaceTable<T extends Insertable<dynamic>>(TableInfo<Table, dynamic> table, List<T> rows) async {
        await delete(table).go();
        if (rows.isEmpty) {
          return;
        }
        await batch((batch) {
          batch.insertAll(table, rows, mode: InsertMode.insertOrReplace);
        });
      }

      List<Map<String, dynamic>> _asList(String key) {
        return (merged[key] as List<dynamic>? ?? [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
      }

      await replaceTable<Room>(rooms, _asList('rooms').map((row) => Room.fromJson(row)).toList());
      await replaceTable<Booking>(bookings, _asList('bookings').map((row) => Booking.fromJson(row)).toList());
      await replaceTable<BookingNote>(bookingNotes, _asList('booking_notes').map((row) => BookingNote.fromJson(row)).toList());
      await replaceTable<Employee>(employees, _asList('employees').map((row) => Employee.fromJson(row)).toList());
      await replaceTable<Expense>(expenses, _asList('expenses').map((row) => Expense.fromJson(row)).toList());
      await replaceTable<CashTransaction>(cashTransactions, _asList('cash_transactions').map((row) => CashTransaction.fromJson(row)).toList());
      await replaceTable<Payment>(payments, _asList('payments').map((row) => Payment.fromJson(row)).toList());
      await replaceTable<Debt>(debts, _asList('debts').map((row) => Debt.fromJson(row)).toList());
    });
  }
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final executor = SqfliteQueryExecutor.inDatabaseFolder(path: 'marina_hotel.db', logStatements: false);
    return executor;
  });
}

extension EmployeeX on Employee {
  double get salary => basicSalary;
}

/// Singleton manager for the Drift database to support clean close/reopen during file-based restores
class DatabaseManager {
  static AppDatabase? _instance;

  static AppDatabase get instance => _instance ??= AppDatabase();

  static Future<void> close() async {
    try {
      await _instance?.close();
    } catch (_) {}
    _instance = null;
  }

  static Future<void> reopen() async {
    await close();
    _instance = AppDatabase();
  }
}

/// DAO خاص بسجلات المزامنة والتضارب لتسهيل التدقيق والاسترجاع
class SyncAuditDao {
  SyncAuditDao(this._db);

  final AppDatabase _db;

  Future<int> insertSyncLog({
    required String syncId,
    required String direction,
    required String deviceId,
    required Map<String, dynamic> metadata,
    required List<SyncOperation> appliedOperations,
    required List<SyncConflict> conflicts,
    required bool checksumMatched,
  }) async {
    final createdAt = DateTime.now().toUtc().toIso8601String();
    return _db.transaction(() async {
      final logId = await _db.into(_db.syncLog).insert(
            SyncLogCompanion.insert(
              syncId: syncId,
              direction: direction,
              deviceId: deviceId,
              metadata: jsonEncode(metadata),
              operations: jsonEncode(appliedOperations.map((e) => {
                    'table': e.table,
                    'uuid': e.uuid,
                    'operation': e.operation,
                    'payload': e.payload,
                    'timestamp': e.timestamp,
                  }).toList()),
              checksumMatched: Value(checksumMatched ? 1 : 0),
              createdAt: createdAt,
              completedAt: Value(createdAt),
            ),
          );

      if (conflicts.isNotEmpty) {
        await _db.batch((batch) {
          for (final conflict in conflicts) {
            batch.insert(
              _db.syncConflicts,
              SyncConflictsCompanion.insert(
                logId: logId,
                tableName: conflict.table,
                uuid: conflict.uuid,
                resolution: conflict.resolution,
                localPayload: jsonEncode(conflict.localPayload),
                remotePayload: jsonEncode(conflict.remotePayload),
                createdAt: createdAt,
              ),
            );
          }
        });
      }

      return logId;
    });
  }

  Future<List<SyncLogData>> fetchRecentLogs(int limit) {
    return (_db.select(_db.syncLog)
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<List<SyncConflictsData>> fetchConflictsForLog(int logId) {
    return (_db.select(_db.syncConflicts)..where((tbl) => tbl.logId.equals(logId))).get();
  }
}
