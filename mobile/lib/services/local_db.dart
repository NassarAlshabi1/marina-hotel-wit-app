import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import '../data/sync_models.dart' as sync_models;

part 'local_db.g.dart';

const String _dbFileName = 'marina_hotel.db';

mixin SyncFields on Table {
  TextColumn get localUuid => text().unique()();
  IntColumn get serverId => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get lastModified => integer()();
  TextColumn get createdAtIso => text().nullable()();
  TextColumn get updatedAtIso => text().nullable()();
  TextColumn get deletedAtIso => text().nullable()();
  IntColumn get createdAtEpoch => integer().withDefault(const Constant(0))();
  IntColumn get lastModifiedEpoch => integer().withDefault(const Constant(0))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get origin => text().withDefault(const Constant('local'))();
  TextColumn get vectorClock => text().withDefault(const Constant('{}'))();
}

class Rooms extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get roomNumber => text().unique()();
  TextColumn get type => text()();
  RealColumn get price => real()();
  TextColumn get status => text()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get cleaningStatus =>
      text().withDefault(const Constant('clean'))();
  TextColumn get lastCleanedHotelDay => text().nullable()();
  TextColumn get lastOccupiedHotelDay => text().nullable()();
  BoolColumn get requiresMaintenance =>
      boolean().withDefault(const Constant(false))();

  List<Index> get indexes => [
        Index(
          'idx_rooms_status',
          'CREATE INDEX idx_rooms_status ON rooms (status, cleaning_status)',
        ),
        Index(
          'idx_rooms_maintenance',
          'CREATE INDEX idx_rooms_maintenance ON rooms (requires_maintenance)',
        ),
      ];
}

