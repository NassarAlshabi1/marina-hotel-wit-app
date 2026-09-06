import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:uuid/uuid.dart';

import '../data/sync_models.dart' as sync_models;
import '../utils/weak_device_optimizer.dart';

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
  TextColumn get deviceId => text().withDefault(const Constant(''))();
  IntColumn get syncTimestamp => integer().withDefault(const Constant(0))();
  // ✅ v2: مفتاح إزالة التكرار (idempotency) — يمنع تكرار العمليات عبر الأجهزة
  TextColumn get idempotencyKey => text().nullable()();
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
  IntColumn get financialFrozenAt => integer().nullable()();
  TextColumn get financialHash => text().nullable()();

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
    Index(
      'idx_bookings_deleted',
      'CREATE INDEX idx_bookings_deleted ON bookings (deleted_at)',
    ),
    Index(
      'idx_bookings_checkin',
      'CREATE INDEX idx_bookings_checkin ON bookings (checkin_date)',
    ),
    Index(
      'idx_bookings_active_checkin',
      'CREATE INDEX idx_bookings_active_checkin ON bookings (checkin_date DESC) WHERE deleted_at IS NULL',
    ),
  ];
}

class BookingNotes extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookingId => integer().references(Bookings, #id)();
  TextColumn get noteText => text()();
  TextColumn get alertType => text()();
  TextColumn get alertUntil => text().nullable()();
  // ⚠️ TODO: IntColumn بدلاً من BoolColumn — يتطلب ترحيل و إعادة توليد الكود
  IntColumn get isActive => integer().withDefault(const Constant(1))();

  List<Index> get indexes => [
    Index(
      'idx_booking_notes_booking',
      'CREATE INDEX idx_booking_notes_booking ON booking_notes (booking_id)',
    ),
  ];
}

