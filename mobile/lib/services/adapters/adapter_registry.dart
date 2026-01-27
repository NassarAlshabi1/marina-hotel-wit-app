import '../local_db.dart';
import 'bookings_adapter.dart';
import 'payments_adapter.dart';
import 'expenses_adapter.dart';
import 'debts_adapter.dart';
import 'rooms_adapter.dart';
import 'nights_adapter.dart';
import 'id_resolver.dart';
import '../repositories/base_repository.dart';
import 'employees_adapter.dart';
import 'salary_cycles_adapter.dart';
import 'salary_payments_adapter.dart';
import 'booking_notes_adapter.dart';

class AdapterRegistry {
  AdapterRegistry(this.db)
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
        debts = BaseRepository<Debt, DebtsCompanion>(
          db: db,
          table: db.debts,
          adapter: DebtsAdapter(IdResolver(db)),
        ),
        rooms = BaseRepository<Room, RoomsCompanion>(
          db: db,
          table: db.rooms,
          adapter: RoomsAdapter(IdResolver(db)),
        ),
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
        );

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
}
