// ignore_for_file: sort_constructors_first, sort_unnamed_constructors_first

import '../local_db.dart';
import '../repositories/base_repository.dart';
import 'audit_logs_adapter.dart';
import 'booking_notes_adapter.dart';
import 'booking_price_adjustments_adapter.dart';
import 'bookings_adapter.dart';
import 'cash_transactions_adapter.dart';
import 'debts_adapter.dart';
import 'employees_adapter.dart';
import 'expenses_adapter.dart';
import 'guest_infos_adapter.dart';
import 'id_resolver.dart';
import 'nights_adapter.dart';
import 'payment_voids_adapter.dart';
import 'payments_adapter.dart';
import 'price_adjustments_adapter.dart';
import 'rooms_adapter.dart';
import 'salary_carry_over_logs_adapter.dart';
import 'salary_cycles_adapter.dart';
import 'salary_payments_adapter.dart';
import 'salary_withdrawals_adapter.dart';
import 'shift_notes_adapter.dart';

/// ✅ Singleton AdapterRegistry - يضمن وجود instance واحد فقط
/// يُستخدم عبر Provider في repository_providers.dart
class AdapterRegistry {
  AdapterRegistry._(this.db)
    : resolver = IdResolver(db),
      bookings = BaseRepository<Booking, BookingsCompanion>(
        db: db,
        table: db.bookings,
        adapter: BookingsAdapter(IdResolver(db)),
      ),
      payments = BaseRepository<Payment, PaymentsCompanion>(
        db: db,
        table: db.payments,
        adapter: PaymentsAdapter(IdResolver(db)),
      ),
      expenses = BaseRepository<Expense, ExpensesCompanion>(
        db: db,
        table: db.expenses,
        adapter: ExpensesAdapter(IdResolver(db)),
      ),
      debts = BaseRepository<Debt, DebtsCompanion>(db: db, table: db.debts, adapter: DebtsAdapter(IdResolver(db))),
      rooms = BaseRepository<Room, RoomsCompanion>(db: db, table: db.rooms, adapter: RoomsAdapter(IdResolver(db))),
      nights = BaseRepository<BookingNight, BookingNightsCompanion>(
        db: db,
        table: db.bookingNights,
        adapter: NightsAdapter(IdResolver(db)),
      ),
      employees = BaseRepository<Employee, EmployeesCompanion>(
        db: db,
        table: db.employees,
        adapter: EmployeesAdapter(IdResolver(db)),
      ),
      salaryCycles = BaseRepository<SalaryCycle, SalaryCyclesCompanion>(
        db: db,
        table: db.salaryCycles,
        adapter: SalaryCyclesAdapter(IdResolver(db)),
      ),
      salaryPayments = BaseRepository<SalaryPayment, SalaryPaymentsCompanion>(
        db: db,
        table: db.salaryPayments,
        adapter: SalaryPaymentsAdapter(IdResolver(db)),
      ),
      bookingNotes = BaseRepository<BookingNote, BookingNotesCompanion>(
        db: db,
        table: db.bookingNotes,
        adapter: BookingNotesAdapter(IdResolver(db)),
      ),
      cashTransactions = BaseRepository<CashTransaction, CashTransactionsCompanion>(
        db: db,
        table: db.cashTransactions,
        adapter: CashTransactionsAdapter(IdResolver(db)),
      ),
      shiftNotes = BaseRepository<ShiftNote, ShiftNotesCompanion>(
        db: db,
        table: db.shiftNotes,
        adapter: ShiftNotesAdapter(IdResolver(db)),
      ),
      priceAdjustments = BaseRepository<PriceAdjustment, PriceAdjustmentsCompanion>(
        db: db,
        table: db.priceAdjustments,
        adapter: PriceAdjustmentsAdapter(IdResolver(db)),
      ),
      auditLogs = BaseRepository<AuditLog, AuditLogsCompanion>(
        db: db,
        table: db.auditLogs,
        adapter: AuditLogsAdapter(IdResolver(db)),
      ),
      paymentVoids = BaseRepository<PaymentVoid, PaymentVoidsCompanion>(
        db: db,
        table: db.paymentVoids,
        adapter: PaymentVoidsAdapter(IdResolver(db)),
      ),
      bookingPriceAdjustments = BaseRepository<BookingPriceAdjustment, BookingPriceAdjustmentsCompanion>(
        db: db,
        table: db.bookingPriceAdjustments,
        adapter: BookingPriceAdjustmentsAdapter(IdResolver(db)),
      ),
      guestInfos = BaseRepository<GuestInfo, GuestInfosCompanion>(
        db: db,
        table: db.guestInfos,
        adapter: GuestInfosAdapter(IdResolver(db)),
      ),
      salaryWithdrawals = BaseRepository<SalaryWithdrawal, SalaryWithdrawalsCompanion>(
        db: db,
        table: db.salaryWithdrawals,
        adapter: SalaryWithdrawalsAdapter(IdResolver(db)),
      ),
      salaryCarryOverLogs = BaseRepository<SalaryCarryOverLog, SalaryCarryOverLogsCompanion>(
        db: db,
        table: db.salaryCarryOverLogs,
        adapter: SalaryCarryOverLogsAdapter(IdResolver(db)),
      );

