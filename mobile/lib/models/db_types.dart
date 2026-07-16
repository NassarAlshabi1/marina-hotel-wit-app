// lib/models/db_types.dart
//
// ✅ ملف types مركزي يُصدّر كل الـ drift-generated types من local_db.dart.
//
// المشكلة التي يُحلّها:
// - screens تستورد 'services/local_db.dart' فقط لاستخدام types مثل Booking, Room
// - هذا يُعتبر انتهاك لـ Clean Architecture (UI → Data layer)
// - الحل: screens تستورد 'models/db_types.dart' بدلاً من ذلك
//
// ملاحظة: DatabaseManager غير مُصدّر هنا عمداً — screens يجب أن تستخدم
// ref.read(databaseProvider) بدلاً من DatabaseManager.instance المباشر.

export 'package:drift/drift.dart' show Value;

export '../services/local_db.dart'
    show
        // Database type (for type annotations in reports)
        AppDatabase,
        // Main entities (data classes)
        Room,
        Booking,
        BookingNote,
        ShiftNote,
        Employee,
        Expense,
        CashTransaction,
        Payment,
        Debt,
        BookingNight,
        HotelDayLedgerEntry,
        AutoFixRun,
        IntegrityViolation,
        AppSession,
        SalaryCycle,
        SalaryPayment,
        SalaryWithdrawal,
        SalaryCarryOverLog,
        OutboxData,
        SyncStateData,
        SyncLogData,
        SyncConflictRow,
        PriceAdjustment,
        BookingPriceAdjustment,
        AuditLog,
        PaymentVoid,
        GuestInfo,
        // Companion classes (for inserts/updates)
        RoomsCompanion,
        BookingsCompanion,
        BookingNotesCompanion,
        ShiftNotesCompanion,
        EmployeesCompanion,
        ExpensesCompanion,
        CashTransactionsCompanion,
        PaymentsCompanion,
        DebtsCompanion,
        BookingNightsCompanion,
        HotelDayLedgerCompanion,
        AutoFixRunsCompanion,
        IntegrityViolationsCompanion,
        AppSessionsCompanion,
        SalaryCyclesCompanion,
        SalaryPaymentsCompanion,
        SalaryWithdrawalsCompanion,
        OutboxCompanion,
        SyncStateCompanion,
        SyncLogCompanion,
        SyncConflictsCompanion,
        PriceAdjustmentsCompanion,
        BookingPriceAdjustmentsCompanion,
        AuditLogsCompanion,
        PaymentVoidsCompanion,
        GuestInfosCompanion;

// Extension: Employee.salary → basicSalary
export '../services/local_db.dart' show EmployeeX;
