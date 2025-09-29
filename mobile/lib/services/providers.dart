import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'local_db.dart';
import 'repositories/rooms_repository.dart';
import 'repositories/bookings_repository.dart';
import 'repositories/employees_repository.dart';
import 'repositories/expenses_repository.dart';
import 'repositories/cash_repository.dart';
import 'repositories/payments_repository.dart';
import 'repositories/notes_repository.dart';

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

final roomsRepoProvider = Provider<RoomsRepository>((ref) => RoomsRepository(ref.read(databaseProvider)));
final bookingsRepoProvider = Provider<BookingsRepository>((ref) => BookingsRepository(ref.read(databaseProvider)));
final employeesRepoProvider = Provider<EmployeesRepository>((ref) => EmployeesRepository(ref.read(databaseProvider)));
final expensesRepoProvider = Provider<ExpensesRepository>((ref) => ExpensesRepository(ref.read(databaseProvider)));
final cashRepoProvider = Provider<CashRepository>((ref) => CashRepository(ref.read(databaseProvider)));
final paymentsRepoProvider = Provider<PaymentsRepository>((ref) => PaymentsRepository(ref.read(databaseProvider)));
final notesRepoProvider = Provider<NotesRepository>((ref) => NotesRepository(ref.read(databaseProvider)));

final roomsListProvider = StreamProvider.autoDispose((ref) => ref.watch(roomsRepoProvider).watchAll());

final bookingsListProvider = StreamProvider.autoDispose((ref) => ref.watch(bookingsRepoProvider).watch());
final activeNotesProvider = FutureProvider.autoDispose((ref) => ref.watch(notesRepoProvider).listAllActive());

final employeesListProvider = StreamProvider.autoDispose((ref) => ref.watch(employeesRepoProvider).watchAll());

final expensesListProvider = StreamProvider.autoDispose((ref) => ref.watch(expensesRepoProvider).watchAll());

final cashTransactionsListProvider = StreamProvider.autoDispose((ref) => ref.watch(cashRepoProvider).watchAll());