class Bookings extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get serverBookingId => integer().nullable()();
  TextColumn get roomNumber => text().references(Rooms, #roomNumber)();
  TextColumn get guestName => text()();
  TextColumn get guestPhone => text()();
  TextColumn get guestIdType =>
      text().withDefault(const Constant('بطاقة شخصية'))();
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
  IntColumn get totalNightsCached => integer().withDefault(const Constant(0))();
  TextColumn get stayDurationIso => text().nullable()();
  IntColumn get lastNightEpoch => integer().nullable()();
  BoolColumn get isOverdue => boolean().withDefault(const Constant(false))();
  BoolColumn get needsCheckoutReview =>
      boolean().withDefault(const Constant(false))();
  RealColumn get totalDueCached => real().withDefault(const Constant(0))();
  RealColumn get totalPaidCached => real().withDefault(const Constant(0))();
  RealColumn get remainingBalanceCached =>
      real().withDefault(const Constant(0))();
  BoolColumn get isFullyPaid => boolean().withDefault(const Constant(false))();
  TextColumn get hotelDayCheckin => text().nullable()();
  TextColumn get hotelDayCheckout => text().nullable()();

  List<Index> get indexes => [
        Index(
          'idx_bookings_status_day',
          'CREATE INDEX idx_bookings_status_day ON bookings (status, hotel_day_checkin)',
        ),
        Index(
          'idx_bookings_room',
          'CREATE INDEX idx_bookings_room ON bookings (room_number)',
        ),
        Index(
          'idx_bookings_guest',
          'CREATE INDEX idx_bookings_guest ON bookings (guest_name)',
        ),
      ];
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
  TextColumn get hotelDayKey => text().nullable()();
  TextColumn get categoryUuid => text().nullable()();
  TextColumn get cashFlowUuid => text().nullable()();
  BoolColumn get isAutoGenerated =>
      boolean().withDefault(const Constant(false))();

  List<Index> get indexes => [
        Index(
          'idx_expenses_hotel_day',
          'CREATE INDEX idx_expenses_hotel_day ON expenses (hotel_day_key)',
        ),
        Index(
          'idx_expenses_category',
          'CREATE INDEX idx_expenses_category ON expenses (category_uuid)',
        ),
      ];
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
  IntColumn get bookingLocalId =>
      integer().nullable().references(Bookings, #id)();
  IntColumn get serverBookingId => integer().nullable()();
  TextColumn get roomNumber => text().nullable()();
  RealColumn get amount => real()();
  TextColumn get paymentDate => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get paymentMethod => text()();
  TextColumn get revenueType => text()();
  IntColumn get cashTransactionLocalId =>
      integer().nullable().references(CashTransactions, #id)();
  IntColumn get cashTransactionServerId => integer().nullable()();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get hotelDayKey => text().nullable()();
  BoolColumn get isPendingBalance =>
      boolean().withDefault(const Constant(false))();
  TextColumn get linkedDebtUuid => text().nullable()();
  TextColumn get bookingUuidCache => text().nullable()();

  List<Index> get indexes => [
        Index(
          'idx_payments_booking',
          'CREATE INDEX idx_payments_booking ON payments (booking_local_id, hotel_day_key)',
        ),
        Index(
          'idx_payments_room_day',
          'CREATE INDEX idx_payments_room_day ON payments (room_number, hotel_day_key)',
        ),
      ];
}

class Debts extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookingLocalId =>
      integer().nullable().references(Bookings, #id)();
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
  TextColumn get debtUuid => text().nullable()();
  TextColumn get hotelDayOpened => text().nullable()();
  TextColumn get hotelDayClosed => text().nullable()();
  BoolColumn get isFromAutoFix =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get settlementConfirmed =>
      boolean().withDefault(const Constant(false))();

  List<Index> get indexes => [
        Index(
          'idx_debts_status',
          'CREATE INDEX idx_debts_status ON debts (is_settled, is_from_auto_fix)',
        ),
        Index(
          'idx_debts_guest',
          'CREATE INDEX idx_debts_guest ON debts (guest_name)',
        ),
      ];
}

// جدول الملاحظات البسيط
class ShiftNotes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get content => text()();
  TextColumn get priority =>
      text().withDefault(const Constant('medium'))(); // high, medium, low
  TextColumn get shiftType => text().withDefault(
        const Constant('all'),
      )(); // morning, evening, night, all
  IntColumn get isRead =>
      integer().withDefault(const Constant(0))(); // 0 = غير مقروء، 1 = مقروء
  TextColumn get createdAt => text()();
  TextColumn get expiresAt => text().nullable()();
  TextColumn get createdBy => text().withDefault(const Constant('user'))();
}

@DataClassName('BookingNight')
class BookingNights extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookingLocalId => integer().references(Bookings, #id)();
  TextColumn get hotelDayKey => text()();
  TextColumn get nightStart => text()();
  TextColumn get nightEnd => text()();
  RealColumn get nightlyRate => real().withDefault(const Constant(0))();
  IntColumn get sequence => integer().withDefault(const Constant(0))();
  BoolColumn get isProcessedByAutoFix =>
      boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>>? get uniqueKeys => [
        {bookingLocalId, hotelDayKey},
      ];
}

@DataClassName('HotelDayLedgerEntry')
class HotelDayLedger extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get hotelDayKey => text()();
  RealColumn get totalIncome => real().withDefault(const Constant(0))();
  RealColumn get totalExpenses => real().withDefault(const Constant(0))();
  RealColumn get pendingBalances => real().withDefault(const Constant(0))();
  RealColumn get occupancyRate => real().withDefault(const Constant(0))();
  IntColumn get bookingsProcessed => integer().withDefault(const Constant(0))();
  IntColumn get paymentsProcessed => integer().withDefault(const Constant(0))();
  IntColumn get debtsProcessed => integer().withDefault(const Constant(0))();
  IntColumn get expensesProcessed => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('draft'))();

  @override
  List<Set<Column>>? get uniqueKeys => [
        {hotelDayKey},
      ];
}

@DataClassName('AutoFixRun')
class AutoFixRuns extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get runUuid => text().unique()();
  TextColumn get source => text().withDefault(const Constant('unknown'))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get startedAtEpoch => integer()();
  TextColumn get startedAtIso => text()();
  IntColumn get completedAtEpoch => integer().nullable()();
  TextColumn get completedAtIso => text().nullable()();
  IntColumn get fixesApplied => integer().withDefault(const Constant(0))();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get metadata => text().nullable()();
}

