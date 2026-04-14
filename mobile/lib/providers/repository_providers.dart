import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/local_db.dart';
import '../services/repositories/rooms_repository.dart';
import '../services/repositories/bookings_repository.dart';
import '../services/repositories/employees_repository.dart';
import '../services/repositories/expenses_repository.dart';
import '../utils/time.dart';
import '../services/repositories/cash_repository.dart';
import '../services/repositories/payments_repository.dart';
import '../services/repositories/debts_repository.dart';
import '../services/repositories/notes_repository.dart';
import '../services/repositories/simple_notes_repository.dart';
import '../services/repositories/shift_notes_repository.dart';
import '../services/repositories/blacklist_repository.dart';
import '../services/repositories/salary_withdrawals_repository.dart';
import '../services/repositories/guest_infos_repository.dart';
import '../services/auth_local_store.dart';
import '../services/sync_guardian.dart';
import '../services/diagnostics/diagnostics_logger.dart';
import 'core_providers.dart';

import '../services/whatsapp_service.dart';
import '../utils/status_utils.dart';

// إضافة Backup Providers
export '../providers/backup_provider.dart';
// إضافة Auto Backup Providers
export '../providers/auto_backup_provider.dart';
// إضافة Smart Sync Providers
export '../providers/smart_sync_provider.dart';

final syncGuardianProvider = Provider<SyncGuardian>(
  (ref) => SyncGuardian.instance,
);
final syncHealthProvider = StreamProvider<SyncHealthSnapshot>(
  (ref) => ref.watch(syncGuardianProvider).watchHealth(),
);

final diagnosticsLoggerProvider = ChangeNotifierProvider<DiagnosticsLogger>(
  (ref) => DiagnosticsLogger.instance,
);

final databaseProvider = Provider<AppDatabase>(
  (ref) => DatabaseManager.instance,
);

final roomsRepoProvider = Provider<RoomsRepository>(
  (ref) => RoomsRepository(ref.read(databaseProvider)),
);
final bookingsRepoProvider = Provider<BookingsRepository>(
  (ref) => BookingsRepository(ref.read(databaseProvider)),
);
final employeesRepoProvider = Provider<EmployeesRepository>(
  (ref) => EmployeesRepository(ref.read(databaseProvider)),
);
final expensesRepoProvider = Provider<ExpensesRepository>(
  (ref) => ExpensesRepository(ref.read(databaseProvider)),
);
final cashRepoProvider = Provider<CashRepository>(
  (ref) => CashRepository(ref.read(databaseProvider)),
);
final paymentsRepoProvider = Provider<PaymentsRepository>(
  (ref) => PaymentsRepository(ref.read(databaseProvider)),
);
final debtsRepoProvider = Provider<DebtsRepository>(
  (ref) => DebtsRepository(ref.read(databaseProvider)),
);
final notesRepoProvider = Provider<NotesRepository>(
  (ref) => NotesRepository(ref.read(databaseProvider)),
);
final salaryWithdrawalsRepoProvider = Provider<SalaryWithdrawalsRepository>(
  (ref) => SalaryWithdrawalsRepository(ref.read(databaseProvider)),
);
final simpleNotesRepoProvider = Provider<SimpleNotesRepository>(
  (ref) => SimpleNotesRepository(ref.read(databaseProvider)),
);
final shiftNotesRepoProvider = Provider<ShiftNotesRepository>(
  (ref) => ShiftNotesRepository(ref.read(databaseProvider)),
);
final blacklistRepoProvider = Provider<BlacklistRepository>(
  (ref) => BlacklistRepository(ref.read(databaseProvider)),
);
final whatsappServiceProvider = Provider<WhatsAppService>(
  (ref) => WhatsAppService(
    baseUrl: 'https://7103.api.greenapi.com',
    instanceId: 'waInstance7103894450',
    token: 'a8856c55173047d6b2d3078380a16f5f5d088c1e146b4903b1',
  ),
);

final roomsListProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(roomsRepoProvider).watchAll(),
);
final availableRoomsProvider = StreamProvider.autoDispose(
  (ref) => ref
      .watch(roomsRepoProvider)
      .watchAll()
      .map(
        (rooms) => rooms
            .where((room) => StatusUtils.isRoomAvailable(room.status))
            .toList(),
      ),
);

final bookingsListProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(bookingsRepoProvider).watch(),
);
final activeNotesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(notesRepoProvider).listAllActive(),
);

// Simple Notes Providers
final simpleNotesListProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(simpleNotesRepoProvider).watchAllNotes(),
);
final simpleNotesUnreadCountProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(simpleNotesRepoProvider).watchUnreadCount(),
);
final allSimpleNotesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(simpleNotesRepoProvider).getAllNotes(),
);
final unreadSimpleNotesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(simpleNotesRepoProvider).getUnreadNotes(),
);
final highPrioritySimpleNotesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(simpleNotesRepoProvider).getHighPriorityNotes(),
);

final employeesListProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(employeesRepoProvider).watchAll(),
);

final expensesListProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(expensesRepoProvider).watchAll(),
);

final cashTransactionsListProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(cashRepoProvider).watchAll(),
);

// Users count based on AuthLocalStore (fixed accounts + saved users)
final usersCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final store = AuthLocalStore();
  return store.getUsersCount();
});

// Daily Statistics Providers — StreamProvider لتحديث لحظي
// ──────────────────────────────────────────────────────────────────
// الاستعلام يشمل:
//   1. السجلات ذات hotel_day_key مطابق لليوم الفندقي الحالي
//   2. السجلات ذات hotel_day_key = NULL مع تاريخ مطابق (fallback
//      للمصروفات/المدفوعات القادمة من المزامنة بدون hotel_day_key)
// ──────────────────────────────────────────────────────────────────
final todayPaymentsProvider = StreamProvider<double>((ref) {
  final db = ref.watch(dbProvider);
  final todayKey = Time.hotelDayKey();
  return db
      .customSelect(
        'SELECT COALESCE(SUM(amount), 0) as total FROM payments '
        'WHERE deleted_at IS NULL AND is_voided = 0 AND ('
        '  hotel_day_key = ? '
        '  OR (hotel_day_key IS NULL AND substr(payment_date, 1, 10) = ?)'
        ')',
        variables: [
          Variable.withString(todayKey),
          Variable.withString(todayKey),
        ],
        readsFrom: {db.payments},
      )
      .watch()
      .map(
        (rows) => rows.isEmpty
            ? 0.0
            : (rows.first.data['total'] as num? ?? 0.0).toDouble(),
      );
});

final todayExpensesProvider = StreamProvider<double>((ref) {
  final db = ref.watch(dbProvider);
  final todayKey = Time.hotelDayKey();
  return db
      .customSelect(
        'SELECT COALESCE(SUM(amount), 0) as total FROM expenses '
        'WHERE deleted_at IS NULL AND ('
        '  hotel_day_key = ? '
        '  OR (hotel_day_key IS NULL AND date = ?)'
        ')',
        variables: [
          Variable.withString(todayKey),
          Variable.withString(todayKey),
        ],
        readsFrom: {db.expenses},
      )
      .watch()
      .map(
        (rows) => rows.isEmpty
            ? 0.0
            : (rows.first.data['total'] as num? ?? 0.0).toDouble(),
      );
});
final debtsListProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(debtsRepoProvider).watchAll(),
);
final pendingDebtsProvider = StreamProvider.autoDispose(
  (ref) => ref
      .watch(debtsRepoProvider)
      .watchAll()
      .map(
        (debts) => debts
            .where((debt) => debt.isSettled == 0 && debt.remainingAmount > 0)
            .toList(),
      ),
);
final settledDebtsProvider = StreamProvider.autoDispose(
  (ref) => ref
      .watch(debtsRepoProvider)
      .watchAll()
      .map(
        (debts) => debts
            .where((debt) => debt.isSettled == 1 || debt.remainingAmount <= 0)
            .toList(),
      ),
);

// دالة للحصول على Database instance (singleton)
AppDatabase getDatabase() => DatabaseManager.instance;


// GuestInfo repo helper for CRUD operations
final guestInfoRepoProvider = Provider<GuestInfosRepository>(
  (ref) => GuestInfosRepository(ref.read(databaseProvider)),
);

// GuestInfos Providers (for information_screen)
final guestInfoListProvider = StreamProvider.autoDispose(
  (ref) {
    final repo = ref.read(guestInfoRepoProvider);
    return repo.watchAll();
  },
);
