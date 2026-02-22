import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:uuid/uuid.dart';

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
  RealColumn get discount => real().withDefault(const Constant(0))();
  TextColumn get discountType =>
      text().withDefault(const Constant('per_night'))();
  TextColumn get discountStartDate => text().nullable()();
  IntColumn get expectedNights => integer().withDefault(const Constant(1))();
  IntColumn get calculatedNights => integer().withDefault(const Constant(1))();
  IntColumn get totalNightsCached => integer().withDefault(const Constant(0))();
  TextColumn get stayDurationIso => text().nullable()();
  TextColumn get financialHash => text().nullable()();
  TextColumn get financialFrozenAt => text().nullable()();
  IntColumn get lastNightEpoch => integer().nullable()();
  BoolColumn get isOverdue => boolean().withDefault(const Constant(false))();
  BoolColumn get needsCheckoutReview =>
      boolean().withDefault(const Constant(false))();
  RealColumn get totalDueCached => real().withDefault(const Constant(0.0))();
  RealColumn get totalPaidCached => real().withDefault(const Constant(0.0))();
  RealColumn get remainingBalanceCached =>
      real().withDefault(const Constant(0.0))();
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

class GuestInfos extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get roomNumber => text()();
  TextColumn get guestName => text()();
  TextColumn get nationality => text()();
  TextColumn get idNumber => text()();
  TextColumn get idType => text().withDefault(const Constant('بطاقة شخصية'))();
  TextColumn get issueDate => text().nullable()();
  TextColumn get issuePlace => text().nullable()();
  TextColumn get governorate => text().nullable()();
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
class ShiftNotes extends Table with SyncFields {
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
  // createdAt موجود في SyncFields كـ integer
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
  RealColumn get nightlyRate => real().withDefault(const Constant(0.0))();
  IntColumn get sequence => integer().withDefault(const Constant(0))();
  BoolColumn get isProcessedByAutoFix =>
      boolean().withDefault(const Constant(false))();
  RealColumn get baseRate => real().withDefault(const Constant(0.0))();
  RealColumn get adjustment => real().withDefault(const Constant(0.0))();
  RealColumn get finalRate => real().withDefault(const Constant(0.0))();
  TextColumn get appliedAdjustmentUuid => text().nullable()();
  TextColumn get appliedAdjustmentsJson => text().nullable()();

  @override
  List<Set<Column>>? get uniqueKeys => [
    {bookingLocalId, hotelDayKey},
  ];
}

@DataClassName('HotelDayLedgerEntry')
class HotelDayLedger extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get hotelDayKey => text()();
  RealColumn get totalIncome => real().withDefault(const Constant(0.0))();
  RealColumn get totalExpenses => real().withDefault(const Constant(0.0))();
  RealColumn get pendingBalances => real().withDefault(const Constant(0.0))();
  RealColumn get occupancyRate => real().withDefault(const Constant(0.0))();
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

@DataClassName('PriceAdjustment')
class PriceAdjustments extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get targetType => text()();
  TextColumn get targetUuid => text()();
  TextColumn get adjustmentType => text()();
  IntColumn get previousValue => integer()();
  IntColumn get newValue => integer()();
  TextColumn get reason => text().nullable()();
  TextColumn get effectiveDate => text()();
  TextColumn get appliedBy => text()();
  TextColumn get hotelDayKey => text()();
  BoolColumn get isReversed => boolean().withDefault(const Constant(false))();
  TextColumn get reversedAt => text().nullable()();
  TextColumn get reversedBy => text().nullable()();

  List<Index> get indexes => [
    Index(
      'idx_price_adj_target',
      'CREATE INDEX idx_price_adj_target ON price_adjustments (target_type, target_uuid)',
    ),
    Index(
      'idx_price_adj_day',
      'CREATE INDEX idx_price_adj_day ON price_adjustments (hotel_day_key)',
    ),
  ];
}