@DataClassName('IntegrityViolation')
class IntegrityViolations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get runId => integer().references(AutoFixRuns, #id)();
  TextColumn get affectedTableName => text()();
  TextColumn get recordUuid => text().nullable()();
  TextColumn get violationType => text()();
  TextColumn get details => text()();
  BoolColumn get isCritical => boolean().withDefault(const Constant(false))();
  TextColumn get createdAtIso => text()();
  IntColumn get createdAtEpoch => integer()();

  List<Index> get indexes => [
        Index(
          'idx_integrity_run',
          'CREATE INDEX idx_integrity_run ON integrity_violations (run_id, violation_type)',
        ),
      ];
}

@DataClassName('AppSession')
class AppSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionUuid => text().unique()();
  TextColumn get deviceId => text().nullable()();
  TextColumn get sessionStartIso => text()();
  TextColumn get sessionEndIso => text().nullable()();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  TextColumn get lastKnownVersion => text().nullable()();
  TextColumn get metadata => text().nullable()();
}

@DataClassName('SalaryCycle')
class SalaryCycles extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id)();
  TextColumn get cycleKey => text()();
  TextColumn get hotelDayStart => text().nullable()();
  TextColumn get hotelDayEnd => text().nullable()();
  RealColumn get expectedAmount => real().withDefault(const Constant(0))();
  RealColumn get actualPaid => real().withDefault(const Constant(0))();
  RealColumn get remainingAmount => real().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('draft'))();

  @override
  List<Set<Column>>? get uniqueKeys => [
        {employeeId, cycleKey},
      ];
}

