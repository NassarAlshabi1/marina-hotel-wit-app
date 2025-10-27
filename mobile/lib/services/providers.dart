import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'local_db.dart';
import 'repositories/rooms_repository.dart';
import 'repositories/bookings_repository.dart';
import 'repositories/employees_repository.dart';
import 'repositories/expenses_repository.dart';
import 'repositories/cash_repository.dart';
import 'repositories/payments_repository.dart';
import 'repositories/debts_repository.dart';
import 'repositories/notes_repository.dart';
import 'whatsapp_service.dart';
import '../utils/status_utils.dart';
import '../utils/time.dart';

// إضافة Backup Providers
export '../providers/backup_provider.dart';
// إضافة Auto Backup Providers
export '../providers/auto_backup_provider.dart';
// إضافة Smart Sync Providers
export '../providers/smart_sync_provider.dart';

final databaseProvider = Provider<AppDatabase>((ref) => DatabaseManager.instance);

final roomsRepoProvider = Provider<RoomsRepository>((ref) => RoomsRepository(ref.read(databaseProvider)));
final bookingsRepoProvider = Provider<BookingsRepository>((ref) => BookingsRepository(ref.read(databaseProvider)));
final employeesRepoProvider = Provider<EmployeesRepository>((ref) => EmployeesRepository(ref.read(databaseProvider)));
final expensesRepoProvider = Provider<ExpensesRepository>((ref) => ExpensesRepository(ref.read(databaseProvider)));
final cashRepoProvider = Provider<CashRepository>((ref) => CashRepository(ref.read(databaseProvider)));
final paymentsRepoProvider = Provider<PaymentsRepository>((ref) => PaymentsRepository(ref.read(databaseProvider)));
final debtsRepoProvider = Provider<DebtsRepository>((ref) => DebtsRepository(ref.read(databaseProvider)));
final notesRepoProvider = Provider<NotesRepository>((ref) => NotesRepository(ref.read(databaseProvider)));
final whatsappServiceProvider = Provider<WhatsAppService>(
  (ref) => WhatsAppService(
    baseUrl: 'https://7103.api.greenapi.com',
    instanceId: 'waInstance7103894450',
    token: 'a8856c55173047d6b2d3078380a16f5f5d088c1e146b4903b1',
  ),
);

final roomsListProvider = StreamProvider.autoDispose((ref) => ref.watch(roomsRepoProvider).watchAll());
final availableRoomsProvider = StreamProvider.autoDispose((ref) =>
    ref.watch(roomsRepoProvider).watchAll().map((rooms) => rooms.where((room) => StatusUtils.isRoomAvailable(room.status)).toList()));

final bookingsListProvider = StreamProvider.autoDispose((ref) => ref.watch(bookingsRepoProvider).watch());
final activeNotesProvider = FutureProvider.autoDispose((ref) => ref.watch(notesRepoProvider).listAllActive());

final employeesListProvider = StreamProvider.autoDispose((ref) => ref.watch(employeesRepoProvider).watchAll());

final expensesListProvider = StreamProvider.autoDispose((ref) => ref.watch(expensesRepoProvider).watchAll());

final cashTransactionsListProvider = StreamProvider.autoDispose((ref) => ref.watch(cashRepoProvider).watchAll());
final debtsListProvider = StreamProvider.autoDispose((ref) => ref.watch(debtsRepoProvider).watchAll());

// دالة للحصول على Database instance (singleton)
AppDatabase getDatabase() => DatabaseManager.instance;

// Providers للمدفوعات والمصروفات اليومية
final dailyPaymentsProvider = FutureProvider.autoDispose<double>((ref) async {
  final paymentsRepo = ref.watch(paymentsRepoProvider);
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day); // الساعة 00:00:00
  final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59); // الساعة 23:59:59
  
  final allPayments = await paymentsRepo.watchAll().first;
  
  double totalPayments = 0.0;
  for (final payment in allPayments) {
    final paymentDate = DateTime.tryParse(payment.paymentDate);
    if (paymentDate != null && 
        paymentDate.isAfter(startOfDay) && 
        paymentDate.isBefore(endOfDay)) {
      totalPayments += payment.amount;
    }
  }
  
  return totalPayments;
});

final dailyExpensesProvider = FutureProvider.autoDispose<double>((ref) async {
  final expensesRepo = ref.watch(expensesRepoProvider);
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day, 1); // الساعة 1:00 صباحاً
  final endOfDay = DateTime(now.year, now.month, now.day, 12); // الساعة 12:00 ظهراً
  
  final allExpenses = await expensesRepo.watchAll().first;
  
  double totalExpenses = 0.0;
  for (final expense in allExpenses) {
    final expenseDate = DateTime.tryParse(expense.date);
    if (expenseDate != null && 
        expenseDate.isAfter(startOfDay) && 
        expenseDate.isBefore(endOfDay)) {
      totalExpenses += expense.amount;
    }
  }
  
  return totalExpenses;
});