  static AdapterRegistry? _instance;

  /// For testing — creates a fresh instance with given database
  AdapterRegistry(AppDatabase db) : this._(db);

  /// For testing — creates a fresh instance with given database
  AdapterRegistry.testing(AppDatabase db) : this._(db);

  /// Get singleton instance (created via Provider)
  // ignore: prefer_constructors_over_static_methods — singleton getter
  static AdapterRegistry get instance {
    _instance ??= AdapterRegistry._(DatabaseManager.instance);
    return _instance!;
  }

  /// Initialize with specific database (for testing or explicit control)
  static void initialize(AppDatabase db) {
    _instance = AdapterRegistry._(db);
  }

  /// Reset singleton (for testing or re-initialization)
  static void reset() {
    _instance = null;
  }

  final AppDatabase db;
  final IdResolver resolver;
  final BaseRepository<Booking, BookingsCompanion> bookings;
  final BaseRepository<Payment, PaymentsCompanion> payments;
  final BaseRepository<Expense, ExpensesCompanion> expenses;
  final BaseRepository<Debt, DebtsCompanion> debts;
  final BaseRepository<Room, RoomsCompanion> rooms;
  final BaseRepository<BookingNight, BookingNightsCompanion> nights;
  final BaseRepository<Employee, EmployeesCompanion> employees;
  final BaseRepository<SalaryCycle, SalaryCyclesCompanion> salaryCycles;
  final BaseRepository<SalaryPayment, SalaryPaymentsCompanion> salaryPayments;
  final BaseRepository<BookingNote, BookingNotesCompanion> bookingNotes;
  final BaseRepository<CashTransaction, CashTransactionsCompanion> cashTransactions;
  final BaseRepository<ShiftNote, ShiftNotesCompanion> shiftNotes;
  final BaseRepository<PriceAdjustment, PriceAdjustmentsCompanion> priceAdjustments;
  final BaseRepository<AuditLog, AuditLogsCompanion> auditLogs;
  final BaseRepository<PaymentVoid, PaymentVoidsCompanion> paymentVoids;
  final BaseRepository<BookingPriceAdjustment, BookingPriceAdjustmentsCompanion> bookingPriceAdjustments;
  final BaseRepository<GuestInfo, GuestInfosCompanion> guestInfos;
  final BaseRepository<SalaryWithdrawal, SalaryWithdrawalsCompanion> salaryWithdrawals;
  final BaseRepository<SalaryCarryOverLog, SalaryCarryOverLogsCompanion> salaryCarryOverLogs;
}
