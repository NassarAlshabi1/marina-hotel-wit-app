import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'local_db.dart';
import 'repositories/rooms_repository.dart';
import 'repositories/bookings_repository.dart';
import 'repositories/employees_repository.dart';
import 'repositories/expenses_repository.dart';
import 'repositories/cash_repository.dart';
import 'repositories/payments_repository.dart';
import 'repositories/debts_repository.dart';
import 'repositories/guarantees_repository.dart';
import 'repositories/notes_repository.dart';
import 'backup_sync_service.dart';
import 'whatsapp_service.dart';
import '../utils/status_utils.dart';
import '../providers/backup_provider.dart';

// إضافة Backup Providers
export '../providers/backup_provider.dart';

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

final roomsRepoProvider = Provider<RoomsRepository>((ref) => RoomsRepository(
      ref.read(databaseProvider),
      backupSyncService: ref.read(backupSyncServiceProvider),
    ));
final bookingsRepoProvider = Provider<BookingsRepository>((ref) => BookingsRepository(
      ref.read(databaseProvider),
      backupSyncService: ref.read(backupSyncServiceProvider),
    ));
final employeesRepoProvider = Provider<EmployeesRepository>((ref) => EmployeesRepository(
      ref.read(databaseProvider),
      backupSyncService: ref.read(backupSyncServiceProvider),
    ));
final expensesRepoProvider = Provider<ExpensesRepository>((ref) => ExpensesRepository(
      ref.read(databaseProvider),
      whatsAppService: ref.read(whatsappServiceProvider),
      backupSyncService: ref.read(backupSyncServiceProvider),
    ));
final cashRepoProvider = Provider<CashRepository>((ref) => CashRepository(
      ref.read(databaseProvider),
      backupSyncService: ref.read(backupSyncServiceProvider),
    ));
final paymentsRepoProvider = Provider<PaymentsRepository>((ref) => PaymentsRepository(
      ref.read(databaseProvider),
      backupSyncService: ref.read(backupSyncServiceProvider),
    ));
final debtsRepoProvider = Provider<DebtsRepository>((ref) => DebtsRepository(
      ref.read(databaseProvider),
      backupSyncService: ref.read(backupSyncServiceProvider),
    ));
final guaranteesRepoProvider = Provider<GuaranteesRepository>((ref) => GuaranteesRepository(
      ref.read(databaseProvider),
      backupSyncService: ref.read(backupSyncServiceProvider),
    ));
final notesRepoProvider = Provider<NotesRepository>((ref) => NotesRepository(
      ref.read(databaseProvider),
      backupSyncService: ref.read(backupSyncServiceProvider),
    ));
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

// دالة للحصول على Database instance
AppDatabase getDatabase() => AppDatabase();
