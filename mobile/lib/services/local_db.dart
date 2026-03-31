import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:uuid/uuid.dart';

import '../data/sync_models.dart' as sync_models;
import 'daos/outbox_dao.dart';

part 'local_db.g.dart';

const String _dbFileName = 'marina_hotel.db';

/// JSON converter for field-level vector clock
class FieldLevelVectorClockConverter
    extends TypeConverter<Map<String, dynamic>, String> {
  const FieldLevelVectorClockConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    if (fromDb.isEmpty) return {};
    try {
      return jsonDecode(fromDb) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  @override
  String toSql(Map<String, dynamic> value) {
    if (value.isEmpty) return '{}';
    return jsonEncode(value);
  }
}

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
  // Enhanced VectorClock for field-level sync tracking
  TextColumn get vectorClock => text()
      .map(const FieldLevelVectorClockConverter())
      .withDefault(const Constant('{}'))();
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
  RealColumn get basicSalary => real().withDefault(const Constant(0.0))();
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
  RealColumn get amount => real().withDefault(const Constant(0.0))();
  TextColumn get date => text()();
  IntColumn get cashTransactionId => integer().nullable()();
  TextColumn get hotelDayKey => text().nullable()();
  TextColumn get categoryUuid => text().nullable()();
  TextColumn get cashFlowUuid => text().nullable()();
  BoolColumn get isAutoGenerated =>
      boolean().withDefault(const Constant(false))();
  TextColumn get idempotencyKey => text().nullable()();
  TextColumn get deviceId => text().nullable()();

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
  RealColumn get amount => real().withDefault(const Constant(0.0))();
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
  RealColumn get amount => real().withDefault(const Constant(0.0))();
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

class SyncMirror extends Table {
  TextColumn get syncEntityName => text()();
  TextColumn get localUuid => text()();
  TextColumn get rowHash => text()();
  TextColumn get payload => text()();
  IntColumn get lastSeenAt => integer()();

  @override
  Set<Column> get primaryKey => {syncEntityName, localUuid};
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
  RealColumn get totalAmount => real().withDefault(const Constant(0.0))();
  RealColumn get paidAmount => real().withDefault(const Constant(0.0))();
  RealColumn get remainingAmount => real().withDefault(const Constant(0.0))();
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
  TextColumn get shiftDate => text().nullable()(); // تاريخ الشيفت للترحيل
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
  TextColumn get roomNumber => text().nullable()();
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
  RealColumn get amountImpact => real().nullable()();
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
  TextColumn get startDate => text().nullable()(); // تاريخ بداية الدورة للترحيل
  TextColumn get endDate => text().nullable()(); // تاريخ نهاية الدورة للترحيل
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
  IntColumn get employeeId =>
      integer().nullable().references(Employees, #id)(); // معرف الموظف للترحيل
  RealColumn get amount => real().withDefault(const Constant(0.0))();
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
    Index(
      'idx_salary_payments_employee',
      'CREATE INDEX idx_salary_payments_employee ON salary_payments (employee_id, payment_date_iso)',
    ),
  ];
}

@DataClassName('SalaryWithdrawal')
class SalaryWithdrawals extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get expenseId => integer().nullable().unique()();
  IntColumn get employeeId => integer().references(Employees, #id)();
  TextColumn get name =>
      text().nullable()(); // اسم الموظف للتخزين المحلي والعرض السريع
  TextColumn get action => text()(); // 'سحب راتب', 'خصم من الراتب'
  RealColumn get amount => real().withDefault(const Constant(0.0))();
  TextColumn get note => text().nullable()();
  TextColumn get date => text()();

  List<Index> get indexes => [
    Index(
      'idx_salary_withdrawals_employee',
      'CREATE INDEX idx_salary_withdrawals_employee ON salary_withdrawals (employeeId, date)',
    ),
    Index(
      'idx_salary_withdrawals_expense',
      'CREATE INDEX idx_salary_withdrawals_expense ON salary_withdrawals (expenseId)',
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
  // === حقول جديدة للتحسين ===
  IntColumn get nextRetryAt => integer().nullable()(); // وقت المحاولة القادمة
  IntColumn get maxAttempts =>
      integer().withDefault(const Constant(5))(); // أقصى عدد محاولات
  TextColumn get priority =>
      text().withDefault(const Constant('normal'))(); // high, normal, low
  IntColumn get lastSuccessfulPushAt =>
      integer().nullable()(); // وقت آخر رفع ناجح

  @override
  List<Index> get indexes => [
    Index(
      'idx_outbox_status_priority',
      'CREATE INDEX idx_outbox_status_priority ON outbox (processing_status, priority, next_retry_at)',
    ),
    Index(
      'idx_outbox_entity_uuid',
      'CREATE INDEX idx_outbox_entity_uuid ON outbox (entity, local_uuid)',
    ),
  ];
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

/// ✅ جدول نسخ الحقول - لتتبع تغييرات كل حقل على حدة
class FieldVersions extends Table {
  TextColumn get syncEntityName => text().named('entity_name')();
  TextColumn get recordUuid => text()();
  TextColumn get fieldName => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get timestamp => integer()();
  TextColumn get deviceId => text()();
  TextColumn get vectorClock => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {syncEntityName, recordUuid, fieldName};

  @override
  List<Index> get indexes => [
    Index(
      'idx_field_versions_entity_record',
      'CREATE INDEX idx_field_versions_entity_record ON field_versions (entity_name, record_uuid)',
    ),
    Index(
      'idx_field_versions_timestamp',
      'CREATE INDEX idx_field_versions_timestamp ON field_versions (timestamp DESC)',
    ),
  ];
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
    SalaryWithdrawals,
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
    SyncMirror,
    FieldVersions, // ✅ إضافة جدول نسخ الحقول
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  AppDatabase._internal(super.executor);

  late final OutboxDao outboxDao = OutboxDao(this);

  static AppDatabase forTesting(QueryExecutor executor) =>
      AppDatabase._internal(executor);

  @override
  int get schemaVersion => 38;

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
          'INSERT INTO rooms (room_number, type, price, status, image_url, localUuid, serverId, createdAt, updatedAt, deletedAt, lastModified, version, origin) '
          'SELECT room_number, type, price, status, image_url, localUuid, serverId, createdAt, updatedAt, deletedAt, lastModified, version, origin FROM rooms_old',
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
        await m.addColumn(cashTransactions, cashTransactions.createdAtEpoch);
        await m.addColumn(cashTransactions, cashTransactions.lastModifiedEpoch);
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
        } catch (e, st) {
          developer.log(
            'Migration add processingStatus failed',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(outbox, outbox.processingStartedAt);
        } catch (e, st) {
          developer.log(
            'Migration add processingStartedAt failed',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(outbox, outbox.processingWorker);
        } catch (e, st) {
          developer.log(
            'Migration add processingWorker failed',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
      }
      if (from < 19) {
        try {
          await m.addColumn(bookings, bookings.vectorClock);
        } catch (e, st) {
          developer.log(
            'Migration add bookings.vectorClock failed',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(rooms, rooms.vectorClock);
        } catch (e, st) {
          developer.log(
            'Migration add rooms.vectorClock failed',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(employees, employees.vectorClock);
        } catch (e, st) {
          developer.log(
            'Migration add employees.vectorClock failed',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(expenses, expenses.vectorClock);
        } catch (e, st) {
          developer.log(
            'Migration add expenses.vectorClock failed',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(cashTransactions, cashTransactions.vectorClock);
        } catch (e, st) {
          developer.log(
            'Migration add cashTransactions.vectorClock failed',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(payments, payments.vectorClock);
        } catch (e, st) {
          developer.log(
            'Migration add payments.vectorClock failed',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(debts, debts.vectorClock);
        } catch (e, st) {
          developer.log(
            'Migration add debts.vectorClock failed',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(bookingNotes, bookingNotes.vectorClock);
        } catch (e, st) {
          developer.log(
            'Migration add bookingNotes.vectorClock failed',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(bookingNights, bookingNights.vectorClock);
        } catch (e, st) {
          developer.log(
            'Migration add bookingNights.vectorClock failed',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(hotelDayLedger, hotelDayLedger.vectorClock);
        } catch (e, st) {
          developer.log(
            'Migration add hotelDayLedger.vectorClock failed',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(salaryCycles, salaryCycles.vectorClock);
        } catch (e, st) {
          developer.log(
            'Migration add salaryCycles.vectorClock failed',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(salaryPayments, salaryPayments.vectorClock);
        } catch (e, st) {
          developer.log(
            'Migration add salaryPayments.vectorClock failed',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
      }
      if (from < 20) {
        // إصلاح مشكلة serverId في الجداول القديمة
        // التحقق من وجود عمود serverId في جدول rooms وإضافته إذا لم يكن موجوداً
        try {
          await m.database.customStatement(
            'SELECT serverId FROM rooms LIMIT 1',
          );
          developer.log(
            'serverId column already exists in rooms table',
            name: 'db.migration',
          );
        } catch (e) {
          // العمود غير موجود، نحتاج لإضافته
          try {
            await m.addColumn(rooms, rooms.serverId);
            developer.log(
              'Added serverId column to rooms table',
              name: 'db.migration',
            );
          } catch (e2, st2) {
            developer.log(
              'Failed to add serverId column to rooms',
              error: e2,
              stackTrace: st2,
              name: 'db.migration',
            );
          }
        }

        // التحقق من وجود عمود serverId في باقي الجداول
        final tablesToCheck = [
          'bookings',
          'employees',
          'expenses',
          'cash_transactions',
          'payments',
          'debts',
        ];

        for (final tableName in tablesToCheck) {
          try {
            await m.database.customStatement(
              'SELECT serverId FROM $tableName LIMIT 1',
            );
          } catch (e) {
            // العمود غير موجود
            try {
              await m.database.customStatement(
                'ALTER TABLE $tableName ADD COLUMN serverId INTEGER',
              );
              developer.log(
                'Added serverId column to $tableName table',
                name: 'db.migration',
              );
            } catch (e2, st2) {
              developer.log(
                'Failed to add serverId to $tableName',
                error: e2,
                stackTrace: st2,
                name: 'db.migration',
              );
            }
          }
        }
      }

      if (from < 21) {
        // إضافة حقول المزامنة لجدول الملاحظات
        await m.database.customStatement(
          'ALTER TABLE shift_notes RENAME TO shift_notes_old',
        );

        await m.createTable(shiftNotes);

        final oldNotes = await m.database
            .customSelect('SELECT * FROM shift_notes_old')
            .get();
        final now = DateTime.now();

        for (final row in oldNotes) {
          final uuid = const Uuid().v4();

          int createdTimestamp;
          final oldCreatedRaw = row.data['createdAt'];
          if (oldCreatedRaw is int) {
            createdTimestamp = oldCreatedRaw;
          } else if (oldCreatedRaw is String) {
            createdTimestamp =
                DateTime.tryParse(oldCreatedRaw)?.millisecondsSinceEpoch ??
                now.millisecondsSinceEpoch;
          } else {
            createdTimestamp = now.millisecondsSinceEpoch;
          }

          final isoDate = DateTime.fromMillisecondsSinceEpoch(
            createdTimestamp,
          ).toIso8601String();

          await m.database.customInsert(
            'INSERT INTO shift_notes ('
            'title, content, priority, shift_type, is_read, created_by, '
            'expires_at, '
            'localUuid, serverId, createdAt, updatedAt, deletedAt, lastModified, '
            'createdAt_iso, updatedAtIso, deletedAtIso, version, origin'
            ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            variables: [
              Variable<String>(row.data['title'] as String),
              Variable<String>(row.data['content'] as String),
              Variable<String>(row.data['priority'] as String),
              Variable<String>(row.data['shift_type'] as String),
              Variable<int>(row.data['is_read'] as int),
              Variable<String>(row.data['created_by'] as String),
              Variable<String>(row.data['expires_at'] as String?),
              Variable<String>(uuid),
              const Variable<int>(null),
              Variable<int>(createdTimestamp),
              Variable<int>(createdTimestamp),
              const Variable<int>(null),
              Variable<int>(createdTimestamp),
              Variable<String>(isoDate),
              Variable<String>(isoDate),
              const Variable<String>(null),
              const Variable<int>(1),
              const Variable<String>('local'),
            ],
          );
        }

        await m.database.customStatement('DROP TABLE shift_notes_old');
      }

      if (from < 22) {
        // إضافة حقل التخفيض للحجوزات
        await m.addColumn(bookings, bookings.discount);
      }
      if (from < 23) {
        // إضافة حقل نوع التخفيض (total أو per_night)
        await m.addColumn(bookings, bookings.discountType);
      }
      if (from < 24) {
        // Migration 24: تحويل المبالغ المالية من REAL إلى INTEGER
        // وإضافة جدول BookingPriceAdjustments

        // 1. إنشاء جداول التعديلات والسجلات
        try {
          await m.createTable(bookingPriceAdjustments);
        } catch (e) {
          developer.log(
            'Migration 24: create bookingPriceAdjustments failed: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.createTable(priceAdjustments);
        } catch (e) {
          developer.log(
            'Migration 24: create priceAdjustments failed: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.createTable(auditLogs);
        } catch (e) {
          developer.log(
            'Migration 24: create auditLogs failed: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.createTable(paymentVoids);
        } catch (e) {
          developer.log(
            'Migration 24: create paymentVoids failed: $e',
            name: 'db.migration',
          );
        }

        // 2. تحويل المبالغ في الجداول الموجودة من REAL إلى INTEGER
        // نستخدم CAST للتحويل مع تقريب القيم

        // rooms.price
        try {
          await m.database.customStatement(
            'UPDATE rooms SET price = CAST(ROUND(price) AS INTEGER) WHERE price IS NOT NULL',
          );
        } catch (e) {
          developer.log(
            'Migration 24: rooms.price conversion failed: $e',
            name: 'db.migration',
          );
        }

        // bookings cached fields
        try {
          await m.database.customStatement(
            'UPDATE bookings SET '
            'discount = CAST(ROUND(discount) AS INTEGER), '
            'total_due_cached = CAST(ROUND(total_due_cached) AS INTEGER), '
            'total_paid_cached = CAST(ROUND(total_paid_cached) AS INTEGER), '
            'remaining_balance_cached = CAST(ROUND(remaining_balance_cached) AS INTEGER) '
            'WHERE 1=1',
          );
        } catch (e) {
          developer.log(
            'Migration 24: bookings conversion failed: $e',
            name: 'db.migration',
          );
        }

        // employees.basic_salary
        try {
          await m.database.customStatement(
            'UPDATE employees SET basic_salary = CAST(ROUND(basic_salary) AS INTEGER) WHERE basic_salary IS NOT NULL',
          );
        } catch (e) {
          developer.log(
            'Migration 24: employees conversion failed: $e',
            name: 'db.migration',
          );
        }

        // expenses.amount
        try {
          await m.database.customStatement(
            'UPDATE expenses SET amount = CAST(ROUND(amount) AS INTEGER) WHERE amount IS NOT NULL',
          );
        } catch (e) {
          developer.log(
            'Migration 24: expenses conversion failed: $e',
            name: 'db.migration',
          );
        }

        // cash_transactions.amount
        try {
          await m.database.customStatement(
            'UPDATE cash_transactions SET amount = CAST(ROUND(amount) AS INTEGER) WHERE amount IS NOT NULL',
          );
        } catch (e) {
          developer.log(
            'Migration 24: cash_transactions conversion failed: $e',
            name: 'db.migration',
          );
        }

        // payments.amount
        try {
          await m.database.customStatement(
            'UPDATE payments SET amount = CAST(ROUND(amount) AS INTEGER) WHERE amount IS NOT NULL',
          );
        } catch (e) {
          developer.log(
            'Migration 24: payments conversion failed: $e',
            name: 'db.migration',
          );
        }

        // debts amounts
        try {
          await m.database.customStatement(
            'UPDATE debts SET '
            'total_amount = CAST(ROUND(total_amount) AS INTEGER), '
            'paid_amount = CAST(ROUND(paid_amount) AS INTEGER), '
            'remaining_amount = CAST(ROUND(remaining_amount) AS INTEGER) '
            'WHERE 1=1',
          );
        } catch (e) {
          developer.log(
            'Migration 24: debts conversion failed: $e',
            name: 'db.migration',
          );
        }

        // booking_nights.nightly_rate + إضافة الأعمدة الجديدة
        try {
          await m.database.customStatement(
            'UPDATE booking_nights SET nightly_rate = CAST(ROUND(nightly_rate) AS INTEGER) WHERE nightly_rate IS NOT NULL',
          );
        } catch (e) {
          developer.log(
            'Migration 24: booking_nights.nightly_rate conversion failed: $e',
            name: 'db.migration',
          );
        }

        // إضافة أعمدة BookingNights الجديدة (baseRate, adjustment, finalRate)
        try {
          await m.addColumn(bookingNights, bookingNights.baseRate);
        } catch (e) {
          developer.log(
            'Migration 24: add baseRate failed: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(bookingNights, bookingNights.adjustment);
        } catch (e) {
          developer.log(
            'Migration 24: add adjustment failed: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(bookingNights, bookingNights.finalRate);
        } catch (e) {
          developer.log(
            'Migration 24: add finalRate failed: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(bookingNights, bookingNights.appliedAdjustmentUuid);
        } catch (e) {
          developer.log(
            'Migration 24: add appliedAdjustmentUuid failed: $e',
            name: 'db.migration',
          );
        }

        // تحديث القيم الافتراضية للأعمدة الجديدة
        try {
          await m.database.customStatement(
            'UPDATE booking_nights SET '
            'base_rate = COALESCE(nightly_rate, 0), '
            'adjustment = 0, '
            'final_rate = COALESCE(nightly_rate, 0) '
            'WHERE base_rate IS NULL OR base_rate = 0',
          );
        } catch (e) {
          developer.log(
            'Migration 24: booking_nights defaults failed: $e',
            name: 'db.migration',
          );
        }

        // hotel_day_ledger amounts
        try {
          await m.database.customStatement(
            'UPDATE hotel_day_ledger SET '
            'total_income = CAST(ROUND(total_income) AS INTEGER), '
            'total_expenses = CAST(ROUND(total_expenses) AS INTEGER), '
            'pending_balances = CAST(ROUND(pending_balances) AS INTEGER), '
            'occupancy_rate = CAST(ROUND(occupancy_rate) AS INTEGER) '
            'WHERE 1=1',
          );
        } catch (e) {
          developer.log(
            'Migration 24: hotel_day_ledger conversion failed: $e',
            name: 'db.migration',
          );
        }

        // price_adjustments amounts
        try {
          await m.database.customStatement(
            'UPDATE price_adjustments SET '
            'previous_value = CAST(ROUND(previous_value) AS INTEGER), '
            'new_value = CAST(ROUND(new_value) AS INTEGER) '
            'WHERE 1=1',
          );
        } catch (e) {
          developer.log(
            'Migration 24: price_adjustments conversion failed: $e',
            name: 'db.migration',
          );
        }

        // payment_voids.voided_amount
        try {
          await m.database.customStatement(
            'UPDATE payment_voids SET voided_amount = CAST(ROUND(voided_amount) AS INTEGER) WHERE voided_amount IS NOT NULL',
          );
        } catch (e) {
          developer.log(
            'Migration 24: payment_voids conversion failed: $e',
            name: 'db.migration',
          );
        }

        // salary_cycles amounts
        try {
          await m.database.customStatement(
            'UPDATE salary_cycles SET '
            'expected_amount = CAST(ROUND(expected_amount) AS INTEGER), '
            'actual_paid = CAST(ROUND(actual_paid) AS INTEGER), '
            'remaining_amount = CAST(ROUND(remaining_amount) AS INTEGER) '
            'WHERE 1=1',
          );
        } catch (e) {
          developer.log(
            'Migration 24: salary_cycles conversion failed: $e',
            name: 'db.migration',
          );
        }

        // salary_payments.amount
        try {
          await m.database.customStatement(
            'UPDATE salary_payments SET amount = CAST(ROUND(amount) AS INTEGER) WHERE amount IS NOT NULL',
          );
        } catch (e) {
          developer.log(
            'Migration 24: salary_payments conversion failed: $e',
            name: 'db.migration',
          );
        }

        // audit_logs.amount_impact
        try {
          await m.database.customStatement(
            'UPDATE audit_logs SET amount_impact = CAST(ROUND(amount_impact) AS INTEGER) WHERE amount_impact IS NOT NULL',
          );
        } catch (e) {
          developer.log(
            'Migration 24: audit_logs conversion failed: $e',
            name: 'db.migration',
          );
        }

        // إضافة حقل discountStartDate للحجوزات إذا لم يكن موجوداً
        try {
          await m.addColumn(bookings, bookings.discountStartDate);
        } catch (e) {
          developer.log(
            'Migration 24: add discountStartDate already exists or failed: $e',
            name: 'db.migration',
          );
        }
      }
      if (from < 25) {
        try {
          await m.addColumn(
            bookingNights,
            bookingNights.appliedAdjustmentsJson,
          );
        } catch (e) {
          developer.log(
            'Migration 25: add appliedAdjustmentsJson failed: $e',
            name: 'db.migration',
          );
        }
      }
      if (from < 26) {
        try {
          await m.addColumn(
            bookingPriceAdjustments,
            bookingPriceAdjustments.adjustmentMode,
          );
          developer.log(
            'Migration 26: added adjustmentMode column to booking_price_adjustments',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 26: add adjustmentMode failed: $e',
            name: 'db.migration',
          );
        }
      }
      if (from < 27) {
        try {
          await m.addColumn(outbox, outbox.remotePayload);
          await m.addColumn(bookings, bookings.financialHash);
          await m.addColumn(bookings, bookings.financialFrozenAt);
          developer.log(
            'Migration 27: added remotePayload to outbox, financialHash/financialFrozenAt to bookings',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log('Migration 27 failed: $e', name: 'db.migration');
        }
      }
      if (from < 28) {
        try {
          await m.createTable(guestInfos);
          developer.log(
            'Migration 28: created guest_infos table',
            name: 'db.migration',
          );
        } catch (e, st) {
          developer.log(
            'Migration 28 failed: $e',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
      }
      if (from < 29) {
        // Migration 29: إضافة جدول سحوبات الرواتب للمزامنة
        try {
          // محاولة ترحيل البيانات من الجدول القديم إن وجد
          final oldTableExists = await m.database
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='salary_withdrawals'",
              )
              .get();

          if (oldTableExists.isNotEmpty) {
            // الجدول القديم موجود، نحتاج لترحيل البيانات
            await m.database.customStatement(
              'ALTER TABLE salary_withdrawals RENAME TO salary_withdrawals_old',
            );
          }

          // إنشاء الجدول الجديد مع حقول المزامنة
          await m.createTable(salaryWithdrawals);

          // ترحيل البيانات القديمة إن وجدت
          if (oldTableExists.isNotEmpty) {
            final oldData = await m.database
                .customSelect('SELECT * FROM salary_withdrawals_old')
                .get();

            for (final row in oldData) {
              final uuid = const Uuid().v4();
              final now = DateTime.now().millisecondsSinceEpoch;
              final dateStr = DateTime.now().toIso8601String();

              await m.database.customInsert(
                'INSERT INTO salary_withdrawals ('
                'expense_id, employee_id, action, amount, note, date, '
                'localUuid, serverId, createdAt, updatedAt, deletedAt, lastModified, '
                'createdAt_iso, updatedAtIso, deletedAtIso, version, origin'
                ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                variables: [
                  Variable<int>(row.data['expense_id'] as int? ?? 0),
                  Variable<int>(row.data['employee_id'] as int),
                  Variable<String>(row.data['action'] as String),
                  Variable<int>((row.data['amount'] as num?)?.toInt() ?? 0),
                  Variable<String>(row.data['note'] as String? ?? ''),
                  Variable<String>(row.data['date'] as String),
                  Variable<String>(uuid),
                  const Variable<int>(0),
                  Variable<int>(now),
                  Variable<int>(now),
                  const Variable<int>(0),
                  Variable<int>(now),
                  Variable<String>(dateStr),
                  Variable<String>(dateStr),
                  const Variable<String>(''),
                  const Variable<int>(1),
                  const Variable<String>('local'),
                ],
              );
            }

            // حذف الجدول القديم
            await m.database.customStatement(
              'DROP TABLE salary_withdrawals_old',
            );
          }

          developer.log(
            'Migration 29: created salary_withdrawals table with sync fields',
            name: 'db.migration',
          );
        } catch (e, st) {
          developer.log(
            'Migration 29 failed: $e',
            error: e,
            stackTrace: st,
            name: 'db.migration',
          );
        }
      }
      if (from < 30) {
        // Migration 30: تحويل RealColumn إلى IntColumn للمبالغ
        developer.log(
          'Migration 30: Converting amount fields from REAL to INTEGER',
          name: 'db.migration',
        );

        // expenses.amount
        try {
          await m.database.customStatement(
            'UPDATE expenses SET amount = CAST(ROUND(amount) AS INTEGER) WHERE amount IS NOT NULL',
          );
        } catch (e) {
          developer.log(
            'Migration 30: expenses.amount failed: $e',
            name: 'db.migration',
          );
        }

        // cash_transactions.amount
        try {
          await m.database.customStatement(
            'UPDATE cash_transactions SET amount = CAST(ROUND(amount) AS INTEGER) WHERE amount IS NOT NULL',
          );
        } catch (e) {
          developer.log(
            'Migration 30: cash_transactions.amount failed: $e',
            name: 'db.migration',
          );
        }

        // payments.amount
        try {
          await m.database.customStatement(
            'UPDATE payments SET amount = CAST(ROUND(amount) AS INTEGER) WHERE amount IS NOT NULL',
          );
        } catch (e) {
          developer.log(
            'Migration 30: payments.amount failed: $e',
            name: 'db.migration',
          );
        }

        // debts
        try {
          await m.database.customStatement(
            'UPDATE debts SET total_amount = CAST(ROUND(total_amount) AS INTEGER), paid_amount = CAST(ROUND(paid_amount) AS INTEGER), remaining_amount = CAST(ROUND(remaining_amount) AS INTEGER) WHERE total_amount IS NOT NULL OR paid_amount IS NOT NULL OR remaining_amount IS NOT NULL',
          );
        } catch (e) {
          developer.log(
            'Migration 30: debts amounts failed: $e',
            name: 'db.migration',
          );
        }

        // hotel_day_ledger
        try {
          await m.database.customStatement(
            'UPDATE hotel_day_ledger SET total_income = CAST(ROUND(total_income) AS INTEGER), total_expenses = CAST(ROUND(total_expenses) AS INTEGER), pending_balances = CAST(ROUND(pending_balances) AS INTEGER)',
          );
        } catch (e) {
          developer.log(
            'Migration 30: hotel_day_ledger failed: $e',
            name: 'db.migration',
          );
        }

        // booking_price_adjustments.amount
        try {
          await m.database.customStatement(
            'UPDATE booking_price_adjustments SET amount = CAST(ROUND(amount) AS INTEGER) WHERE amount IS NOT NULL',
          );
        } catch (e) {
          developer.log(
            'Migration 30: booking_price_adjustments.amount failed: $e',
            name: 'db.migration',
          );
        }

        developer.log(
          'Migration 30: completed converting amount fields',
          name: 'db.migration',
        );
      }
      if (from < 31) {
        // Migration 31: تحويل أسماء الأعمدة من snake_case إلى camelCase
        // هذا يضمن التوافق مع الكود المُحسّن
        developer.log(
          'Migration 31: Converting snake_case columns to camelCase',
          name: 'db.migration',
        );

        try {
          // SnakeToCamelMigration removed - now using camelCase consistently
          developer.log(
            'Migration 31: skipped snake_case to camelCase conversion (now using camelCase consistently)',
            name: 'db.migration',
          );
        } catch (e, st) {
          developer.log(
            'Migration 31: failed - $e',
            name: 'db.migration',
            error: e,
            stackTrace: st,
          );
        }
      }
      if (from < 32) {
        // Migration 32: إضافة حقول جديدة لجدول Outbox لتحسين المزامنة
        developer.log(
          'Migration 32: Adding enhanced Outbox fields for better sync',
          name: 'db.migration',
        );

        try {
          // إضافة حقل nextRetryAt للمحاولات المؤجلة
          await m.addColumn(outbox, outbox.nextRetryAt);
          developer.log(
            'Migration 32: added nextRetryAt to outbox',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 32: nextRetryAt already exists or failed: $e',
            name: 'db.migration',
          );
        }

        try {
          // إضافة حقل maxAttempts لتحديد أقصى عدد محاولات
          await m.addColumn(outbox, outbox.maxAttempts);
          developer.log(
            'Migration 32: added maxAttempts to outbox',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 32: maxAttempts already exists or failed: $e',
            name: 'db.migration',
          );
        }

        try {
          // إضافة حقل priority للأولوية
          await m.addColumn(outbox, outbox.priority);
          developer.log(
            'Migration 32: added priority to outbox',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 32: priority already exists or failed: $e',
            name: 'db.migration',
          );
        }

        try {
          // إضافة حقل lastSuccessfulPushAt لتتبع آخر رفع ناجح
          await m.addColumn(outbox, outbox.lastSuccessfulPushAt);
          developer.log(
            'Migration 32: added lastSuccessfulPushAt to outbox',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 32: lastSuccessfulPushAt already exists or failed: $e',
            name: 'db.migration',
          );
        }

        // إنشاء الفهارس الجديدة
        try {
          await m.database.customStatement(
            'CREATE INDEX IF NOT EXISTS idx_outbox_status_priority ON outbox (processing_status, priority, next_retry_at)',
          );
          await m.database.customStatement(
            'CREATE INDEX IF NOT EXISTS idx_outbox_entity_uuid ON outbox (entity, local_uuid)',
          );
          developer.log(
            'Migration 32: created outbox indexes',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 32: index creation failed: $e',
            name: 'db.migration',
          );
        }

        developer.log(
          'Migration 32: completed enhanced Outbox fields',
          name: 'db.migration',
        );
      }
      if (from < 33) {
        // Migration 33: إضافة UNIQUE constraint لـ expenseId في salary_withdrawals
        developer.log(
          'Migration 33: Adding UNIQUE constraint to salary_withdrawals.expenseId',
          name: 'db.migration',
        );

        try {
          // إعادة إنشاء الجدول مع UNIQUE constraint (camelCase columns)
          await m.database.customStatement('''
                CREATE TABLE IF NOT EXISTS salary_withdrawals_new (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  expenseId INTEGER UNIQUE,
                  employeeId INTEGER,
                  action TEXT,
                  amount REAL,
                  note TEXT,
                  date TEXT,
                  localUuid TEXT,
                  serverId INTEGER,
                  createdAt INTEGER,
                  updatedAt INTEGER,
                  deletedAt INTEGER,
                  lastModified INTEGER,
                  createdAtIso TEXT,
                  updatedAtIso TEXT,
                  deletedAtIso TEXT,
                  version INTEGER,
                  origin TEXT
                )
              ''');

          // نسخ البيانات القديمة مع تحويل أسماء الأعمدة من snake_case إلى camelCase
          await m.database.customStatement('''
                INSERT INTO salary_withdrawals_new (
                  id, expenseId, employeeId, action, amount, note, date,
                  localUuid, serverId, createdAt, updatedAt, deletedAt,
                  lastModified, createdAtIso, updatedAtIso, deletedAtIso, version, origin
                )
                SELECT 
                  id, expense_id, employee_id, action, amount, note, date,
                  local_uuid, server_id, created_at, updated_at, deleted_at,
                  last_modified, created_at_iso, updated_at_iso, deleted_at_iso, version, origin
                FROM salary_withdrawals
              ''');

          // حذف الجدول القديم
          await m.database.customStatement('DROP TABLE salary_withdrawals');

          // إعادة تسمية الجدول الجديد
          await m.database.customStatement(
            'ALTER TABLE salary_withdrawals_new RENAME TO salary_withdrawals',
          );

          // إعادة إنشاء الفهارس (camelCase)
          await m.database.customStatement(
            'CREATE INDEX IF NOT EXISTS idx_salary_withdrawals_employee ON salary_withdrawals (employeeId, date)',
          );

          developer.log(
            'Migration 33: completed adding UNIQUE constraint and converting to camelCase',
            name: 'db.migration',
          );
        } catch (e, st) {
          developer.log(
            'Migration 33: failed - $e',
            name: 'db.migration',
            error: e,
            stackTrace: st,
          );
        }
      }
      if (from < 34) {
        // Migration 34: إضافة حقول مفقودة للمزامنة مع Appwrite
        developer.log(
          'Migration 34: Adding missing fields for Appwrite sync compatibility',
          name: 'db.migration',
        );

        // إضافة حقل shiftDate لجدول shift_notes
        try {
          await m.addColumn(shiftNotes, shiftNotes.shiftDate);
          developer.log(
            'Migration 34: added shiftDate to shift_notes',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 34: shiftDate already exists or failed: $e',
            name: 'db.migration',
          );
        }

        // إضافة حقل employeeId لجدول salary_payments
        try {
          await m.addColumn(salaryPayments, salaryPayments.employeeId);
          developer.log(
            'Migration 34: added employeeId to salary_payments',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 34: employeeId already exists or failed: $e',
            name: 'db.migration',
          );
        }

        // إضافة vectorClock للجداول التي تفتقر إليه
        try {
          await m.addColumn(salaryPayments, salaryPayments.vectorClock);
          developer.log(
            'Migration 34: added vectorClock to salary_payments',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 34: salary_payments.vectorClock already exists: $e',
            name: 'db.migration',
          );
        }

        try {
          await m.addColumn(salaryCycles, salaryCycles.vectorClock);
          developer.log(
            'Migration 34: added vectorClock to salary_cycles',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 34: salary_cycles.vectorClock already exists: $e',
            name: 'db.migration',
          );
        }

        try {
          await m.addColumn(shiftNotes, shiftNotes.vectorClock);
          developer.log(
            'Migration 34: added vectorClock to shift_notes',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 34: shift_notes.vectorClock already exists: $e',
            name: 'db.migration',
          );
        }

        // إنشاء فهرس جديد لـ salary_payments
        try {
          await m.database.customStatement(
            'CREATE INDEX IF NOT EXISTS idx_salary_payments_employee ON salary_payments (employee_id, payment_date_iso)',
          );
          developer.log(
            'Migration 34: created salary_payments employee index',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 34: index creation failed: $e',
            name: 'db.migration',
          );
        }

        // تحديث shiftDate بقيمة افتراضية من createdAtIso
        try {
          await m.database.customStatement(
            'UPDATE shift_notes SET shift_date = created_at_iso WHERE shift_date IS NULL',
          );
          developer.log(
            'Migration 34: populated shiftDate from createdAtIso',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 34: shiftDate population failed: $e',
            name: 'db.migration',
          );
        }

        // إضافة حقول startDate و endDate لـ salary_cycles
        try {
          await m.addColumn(salaryCycles, salaryCycles.startDate);
          await m.addColumn(salaryCycles, salaryCycles.endDate);
          developer.log(
            'Migration 34: added startDate and endDate to salary_cycles',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 34: salary_cycles date fields failed: $e',
            name: 'db.migration',
          );
        }

        // تحديث startDate و endDate من hotelDayStart و hotelDayEnd
        try {
          await m.database.customStatement(
            'UPDATE salary_cycles SET start_date = hotel_day_start, end_date = hotel_day_end WHERE start_date IS NULL',
          );
          developer.log(
            'Migration 34: populated startDate/endDate from hotelDayStart/hotelDayEnd',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 34: salary_cycles date population failed: $e',
            name: 'db.migration',
          );
        }

        developer.log(
          'Migration 34: completed adding missing sync fields',
          name: 'db.migration',
        );
      }
      if (from < 35) {
        // Migration 35: إضافة جدول Field-Level Sync لتتبع نسخ الحقول
        developer.log(
          'Migration 35: Adding FieldVersions table for Field-Level Delta Sync',
          name: 'db.migration',
        );

        try {
          await m.createTable(fieldVersions);
          developer.log(
            'Migration 35: created field_versions table',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 35: field_versions table creation failed: $e',
            name: 'db.migration',
          );
        }

        // إنشاء الفهارس
        try {
          await m.database.customStatement(
            'CREATE INDEX IF NOT EXISTS idx_field_versions_entity_record ON field_versions (entity_name, record_uuid)',
          );
          await m.database.customStatement(
            'CREATE INDEX IF NOT EXISTS idx_field_versions_timestamp ON field_versions (timestamp DESC)',
          );
          developer.log(
            'Migration 35: created field_versions indexes',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 35: index creation failed: $e',
            name: 'db.migration',
          );
        }

        developer.log(
          'Migration 35: completed Field-Level Sync schema',
          name: 'db.migration',
        );
      }
      if (from < 36) {
        // Migration 36: ترحيل مصروفات الرواتب القديمة إلى النظام الجديد
        developer.log(
          'Migration 36: Migrating old salary expenses to new system',
          name: 'db.migration',
        );

        try {
          // 1. العثور على المصروفات التي تحتوي على expenseType = "سحب راتب" أو "خصم راتب"
          final oldSalaryExpenses = await m.database
              .customSelect(
                'SELECT id, relatedId, description, amount, date, localUuid, createdAt, updatedAt '
                "FROM expenses WHERE expenseType IN ('سحب راتب', 'خصم راتب', 'سحب من الراتب', 'خصم من الراتب')",
              )
              .get();

          developer.log(
            'Migration 36: Found ${oldSalaryExpenses.length} old salary expenses to migrate',
            name: 'db.migration',
          );

          // 2. تحديث expenseType إلى "رواتب"
          await m.database.customStatement(
            "UPDATE expenses SET expenseType = 'رواتب' WHERE expenseType IN ('سحب راتب', 'خصم راتب', 'سحب من الراتب', 'خصم من الراتب')",
          );

          // 3. إنشاء سجلات في salary_withdrawals للمصروفات التي لها relatedId (موظف)
          for (final row in oldSalaryExpenses) {
            final expenseId = row.data['id'] as int?;
            final employeeId = row.data['relatedId'] as int?;
            final description = row.data['description'] as String?;
            final amount = row.data['amount'] as double?;
            final date = row.data['date'] as String?;
            final localUuid = row.data['localUuid'] as String?;
            final createdAt = row.data['createdAt'] as int?;
            final updatedAt = row.data['updatedAt'] as int?;

            if (expenseId != null && employeeId != null && employeeId > 0) {
              // التحقق من عدم وجود سجل مسبق
              final existing = await m.database
                  .customSelect(
                    'SELECT id FROM salary_withdrawals WHERE expenseId = $expenseId',
                  )
                  .get();

              if (existing.isEmpty) {
                // تحديد نوع الإجراء من الوصف أو الافتراضي
                String action = 'سحب من الراتب';
                if (description != null) {
                  if (description.contains('خصم')) {
                    action = 'خصم من الراتب';
                  }
                }

                // إنشاء سجل جديد
                await m.database.customStatement(
                  'INSERT INTO salary_withdrawals '
                  '(expenseId, employeeId, action, amount, note, date, localUuid, createdAt, updatedAt, lastModified, version, origin) '
                  "VALUES ($expenseId, $employeeId, '$action', ${amount ?? 0}, '$description', '$date', '${localUuid ?? const Uuid().v4()}', ${createdAt ?? DateTime.now().millisecondsSinceEpoch}, ${updatedAt ?? DateTime.now().millisecondsSinceEpoch}, ${updatedAt ?? DateTime.now().millisecondsSinceEpoch}, 1, 'migration')",
                );
              }
            }
          }

          developer.log(
            'Migration 36: completed migrating old salary expenses',
            name: 'db.migration',
          );
        } catch (e, st) {
          developer.log(
            'Migration 36: failed - $e',
            name: 'db.migration',
            error: e,
            stackTrace: st,
          );
        }
      }
      if (from < 37) {
        // Migration 37: إنشاء جدول sync_mirror للمزامنة
        developer.log(
          'Migration 37: Creating sync_mirror table',
          name: 'db.migration',
        );
        try {
          await m.createTable(syncMirror);
          developer.log(
            'Migration 37: sync_mirror table created successfully',
            name: 'db.migration',
          );
        } catch (e, st) {
          developer.log(
            'Migration 37: failed - $e',
            name: 'db.migration',
            error: e,
            stackTrace: st,
          );
        }
      }
      if (from < 38) {
        // Migration 38: إضافة حقل name لجدول salary_withdrawals
        developer.log(
          'Migration 38: Adding name column to salary_withdrawals',
          name: 'db.migration',
        );
        try {
          await m.addColumn(
            salaryWithdrawals,
            salaryWithdrawals.name as GeneratedColumn<Object>,
          );
          developer.log(
            'Migration 38: name column added to salary_withdrawals',
            name: 'db.migration',
          );
        } catch (e, st) {
          developer.log(
            'Migration 38: failed - $e',
            name: 'db.migration',
            error: e,
            stackTrace: st,
          );
        }
      }
    },
  );

  /// تجميع جميع الجداول المطلوب مزامنتها في خريطة JSON
  ///
  /// ⭐ يتم تحويل جميع المفاتيح إلى camelCase للتوافق مع Google Drive و Appwrite
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
    final priceAdjustmentsData = await select(priceAdjustments).get();
    final auditLogsData = await select(auditLogs).get();
    final paymentVoidsData = await select(paymentVoids).get();
    final salaryWithdrawalsData = await select(salaryWithdrawals).get();

    // ⭐ تجميع البيانات بصيغة camelCase
    return {
      'rooms': roomsData.map((e) => e.toJson()).toList(),
      'bookings': bookingsData.map((e) => e.toJson()).toList(),
      'bookingNotes': bookingNotesData.map((e) => e.toJson()).toList(),
      'shiftNotes': shiftNotesData.map((e) => e.toJson()).toList(),
      'employees': employeesData.map((e) => e.toJson()).toList(),
      'guestInfos': guestInfosData.map((e) => e.toJson()).toList(),
      'expenses': expensesData.map((e) => e.toJson()).toList(),
      'cashTransactions': cashTransactionsData.map((e) => e.toJson()).toList(),
      'payments': paymentsData.map((e) => e.toJson()).toList(),
      'debts': debtsData.map((e) => e.toJson()).toList(),
      'bookingNights': bookingNightsData.map((e) => e.toJson()).toList(),
      'hotelDayLedger': ledgerData.map((e) => e.toJson()).toList(),
      'autoFixRuns': autoFixRunsData.map((e) => e.toJson()).toList(),
      'integrityViolations': violationsData.map((e) => e.toJson()).toList(),
      'appSessions': sessionsData.map((e) => e.toJson()).toList(),
      'salaryCycles': salaryCyclesData.map((e) => e.toJson()).toList(),
      'salaryPayments': salaryPaymentsData.map((e) => e.toJson()).toList(),
      'bookingPriceAdjustments': bookingPriceAdjustmentsData
          .map((e) => e.toJson())
          .toList(),
      'priceAdjustments': priceAdjustmentsData
          .map((e) => e.toJson())
          .toList(),
      'auditLogs': auditLogsData.map((e) => e.toJson()).toList(),
      'paymentVoids': paymentVoidsData.map((e) => e.toJson()).toList(),
      'salaryWithdrawals': salaryWithdrawalsData
          .map((e) => e.toJson())
          .toList(),
      'guests': <Map<String, dynamic>>[],
      'services': <Map<String, dynamic>>[],
      'settings': <Map<String, dynamic>>[],
    };
  }

  /// كشف صيغة البيانات (snake_case أو camelCase)
  String _detectDataFormat(Map<String, dynamic> data) {
    // فحص مفاتيح المستوى الأعلى
    for (final key in data.keys) {
      if (key.contains('_')) {
        return 'snake_case';
      }
      if (key.contains(RegExp('[A-Z]'))) {
        return 'camelCase';
      }
    }

    // فحص عينة من البيانات الداخلية
    for (final entry in data.entries) {
      if (entry.value is List) {
        final list = entry.value as List;
        if (list.isNotEmpty && list.first is Map) {
          final firstRow = list.first as Map;
          for (final key in firstRow.keys) {
            if (key.toString().contains('_')) {
              return 'snake_case';
            }
          }
        }
      }
    }

    return 'unknown';
  }

  /// تطبيع البيانات إلى camelCase
  Map<String, dynamic> _normalizeBackupData(Map<String, dynamic> data) {
    final result = <String, dynamic>{};

    for (final entry in data.entries) {
      var key = entry.key;
      final value = entry.value;

      // تحويل اسم الجدول إلى camelCase
      if (key.contains('_')) {
        key = _snakeToCamelCase(key);
      }

      if (value is List) {
        result[key] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return _normalizeRowKeys(item);
          }
          return item;
        }).toList();
      } else {
        result[key] = value;
      }
    }

    return result;
  }

  /// تحويل مفاتيح الصف إلى camelCase
  Map<String, dynamic> _normalizeRowKeys(Map<String, dynamic> row) {
    final result = <String, dynamic>{};
    for (final entry in row.entries) {
      final key = entry.key;
      if (key.contains('_')) {
        result[_snakeToCamelCase(key)] = entry.value;
      } else {
        result[key] = entry.value;
      }
    }
    return result;
  }

  /// تحويل snake_case إلى camelCase
  String _snakeToCamelCase(String input) {
    return input.replaceAllMapped(
      RegExp('_([a-z])'),
      (match) => match.group(1)!.toUpperCase(),
    );
  }

  /// تحويل أسماء الجداول من camelCase إلى snake_case
  /// ⭐ Drift يتوقع snake_case لأسماء الجداول
  Map<String, dynamic> _convertTableNamesToSnakeCase(
    Map<String, dynamic> data,
  ) {
    // جدول تحويل أسماء الجداول
    const tableNamesMap = {
      'rooms': 'rooms',
      'bookings': 'bookings',
      'bookingNotes': 'booking_notes',
      'shiftNotes': 'shift_notes',
      'employees': 'employees',
      'guestInfos': 'guest_infos',
      'expenses': 'expenses',
      'cashTransactions': 'cash_transactions',
      'payments': 'payments',
      'debts': 'debts',
      'bookingNights': 'booking_nights',
      'hotelDayLedger': 'hotel_day_ledger',
      'autoFixRuns': 'auto_fix_runs',
      'integrityViolations': 'integrity_violations',
      'appSessions': 'app_sessions',
      'salaryCycles': 'salary_cycles',
      'salaryPayments': 'salary_payments',
      'salaryWithdrawals': 'salary_withdrawals',
      'bookingPriceAdjustments': 'booking_price_adjustments',
      'priceAdjustments': 'price_adjustments',
      'auditLogs': 'audit_logs',
      'paymentVoids': 'payment_voids',
      'guests': 'guests',
      'services': 'services',
      'settings': 'settings',
    };

    final result = <String, dynamic>{};

    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;

      // تحويل اسم الجدول إلى snake_case
      final newKey = tableNamesMap[key] ?? key;
      result[newKey] = value;
    }

    return result;
  }

  /// تطبيق البيانات المدمجة على قاعدة البيانات المحلية داخل معاملة واحدة
  ///
  /// ⭐ نظام ذكي للتحويل التلقائي:
  /// - يكتشف صيغة البيانات الواردة (snake_case أو camelCase)
  /// - يحول snake_case القديم إلى camelCase تلقائياً
  /// - يتوافق مع النسخ الاحتياطية القديمة والجديدة
  Future<void> applyMergedData(Map<String, dynamic> merged) async {
    if (merged.isEmpty) {
      developer.log(
        'applyMergedData: merged snapshot is empty. Skipping apply to avoid wiping local data.',
        name: 'AppDatabase',
        level: 900,
      );
      return;
    }

    // ⭐ معالجة ذكية للبيانات الواردة
    // يكتشف الصيغة ويحولها تلقائياً
    final detectedFormat = _detectDataFormat(merged);
    developer.log(
      'applyMergedData: Detected format: $detectedFormat',
      name: 'AppDatabase',
    );

    // ⭐ تطبيع البيانات إلى camelCase
    final normalizedData = _normalizeBackupData(merged);

    // ⭐ تحويل أسماء الجداول من camelCase إلى snake_case (لأن Drift يستخدم snake_case)
    final snakeCaseData = _convertTableNamesToSnakeCase(normalizedData);

    List<Map<String, dynamic>>? asListIfPresent(String key) {
      if (!snakeCaseData.containsKey(key)) {
        return null;
      }
      final value = snakeCaseData[key];
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
      // تعطيل foreign key constraints مؤقتاً لتجنب مشاكل الحذف
      await customStatement('PRAGMA foreign_keys = OFF');

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

      await replaceTableIfNonEmpty<Room>(rooms, 'rooms', Room.fromJson);
      await replaceTableIfNonEmpty<Booking>(
        bookings,
        'bookings',
        Booking.fromJson,
      );
      await replaceTableIfNonEmpty<BookingNote>(
        bookingNotes,
        'booking_notes',
        BookingNote.fromJson,
      );
      await replaceTableIfNonEmpty<ShiftNote>(
        shiftNotes,
        'shift_notes',
        ShiftNote.fromJson,
      );
      await replaceTableIfNonEmpty<Employee>(
        employees,
        'employees',
        Employee.fromJson,
      );
      await replaceTableIfNonEmpty<Expense>(
        expenses,
        'expenses',
        Expense.fromJson,
      );
      await replaceTableIfNonEmpty<CashTransaction>(
        cashTransactions,
        'cash_transactions',
        CashTransaction.fromJson,
      );
      await replaceTableIfNonEmpty<Payment>(
        payments,
        'payments',
        Payment.fromJson,
      );
      await replaceTableIfNonEmpty<Debt>(debts, 'debts', Debt.fromJson);
      await replaceTableIfNonEmpty<BookingNight>(
        bookingNights,
        'booking_nights',
        BookingNight.fromJson,
      );
      await replaceTableIfNonEmpty<HotelDayLedgerEntry>(
        hotelDayLedger,
        'hotel_day_ledger',
        HotelDayLedgerEntry.fromJson,
      );
      await replaceTableIfNonEmpty<AutoFixRun>(
        autoFixRuns,
        'auto_fix_runs',
        AutoFixRun.fromJson,
      );
      await replaceTableIfNonEmpty<IntegrityViolation>(
        integrityViolations,
        'integrity_violations',
        IntegrityViolation.fromJson,
      );
      await replaceTableIfNonEmpty<AppSession>(
        appSessions,
        'app_sessions',
        AppSession.fromJson,
      );
      await replaceTableIfNonEmpty<SalaryCycle>(
        salaryCycles,
        'salary_cycles',
        SalaryCycle.fromJson,
      );
      await replaceTableIfNonEmpty<SalaryPayment>(
        salaryPayments,
        'salary_payments',
        SalaryPayment.fromJson,
      );
      await replaceTableIfNonEmpty<BookingPriceAdjustment>(
        bookingPriceAdjustments,
        'booking_price_adjustments',
        BookingPriceAdjustment.fromJson,
      );

      // إعادة تفعيل foreign key constraints
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
  double get salary =>
      basicSalary; // basicSalary is already a double (RealColumn)
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

  static Future<String> get databasePath async {
    final dbDir = await sqflite.getDatabasesPath();
    return p.join(dbDir, _dbFileName);
  }

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