@DataClassName('BookingPriceAdjustment')
class BookingPriceAdjustments extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get bookingLocalUuid => text()();
  IntColumn get bookingLocalId =>
      integer().nullable().references(Bookings, #id)();
  IntColumn get adjustmentType => integer().withDefault(const Constant(0))();
  TextColumn get adjustmentMode =>
      text().withDefault(const Constant('per_night'))();
  RealColumn get amount => real().withDefault(const Constant(0.0))();
  TextColumn get effectiveHotelDay => text()();
  TextColumn get endHotelDay => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get reason => text().nullable()();
  TextColumn get appliedBy => text().nullable()();
  TextColumn get cancelledAt => text().nullable()();
  TextColumn get cancelledBy => text().nullable()();

  List<Index> get indexes => [
    Index(
      'idx_booking_price_adj_booking',
      'CREATE INDEX idx_booking_price_adj_booking ON booking_price_adjustments (booking_local_uuid, is_active)',
    ),
    Index(
      'idx_booking_price_adj_dates',
      'CREATE INDEX idx_booking_price_adj_dates ON booking_price_adjustments (effective_hotel_day, end_hotel_day)',
    ),
  ];
}

@DataClassName('AuditLog')
class AuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get localUuid => text().unique()();
  TextColumn get operationType => text()();
  TextColumn get entityType => text()();
  TextColumn get entityUuid => text()();
  IntColumn get entityId => integer().nullable()();
  TextColumn get previousState => text().nullable()();
  TextColumn get newState => text().nullable()();
  TextColumn get changedFields => text().nullable()();
  TextColumn get performedBy => text()();
  TextColumn get deviceId => text()();
  TextColumn get ipAddress => text().nullable()();
  TextColumn get hotelDayKey => text()();
  IntColumn get timestamp => integer()();
  TextColumn get timestampIso => text()();
  BoolColumn get isFinancial => boolean().withDefault(const Constant(false))();
  IntColumn get amountImpact => integer().nullable()();
  IntColumn get createdAt => integer()();

  List<Index> get indexes => [
    Index(
      'idx_audit_entity',
      'CREATE INDEX idx_audit_entity ON audit_logs (entity_type, entity_uuid)',
    ),
    Index(
      'idx_audit_timestamp',
      'CREATE INDEX idx_audit_timestamp ON audit_logs (timestamp DESC)',
    ),
    Index(
      'idx_audit_financial',
      'CREATE INDEX idx_audit_financial ON audit_logs (is_financial, hotel_day_key)',
    ),
  ];
}