@DataClassName('SalaryPayment')
class SalaryPayments extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cycleId => integer().references(SalaryCycles, #id)();
  RealColumn get amount => real().withDefault(const Constant(0))();
  TextColumn get hotelDayKey => text().nullable()();
  TextColumn get paymentDateIso => text()();
  TextColumn get method => text().nullable()();
  BoolColumn get isAutoGenerated =>
      boolean().withDefault(const Constant(false))();

  List<Index> get indexes => [
        Index(
          'idx_salary_payments_cycle',
          'CREATE INDEX idx_salary_payments_cycle ON salary_payments (cycle_id, hotel_day_key)',
        ),
      ];
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
  TextColumn get idempotencyKey => text().nullable()();
  TextColumn get processingStatus =>
      text().withDefault(const Constant('pending'))();
  IntColumn get processingStartedAt => integer().nullable()();
  TextColumn get processingWorker => text().nullable()();
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
  TextColumn get targetTable => text().named('table_name')();
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

@DataClassName('SyncConflictRow')
class SyncConflicts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get logId => integer().references(SyncLog, #id)();
  TextColumn get targetTable => text().named('table_name')();
  TextColumn get uuid => text()();
  TextColumn get resolution => text()();
  TextColumn get localPayload => text()();
  TextColumn get remotePayload => text()();
  TextColumn get createdAt => text()();
}

@DriftDatabase(
  tables: [
    Rooms,
    Bookings,
    BookingNotes,
    ShiftNotes,
    Employees,
    Expenses,
    CashTransactions,
    Payments,
    Debts,
    BookingNights,
    HotelDayLedger,
    AutoFixRuns,
    IntegrityViolations,
    AppSessions,
    SalaryCycles,
    SalaryPayments,
    Outbox,
    SyncState,
    RestoreFixLog,
    SyncQueue,
    SyncLog,
    SyncConflicts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  AppDatabase._internal(super.executor);

  static AppDatabase forTesting(QueryExecutor executor) =>
      AppDatabase._internal(executor);

  @override
  int get schemaVersion => 19;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(bookings, bookings.guestIdType);
            await m.addColumn(bookings, bookings.guestIdNumber);
            await m.addColumn(bookings, bookings.guestIdIssueDate);
            await m.addColumn(bookings, bookings.guestIdIssuePlace);
            await m.addColumn(bookings, bookings.actualCheckout);
            await m.addColumn(bookings, bookings.expectedNights);
            await m.database.customStatement(
              'UPDATE bookings SET expected_nights = calculated_nights',
            );
          }
          if (from < 3) {
            await m.database.customStatement(
              'ALTER TABLE rooms RENAME TO rooms_old',
            );
            await m.createTable(rooms);
            await m.database.customStatement(
              'INSERT INTO rooms (room_number, type, price, status, image_url, local_uuid, server_id, created_at, updated_at, deleted_at, last_modified, version, origin) '
              'SELECT room_number, type, price, status, image_url, local_uuid, server_id, created_at, updated_at, deleted_at, last_modified, version, origin FROM rooms_old',
            );
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
          if (from < 13) {
            // SyncFields ISO/Epoch columns
            await m.addColumn(bookings, bookings.createdAtIso);
            await m.addColumn(bookings, bookings.updatedAtIso);
            await m.addColumn(bookings, bookings.deletedAtIso);
            await m.addColumn(bookings, bookings.createdAtEpoch);
            await m.addColumn(bookings, bookings.lastModifiedEpoch);
            await m.addColumn(rooms, rooms.createdAtIso);
            await m.addColumn(rooms, rooms.updatedAtIso);
            await m.addColumn(rooms, rooms.deletedAtIso);
            await m.addColumn(rooms, rooms.createdAtEpoch);
            await m.addColumn(rooms, rooms.lastModifiedEpoch);
            await m.addColumn(employees, employees.createdAtIso);
            await m.addColumn(employees, employees.updatedAtIso);
            await m.addColumn(employees, employees.deletedAtIso);
            await m.addColumn(employees, employees.createdAtEpoch);
            await m.addColumn(employees, employees.lastModifiedEpoch);
            await m.addColumn(expenses, expenses.createdAtIso);
            await m.addColumn(expenses, expenses.updatedAtIso);
            await m.addColumn(expenses, expenses.deletedAtIso);
            await m.addColumn(expenses, expenses.createdAtEpoch);
            await m.addColumn(expenses, expenses.lastModifiedEpoch);
            await m.addColumn(cashTransactions, cashTransactions.createdAtIso);
            await m.addColumn(cashTransactions, cashTransactions.updatedAtIso);
            await m.addColumn(cashTransactions, cashTransactions.deletedAtIso);
            await m.addColumn(
                cashTransactions, cashTransactions.createdAtEpoch);
            await m.addColumn(
                cashTransactions, cashTransactions.lastModifiedEpoch);
            await m.addColumn(payments, payments.createdAtIso);
            await m.addColumn(payments, payments.updatedAtIso);
            await m.addColumn(payments, payments.deletedAtIso);
            await m.addColumn(payments, payments.createdAtEpoch);
            await m.addColumn(payments, payments.lastModifiedEpoch);
            await m.addColumn(debts, debts.createdAtIso);
            await m.addColumn(debts, debts.updatedAtIso);
            await m.addColumn(debts, debts.deletedAtIso);
            await m.addColumn(debts, debts.createdAtEpoch);
            await m.addColumn(debts, debts.lastModifiedEpoch);
            await m.addColumn(bookingNotes, bookingNotes.createdAtIso);
            await m.addColumn(bookingNotes, bookingNotes.updatedAtIso);
            await m.addColumn(bookingNotes, bookingNotes.deletedAtIso);
            await m.addColumn(bookingNotes, bookingNotes.createdAtEpoch);
            await m.addColumn(bookingNotes, bookingNotes.lastModifiedEpoch);
          }
          if (from < 14) {
            await m.addColumn(bookings, bookings.totalNightsCached);
            await m.addColumn(bookings, bookings.stayDurationIso);
            await m.addColumn(bookings, bookings.lastNightEpoch);
            await m.addColumn(bookings, bookings.isOverdue);
            await m.addColumn(bookings, bookings.needsCheckoutReview);
            await m.addColumn(bookings, bookings.totalDueCached);
            await m.addColumn(bookings, bookings.totalPaidCached);
            await m.addColumn(bookings, bookings.remainingBalanceCached);
            await m.addColumn(bookings, bookings.isFullyPaid);
            await m.addColumn(bookings, bookings.hotelDayCheckin);
            await m.addColumn(bookings, bookings.hotelDayCheckout);
            await m.addColumn(rooms, rooms.cleaningStatus);
            await m.addColumn(rooms, rooms.lastCleanedHotelDay);
            await m.addColumn(rooms, rooms.lastOccupiedHotelDay);
            await m.addColumn(rooms, rooms.requiresMaintenance);
            await m.addColumn(expenses, expenses.hotelDayKey);
            await m.addColumn(expenses, expenses.categoryUuid);
            await m.addColumn(expenses, expenses.cashFlowUuid);
            await m.addColumn(expenses, expenses.isAutoGenerated);
            await m.addColumn(payments, payments.hotelDayKey);
            await m.addColumn(payments, payments.isPendingBalance);
            await m.addColumn(payments, payments.linkedDebtUuid);
            await m.addColumn(payments, payments.bookingUuidCache);
            await m.addColumn(debts, debts.debtUuid);
            await m.addColumn(debts, debts.hotelDayOpened);
            await m.addColumn(debts, debts.hotelDayClosed);
            await m.addColumn(debts, debts.isFromAutoFix);
            await m.addColumn(debts, debts.settlementConfirmed);
          }
          if (from < 15) {
            await m.createTable(bookingNights);
            await m.createTable(hotelDayLedger);
            await m.createTable(autoFixRuns);
            await m.createTable(integrityViolations);
            await m.createTable(appSessions);
            await m.createTable(salaryCycles);
            await m.createTable(salaryPayments);
          }
          if (from < 17) {
            await m.addColumn(outbox, outbox.idempotencyKey);
          }
          if (from < 18) {
            try {
              await m.addColumn(outbox, outbox.processingStatus);
            } catch (_) {}
            try {
              await m.addColumn(outbox, outbox.processingStartedAt);
            } catch (_) {}
            try {
              await m.addColumn(outbox, outbox.processingWorker);
            } catch (_) {}
          }
          if (from < 19) {
            try {
              await m.addColumn(
                bookings,
                bookings.vectorClock as GeneratedColumn<String>,
              );
            } catch (_) {}
            try {
              await m.addColumn(
                rooms,
                rooms.vectorClock as GeneratedColumn<String>,
              );
            } catch (_) {}
            try {
              await m.addColumn(
                employees,
                employees.vectorClock as GeneratedColumn<String>,
              );
            } catch (_) {}
            try {
              await m.addColumn(
                expenses,
                expenses.vectorClock as GeneratedColumn<String>,
              );
            } catch (_) {}
            try {
              await m.addColumn(
                cashTransactions,
                cashTransactions.vectorClock as GeneratedColumn<String>,
              );
            } catch (_) {}
            try {
              await m.addColumn(
                payments,
                payments.vectorClock as GeneratedColumn<String>,
              );
            } catch (_) {}
            try {
              await m.addColumn(
                debts,
                debts.vectorClock as GeneratedColumn<String>,
              );
            } catch (_) {}
            try {
              await m.addColumn(
                bookingNotes,
                bookingNotes.vectorClock as GeneratedColumn<String>,
              );
            } catch (_) {}
            try {
              await m.addColumn(
                bookingNights,
                bookingNights.vectorClock as GeneratedColumn<String>,
              );
            } catch (_) {}
            try {
              await m.addColumn(
                hotelDayLedger,
                hotelDayLedger.vectorClock as GeneratedColumn<String>,
              );
            } catch (_) {}
            try {
              await m.addColumn(
                salaryCycles,
                salaryCycles.vectorClock as GeneratedColumn<String>,
              );
            } catch (_) {}
            try {
              await m.addColumn(
                salaryPayments,
                salaryPayments.vectorClock as GeneratedColumn<String>,
              );
            } catch (_) {}
          }
        },
      );

  /// تجميع جميع الجداول المطلوب مزامنتها في خريطة JSON
  Future<Map<String, dynamic>> getAllTablesAsJson() async {
    final roomsData = await select(rooms).get();
    final bookingsData = await select(bookings).get();
    final bookingNotesData = await select(bookingNotes).get();
    final shiftNotesData = await select(shiftNotes).get();
    final employeesData = await select(employees).get();
    final expensesData = await select(expenses).get();
    final cashTransactionsData = await select(cashTransactions).get();
    final paymentsData = await select(payments).get();
    final debtsData = await select(debts).get();
    final bookingNightsData = await select(bookingNights).get();
    final ledgerData = await select(hotelDayLedger).get();
    final autoFixRunsData = await select(autoFixRuns).get();
    final violationsData = await select(integrityViolations).get();
    final sessionsData = await select(appSessions).get();
    final salaryCyclesData = await select(salaryCycles).get();
    final salaryPaymentsData = await select(salaryPayments).get();

    return {
      'rooms': roomsData.map((e) => e.toJson()).toList(),
      'bookings': bookingsData.map((e) => e.toJson()).toList(),
      'booking_notes': bookingNotesData.map((e) => e.toJson()).toList(),
      'shift_notes': shiftNotesData.map((e) => e.toJson()).toList(),
      'employees': employeesData.map((e) => e.toJson()).toList(),
      'expenses': expensesData.map((e) => e.toJson()).toList(),
      'cash_transactions': cashTransactionsData.map((e) => e.toJson()).toList(),
      'payments': paymentsData.map((e) => e.toJson()).toList(),
      'debts': debtsData.map((e) => e.toJson()).toList(),
      'booking_nights': bookingNightsData.map((e) => e.toJson()).toList(),
      'hotel_day_ledger': ledgerData.map((e) => e.toJson()).toList(),
      'auto_fix_runs': autoFixRunsData.map((e) => e.toJson()).toList(),
      'integrity_violations': violationsData.map((e) => e.toJson()).toList(),
      'app_sessions': sessionsData.map((e) => e.toJson()).toList(),
      'salary_cycles': salaryCyclesData.map((e) => e.toJson()).toList(),
      'salary_payments': salaryPaymentsData.map((e) => e.toJson()).toList(),
      'guests': <Map<String, dynamic>>[],
      'services': <Map<String, dynamic>>[],
      'settings': <Map<String, dynamic>>[],
    };
  }

  /// تطبيق البيانات المدمجة على قاعدة البيانات المحلية داخل معاملة واحدة
  Future<void> applyMergedData(Map<String, dynamic> merged) async {
    if (merged.isEmpty) {
      developer.log(
        'applyMergedData: merged snapshot is empty. Skipping apply to avoid wiping local data.',
        name: 'AppDatabase',
        level: 900,
      );
      return;
    }

    List<Map<String, dynamic>>? asListIfPresent(String key) {
      if (!merged.containsKey(key)) {
        return null;
      }
      final value = merged[key];
      if (value == null) {
        return <Map<String, dynamic>>[];
      }
      if (value is! List) {
        throw StateError(
          'Invalid snapshot table type for $key: ${value.runtimeType}',
        );
      }
      return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
    }

    await transaction(() async {
      Future<void> replaceTableIfNonEmpty<T extends Insertable<dynamic>>(
        TableInfo<Table, dynamic> table,
        String key,
        T Function(Map<String, dynamic> json) fromJson,
      ) async {
        final rows = asListIfPresent(key);
        if (rows == null) {
          return;
        }
        await delete(table).go();
        await batch((batch) {
          batch.insertAll(
            table,
            rows.map(fromJson).toList(),
            mode: InsertMode.insertOrReplace,
          );
        });
      }

      await replaceTableIfNonEmpty<Room>(
        rooms,
        'rooms',
        (row) => Room.fromJson(row),
      );
      await replaceTableIfNonEmpty<Booking>(
        bookings,
        'bookings',
        (row) => Booking.fromJson(row),
      );
      await replaceTableIfNonEmpty<BookingNote>(
        bookingNotes,
        'booking_notes',
        (row) => BookingNote.fromJson(row),
      );
      await replaceTableIfNonEmpty<ShiftNote>(
        shiftNotes,
        'shift_notes',
        (row) => ShiftNote.fromJson(row),
      );
      await replaceTableIfNonEmpty<Employee>(
        employees,
        'employees',
        (row) => Employee.fromJson(row),
      );
      await replaceTableIfNonEmpty<Expense>(
        expenses,
        'expenses',
        (row) => Expense.fromJson(row),
      );
      await replaceTableIfNonEmpty<CashTransaction>(
        cashTransactions,
        'cash_transactions',
        (row) => CashTransaction.fromJson(row),
      );
      await replaceTableIfNonEmpty<Payment>(
        payments,
        'payments',
        (row) => Payment.fromJson(row),
      );
      await replaceTableIfNonEmpty<Debt>(
        debts,
        'debts',
        (row) => Debt.fromJson(row),
      );
      await replaceTableIfNonEmpty<BookingNight>(
        bookingNights,
        'booking_nights',
        (row) => BookingNight.fromJson(row),
      );
      await replaceTableIfNonEmpty<HotelDayLedgerEntry>(
        hotelDayLedger,
        'hotel_day_ledger',
        (row) => HotelDayLedgerEntry.fromJson(row),
      );
      await replaceTableIfNonEmpty<AutoFixRun>(
        autoFixRuns,
        'auto_fix_runs',
        (row) => AutoFixRun.fromJson(row),
      );
      await replaceTableIfNonEmpty<IntegrityViolation>(
        integrityViolations,
        'integrity_violations',
        (row) => IntegrityViolation.fromJson(row),
      );
      await replaceTableIfNonEmpty<AppSession>(
        appSessions,
        'app_sessions',
        (row) => AppSession.fromJson(row),
      );
      await replaceTableIfNonEmpty<SalaryCycle>(
        salaryCycles,
        'salary_cycles',
        (row) => SalaryCycle.fromJson(row),
      );
      await replaceTableIfNonEmpty<SalaryPayment>(
        salaryPayments,
        'salary_payments',
        (row) => SalaryPayment.fromJson(row),
      );
    });
  }
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dbDir = await sqflite.getDatabasesPath();
    final file = File(p.join(dbDir, _dbFileName));
    return NativeDatabase.createInBackground(file, logStatements: false);
  });
}