class Employees extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  RealColumn get basicSalary => real()();
  TextColumn get position => text().withDefault(const Constant('موظف'))();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get hireDate => text().withDefault(const Constant(''))();
  TextColumn get status => text()();
  TextColumn get terminationDate => text().nullable()();
  TextColumn get terminationReason => text().nullable()();
  // ✅ v2: معرّف الموظف الإداري (رقم الهوية / الرقم الوظيفي)
  TextColumn get employeeID => text().nullable()();

  // فهرس لتسريع البحث بالاسم والحالة
  List<Index> get indexes => [
    Index(
      'idx_employees_name',
      'CREATE INDEX idx_employees_name ON employees (name)',
    ),
    Index(
      'idx_employees_status',
      'CREATE INDEX idx_employees_status ON employees (status)',
    ),
  ];
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
  // ✅ v2: UUID الموظف المرتبط (لمصروفات الرواتب والسلف)
  TextColumn get employeeUuid => text().nullable()();

  List<Index> get indexes => [
    Index(
      'idx_expenses_hotel_day',
      'CREATE INDEX idx_expenses_hotel_day ON expenses (hotel_day_key)',
    ),
    Index(
      'idx_expenses_category',
      'CREATE INDEX idx_expenses_category ON expenses (category_uuid)',
    ),
    Index(
      'idx_expenses_date',
      'CREATE INDEX idx_expenses_date ON expenses (date)',
    ),
    Index(
      'idx_expenses_active_hotel_day',
      'CREATE INDEX idx_expenses_active_hotel_day ON expenses (hotel_day_key, expense_type, date) WHERE deleted_at IS NULL',
    ),
    Index(
      'idx_expenses_legacy_active_date',
      'CREATE INDEX idx_expenses_legacy_active_date ON expenses (date) WHERE hotel_day_key IS NULL AND deleted_at IS NULL',
    ),
    Index(
      'idx_expenses_active_date',
      'CREATE INDEX idx_expenses_active_date ON expenses (date DESC) WHERE deleted_at IS NULL',
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

  // فهارس لتسريع البحث بوقت المعاملة والنوع
  List<Index> get indexes => [
    Index(
      'idx_cash_trans_type_time',
      'CREATE INDEX idx_cash_trans_type_time ON cash_transactions (transaction_type, transaction_time)',
    ),
    Index(
      'idx_cash_trans_ref',
      'CREATE INDEX idx_cash_trans_ref ON cash_transactions (reference_type, reference_id)',
    ),
  ];
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
  RealColumn get discountAmount => real().nullable()();
  TextColumn get discountStartDate => text().nullable()();
  BoolColumn get isVoided => boolean().withDefault(const Constant(false))();
  IntColumn get voidedAt => integer().nullable()();
  TextColumn get voidedBy => text().nullable()();
  TextColumn get voidReason => text().nullable()();
  BoolColumn get isImmutable => boolean().withDefault(const Constant(false))();
  // هوية الموظف وجلسة تسجيل الدخول التي استلمت الدفعة.
  // Nullable للتوافق مع السجلات القديمة قبل تفعيل الخيار A.
  IntColumn get receivedByUserId => integer().nullable()();
  TextColumn get receivedByName => text().nullable()();
  TextColumn get receivedSessionUuid => text().nullable()();
  // معرّف مستخدم Appwrite Cloud الثابت بين الأجهزة.
  TextColumn get receivedByCloudId => text().nullable()();

  List<Index> get indexes => [
    Index(
      'idx_payments_booking',
      'CREATE INDEX idx_payments_booking ON payments (booking_local_id, hotel_day_key)',
    ),
    Index(
      'idx_payments_room_day',
      'CREATE INDEX idx_payments_room_day ON payments (room_number, hotel_day_key)',
    ),
    Index(
      'idx_payments_date',
      'CREATE INDEX idx_payments_date ON payments (payment_date)',
    ),
    Index(
      'idx_payments_revenue',
      'CREATE INDEX idx_payments_revenue ON payments (revenue_type, hotel_day_key)',
    ),
    Index(
      'idx_payments_void',
      'CREATE INDEX idx_payments_void ON payments (is_voided)',
    ),
    Index(
      'idx_payments_method',
      'CREATE INDEX idx_payments_method ON payments (payment_method)',
    ),
    Index(
      'idx_payments_active_hotel_day',
      'CREATE INDEX idx_payments_active_hotel_day ON payments (hotel_day_key, revenue_type, payment_date) WHERE deleted_at IS NULL AND is_voided = 0',
    ),
    Index(
      'idx_payments_legacy_active_date',
      'CREATE INDEX idx_payments_legacy_active_date ON payments (payment_date) WHERE hotel_day_key IS NULL AND deleted_at IS NULL AND is_voided = 0',
    ),
    Index(
      'idx_payments_active_report_date',
      'CREATE INDEX idx_payments_active_report_date ON payments (payment_date DESC) WHERE deleted_at IS NULL AND is_voided = 0 AND is_pending_balance = 0',
    ),
    Index(
      'idx_payments_active_receiver_session',
      'CREATE INDEX idx_payments_active_receiver_session ON payments (received_by_user_id, received_session_uuid, hotel_day_key) WHERE deleted_at IS NULL AND is_voided = 0 AND is_pending_balance = 0',
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
  // ⚠️ TODO: IntColumn بدلاً من BoolColumn — يتطلب ترحيل و إعادة توليد الكود
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
  TextColumn get guestPhone => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().nullable()();
  TextColumn get dueDate => text().nullable()();

  /// ✅ Wave 6 (2026-08-12): حقول إضافية مطلوبة من Appwrite Cloud.
  /// موجودة في schemaAttributeTypes و filterPayload لـ debts لكنها
  /// كانت مفقودة من الـ Drift table — مما يمنع الـ push و pull.
  /// انظر appwrite_sync_utils.dart:362-411 (whitelist) و
  /// appwrite_schema_verifier.dart:301-304 (Cloud schema).
  TextColumn get bookingUuidCache => text().nullable()();
  TextColumn get debtorName => text().nullable()();
  RealColumn get amount => real().nullable()();
  TextColumn get date => text().nullable()();

  List<Index> get indexes => [
    Index(
      'idx_debts_status',
      'CREATE INDEX idx_debts_status ON debts (is_settled, is_from_auto_fix)',
    ),
    Index(
      'idx_debts_guest',
      'CREATE INDEX idx_debts_guest ON debts (guest_name)',
    ),
    Index(
      'idx_debts_booking',
      'CREATE INDEX idx_debts_booking ON debts (booking_local_id)',
    ),
    Index(
      'idx_debts_payment_date',
      'CREATE INDEX idx_debts_payment_date ON debts (payment_date)',
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
  // ⚠️ TODO: IntColumn بدلاً من BoolColumn — يتطلب ترحيل و إعادة توليد الكود
  IntColumn get isRead =>
      integer().withDefault(const Constant(0))(); // 0 = غير مقروء، 1 = مقروء
  // createdAt موجود في SyncFields كـ integer
  TextColumn get expiresAt => text().nullable()();
  TextColumn get createdBy => text().withDefault(const Constant('user'))();

  // فهارس لتسريع البحث بمنشئ الملاحظة والتاريخ والأولوية
  List<Index> get indexes => [
    Index(
      'idx_shift_notes_created_by',
      'CREATE INDEX idx_shift_notes_created_by ON shift_notes (created_by)',
    ),
    Index(
      'idx_shift_notes_date',
      'CREATE INDEX idx_shift_notes_date ON shift_notes (created_at)',
    ),
    Index(
      'idx_shift_notes_read',
      'CREATE INDEX idx_shift_notes_read ON shift_notes (is_read)',
    ),
    Index(
      'idx_shift_notes_priority',
      'CREATE INDEX idx_shift_notes_priority ON shift_notes (priority)',
    ),
    Index(
      'idx_shift_notes_shift_type',
      'CREATE INDEX idx_shift_notes_shift_type ON shift_notes (shift_type)',
    ),
  ];
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
  // ✅ حقول مضافة لمطابقة مخطط Appwrite
  TextColumn get bookingUuidCache => text().nullable()();
  IntColumn get serverBookingId => integer().nullable()();

  @override
  List<Set<Column>>? get uniqueKeys => [
    {bookingLocalId, hotelDayKey},
  ];

  List<Index> get indexes => [
    Index(
      'idx_booking_nights_booking',
      'CREATE INDEX idx_booking_nights_booking ON booking_nights (booking_local_id)',
    ),
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
  // ✅ Wave 6b (2026-08-12): changed from IntColumn → RealColumn
  // Cloud schema defines these as 'double' (انظر appwrite_schema_verifier.dart).
  // سابقاً كانت IntColumn مما يسبب truncation للقيم الكسرية مثل 1500.75 → 1500.
  RealColumn get previousValue => real()();
  RealColumn get newValue => real()();
  TextColumn get reason => text().nullable()();
  TextColumn get effectiveDate => text()();
  TextColumn get appliedBy => text()();
  TextColumn get hotelDayKey => text().nullable()();
  TextColumn get adjustmentMode =>
      text().withDefault(const Constant('per_night'))();
  TextColumn get bookingUuid => text().nullable()();
  IntColumn get appliedAt => integer().nullable()();
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
  // ✅ إصلاح: إضافة FK reference لضمان سلامة البيانات
  // @ReferenceName: تفادي تضارب أسماء الـ reverse reference على $BookingsTable
  @ReferenceName('bookingPriceAdjustmentsByUuid')
  TextColumn get bookingLocalUuid => text().references(Bookings, #localUuid)();
  @ReferenceName('bookingPriceAdjustmentsById')
  IntColumn get bookingLocalId =>
      integer().nullable().references(Bookings, #id)();
  TextColumn get roomNumber => text().withLength(min: 1, max: 20).nullable()();
  RealColumn get amount => real().withDefault(const Constant(0.0))();
  TextColumn get effectiveHotelDay => text()();
  TextColumn get endHotelDay => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get reason => text().nullable()();
  TextColumn get appliedBy => text().nullable()();
  TextColumn get cancelledAt => text().nullable()();
  TextColumn get cancelledBy => text().nullable()();
  TextColumn get bookingUuid => text().nullable()();
  // ✅ حقول مضافة لمطابقة مخطط Appwrite (Migration 53 / payload_mapper)
  IntColumn get adjustmentType => integer().nullable()();
  TextColumn get adjustmentMode => text().nullable()();
  IntColumn get appliedAt => integer().nullable()();

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
class AuditLogs extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  // localUuid, deviceId, createdAt — موروثة من SyncFields
  TextColumn get operationType => text()();
  TextColumn get entityType => text()();
  TextColumn get entityUuid => text()();
  IntColumn get entityId => integer().nullable()();
  TextColumn get previousState => text().nullable()();
  TextColumn get newState => text().nullable()();
  TextColumn get changedFields => text().nullable()();
  TextColumn get performedBy => text()();
  TextColumn get ipAddress => text().nullable()();
  TextColumn get hotelDayKey => text()();
  IntColumn get timestamp => integer()();
  TextColumn get timestampIso => text()();
  BoolColumn get isFinancial => boolean().withDefault(const Constant(false))();
  IntColumn get amountImpact => integer().nullable()();

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
  // ✅ v2: حقول إضافية موجودة على Appwrite Cloud
  TextColumn get note => text().nullable()();
  RealColumn get originalAmount => real().nullable()();
  TextColumn get paymentUuid => text().nullable()();

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

@DataClassName('GuestInfo')
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
  TextColumn get notes => text().nullable()();
  TextColumn get guestPhone => text().nullable()();

  List<Index> get indexes => [
    Index(
      'idx_guest_infos_room',
      'CREATE INDEX idx_guest_infos_room ON guest_infos (room_number)',
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

@DataClassName('SalaryWithdrawal')
class SalaryWithdrawals extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  // ✅ إصلاح: إضافة FK constraint إلى جدول الموظفين
  IntColumn get employeeId => integer().references(Employees, #id)();
  RealColumn get amount => real()();
  TextColumn get withdrawDate => text()();
  TextColumn get reason => text().nullable()();
  TextColumn get hotelDayKey => text().nullable()();
  TextColumn get withdrawalType => text().nullable()();
  TextColumn get description => text().nullable()();
  // ✅ إصلاح (audit agent-10 G4 + engineer recommendation):
  // العمود expense_id موجود في DB (أُضيف في migration 40) لكنه لم يكن
  // مُعلناً في Drift class → الكود كان يستخدم customSelect بدلاً من ORM
  // → أخطاء صامتة وعدم استفادة من type safety.
  // الآن مُعلن ومتاح عبر ORM. (migration 42 يضمن وجوده في DBs القديمة)
  IntColumn get expenseId => integer().nullable()();

  List<Index> get indexes => [
    Index(
      'idx_salary_withdrawals_employee',
      'CREATE INDEX idx_salary_withdrawals_employee ON salary_withdrawals (employee_id)',
    ),
    Index(
      'idx_salary_withdrawals_expense',
      'CREATE INDEX idx_salary_withdrawals_expense ON salary_withdrawals (expense_id)',
    ),
  ];
}

/// ✅ جدول سجل ترحيل الراتب — يسجّل كل عملية ترحيل تلقائية
/// عندما يتجاوز الموظف راتبه في دورة شهرية.
@DataClassName('SalaryCarryOverLog')
class SalaryCarryOverLogs extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id)();
  RealColumn get amount => real()();
  TextColumn get previousCycleStart => text()();
  TextColumn get previousCycleEnd => text()();
  TextColumn get newCycleStart => text()();
  TextColumn get newCycleEnd => text()();
  TextColumn get reason => text()();
  IntColumn get carriedAt => integer()();
  TextColumn get fromCycleId => text().nullable()();
  TextColumn get toCycleId => text().nullable()();
  TextColumn get carryDate => text().nullable()();
  TextColumn get performedBy => text().nullable()();
  // ✅ حقل مضاف لمطابقة مخطط Appwrite
  TextColumn get hotelDayKey => text().nullable()();

  List<Index> get indexes => [
    Index(
      'idx_salary_carryover_employee',
      'CREATE INDEX idx_salary_carryover_employee ON salary_carry_over_logs (employee_id)',
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
  // ✅ P0-1 Audit Fix (2026-08-06): UNIQUE constraint على idempotencyKey
  // سابقاً كان nullable بدون unique، مما يسمح بتكرار نفس العملية على الـ cloud
  // عند retry بعد timeout. UNIQUE يمنع التكرار ويُطبَّق عبر partial unique index
  // في migration 51 (WHERE idempotency_key IS NOT NULL).
  TextColumn get idempotencyKey => text().nullable()();
  TextColumn get processingStatus =>
      text().withDefault(const Constant('pending'))();
  IntColumn get processingStartedAt => integer().nullable()();
  TextColumn get processingWorker => text().nullable()();

  /// مصدر عنصر outbox: 'local' = تغيير محلي (مستخدم)، 'restore' = استعادة من نسخة احتياطية
  /// هذا يفصل بين تتبع التغييرات المحلية وعمليات الاستعادة/المزامنة البعيدة
  TextColumn get source => text().withDefault(const Constant('local'))();

  /// ✅ تتبع التسليم لكل وجهة (dual-delivery tracking)
  ///
  /// بدلاً من حذف السجل بعد نجاح الرفع للرئيسي فقط، نحتفظ بالسجل حتى يتم
  /// تسليمه لـ Primary و Secondary معاً. هذا يمنع فقدان البيانات من
  /// الوجهة الثانوية عند فشل الرفع لها، ويمنع تكرار العمليات في الوجهة
  /// الواحدة بسبب سباق البيانات بين مزامنتين متوازيتين.
  ///
  /// القيم الافتراضية:
  ///   - delivered_to_primary = false (لم يُسلّم للرئيسي بعد)
  ///   - delivered_to_secondary = true (افتراضياً مُسلّم: تجنّب حجب السجلات
  ///     عندما Secondary غير مُفعّل — فقط SecondarySyncManager يضبطها على false)
  BoolColumn get deliveredToPrimary =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get deliveredToSecondary =>
      boolean().withDefault(const Constant(true))();

  /// ✅ Sync Safety Fix (2026-08-10): فصل processing state لكل وجهة.
  /// سابقاً، processingStatus و attempts و lastError كانت مشتركة بين
  /// Primary و Secondary. هذا يعني أن فشل Secondary في معالجة سجل
  /// يمنع Primary من معالجته (لأن processingStatus قد تكون 'failed').
  /// الآن: كل وجهة لها حالة منفصلة.
  TextColumn get primaryProcessingStatus =>
      text().withDefault(const Constant('pending'))();
  IntColumn get primaryAttempts => integer().withDefault(const Constant(0))();
  TextColumn get primaryLastError => text().nullable()();
  TextColumn get secondaryProcessingStatus =>
      text().withDefault(const Constant('pending'))();
  IntColumn get secondaryAttempts => integer().withDefault(const Constant(0))();
  TextColumn get secondaryLastError => text().nullable()();

  /// ✅ Wave 5 (2026-08-12): Generation field لمنع stale acknowledgements.
  ///
  /// يُزداد بمقدار 1 كل مرة يتم فيها تحديث payload أو op أو clientTs في
  /// `merge()`. عند الالتقاط (claim)، يتم تخزين قيمة `payloadVersion` في
  /// `processingPayloadVersion`. عند التأكيد (markDelivered/setError/etc.)
  /// يتحقق الكود أن `processingPayloadVersion == payloadVersion` الحالية.
  ///
  /// إذا تغيرت `payloadVersion` أثناء المعالجة (لأن `merge` أخرى حدّثت
  /// payload أثناء عمل worker قديم)، يرفض الكود التأكيد ويُعيد السجل
  /// لـ pending ليُعالج من جديد.
  ///
  /// **مثال على السباق الذي يمنعه**:
  /// 1. worker-A يلتقط السجل (payloadVersion=5, processingPayloadVersion=5)
  /// 2. أثناء معالجة worker-A، payload يُحدَّث (payloadVersion=6)
  /// 3. worker-A يحاول تأكيد التسليم
  /// 4. الكود يرى processingPayloadVersion=5 != payloadVersion=6
  /// 5. التأكيد يُرفض، السجل يُعاد لـ pending، worker-A يُعاد رفعه
  ///
  /// القيمة الافتراضية: 1 (للسجلات الجديدة)
  IntColumn get payloadVersion => integer().withDefault(const Constant(1))();

  /// ✅ Wave 5: قيمة `payloadVersion` عند الالتقاط (claim).
  /// تُستخدم للتحقق من أن العامل الذي يؤكد التسليم هو نفس العامل الذي التقطه.
  IntColumn get processingPayloadVersion => integer().nullable()();

  List<Index> get indexes => [
    Index(
      'idx_outbox_status',
      'CREATE INDEX idx_outbox_status ON outbox (processing_status)',
    ),
    Index(
      'idx_outbox_entity_status',
      'CREATE INDEX idx_outbox_entity_status ON outbox (entity, op, processing_status)',
    ),
    Index(
      'idx_outbox_uuid_pending',
      'CREATE INDEX idx_outbox_uuid_pending ON outbox (entity, local_uuid, processing_status)',
    ),
    Index(
      'idx_outbox_client_ts',
      'CREATE INDEX idx_outbox_client_ts ON outbox (client_ts)',
    ),
    Index(
      'idx_outbox_processing_started',
      'CREATE INDEX idx_outbox_processing_started ON outbox (processing_status, processing_started_at)',
    ),
    Index(
      'idx_outbox_source_status',
      'CREATE INDEX idx_outbox_source_status ON outbox (source, processing_status)',
    ),
    // ✅ فهرس مركّب لتسريع استعلامات "ما الذي لم يُسلّم بعد لكل وجهة"
    Index(
      'idx_outbox_delivery_primary',
      'CREATE INDEX idx_outbox_delivery_primary ON outbox (delivered_to_primary, processing_status)',
    ),
    Index(
      'idx_outbox_delivery_secondary',
      'CREATE INDEX idx_outbox_delivery_secondary ON outbox (delivered_to_secondary, processing_status)',
    ),
    Index(
      'idx_outbox_pending_primary_source_ts',
      "CREATE INDEX idx_outbox_pending_primary_source_ts ON outbox (source, client_ts) WHERE processing_status = 'pending' AND delivered_to_primary = 0",
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

  /// ✅ Sync Safety Wave 2 (2026-08-12): Full Sync Bootstrap Flag.
  ///
  /// `full_sync_complete = 0` (default): الجهاز في مرحلة bootstrap — يجب
  /// القيام بـ full sync كامل. لا يُسمح بالتحول لـ delta sync حتى تكتمل
  /// كل الكولكشنات بنجاح في دورة واحدة.
  ///
  /// `full_sync_complete = 1`: اكتملت أول full sync بنجاح — يمكن استخدام
  /// delta sync بشكل آمن (لن نفقد سجلات لم تُسحب بعد).
  ///
  /// **المشكلة التي يحلها**: قبل هذا الـ flag، كان النظام يعتمد فقط على
  /// `lastPullTs == 0` لتحديد "full sync mode". لكن هذا يعني:
  /// 1. إذا نجحت أول دورة full sync جزئياً (مثلاً 18 من 19 collection)،
  ///    `failedCollections.isEmpty` يمنع تحديث `lastPullTs`، فالدورة التالية
  ///    تعيد full sync — هذا جيد.
  /// 2. لكن إذا نجحت كل الكولكشنات ظاهرياً (لا exception) لكن بعض السجلات
  ///    لم تُعالج داخل `_syncXxx` (مثلاً skip بسبب تعارض غير متوقع)،
  ///    `lastPullTs` يُحدَّث والجهاز يتحول لـ delta mode — فقدان صامت.
  ///
  /// مع هذا الـ flag، حتى لو نُجح الـ full sync ظاهرياً، نضبط الـ flag
  /// فقط بعد التحقق من أن كل كولكشن عاد بنتيجة متوقعة (records > 0 أو
  /// دورة فارغة معروفة). حتى ذلك الحين، الـ delta queries تُرجع قائمة
  /// فارغة (full fetch) لضمان عدم فقدان أي سجل.
  ///
  /// Migration 56 يضيف هذا العمود مع DEFAULT 0.
  IntColumn get fullSyncComplete => integer().withDefault(const Constant(0))();

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

  List<Index> get indexes => [
    Index(
      'idx_sync_queue_status',
      'CREATE INDEX idx_sync_queue_status ON sync_queue (status)',
    ),
    Index(
      'idx_sync_queue_table',
      'CREATE INDEX idx_sync_queue_table ON sync_queue (table_name)',
    ),
  ];
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

  List<Index> get indexes => [
    Index(
      'idx_sync_log_created',
      'CREATE INDEX idx_sync_log_created ON sync_log (created_at)',
    ),
    Index(
      'idx_sync_log_sync_id',
      'CREATE INDEX idx_sync_log_sync_id ON sync_log (sync_id)',
    ),
    Index(
      'idx_sync_log_device_id',
      'CREATE INDEX idx_sync_log_device_id ON sync_log (device_id)',
    ),
  ];
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

  List<Index> get indexes => [
    Index(
      'idx_sync_conflicts_table_uuid',
      'CREATE INDEX idx_sync_conflicts_table_uuid ON sync_conflicts (table_name, uuid)',
    ),
  ];
}

/// أصناف المخزون المحلية. الرصيد الحالي مشتق من حركات الوارد والصرف والجرد.
class InventoryItems extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  TextColumn get unit => text().withDefault(const Constant('قطعة'))();
  TextColumn get category => text().nullable()();
  IntColumn get quantity => integer().withDefault(const Constant(0))();
  IntColumn get minimumQuantity => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  List<Index> get indexes => [
    Index(
      'idx_inventory_items_active_name',
      'CREATE INDEX idx_inventory_items_active_name ON inventory_items (is_active, name)',
    ),
  ];
}

class InventoryTransactions extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get itemLocalUuid => text().nullable()();
  IntColumn get itemId => integer().references(InventoryItems, #id)();
  TextColumn get movementType => text()();
  IntColumn get quantity => integer()();
  IntColumn get balanceAfter => integer()();
  TextColumn get note => text().nullable()();
  IntColumn get userId => integer().nullable()();
  TextColumn get userName => text().nullable()();
  List<Index> get indexes => [
    Index(
      'idx_inventory_transactions_item_date',
      'CREATE INDEX idx_inventory_transactions_item_date ON inventory_transactions (item_id, created_at DESC)',
    ),
  ];
}

/// ✅ (2026-09-05) جدول app_users — حسابات مستخدمي التطبيق ككيان متزامن.
///
/// تعليمات المستخدم («النطاق الافتراضي المزامنة … user_app … أيضاً
/// pull/push و outbox delta sync»): كيان app_users كان يُزامَن عبر
/// Appwrite Cloud (appwrite_config.dart:116، outbox_dao.dart
/// _entityTableMap، auth_local_store._enqueuePermissionSync) لكن طبقة
/// Cloudflare أسقطته كلياً — لا جدول Drift ولا جدول D1 ولا إدخال في
/// ENTITY_TABLES، فأي تغيير حسابات لا يصل D1 وأي سحب له يتقدم cursor
/// فوق صفوف مفقودة.
///
/// يخدم ثلاث أدوار:
/// 1. Landing zone للسحب (delta pull) — بدونه _applyChange يَطيّر
///    الكيان بلا جدول محلي ويُفقَد صمتاً.
/// 2. مصدر رفع D1 (تبويب النسخ الاحتياطي + مسار الترحيل).
/// 3. هدف الكتابة المحلية لتغيّرات الحسابات (auth_local_store) التي
///    تُغذّي outbox بحمولات snake_case مطابقة لأعمدة D1.
///
/// الأعمدة مرآة مجموعة app_users الحية في Appwrite
/// (schema_extract.json validFieldsPerCollection['app_users'])
/// بصيغة snake_case؛ الحقلان المكرران userType/user_type في المجموعة
/// الحية يُمثَّلان بعمود user_type واحد (الكود المُنشئ يكتبهما
/// بنفس القيمة دائماً — auth_local_store).
class AppUsers extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text()();
  TextColumn get password => text().nullable()();
  TextColumn get fullName => text().withDefault(const Constant(''))();
  TextColumn get userType => text().withDefault(const Constant(''))();
  TextColumn get permissions => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get lastLogin => integer().nullable()();
  IntColumn get credentialsVersion =>
      integer().withDefault(const Constant(0))();
  TextColumn get role => text().nullable()();

  List<Index> get indexes => [
    Index(
      'idx_app_users_updated',
      'CREATE INDEX idx_app_users_updated ON app_users (updated_at)',
    ),
    Index(
      'idx_app_users_deleted',
      'CREATE INDEX idx_app_users_deleted ON app_users (deleted_at)',
    ),
    Index(
      'idx_app_users_username',
      'CREATE INDEX idx_app_users_username ON app_users (username)',
    ),
  ];
}

/// ✅ (2026-09-05) جدول devices — سجل الأجهزة ككيان متزامن (تعليمات
/// المستخدم: «… و devices — أيضاً pull/push و outbox و delta sync»).
///
/// سابقاً كان تسجيل الجهاز مساراً REST فقط (/api/devices/register يكتب
/// جدول FCM الضيق بلا local_uuid/SyncFields) بينما سجل Appwrite
/// (DeviceRegistrar → مجموعة devices) سقط من طبقة Cloudflare. الآن:
/// 1. Landing zone للسحب — سجل كل جهاز يُسحب محلياً (شاشات الأجهزة
///    تقرأ من هنا — getRegisteredDevices).
/// 2. مصدر رفع D1 (تبويب النسخ + الترحيل).
/// 3. هدف كتابة تسجيل الجهاز (registerDevice/setFcmToken) مع outbox.
///
/// الأعمدة مرآة مجموعة devices الحية في Appwrite
/// (appwrite_sync_utils.dart whitelist) بصيغة snake_case.
/// ملاحظة معمارية: SyncFields.deviceId (جهاز الكاتب) يُعاد تعريفه هنا
/// ليهو هوية الجهاز نفسها الفريدة — لصف الجهاز، الكاتب هو الجهاز.
@DataClassName('DeviceRow')
class Devices extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();

  /// ✅ إعادة تعريف عمود SyncFields.device_id: هوية الجهاز الفريدة
  /// (cf_dev_*) — نفس القيمة المرسلة في /api/devices/register وفي
  /// عمليات outbox، فتتقارب مسارات REST والمزامنة على صف واحد.
  @override
  TextColumn get deviceId => text().unique()();
  TextColumn get deviceName => text().withDefault(const Constant(''))();
  TextColumn get deviceModel => text().nullable()();
  TextColumn get deviceType => text().nullable()();
  TextColumn get osVersion => text().nullable()();
  TextColumn get platform => text().nullable()();
  TextColumn get appVersion => text().nullable()();
  TextColumn get fcmToken => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get lastSeen => text().nullable()();
  IntColumn get lastActive => integer().nullable()();

  List<Index> get indexes => [
    Index(
      'idx_devices_updated',
      'CREATE INDEX idx_devices_updated ON devices (updated_at)',
    ),
    Index(
      'idx_devices_deleted',
      'CREATE INDEX idx_devices_deleted ON devices (deleted_at)',
    ),
    Index(
      'idx_devices_status',
      'CREATE INDEX idx_devices_status ON devices (status)',
    ),
  ];
}

/// ✅ جدول AncestorCache — يخزّن آخر نسخة معروفة مشتركة (common ancestor)
/// لكل سجل، ويُستخدم في الدمج ثلاثي الأطراف (3-way merge) لحل التعارضات.
///
/// عند كل سحب ناجح من Cloud، نحفظ نسخة من البيانات البعيدة هنا.
/// عند المزامنة التالية، نستخدمها كـ "common ancestor" لمقارنة التغييرات.
class AncestorCache extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get localUuid => text()();
  TextColumn get dataJson => text()();
  IntColumn get capturedAt => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {entity, localUuid},
  ];
}

/// ✅ (2026-08-30) الفجوتان 3+4 — خريطة $updatedAt البعيدة لكل مستند مُسحوب.
///
/// تُستخدم في السحب الكامل (metadata-first): نسحب ($id + $updatedAt) فقط من
/// الخادم ونقارنها بهذه الخريطة، ثم نُنزّل المستند الكامل فقط لما تغيّر فعلاً.
/// تُحدَّث في `_checkpointEntity` بعد نجاح تطبيق كل دفعة سحب (delta أو full)،
/// لذا وجود صف بطابع زمني يعني أن المحلي يملك محتوى ذلك الإصدار من الخادم.
@DataClassName('SyncRemoteMetaRow')
class SyncRemoteMeta extends Table {
  /// معرّف كولكشن Appwrite (مثل 'bookings')
  TextColumn get collection => text()();

  /// معرّف المستند على الخادم ($id)
  TextColumn get docId => text()();

  /// $updatedAt بالثواني لآخر إصدار جُلب وطبّق بنجاح (سلطة الخادم)
  IntColumn get remoteUpdatedAtSec => integer()();

  @override
  Set<Column> get primaryKey => {collection, docId};
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
    PriceAdjustments,
    BookingPriceAdjustments,
    AuditLogs,
    PaymentVoids,
    GuestInfos,
    SalaryWithdrawals,
    SalaryCarryOverLogs,
    InventoryItems,
    InventoryTransactions,
    AppUsers,
    Devices,
    AncestorCache,
    SyncRemoteMeta,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  AppDatabase._internal(super.executor);

  AppDatabase.forTesting(QueryExecutor executor) : this._internal(executor);

  @override
  int get schemaVersion => 67;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // تحسينات الأداء: WAL mode للقراءة والكتابة المتوازية
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA synchronous = NORMAL');
      // ✅ Low-RAM tuning (1GB devices): تقليل بصمة الذاكرة لمنع OOM-kill.
      // القيم الافتراضية للأجهزة العادية؛ تُخفّض فقط على الأجهزة الضعيفة.
      final weak = WeakDeviceOptimizer.instance.isWeakDevice;
      await customStatement('PRAGMA busy_timeout = 5000');
      if (weak) {
        // 2MB page cache + 16MB mmap، temp يذهب للملف لا للذاكرة.
        await customStatement('PRAGMA cache_size = -2048');
        await customStatement('PRAGMA temp_store = FILE');
        await customStatement('PRAGMA mmap_size = 16777216');
      } else {
        await customStatement('PRAGMA cache_size = -8192');
        await customStatement('PRAGMA temp_store = MEMORY');
        await customStatement('PRAGMA mmap_size = 268435456');
      }
      // ✅ تم إزالة PRAGMA page_size = 4096 — لا يعمل بعد إنشاء قاعدة البيانات
      // page_size يجب تعيينه فقط عند إنشاء قاعدة بيانات جديدة، وبما أن
      // قاعدة البيانات موجودة مسبقاً بقيمة مختلفة (غالباً 1024) فهذا إهدار I/O
      await customStatement('PRAGMA wal_autocheckpoint = 1000');
    },
    onUpgrade: (m, from, to) async {
      // ✅ (2026-09-05) الإصدار 67: جدول devices ككيان متزامن كامل
      // (تعليمات المستخدم: النطاق الافتراضي يشمل devices مع pull/push
      // وoutbox وdelta sync). يُنشأ لكل الترقيات (من أي إصدار) — فارغ
      // مبدئياً؛ تمتلئ صفوفه من تسجيل الجهاز (registerDevice) والسحب.
      if (from < 67) {
        await m.createTable(devices);
      }
      // ✅ (2026-09-05) الإصدار 66: جدول app_users ككيان متزامن كامل
      // (تعليمات المستخدم: النطاق الافتراضي للمزامنة يشمل حسابات
      // المستخدمين مع pull/push وoutbox delta sync). يُنشأ لكل الترقيات
      // (من أي إصدار) — فارغ مبدئياً؛ تمتلئ صفوفه من كتابة
      // auth_local_store المحلية ومن السحب من D1.
      if (from < 66) {
        await m.createTable(appUsers);
      }
      // ✅ (2026-08-30) الإصدار 65: جدول sync_remote_meta للسحب metadata-first.
      // يُنشأ لكل الترقيات (من أي إصدار) — فارغ مبدئياً فأول سحب كامل بعد
      // الترقية يبنيه تدريجياً من دفعات checkpoint الناجحة.
      if (from < 65) {
        await m.createTable(syncRemoteMeta);
      }
      if (from < 62) {
        await m.createTable(inventoryItems);
        await m.createTable(inventoryTransactions);
      }
      // الإصدار 63: إضافة UUID المرجعي لحركات المخزون الموجودة منذ الإصدار 62.
      // لا نضيف العمود عند إنشاء الجداول لأول مرة (from < 62)، لأنه موجود
      // ضمن تعريف الجدول الحالي بالفعل.
      if (from >= 62 && from < 63) {
        await m.addColumn(
          inventoryTransactions,
          inventoryTransactions.itemLocalUuid,
        );
      }
      if (from < 61) {
        await m.addColumn(payments, payments.receivedByUserId);
        await m.addColumn(payments, payments.receivedByName);
        await m.addColumn(payments, payments.receivedSessionUuid);
      }
      // الإصدار 64: هوية Appwrite Cloud الثابتة لاستلام الدفعة.
      // Nullable عمداً؛ لا نعيد نسب السجلات القديمة إلى مستخدم دون دليل.
      if (from < 64) {
        await m.addColumn(payments, payments.receivedByCloudId);
      }
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
            'SELECT server_id FROM rooms LIMIT 1',
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
              'SELECT server_id FROM $tableName LIMIT 1',
            );
          } catch (e) {
            // العمود غير موجود
            try {
              await m.database.customStatement(
                'ALTER TABLE $tableName ADD COLUMN server_id INTEGER',
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
          final oldCreatedRaw = row.data['created_at'];
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
            ' title, content, priority, shift_type, is_read, created_by, '
            ' expires_at, '
            ' local_uuid, server_id, created_at, updated_at, deleted_at, last_modified, '
            ' created_at_iso, updated_at_iso, deleted_at_iso, version, origin '
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

        // 1. إنشاء جدول BookingPriceAdjustments
        await m.createTable(bookingPriceAdjustments);

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
        // إنشاء جدول سجل المعلومية
        try {
          await m.createTable(guestInfos);
          developer.log(
            'Migration 27: created guest_infos table',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 27: create guest_infos failed: $e',
            name: 'db.migration',
          );
        }
      }
      if (from < 28) {
        // إنشاء جدول سحوبات الرواتب
        try {
          await m.createTable(salaryWithdrawals);
          developer.log(
            'Migration 28: created salary_withdrawals table',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 28: create salary_withdrawals failed: $e',
            name: 'db.migration',
          );
        }
      }
      if (from < 29) {
        // إضافة حقول جديدة لجدول payments للمزامنة مع Appwrite
        try {
          await m.addColumn(payments, payments.discountAmount);
          developer.log(
            'Migration 29: added payments.discountAmount',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 29: add payments.discountAmount failed: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(payments, payments.discountStartDate);
          developer.log(
            'Migration 29: added payments.discountStartDate',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 29: add payments.discountStartDate failed: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(payments, payments.isVoided);
          developer.log(
            'Migration 29: added payments.isVoided',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 29: add payments.isVoided failed: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(payments, payments.voidedAt);
          developer.log(
            'Migration 29: added payments.voidedAt',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 29: add payments.voidedAt failed: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(payments, payments.voidedBy);
          developer.log(
            'Migration 29: added payments.voidedBy',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 29: add payments.voidedBy failed: $e',
            name: 'db.migration',
          );
        }
      }
      if (from < 30) {
        // إضافة حقول withdrawalType و description لجدول salary_withdrawals
        try {
          await m.addColumn(
            salaryWithdrawals,
            salaryWithdrawals.withdrawalType,
          );
          developer.log(
            'Migration 30: added salary_withdrawals.withdrawalType',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 30: add salary_withdrawals.withdrawalType failed: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(salaryWithdrawals, salaryWithdrawals.description);
          developer.log(
            'Migration 30: added salary_withdrawals.description',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 30: add salary_withdrawals.description failed: $e',
            name: 'db.migration',
          );
        }
      }

      // === Migration 31: Performance indexes ===
      if (from < 31) {
        const perfIndexes = [
          // Outbox: تسريع الاستعلامات الأساسية
          'CREATE INDEX IF NOT EXISTS idx_outbox_status ON outbox (processing_status)',
          'CREATE INDEX IF NOT EXISTS idx_outbox_entity_status ON outbox (entity, op, processing_status)',
          'CREATE INDEX IF NOT EXISTS idx_outbox_uuid_pending ON outbox (entity, local_uuid, processing_status)',
          'CREATE INDEX IF NOT EXISTS idx_outbox_client_ts ON outbox (client_ts)',
          'CREATE INDEX IF NOT EXISTS idx_outbox_processing_started ON outbox (processing_status, processing_started_at)',
          // Debts: تسريع البحث بالحجز
          'CREATE INDEX IF NOT EXISTS idx_debts_booking ON debts (booking_local_id)',
          // Payments: تسريع البحث بالتاريخ والنوع
          'CREATE INDEX IF NOT EXISTS idx_payments_date ON payments (payment_date)',
          'CREATE INDEX IF NOT EXISTS idx_payments_revenue ON payments (revenue_type, hotel_day_key)',
          'CREATE INDEX IF NOT EXISTS idx_payments_void ON payments (is_voided)',
          // Bookings: تسريع فلترة المحذوفات
          'CREATE INDEX IF NOT EXISTS idx_bookings_deleted ON bookings (deleted_at)',
          // BookingNotes: تسريع البحث بالحجز
          'CREATE INDEX IF NOT EXISTS idx_booking_notes_booking ON booking_notes (booking_id)',
        ];
        for (final sql in perfIndexes) {
          try {
            await m.database.customStatement(sql);
          } catch (e) {
            developer.log(
              'Migration 31: $sql failed: $e',
              name: 'db.migration',
            );
          }
        }
        developer.log(
          'Migration 31: performance indexes created successfully',
          name: 'db.migration',
        );
      }
      if (from < 32) {
        await m.addColumn(
          bookingPriceAdjustments,
          bookingPriceAdjustments.roomNumber,
        );
        developer.log(
          'Migration 32: added roomNumber to booking_price_adjustments',
          name: 'db.migration',
        );
      }

      // === Migration 33: إصلاح مصروفات الرواتب المفقودة من salary_withdrawals ===
      // نستخدم SQL مباشرة لأن m.database لا يدعم typed accessors داخل المايكريشن
      if (from < 33) {
        try {
          final now = DateTime.now().millisecondsSinceEpoch;

          // جلب مصروفات الرواتب التي لها موظف مرتبط ولم تُحذف
          // وأنواعها من: سحب راتب، خصم راتب، سحب من الراتب، خصم من الراتب
          const salaryTypes =
              "'سحب راتب','خصم راتب','سحب من الراتب','خصم من الراتب'";

          final missingExpenses = await m.database.customSelect('''
            SELECT e.id, e.related_id, e.amount, e.date, e.hotel_day_key,
                   e.expense_type, e.description
            FROM expenses e
            WHERE e.deleted_at IS NULL
              AND e.related_id IS NOT NULL
              AND TRIM(e.expense_type) IN ($salaryTypes)
              AND NOT EXISTS (
                SELECT 1 FROM salary_withdrawals sw
                WHERE sw.reason LIKE '%' || 'exp_' || e.id || '%'
              )
            ''').get();

          int created = 0;
          for (final row in missingExpenses) {
            final expId = row.read<int>('id');
            final relatedId = row.read<int>('related_id');
            final amount = row.read<double>('amount');
            final date = row.read<String>('date');
            final hotelDayKey = row.read<String?>('hotel_day_key');
            final expenseType = row.read<String>('expense_type');
            final description = row.read<String?>('description');

            // توليد UUID فريد
            final uuid = 'mig33_${expId}_$now';

            await m.database.customInsert(
              '''
              INSERT INTO salary_withdrawals (
                local_uuid, server_id, employee_id, amount, withdraw_date,
                reason, hotel_day_key, withdrawal_type, description,
                created_at, updated_at, deleted_at, last_modified,
                created_at_epoch, last_modified_epoch, version, origin, vector_clock
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ''',
              variables: [
                Variable<String>(uuid),
                const Variable<Object>(null),
                Variable<int>(relatedId),
                Variable<double>(amount),
                Variable<String>(date),
                Variable<String>('exp_$expId'),
                Variable<String>(hotelDayKey ?? date),
                Variable<String>(expenseType),
                Variable<String>(description ?? ''),
                Variable<int>(now),
                Variable<int>(now),
                const Variable<Object>(null),
                Variable<int>(now),
                Variable<int>(now),
                Variable<int>(now),
                const Variable<int>(1),
                const Variable<String>('local'),
                const Variable<String>('{}'),
              ],
            );

            // إضافة سجل Outbox للمزامنة
            await m.database.customInsert(
              '''
              INSERT INTO outbox (
                entity, op, local_uuid, server_id, payload,
                client_ts, idempotency_key, processing_status
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
              ''',
              variables: [
                const Variable<String>('salary_withdrawals'),
                const Variable<String>('create'),
                Variable<String>(uuid),
                const Variable<Object>(null),
                const Variable<String>('{}'),
                Variable<int>(now),
                Variable<String>('mig33_$expId'),
                const Variable<String>('pending'),
              ],
            );

            created++;
          }
          developer.log(
            'Migration 33: created $created missing salary_withdrawals records',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log('Migration 33: failed - $e', name: 'db.migration');
        }
      }

      // === Migration 34: فهارس الأداء الجديدة ===
      if (from < 34) {
        const newIndexes = [
          // Employees: فهرس البحث بالاسم
          'CREATE INDEX IF NOT EXISTS idx_employees_name ON employees (name)',
          // CashTransactions: فهارس البحث بالمعاملات
          'CREATE INDEX IF NOT EXISTS idx_cash_trans_type_time ON cash_transactions (transaction_type, transaction_time)',
          'CREATE INDEX IF NOT EXISTS idx_cash_trans_ref ON cash_transactions (reference_type, reference_id)',
          // ShiftNotes: فهارس البحث بمنشئ الملاحظة والتاريخ والحالة
          'CREATE INDEX IF NOT EXISTS idx_shift_notes_created_by ON shift_notes (created_by)',
          'CREATE INDEX IF NOT EXISTS idx_shift_notes_date ON shift_notes (created_at)',
          'CREATE INDEX IF NOT EXISTS idx_shift_notes_read ON shift_notes (is_read)',
        ];
        for (final sql in newIndexes) {
          try {
            await m.database.customStatement(sql);
          } catch (e) {
            developer.log(
              'Migration 34: $sql failed: $e',
              name: 'db.migration',
            );
          }
        }
        developer.log(
          'Migration 34: new performance indexes created successfully',
          name: 'db.migration',
        );
      }
      // === Migration 35: فهارس إضافية للمدفوعات والمصروفات والموظفين والملاحظات ===
      if (from < 35) {
        const newIndexes = [
          'CREATE INDEX IF NOT EXISTS idx_employees_status ON employees (status)',
          'CREATE INDEX IF NOT EXISTS idx_shift_notes_priority ON shift_notes (priority)',
          'CREATE INDEX IF NOT EXISTS idx_shift_notes_shift_type ON shift_notes (shift_type)',
          'CREATE INDEX IF NOT EXISTS idx_payments_method ON payments (payment_method)',
          'CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses (date)',
        ];
        for (final sql in newIndexes) {
          try {
            await m.database.customStatement(sql);
          } catch (e) {
            developer.log(
              'Migration 35: $sql failed: $e',
              name: 'db.migration',
            );
          }
        }
        developer.log(
          'Migration 35: additional performance indexes created successfully',
          name: 'db.migration',
        );
      }

      // === Migration 36: فهارس GuestInfos و BookingNights + تحسينات سلامة البيانات ===
      if (from < 36) {
        const newIndexes = [
          // GuestInfos: فهارس البحث برقم الغرفة ورقم الهوية
          'CREATE INDEX IF NOT EXISTS idx_guest_infos_room ON guest_infos (room_number)',
          'CREATE INDEX IF NOT EXISTS idx_guest_infos_id_number ON guest_infos (id_number)',
          'CREATE INDEX IF NOT EXISTS idx_guest_infos_name ON guest_infos (guest_name)',
          // BookingNights: فهرس البحث بيوم الفندق
          'CREATE INDEX IF NOT EXISTS idx_booking_nights_hotel_day ON booking_nights (hotel_day_key)',
          'CREATE INDEX IF NOT EXISTS idx_booking_nights_booking ON booking_nights (booking_local_id, hotel_day_key)',
          // SalaryWithdrawals: فهرس البحث بالموظف والتاريخ
          'CREATE INDEX IF NOT EXISTS idx_salary_withdrawals_date ON salary_withdrawals (withdraw_date)',
          'CREATE INDEX IF NOT EXISTS idx_salary_withdrawals_employee_date ON salary_withdrawals (employee_id, withdraw_date)',
          // BookingPriceAdjustments: فهرس إضافي
          'CREATE INDEX IF NOT EXISTS idx_booking_price_adj_room ON booking_price_adjustments (room_number)',
          // Expenses: فهرس النوع والتاريخ
          'CREATE INDEX IF NOT EXISTS idx_expenses_type_date ON expenses (expense_type, date)',
          // HotelDayLedger: فهرس الحالة
          'CREATE INDEX IF NOT EXISTS idx_ledger_status ON hotel_day_ledger (status)',
        ];
        for (final sql in newIndexes) {
          try {
            await m.database.customStatement(sql);
          } catch (e) {
            developer.log(
              'Migration 36: $sql failed: $e',
              name: 'db.migration',
            );
          }
        }
        developer.log(
          'Migration 36: additional indexes created successfully',
          name: 'db.migration',
        );
      }

      // === Migration 37: جدول القوائم المخصصة (أنواع المصروفات، أنواع الهوية، طرق الدفع) ===
      if (from < 37) {
        await m.database.customStatement(
          'CREATE TABLE IF NOT EXISTS custom_list_items '
          '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'list_key TEXT NOT NULL, '
          'name TEXT NOT NULL, '
          'sort_order INTEGER NOT NULL DEFAULT 0, '
          'is_active INTEGER NOT NULL DEFAULT 1, '
          'is_system INTEGER NOT NULL DEFAULT 0)',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_custom_list_key '
          'ON custom_list_items (list_key, sort_order)',
        );

        // بذر أنواع المصروفات الافتراضية
        const expenseDefaults = [
          ['رواتب', '1', '1'],
          ['ديزل', '2', '0'],
          ['صيانة', '3', '0'],
          ['فواتير كهرباء ومياه', '4', '0'],
          ['مستلزمات', '5', '0'],
          ['مساعدة محتاج', '6', '0'],
          ['اخرى', '7', '0'],
        ];
        for (final e in expenseDefaults) {
          await m.database.customStatement(
            'INSERT INTO custom_list_items (list_key, name, sort_order, is_active, is_system) '
            "VALUES ('expense_type', '${e[0]}', ${e[1]}, 1, ${e[2]})",
          );
        }

        // بذر أنواع الهوية الافتراضية
        const idTypeDefaults = [
          ['بطاقة شخصية', '1', '0'],
          ['جواز سفر', '2', '0'],
          ['رخصة قيادة', '3', '0'],
          ['بطاقة عسكرية', '4', '0'],
          ['استبيان', '5', '0'],
          ['شهادة ميلاد', '6', '0'],
        ];
        for (final e in idTypeDefaults) {
          await m.database.customStatement(
            'INSERT INTO custom_list_items (list_key, name, sort_order, is_active, is_system) '
            "VALUES ('id_type', '${e[0]}', ${e[1]}, 1, ${e[2]})",
          );
        }

        // بذر طرق الدفع الافتراضية
        const paymentMethodDefaults = [
          ['نقدي', '1', '0'],
          ['تحويل بنكي', '2', '0'],
        ];
        for (final e in paymentMethodDefaults) {
          await m.database.customStatement(
            'INSERT INTO custom_list_items (list_key, name, sort_order, is_active, is_system) '
            "VALUES ('payment_method', '${e[0]}', ${e[1]}, 1, ${e[2]})",
          );
        }

        developer.log(
          'Migration 37: custom_list_items table created and seeded',
          name: 'db.migration',
        );
      }

      // Migration 38: إضافة عمود source إلى جدول outbox
      // يفصل بين عناصر outbox الناتجة عن تغييرات محلية (source='local')
      // وعناصر الاستعادة/المزامنة البعيدة (source='restore')
      if (from < 38) {
        await m.database.customStatement(
          'ALTER TABLE outbox ADD COLUMN source TEXT NOT NULL DEFAULT \'local\'',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_outbox_source_status '
          'ON outbox (source, processing_status)',
        );
        developer.log(
          'Migration 38: added source column to outbox table',
          name: 'db.migration',
        );
      }
      // === Migration 39: إضافة حقول إنهاء الخدمة للموظفين ===
      if (from < 39) {
        try {
          await m.addColumn(employees, employees.terminationDate);
          developer.log(
            'Migration 39: added employees.terminationDate',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 39: add employees.terminationDate failed: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.addColumn(employees, employees.terminationReason);
          developer.log(
            'Migration 39: added employees.terminationReason',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 39: add employees.terminationReason failed: $e',
            name: 'db.migration',
          );
        }
      }

      // ═══════════════════════════════════════════════════════════
      // ✅ Migration 40: إضافة عمود expense_id لجدول salary_withdrawals
      //
      // هذا العمود يربط سحب الراتب بالمصروف المقابل بشكل موثوق
      // بدلاً من الاعتماد على نمط exp_XX في حقل reason (ربط هش)
      //
      // المخطط: expense_id INTEGER NULLABLE
      // التعبئة: من حقل reason (استخراج exp_XX → expense_id)
      // ═══════════════════════════════════════════════════════════
      if (from < 40) {
        try {
          await m.database.customStatement(
            'ALTER TABLE salary_withdrawals ADD COLUMN expense_id INTEGER',
          );
          developer.log(
            'Migration 40: added salary_withdrawals.expense_id',
            name: 'db.migration',
          );
        } catch (e) {
          // العمود قد يكون موجوداً من ترحيل سابق فاشل — نتخطى
          developer.log(
            'Migration 40: add expense_id (may already exist): $e',
            name: 'db.migration',
          );
        }
        // تعبئة expense_id من حقل reason (exp_XX → XX)
        try {
          await m.database.customStatement(
            'UPDATE salary_withdrawals SET expense_id = CAST(SUBSTR(reason, 5) AS INTEGER) '
            "WHERE reason LIKE 'exp_%' AND expense_id IS NULL",
          );
          developer.log(
            'Migration 40: populated expense_id from reason field',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 40: populate expense_id failed: $e',
            name: 'db.migration',
          );
        }
      }
      // ═══════════════════════════════════════════════════════════
      // Migration 41: إضافة حقل device_id إلى جميع جداول SyncFields
      // لتتبع أي جهاز أنشأ أو عدّل كل سجل
      // ═══════════════════════════════════════════════════════════
      if (from < 41) {
        const syncTables = [
          'rooms',
          'bookings',
          'booking_notes',
          'employees',
          'expenses',
          'cash_transactions',
          'payments',
          'debts',
          'shift_notes',
          'booking_nights',
          'hotel_day_ledger',
          'price_adjustments',
          'booking_price_adjustments',
          'payment_voids',
          'guest_infos',
          'salary_cycles',
          'salary_payments',
          'salary_withdrawals',
        ];
        for (final table in syncTables) {
          try {
            await m.database.customStatement(
              'ALTER TABLE $table ADD COLUMN device_id TEXT NOT NULL DEFAULT \'\'',
            );
          } catch (e) {
            developer.log(
              'Migration 41: add device_id to $table (may exist): $e',
              name: 'db.migration',
            );
          }
        }
        developer.log(
          'Migration 41: added device_id to all SyncFields tables',
          name: 'db.migration',
        );
      }

      // ✅ Migration 42 (engineer recommendation):
      // إعلان expense_id في Drift class لـ salary_withdrawals.
      // العمود موجود في DB منذ migration 40، لكن Drift لم يكن يعرفه.
      // هذا migration ضماني: إذا كان DB قديم (قبل migration 40) يضيف العمود،
      // وإذا كان موجوداً بالفعل يتجاهله (IF NOT EXISTS غير مدعوم في ALTER TABLE
      // لذا نستخدم try/catch).
      if (from < 42) {
        try {
          await m.database.customStatement(
            'ALTER TABLE salary_withdrawals ADD COLUMN expense_id INTEGER',
          );
          developer.log(
            'Migration 42: added expense_id to salary_withdrawals',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 42: expense_id already exists in salary_withdrawals: $e',
            name: 'db.migration',
          );
        }
      }

      // ✅ Migration 43: إنشاء جدول سجل ترحيل الراتب
      if (from < 43) {
        try {
          await m.database.customStatement('''
            CREATE TABLE IF NOT EXISTS salary_carry_over_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              employee_id INTEGER NOT NULL REFERENCES employees(id),
              amount REAL NOT NULL,
              previous_cycle_start TEXT NOT NULL,
              previous_cycle_end TEXT NOT NULL,
              new_cycle_start TEXT NOT NULL,
              new_cycle_end TEXT NOT NULL,
              reason TEXT NOT NULL DEFAULT '',
              carried_at INTEGER NOT NULL,
              local_uuid TEXT NOT NULL UNIQUE,
              server_id INTEGER,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER,
              created_at_iso TEXT,
              updated_at_iso TEXT,
              deleted_at_iso TEXT,
              created_at_epoch INTEGER NOT NULL DEFAULT 0,
              last_modified_epoch INTEGER NOT NULL DEFAULT 0,
              version INTEGER NOT NULL DEFAULT 1,
              origin TEXT NOT NULL DEFAULT 'local',
              vector_clock TEXT NOT NULL DEFAULT '{}',
              device_id TEXT NOT NULL DEFAULT ''
            )
          ''');
          await m.database.customStatement(
            'CREATE INDEX IF NOT EXISTS idx_salary_carryover_employee ON salary_carry_over_logs (employee_id)',
          );
          developer.log(
            'Migration 43: created salary_carry_over_logs table',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 43: salary_carry_over_logs already exists: $e',
            name: 'db.migration',
          );
        }
      }
      if (from < 44) {
        // ✅ إضافة عمودي تتبع التسليم لكل وجهة (Primary / Secondary)
        // يسمح بمشاركة outbox بين مزامنتين متوازيتين بدون فقدان بيانات
        // أو سباق race condition. السجل يُحذف فقط بعد نجاح كلا الوجهتين.
        try {
          await m.database.customStatement(
            'ALTER TABLE outbox ADD COLUMN delivered_to_primary INTEGER NOT NULL DEFAULT 0',
          );
          developer.log(
            'Migration 44: added outbox.delivered_to_primary column',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 44: delivered_to_primary already exists: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.database.customStatement(
            'ALTER TABLE outbox ADD COLUMN delivered_to_secondary INTEGER NOT NULL DEFAULT 1',
          );
          developer.log(
            'Migration 44: added outbox.delivered_to_secondary column',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 44: delivered_to_secondary already exists: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.database.customStatement(
            'CREATE INDEX IF NOT EXISTS idx_outbox_delivery_primary ON outbox (delivered_to_primary, processing_status)',
          );
          await m.database.customStatement(
            'CREATE INDEX IF NOT EXISTS idx_outbox_delivery_secondary ON outbox (delivered_to_secondary, processing_status)',
          );
          developer.log(
            'Migration 44: created delivery tracking indexes',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 44: indexes already exist: $e',
            name: 'db.migration',
          );
        }
      }
      if (from < 45) {
        // ✅ إنشاء جدول AncestorCache للدمج ثلاثي الأطراف (3-way merge)
        try {
          await m.database.customStatement('''
            CREATE TABLE IF NOT EXISTS ancestor_cache (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              entity TEXT NOT NULL,
              local_uuid TEXT NOT NULL,
              data_json TEXT NOT NULL,
              captured_at INTEGER NOT NULL,
              UNIQUE(entity, local_uuid)
            )
          ''');
          developer.log(
            'Migration 45: created ancestor_cache table',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 45: ancestor_cache already exists: $e',
            name: 'db.migration',
          );
        }
      }
      if (from < 46) {
        // ✅ v2: إضافة أعمدة جديدة لتطابق Appwrite Cloud Schema v2
        // - idempotencyKey لكل الجداول (عبر SyncFields mixin)
        // - employeeID لجدول employees
        // - employeeUuid لجدول expenses
        final idempotencyTables = [
          'rooms',
          'bookings',
          'payments',
          'expenses',
          'employees',
          'debts',
          'devices',
          'sync_logs',
          'booking_notes',
          'cash_transactions',
          'booking_nights',
          'salary_cycles',
          'salary_payments',
          'salary_withdrawals',
          'shift_notes',
          'price_adjustments',
          'audit_logs',
          'payment_voids',
          'booking_price_adjustments',
          'salary_carry_over_logs',
          'guest_infos',
          'blacklist',
          'app_settings',
          'sync_state',
          'app_users',
        ];
        for (final table in idempotencyTables) {
          try {
            await m.database.customStatement(
              'ALTER TABLE $table ADD COLUMN idempotency_key TEXT',
            );
          } catch (e) {
            developer.log(
              'Migration 46: $table.idempotency_key already exists: $e',
              name: 'db.migration',
            );
          }
        }
        // employeeID لجدول employees
        try {
          await m.database.customStatement(
            'ALTER TABLE employees ADD COLUMN employee_i_d TEXT',
          );
        } catch (e) {
          developer.log(
            'Migration 46: employees.employee_i_d already exists: $e',
            name: 'db.migration',
          );
        }
        // employeeUuid لجدول expenses
        try {
          await m.database.customStatement(
            'ALTER TABLE expenses ADD COLUMN employee_uuid TEXT',
          );
        } catch (e) {
          developer.log(
            'Migration 46: expenses.employee_uuid already exists: $e',
            name: 'db.migration',
          );
        }
        developer.log(
          'Migration 46: added idempotencyKey, employeeID, employeeUuid columns',
          name: 'db.migration',
        );
      }
      if (from < 47) {
        // ✅ v2: إضافة حقول payment_voids الإضافية لتطابق Appwrite Cloud
        // - note: ملاحظة على الإلغاء
        // - originalAmount: المبلغ الأصلي للدفع قبل الإلغاء
        // - paymentUuid: UUID الدفع المرتبط (مستقل عن originalPaymentUuid)
        try {
          await m.database.customStatement(
            'ALTER TABLE payment_voids ADD COLUMN note TEXT',
          );
        } catch (e) {
          developer.log(
            'Migration 47: payment_voids.note already exists: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.database.customStatement(
            'ALTER TABLE payment_voids ADD COLUMN original_amount REAL',
          );
        } catch (e) {
          developer.log(
            'Migration 47: payment_voids.original_amount already exists: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.database.customStatement(
            'ALTER TABLE payment_voids ADD COLUMN payment_uuid TEXT',
          );
        } catch (e) {
          developer.log(
            'Migration 47: payment_voids.payment_uuid already exists: $e',
            name: 'db.migration',
          );
        }
        developer.log(
          'Migration 47: added note, originalAmount, paymentUuid to payment_voids',
          name: 'db.migration',
        );
      }

      // === Migration 48: SyncFields لـ audit_logs ===
      // ✅ P0-5 FIX (2026-08-06 Audit): كان هذا الـ block متعشّشاً داخل
      // `if (from < 47)` — أي مستخدم على v47 لن يدخل الـ block الأب إطلاقاً،
      // وبالتالي لن تُضاف حقول المزامنة إلى audit_logs. النتيجة: فشل صامت
      // في مزامنة audit_logs وتراكمها في outbox بحالة failed ثم dead.
      // الإصلاح: إخراج الـ block إلى top-level في onUpgrade.
      if (from < 48) {
        // ✅ v2: إضافة SyncFields إلى audit_logs للتوافق مع مخطط Appwrite Cloud
        // audit_logs لم يكن يمتلك حقول المزامنة الأساسية (serverId, updatedAt,
        // lastModified, version, origin, vectorClock, إلخ)
        // هذه الحقول ضرورية لتتبع مصدر وتوقيت كل سجل تدقيق عبر الأجهزة.
        final auditLogColumns = <String, String>{
          'server_id': 'INTEGER',
          'updated_at': 'INTEGER',
          'deleted_at': 'INTEGER',
          'last_modified': 'INTEGER',
          'created_at_iso': 'TEXT',
          'updated_at_iso': 'TEXT',
          'deleted_at_iso': 'TEXT',
          'created_at_epoch': 'INTEGER NOT NULL DEFAULT 0',
          'last_modified_epoch': 'INTEGER NOT NULL DEFAULT 0',
          'version': 'INTEGER NOT NULL DEFAULT 1',
          'origin': 'TEXT NOT NULL DEFAULT \'local\'',
          'vector_clock': 'TEXT NOT NULL DEFAULT \'{}\'',
          'idempotency_key': 'TEXT',
        };
        for (final column in auditLogColumns.entries) {
          try {
            await m.database.customStatement(
              'ALTER TABLE audit_logs ADD COLUMN ${column.key} ${column.value}',
            );
            developer.log(
              'Migration 48: added audit_logs.${column.key}',
              name: 'db.migration',
            );
          } catch (e) {
            // العمود موجود مسبقاً — ليس خطأ
            developer.log(
              'Migration 48: audit_logs.${column.key} already exists: $e',
              name: 'db.migration',
            );
          }
        }
        developer.log(
          'Migration 48: added SyncFields columns to audit_logs',
          name: 'db.migration',
        );
      }

      // === Migration 49: Performance indexes for sorted queries ===
      // ✅ P0-5 FIX (2026-08-06 Audit): أُخرج من تعشّش Migration 47.
      if (from < 49) {
        const perfIndexes = [
          'CREATE INDEX IF NOT EXISTS idx_bookings_checkin ON bookings (checkin_date)',
          'CREATE INDEX IF NOT EXISTS idx_debts_payment_date ON debts (payment_date)',
          'CREATE INDEX IF NOT EXISTS idx_salary_withdrawals_expense ON salary_withdrawals (expense_id)',
          'CREATE INDEX IF NOT EXISTS idx_sync_log_created ON sync_log (created_at)',
        ];
        for (final sql in perfIndexes) {
          try {
            await m.database.customStatement(sql);
            developer.log(
              'Migration 49: created index: $sql',
              name: 'db.migration',
            );
          } catch (e) {
            developer.log(
              'Migration 49: index already exists or failed: $e',
              name: 'db.migration',
            );
          }
        }
        developer.log(
          'Migration 49: performance indexes created successfully',
          name: 'db.migration',
        );
      }

      // === Migration 50: Additional indexes for frequently queried columns ===
      // ✅ P0-5 FIX (2026-08-06 Audit): أُخرج من تعشّش Migration 47.
      if (from < 50) {
        const additionalIndexes = [
          'CREATE INDEX IF NOT EXISTS idx_booking_nights_booking ON booking_nights (booking_local_id)',
          'CREATE INDEX IF NOT EXISTS idx_guest_infos_room ON guest_infos (room_number)',
          'CREATE INDEX IF NOT EXISTS idx_sync_log_sync_id ON sync_log (sync_id)',
          'CREATE INDEX IF NOT EXISTS idx_sync_log_device_id ON sync_log (device_id)',
          'CREATE INDEX IF NOT EXISTS idx_sync_conflicts_table_uuid ON sync_conflicts (table_name, uuid)',
          'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue (status)',
          'CREATE INDEX IF NOT EXISTS idx_sync_queue_table ON sync_queue (table_name)',
        ];
        for (final sql in additionalIndexes) {
          try {
            await m.database.customStatement(sql);
            developer.log(
              'Migration 50: created index: $sql',
              name: 'db.migration',
            );
          } catch (e) {
            developer.log(
              'Migration 50: index already exists or failed: $e',
              name: 'db.migration',
            );
          }
        }
        developer.log(
          'Migration 50: additional indexes created successfully',
          name: 'db.migration',
        );
      }

      // === Migration 51: Audit Fixes (2026-08-06) ===
      // ✅ P0-1: UNIQUE index على outbox.idempotency_key (partial — WHERE NOT NULL)
      // ✅ P0-2: تحديث ancestor_cache.capturedAt من ثواني لمللي ثانية (×1000)
      if (from < 51) {
        // P0-1: UNIQUE index يمنع تكرار نفس idempotency_key في outbox
        try {
          await m.database.customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_outbox_idempotency_unique '
            'ON outbox (idempotency_key) WHERE idempotency_key IS NOT NULL',
          );
          developer.log(
            'Migration 51: created unique index on outbox.idempotency_key',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 51: idempotency unique index failed (may already exist): $e',
            name: 'db.migration',
          );
        }

        // P0-2: تحديث ancestor_cache.capturedAt من ثواني لمللي ثانية
        // القيم القديمة (< 10^12) هي ثواني، نضربها في 1000 لتحويلها لمللي ثانية
        try {
          await m.database.customStatement(
            'UPDATE ancestor_cache SET captured_at = captured_at * 1000 '
            'WHERE captured_at < 1000000000000',
          );
          developer.log(
            'Migration 51: converted ancestor_cache.captured_at to milliseconds',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 51: ancestor_cache timestamp conversion failed: $e',
            name: 'db.migration',
          );
        }

        developer.log(
          'Migration 51: audit fixes applied (unique idempotency + timestamp units)',
          name: 'db.migration',
        );
      }
      // === Migration 52: Add sync_timestamp to all SyncFields tables ===
      if (from < 52) {
        const syncTimestampTables = [
          'rooms',
          'bookings',
          'booking_notes',
          'employees',
          'expenses',
          'cash_transactions',
          'payments',
          'debts',
          'shift_notes',
          'booking_nights',
          'hotel_day_ledger',
          'price_adjustments',
          'booking_price_adjustments',
          'payment_voids',
          'guest_infos',
          'salary_cycles',
          'salary_payments',
          'salary_withdrawals',
          'salary_carry_over_logs',
          'audit_logs',
        ];
        for (final table in syncTimestampTables) {
          try {
            await m.database.customStatement(
              'ALTER TABLE $table ADD COLUMN sync_timestamp INTEGER DEFAULT 0',
            );
            developer.log(
              'Migration 52: added sync_timestamp to $table',
              name: 'db.migration',
            );
          } catch (e) {
            developer.log(
              'Migration 52: sync_timestamp already exists in $table: $e',
              name: 'db.migration',
            );
          }
        }
        developer.log(
          'Migration 52: added sync_timestamp to all sync tables',
          name: 'db.migration',
        );
      }
      // === Migration 53: Add missing Appwrite schema fields ===
      if (from < 53) {
        developer.log(
          'Migration 53: adding missing Appwrite fields...',
          name: 'db.migration',
        );

        // bookings: financialFrozenAt, financialHash
        try {
          await m.database.customStatement(
            'ALTER TABLE bookings ADD COLUMN financial_frozen_at INTEGER DEFAULT NULL',
          );
          await m.database.customStatement(
            'ALTER TABLE bookings ADD COLUMN financial_hash TEXT DEFAULT NULL',
          );
          developer.log(
            'Migration 53: added financial_frozen_at, financial_hash to bookings',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 53: bookings fields may already exist: $e',
            name: 'db.migration',
          );
        }

        // payments: voidReason, isImmutable
        try {
          await m.database.customStatement(
            'ALTER TABLE payments ADD COLUMN void_reason TEXT DEFAULT NULL',
          );
          await m.database.customStatement(
            'ALTER TABLE payments ADD COLUMN is_immutable INTEGER DEFAULT 0',
          );
          developer.log(
            'Migration 53: added void_reason, is_immutable to payments',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 53: payments fields may already exist: $e',
            name: 'db.migration',
          );
        }

        // debts: guestPhone, description, status, dueDate
        try {
          await m.database.customStatement(
            'ALTER TABLE debts ADD COLUMN guest_phone TEXT DEFAULT NULL',
          );
          await m.database.customStatement(
            'ALTER TABLE debts ADD COLUMN description TEXT DEFAULT NULL',
          );
          await m.database.customStatement(
            'ALTER TABLE debts ADD COLUMN status TEXT DEFAULT NULL',
          );
          await m.database.customStatement(
            'ALTER TABLE debts ADD COLUMN due_date TEXT DEFAULT NULL',
          );
          developer.log(
            'Migration 53: added guest_phone, description, status, due_date to debts',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 53: debts fields may already exist: $e',
            name: 'db.migration',
          );
        }

        // price_adjustments: adjustmentMode, bookingUuid, appliedAt
        try {
          await m.database.customStatement(
            "ALTER TABLE price_adjustments ADD COLUMN adjustment_mode TEXT DEFAULT 'per_night'",
          );
          await m.database.customStatement(
            'ALTER TABLE price_adjustments ADD COLUMN booking_uuid TEXT DEFAULT NULL',
          );
          await m.database.customStatement(
            'ALTER TABLE price_adjustments ADD COLUMN applied_at INTEGER DEFAULT NULL',
          );
          developer.log(
            'Migration 53: added adjustment_mode, booking_uuid, applied_at to price_adjustments',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 53: price_adjustments fields may already exist: $e',
            name: 'db.migration',
          );
        }

        // booking_price_adjustments: adjustmentMode
        try {
          await m.database.customStatement(
            "ALTER TABLE booking_price_adjustments ADD COLUMN adjustment_mode TEXT DEFAULT 'per_night'",
          );
          developer.log(
            'Migration 53: added adjustment_mode to booking_price_adjustments',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 53: booking_price_adjustments adjustment_mode may already exist: $e',
            name: 'db.migration',
          );
        }

        // booking_nights: bookingUuidCache, serverBookingId
        try {
          await m.database.customStatement(
            'ALTER TABLE booking_nights ADD COLUMN booking_uuid_cache TEXT DEFAULT NULL',
          );
          await m.database.customStatement(
            'ALTER TABLE booking_nights ADD COLUMN server_booking_id INTEGER DEFAULT NULL',
          );
          developer.log(
            'Migration 53: added booking_uuid_cache, server_booking_id to booking_nights',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 53: booking_nights fields may already exist: $e',
            name: 'db.migration',
          );
        }

        // booking_price_adjustments: adjustmentType, appliedAt
        try {
          await m.database.customStatement(
            'ALTER TABLE booking_price_adjustments ADD COLUMN adjustment_type INTEGER DEFAULT NULL',
          );
          await m.database.customStatement(
            'ALTER TABLE booking_price_adjustments ADD COLUMN applied_at INTEGER DEFAULT NULL',
          );
          developer.log(
            'Migration 53: added adjustment_type, applied_at to booking_price_adjustments',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 53: booking_price_adjustments fields may already exist: $e',
            name: 'db.migration',
          );
        }

        // salary_carry_over_logs: fromCycleId, toCycleId, carryDate, performedBy, hotelDayKey
        try {
          await m.database.customStatement(
            'ALTER TABLE salary_carry_over_logs ADD COLUMN from_cycle_id TEXT DEFAULT NULL',
          );
          await m.database.customStatement(
            'ALTER TABLE salary_carry_over_logs ADD COLUMN to_cycle_id TEXT DEFAULT NULL',
          );
          await m.database.customStatement(
            'ALTER TABLE salary_carry_over_logs ADD COLUMN carry_date TEXT DEFAULT NULL',
          );
          await m.database.customStatement(
            'ALTER TABLE salary_carry_over_logs ADD COLUMN performed_by TEXT DEFAULT NULL',
          );
          await m.database.customStatement(
            'ALTER TABLE salary_carry_over_logs ADD COLUMN hotel_day_key TEXT DEFAULT NULL',
          );
          developer.log(
            'Migration 53: added from_cycle_id, to_cycle_id, carry_date, performed_by, hotel_day_key to salary_carry_over_logs',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 53: salary_carry_over_logs fields may already exist: $e',
            name: 'db.migration',
          );
        }

        developer.log(
          'Migration 53: all missing Appwrite schema fields added',
          name: 'db.migration',
        );
      }

      // === Migration 54: syncTimestamp non-nullable DEFAULT 0 ===
      // ✅ syncTimestamp كان nullable في SyncFields. تم تغييره إلى
      // integer().withDefault(const Constant(0))() في الـ schema.
      // SQLite لا يدعم ALTER COLUMN لتغيير nullable → NOT NULL مباشرة.
      // الحل: backfill كل القيم NULL إلى 0. الأعمدة الموجودة فعلاً تحمل
      // DEFAULT 0 (من Migration 52)، لكن القيم NULL المُدرجة يدوياً
      // تحتاج backfill. بعد ذلك، Drift يتعامل مع INSERT الجديد كـ NOT NULL.
      if (from < 54) {
        const syncTimestampTables = [
          'rooms',
          'bookings',
          'booking_notes',
          'employees',
          'expenses',
          'cash_transactions',
          'payments',
          'debts',
          'shift_notes',
          'booking_nights',
          'hotel_day_ledger',
          'price_adjustments',
          'booking_price_adjustments',
          'payment_voids',
          'guest_infos',
          'salary_cycles',
          'salary_payments',
          'salary_withdrawals',
          'salary_carry_over_logs',
          'audit_logs',
        ];
        for (final table in syncTimestampTables) {
          try {
            await m.database.customStatement(
              'UPDATE $table SET sync_timestamp = 0 WHERE sync_timestamp IS NULL',
            );
          } catch (e) {
            developer.log(
              'Migration 54: $table sync_timestamp backfill skipped: $e',
              name: 'db.migration',
            );
          }
        }
        developer.log(
          'Migration 54: sync_timestamp backfilled to 0 for all SyncFields tables',
          name: 'db.migration',
        );
      }

      // === Migration 55: Separate primary/secondary processing state ===
      // ✅ Sync Safety Fix (2026-08-10): فصل حالة المعالجة لكل وجهة.
      // سابقاً، processingStatus و attempts و lastError كانت مشتركة —
      // فشل Secondary يمنع Primary من المعالجة.
      if (from < 55) {
        const newColumns = <String, String>{
          'primary_processing_status': "TEXT DEFAULT 'pending'",
          'primary_attempts': 'INTEGER DEFAULT 0',
          'primary_last_error': 'TEXT',
          'secondary_processing_status': "TEXT DEFAULT 'pending'",
          'secondary_attempts': 'INTEGER DEFAULT 0',
          'secondary_last_error': 'TEXT',
        };
        for (final entry in newColumns.entries) {
          try {
            await m.database.customStatement(
              'ALTER TABLE outbox ADD COLUMN ${entry.key} ${entry.value}',
            );
            developer.log(
              'Migration 55: added outbox.${entry.key}',
              name: 'db.migration',
            );
          } catch (e) {
            developer.log(
              'Migration 55: outbox.${entry.key} may already exist: $e',
              name: 'db.migration',
            );
          }
        }
        // Backfill: نسخ الحالة المشتركة الحالية إلى primary columns
        try {
          await m.database.customStatement(
            'UPDATE outbox SET primary_processing_status = processing_status, '
            'primary_attempts = attempts, primary_last_error = last_error, '
            'secondary_processing_status = processing_status, '
            'secondary_attempts = attempts, secondary_last_error = last_error',
          );
          developer.log(
            'Migration 55: backfilled primary/secondary state from shared columns',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 55: backfill failed: $e',
            name: 'db.migration',
          );
        }
      }

      // === Migration 56: Full Sync Bootstrap Flag ===
      // ✅ Sync Safety Wave 2 (2026-08-12): إضافة عمود `full_sync_complete`
      // إلى جدول sync_state. القيمة الافتراضية 0 (false) تعني أن الجهاز
      // لم يكمل بعد أول full sync بنجاح، فيجب البقاء في وضع "full fetch"
      // بدلاً من delta sync.
      //
      // هذا يمنع سيناريو خطير: إذا نجحت أول دورة full sync ظاهرياً
      // (لا exception) لكن بعض السجلات لم تُعالج داخل `_syncXxx`، فإن
      // `lastPullTs` يُحدَّث والجهاز يتحول لـ delta mode — مما يعني أن
      // السجلات غير المُعالَجة لن تُسحب أبداً (لأن delta filter يستثنيها).
      //
      // مع هذا الـ flag، يتم ضبطه على 1 فقط بعد التحقق من اكتمال كل
      // الكولكشنات بنجاح في دورة واحدة (failedCollections.isEmpty).
      if (from < 56) {
        try {
          await m.database.customStatement(
            'ALTER TABLE sync_state ADD COLUMN full_sync_complete INTEGER NOT NULL DEFAULT 0',
          );
          developer.log(
            'Migration 56: added sync_state.full_sync_complete column',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 56: sync_state.full_sync_complete may already exist: $e',
            name: 'db.migration',
          );
        }
      }

      // === Migration 57: Outbox payload_version + processing_payload_version ===
      // ✅ Sync Safety Wave 5 (2026-08-12): Generation field لمنع stale ack.
      //
      // `payload_version`:
      //   - يُزداد بمقدار 1 عند كل `merge()` تحدّث payload/op/clientTs
      //   - يبدأ من 1 للسجلات الجديدة
      //   - القيمة الافتراضية 1 (DEFAULT 1)
      //
      // `processing_payload_version`:
      //   - قيمة `payload_version` عند الالتقاط (claim)
      //   - nullable (NULL للسجلات غير المُلتقَطة)
      //   - تُستخدم للتحقق أن العامل الذي يؤكد التسليم هو نفسه الذي التقطه
      //
      // السباق الذي يمنعه:
      // 1. worker-A يلتقط السجل (payload_version=5, processing_payload_version=5)
      // 2. أثناء المعالجة، payload يُحدَّث (payload_version=6)
      // 3. worker-A يحاول تأكيد التسليم
      // 4. الكود يرى 5 != 6 → يرفض التأكيد ويُعيد السجل لـ pending
      if (from < 57) {
        try {
          await m.database.customStatement(
            'ALTER TABLE outbox ADD COLUMN payload_version INTEGER NOT NULL DEFAULT 1',
          );
          developer.log(
            'Migration 57: added outbox.payload_version column',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 57: outbox.payload_version may already exist: $e',
            name: 'db.migration',
          );
        }
        try {
          await m.database.customStatement(
            'ALTER TABLE outbox ADD COLUMN processing_payload_version INTEGER',
          );
          developer.log(
            'Migration 57: added outbox.processing_payload_version column',
            name: 'db.migration',
          );
        } catch (e) {
          developer.log(
            'Migration 57: outbox.processing_payload_version may already exist: $e',
            name: 'db.migration',
          );
        }
      }

      // === Migration 59: hot financial-report indexes ===
      // فهارس جزئية تقلل الحجم وكلفة الكتابة، وتستهدف فقط الصفوف النشطة
      // التي تقرؤها تقارير اليوم الفندقي ومسارات fallback للبيانات القديمة.
      if (from < 59) {
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_payments_active_hotel_day '
          'ON payments (hotel_day_key, revenue_type, payment_date) '
          'WHERE deleted_at IS NULL AND is_voided = 0',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_payments_legacy_active_date '
          'ON payments (payment_date) WHERE hotel_day_key IS NULL '
          'AND deleted_at IS NULL AND is_voided = 0',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_expenses_active_hotel_day '
          'ON expenses (hotel_day_key, expense_type, date) '
          'WHERE deleted_at IS NULL',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_expenses_legacy_active_date '
          'ON expenses (date) WHERE hotel_day_key IS NULL '
          'AND deleted_at IS NULL',
        );
      }

      // === Migration 58: debts — bookingUuidCache, debtorName, amount, date ===
      // ✅ Sync Safety Wave 6 (2026-08-12): إضافة 4 حقول مطلوبة من Appwrite Cloud
      // لجدول debts لكنها كانت مفقودة من الـ Drift table.
      //
      // المشكلة التي تم إصلاحها:
      // - Appwrite Cloud يخزّن هذه الحقول (انظر appwrite_schema_verifier.dart:301-304)
      // - filterPayload يسمح بها (انظر appwrite_sync_utils.dart:362-411)
      // - لكن Drift table لم يكن لديها كأعمدة — فلا يمكن قراءتها أو كتابتها
      // - debtToRemote لم يرسلها، DebtsAdapter.fromJson لم يقرأها
      //
      // الحقول:
      // - bookingUuidCache: معرّف UUID للحجز المرتبط (للربط بين الأجهزة بدل bookingLocalId)
      // - debtorName: اسم المدين (قد يختلف عن guestName في حالات معينة)
      // - amount: مبلغ الدين (قد يختلف عن totalAmount في بعض الحالات)
      // - date: تاريخ الدين (مستقل عن checkinDate/checkoutDate/paymentDate)
      //
      // جميع الحقول nullable — لا تتطلب backfill.
      if (from < 58) {
        const newColumns = <String, String>{
          'booking_uuid_cache': 'TEXT',
          'debtor_name': 'TEXT',
          'amount': 'REAL',
          'date': 'TEXT',
        };
        for (final entry in newColumns.entries) {
          try {
            await m.database.customStatement(
              'ALTER TABLE debts ADD COLUMN ${entry.key} ${entry.value}',
            );
            developer.log(
              'Migration 58: added debts.${entry.key}',
              name: 'db.migration',
            );
          } catch (e) {
            developer.log(
              'Migration 58: debts.${entry.key} may already exist: $e',
              name: 'db.migration',
            );
          }
        }
      }

      // === Migration 60: measured low-end query indexes ===
      // These indexes were selected from EXPLAIN QUERY PLAN measurements for
      // the active list/report and pending Outbox queries. Keep this migration
      // after 58 because the historical migration order is not chronological.
      if (from < 60) {
        const indexes = [
          'CREATE INDEX IF NOT EXISTS idx_bookings_active_checkin ON bookings (checkin_date DESC) WHERE deleted_at IS NULL',
          'CREATE INDEX IF NOT EXISTS idx_payments_active_report_date ON payments (payment_date DESC) WHERE deleted_at IS NULL AND is_voided = 0 AND is_pending_balance = 0',
          'CREATE INDEX IF NOT EXISTS idx_expenses_active_date ON expenses (date DESC) WHERE deleted_at IS NULL',
          "CREATE INDEX IF NOT EXISTS idx_outbox_pending_primary_source_ts ON outbox (source, client_ts) WHERE processing_status = 'pending' AND delivered_to_primary = 0",
        ];
        for (final sql in indexes) {
          await m.database.customStatement(sql);
        }
      }
    },
  );

  /// تجميع جميع الجداول المطلوب مزامنتها في خريطة JSON
  ///
  /// ✅ تحسين: استخراج JSON mapping إلى مساعد `_tableToJson` لتقليل duplication
  /// ولتمكين إضافة pagination أو lazy loading مستقبلاً بشكل مركزي.
  /// ملاحظة: sqflite يُنفّذ الاستعلامات تسلسلياً على نفس الاتصال، لذا البقاء
  /// بالترتيب التسلسلي هو الأضمن. للتحسين المستقبلي: نقل هذه الدالة بالكامل
  /// إلى Isolate (انظر توصية P3-15 في تقرير الأداء).
  Future<Map<String, dynamic>> getAllTablesAsJson() async {
    return {
      'rooms': await _tableToJson(rooms),
      'bookings': await _tableToJson(bookings),
      'booking_notes': await _tableToJson(bookingNotes),
      'shift_notes': await _tableToJson(shiftNotes),
      'employees': await _tableToJson(employees),
      'expenses': await _tableToJson(expenses),
      'cash_transactions': await _tableToJson(cashTransactions),
      'payments': await _tableToJson(payments),
      'debts': await _tableToJson(debts),
      'booking_nights': await _tableToJson(bookingNights),
      'hotel_day_ledger': await _tableToJson(hotelDayLedger),
      'auto_fix_runs': await _tableToJson(autoFixRuns),
      'integrity_violations': await _tableToJson(integrityViolations),
      'app_sessions': await _tableToJson(appSessions),
      'salary_cycles': await _tableToJson(salaryCycles),
      'salary_payments': await _tableToJson(salaryPayments),
      'booking_price_adjustments': await _tableToJson(bookingPriceAdjustments),
      'guests': <Map<String, dynamic>>[],
      'services': <Map<String, dynamic>>[],
      'settings': <Map<String, dynamic>>[],
    };
  }

  /// مساعد داخلي: تنفيذ SELECT على جدول وإرجاع صفوفه كـ List<Map<String, dynamic>>.
  /// يعزل منطق JSON serialization عن الاستعلام لتسهيل الصيانة والتحسين المستقبلي.
  Future<List<Map<String, dynamic>>> _tableToJson<T extends Table>(
    TableInfo<T, dynamic> table,
  ) async {
    final rows = await select(table).get();
    return rows
        .map((e) => (e as dynamic).toJson() as Map<String, dynamic>)
        .toList();
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

    // ✅ إصلاح: PRAGMA foreign_keys = OFF يجب أن يكون خارج transaction
    // لأن SQLite يتجاهل هذا الأمر داخل transaction بصمت!
    await customStatement('PRAGMA foreign_keys = OFF');

    try {
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
      }); // نهاية transaction
    } finally {
      // ✅ إعادة تفعيل foreign key constraints خارج transaction
      await customStatement('PRAGMA foreign_keys = ON');
      // ✅ إضافة تحقق من سلامة المفاتيح الأجنبية بعد إعادة التفعيل
      final violations = await customSelect(
        'PRAGMA foreign_key_check',
        readsFrom: Set.unmodifiable({}),
      ).get();
      if (violations.isNotEmpty) {
        developer.log(
          '⚠️ FK violations detected after bulk replace: ${violations.length} rows',
          name: 'AppDatabase',
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ✅ (2026-08-30) SyncRemoteMeta — helpers للسحب metadata-first (الفجوة 3+4)
  // ═══════════════════════════════════════════════════════════════════════

  /// خريطة docId → $updatedAt (بالثواني) لكل مستندات كولكشن معروفة محلياً.
  Future<Map<String, int>> getRemoteMetaMap(String collection) async {
    final rows = await (select(
      syncRemoteMeta,
    )..where((t) => t.collection.equals(collection))).get();
    return {for (final r in rows) r.docId: r.remoteUpdatedAtSec};
  }

  /// تحديث/إدراج خريطة $updatedAt البعيدة لكولكشن (دفعة واحدة على شرائح).
  Future<void> upsertRemoteMeta(
    String collection,
    Map<String, int> meta,
  ) async {
    if (meta.isEmpty) return;
    final entries = meta.entries.toList(growable: false);
    // شرائح 500 لتجنب معاملات ضخمة على أجهزة ضعيفة
    const chunkSize = 500;
    for (var i = 0; i < entries.length; i += chunkSize) {
      final end = (i + chunkSize < entries.length)
          ? i + chunkSize
          : entries.length;
      final chunk = entries.sublist(i, end);
      await batch((b) {
        b.insertAllOnConflictUpdate(syncRemoteMeta, [
          for (final e in chunk)
            SyncRemoteMetaCompanion.insert(
              collection: collection,
              docId: e.key,
              remoteUpdatedAtSec: e.value,
            ),
        ]);
      });
    }
  }

  /// مسح خريطة الـ metadata للكولكشن المحدد أو للكل.
  /// يُستدعى من resetSyncState — مسحه إلزامي وإلا اعتبر السحب الكامل
  /// التالي أن كل شيء محفوظ وتخطى الجلب.
  Future<void> clearRemoteMeta({String? collection}) async {
    if (collection == null) {
      await delete(syncRemoteMeta).go();
    } else {
      await (delete(
        syncRemoteMeta,
      )..where((t) => t.collection.equals(collection))).go();
    }
  }
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    // ✅ دعم Windows/Linux/macOS عبر path_provider + sqflite_common_ffi
    // sqflite.getDatabasesPath() لا يعمل على Desktop (Android/iOS فقط)
    final Directory dbDir;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // على Desktop، استخدم ApplicationDocumentsPath
      final appDir = await getApplicationDocumentsDirectory();
      dbDir = appDir;
    } else {
      // على Mobile، استخدم sqflite path
      final sqfliteDir = await sqflite.getDatabasesPath();
      dbDir = Directory(sqfliteDir);
    }
    final file = File(p.join(dbDir.path, _dbFileName));
    return NativeDatabase.createInBackground(file);
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

  /// Synchronous singleton accessor. Safe for use from synchronous contexts.
  /// During restore operations, asserts that an instance already exists.
  static AppDatabase get instance {
    if (_isRestoring) {
      assert(
        _instance != null,
        'Database is being restored; cannot access instance during restore',
      );
    }
    return _instance ??= AppDatabase();
  }

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
      } catch (e) {
        developer.log(
          '⚠️ Database stop callback error: $e',
          name: 'DatabaseManager',
        );
      }
    }
    try {
      await _instance?.close();
    } catch (e) {
      developer.log('⚠️ Database close error: $e', name: 'DatabaseManager');
    }
    _instance = null;
  }

  static Future<void> reopen() async {
    await close();
    _instance = AppDatabase();
    if (_onRestartCallback != null) {
      try {
        await _onRestartCallback!();
      } catch (e) {
        developer.log(
          '⚠️ Database restart callback error: $e',
          name: 'DatabaseManager',
        );
      }
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