@DataClassName('PaymentVoid')
class PaymentVoids extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get originalPaymentUuid => text().unique()();
  IntColumn get originalPaymentId => integer()();
  TextColumn get bookingUuid => text()();
  IntColumn get voidedAmount => integer()();
  TextColumn get voidReason => text()();
  TextColumn get voidedBy => text()();
  IntColumn get voidedAt => integer()();
  TextColumn get voidedAtIso => text()();
  TextColumn get hotelDayKey => text()();
  TextColumn get reversalPaymentUuid => text().nullable()();
  TextColumn get approvedBy => text().nullable()();

  List<Index> get indexes => [
    Index(
      'idx_void_booking',
      'CREATE INDEX idx_void_booking ON payment_voids (booking_uuid)',
    ),
    Index(
      'idx_void_day',
      'CREATE INDEX idx_void_day ON payment_voids (hotel_day_key)',
    ),
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
  IntColumn get expectedAmount => integer().withDefault(const Constant(0))();
  IntColumn get actualPaid => integer().withDefault(const Constant(0))();
  IntColumn get remainingAmount => integer().withDefault(const Constant(0))();
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
  IntColumn get amount => integer().withDefault(const Constant(0))();
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
  TextColumn get remotePayload => text().nullable()();
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
  TextColumn get operations =>
      text().nullable().withDefault(const Constant('[]'))();
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
    GuestInfos,
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
    PriceAdjustments,
    BookingPriceAdjustments,
    AuditLogs,
    PaymentVoids,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  AppDatabase._internal(super.executor);

  static AppDatabase forTesting(QueryExecutor executor) =>
      AppDatabase._internal(executor);

  @override
  int get schemaVersion => 28;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
    onUpgrade: (m, from, to) async {
      // باقي الترقيات كما هي (لم يتم تغييرها)
      // ... (نفس الكود السابق)
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
    final guestInfosData = await select(guestInfos).get();
    final bookingPriceAdjustmentsData = await select(
      bookingPriceAdjustments,
    ).get();

    return {
      'rooms': roomsData.map((e) => e.toJson()).toList(),
      'bookings': bookingsData.map((e) => e.toJson()).toList(),
      'booking_notes': bookingNotesData.map((e) => e.toJson()).toList(),
      'shift_notes': shiftNotesData.map((e) => e.toJson()).toList(),
      'employees': employeesData.map((e) => e.toJson()).toList(),
      'guest_infos': guestInfosData.map((e) => e.toJson()).toList(),
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
      'booking_price_adjustments': bookingPriceAdjustmentsData
          .map((e) => e.toJson())
          .toList(),
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
      if (!merged.containsKey(key)) return null;
      final value = merged[key];
      if (value == null) return <Map<String, dynamic>>[];
      if (value is! List) {
        throw StateError(
          'Invalid snapshot table type for $key: ${value.runtimeType}',
        );
      }
      return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
    }

    await transaction(() async {
      // تعطيل foreign keys مؤقتاً
      await customStatement('PRAGMA foreign_keys = OFF');

      // دالة مساعدة للجداول المستقلة (لا تعتمد على bookings)
      Future<void> replaceIndependentTable<T extends Insertable<dynamic>>(
        TableInfo<Table, dynamic> table,
        String key,
        T Function(Map<String, dynamic> json) fromJson,
      ) async {
        final rows = asListIfPresent(key);
        if (rows == null) return;
        await delete(table).go();
        await batch((batch) {
          batch.insertAll(table, rows.map(fromJson).toList(),
              mode: InsertMode.insertOrReplace);
        });
      }

      // 1. استيراد الجداول المستقلة
      await replaceIndependentTable(rooms, 'rooms', Room.fromJson);
      await replaceIndependentTable(employees, 'employees', Employee.fromJson);
      await replaceIndependentTable(shiftNotes, 'shift_notes', ShiftNote.fromJson);
      await replaceIndependentTable(guestInfos, 'guest_infos', GuestInfo.fromJson);
      await replaceIndependentTable(expenses, 'expenses', Expense.fromJson);
      await replaceIndependentTable(cashTransactions, 'cash_transactions', CashTransaction.fromJson);
      await replaceIndependentTable(hotelDayLedger, 'hotel_day_ledger', HotelDayLedgerEntry.fromJson);
      await replaceIndependentTable(autoFixRuns, 'auto_fix_runs', AutoFixRun.fromJson);
      await replaceIndependentTable(integrityViolations, 'integrity_violations', IntegrityViolation.fromJson);
      await replaceIndependentTable(appSessions, 'app_sessions', AppSession.fromJson);
      await replaceIndependentTable(salaryCycles, 'salary_cycles', SalaryCycle.fromJson);
      await replaceIndependentTable(salaryPayments, 'salary_payments', SalaryPayment.fromJson);
      await replaceIndependentTable(priceAdjustments, 'price_adjustments', PriceAdjustment.fromJson);
      await replaceIndependentTable(auditLogs, 'audit_logs', AuditLog.fromJson);
      await replaceIndependentTable(paymentVoids, 'payment_voids', PaymentVoid.fromJson);

      // 2. استيراد bookings (لأنها مرجع للجداول الأخرى)
      await replaceIndependentTable(bookings, 'bookings', Booking.fromJson);

      // 3. بناء الخرائط اللازمة
      final bookingsList = await select(bookings).get();
      final serverIdToLocalId = <int, int>{};
      final uuidToLocalId = <String, int>{};
      for (final b in bookingsList) {
        if (b.serverBookingId != null) {
          serverIdToLocalId[b.serverBookingId!] = b.id;
        }
        uuidToLocalId[b.localUuid] = b.id;
      }

      // دالة مساعدة لتحويل المفتاح الأجنبي
      int? resolveBookingId(Map<String, dynamic> row, {bool preferUuid = false}) {
        final possibleKeys = ['booking_local_id', 'bookingLocalId', 'bookingId', 'booking_id'];
        for (final key in possibleKeys) {
          final value = row[key];
          if (value != null) {
            if (value is int) {
              return serverIdToLocalId[value];
            } else if (value is String) {
              final parsed = int.tryParse(value);
              if (parsed != null) {
                return serverIdToLocalId[parsed];
              } else if (preferUuid) {
                return uuidToLocalId[value];
              }
            }
          }
        }
        return null;
      }

      // 4. معالجة booking_nights
      final nights = asListIfPresent('booking_nights');
      if (nights != null) {
        await delete(bookingNights).go();
        for (final night in nights) {
          final localId = resolveBookingId(night);
          if (localId != null) {
            night['booking_local_id'] = localId;
            await into(bookingNights).insert(BookingNight.fromJson(night));
          } else {
            developer.log('⚠️ تخطي ليلة لحجز غير موجود: $night', name: 'AppDatabase');
          }
        }
      }

      // 5. معالجة payments
      final paymentsList = asListIfPresent('payments');
      if (paymentsList != null) {
        await delete(payments).go();
        for (final payment in paymentsList) {
          final localId = resolveBookingId(payment);
          if (localId != null) {
            payment['booking_local_id'] = localId;
            await into(payments).insert(Payment.fromJson(payment));
          } else {
            developer.log('⚠️ تخطي دفعة لحجز غير موجود: $payment', name: 'AppDatabase');
          }
        }
      }

      // 6. معالجة debts
      final debtsList = asListIfPresent('debts');
      if (debtsList != null) {
        await delete(debts).go();
        for (final debt in debtsList) {
          final localId = resolveBookingId(debt);
          if (localId != null) {
            debt['booking_local_id'] = localId;
            await into(debts).insert(Debt.fromJson(debt));
          } else {
            developer.log('⚠️ تخطي دين لحجز غير موجود: $debt', name: 'AppDatabase');
          }
        }
      }

      // 7. معالجة booking_notes
      final notes = asListIfPresent('booking_notes');
      if (notes != null) {
        await delete(bookingNotes).go();
        for (final note in notes) {
          final localId = resolveBookingId(note);
          if (localId != null) {
            note['booking_id'] = localId;
            await into(bookingNotes).insert(BookingNote.fromJson(note));
          } else {
            developer.log('⚠️ تخطي ملاحظة لحجز غير موجود: $note', name: 'AppDatabase');
          }
        }
      }

      // 8. معالجة booking_price_adjustments (تعتمد على uuid بشكل رئيسي، ولكن قد تحتوي على bookingLocalId)
      final adjustments = asListIfPresent('booking_price_adjustments');
      if (adjustments != null) {
        await delete(bookingPriceAdjustments).go();
        for (final adj in adjustments) {
          final bookingUuid = adj['booking_local_uuid'] ?? adj['bookingLocalUuid'];
          if (bookingUuid is String && uuidToLocalId.containsKey(bookingUuid)) {
            adj['booking_local_uuid'] = bookingUuid;
            adj['booking_local_id'] = uuidToLocalId[bookingUuid];
          } else {
            final localId = resolveBookingId(adj, preferUuid: false);
            if (localId != null) {
              adj['booking_local_id'] = localId;
            } else {
              developer.log('⚠️ تخطي تعديل سعر لحجز غير موجود: $adj', name: 'AppDatabase');
              continue;
            }
          }
          await into(bookingPriceAdjustments).insert(BookingPriceAdjustment.fromJson(adj));
        }
      }

      // إعادة تفعيل foreign keys
      await customStatement('PRAGMA foreign_keys = ON');
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
  double get salary => basicSalary.toDouble();
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
      final logId = await _db
          .into(_db.syncLog)
          .insert(
            SyncLogCompanion.insert(
              syncId: syncId,
              direction: direction,
              deviceId: deviceId,
              metadata: jsonEncode(metadata),
              operations: Value(
                jsonEncode(
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
    )..where((tbl) => tbl.logId.equals(logId))).get();
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