extension EmployeeX on Employee {
  double get salary => basicSalary;
}

/// Singleton manager for the Drift database to support clean close/reopen during file-based restores
class DatabaseManager {
  static AppDatabase? _instance;
  static Future<void> Function()? _onStopCallback;
  static Future<void> Function()? _onRestartCallback;
  static bool _isRestoring = false;

  static AppDatabase get instance => _instance ??= AppDatabase();

  static bool get isInitialized => _instance != null;
  static bool get isRestoring => _isRestoring;

  static Future<T> runWithRestoreGuard<T>(Future<T> Function() action) async {
    _isRestoring = true;
    try {
      return await action();
    } finally {
      _isRestoring = false;
    }
  }

  static void registerSyncCallbacks({
    required Future<void> Function() onStop,
    required Future<void> Function() onRestart,
  }) {
    _onStopCallback = onStop;
    _onRestartCallback = onRestart;
  }

  static Future<void> close() async {
    _isRestoring = true;
    if (_onStopCallback != null) {
      try {
        await _onStopCallback!();
      } catch (_) {}
    }
    try {
      await _instance?.close();
    } catch (_) {}
    _instance = null;
  }

  static Future<void> reopen() async {
    await close();
    _instance = AppDatabase();
    if (_onRestartCallback != null) {
      try {
        await _onRestartCallback!();
      } catch (_) {}
    }
    _isRestoring = false;
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
    required List<sync_models.SyncOperation> appliedOperations,
    required List<sync_models.SyncConflictModel> conflicts,
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
              operations: jsonEncode(
                appliedOperations
                    .map(
                      (sync_models.SyncOperation e) => {
                        'table': e.table,
                        'uuid': e.uuid,
                        'operation': e.operation,
                        'payload': e.payload,
                        'timestamp': e.timestamp,
                      },
                    )
                    .toList(),
              ),
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
                targetTable: conflict.table,
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

  Future<List<sync_models.SyncConflictModel>> fetchConflictsForLog(
    int logId,
  ) async {
    final rows = await (_db.select(
      _db.syncConflicts,
    )..where((tbl) => tbl.logId.equals(logId)))
        .get();
    return rows
        .map(
          (row) => sync_models.SyncConflictModel(
            table: row.targetTable,
            uuid: row.uuid,
            localPayload: Map<String, dynamic>.from(
              jsonDecode(row.localPayload) as Map,
            ),
            remotePayload: Map<String, dynamic>.from(
              jsonDecode(row.remotePayload) as Map,
            ),
            resolution: row.resolution,
          ),
        )
        .toList();
  }
}
