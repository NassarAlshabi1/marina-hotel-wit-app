import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/local_db.dart';
import '../services/repositories/rooms_repository.dart';
import '../services/repositories/bookings_repository.dart';
import '../services/repositories/employees_repository.dart';
import '../services/repositories/expenses_repository.dart';
import '../services/repositories/cash_repository.dart';
import '../services/repositories/payments_repository.dart';
import '../services/repositories/debts_repository.dart';
import '../services/repositories/notes_repository.dart';
import '../services/repositories/simple_notes_repository.dart';
import '../services/repositories/shift_notes_repository.dart';
import '../services/repositories/guest_infos_repository.dart';
import '../services/repositories/blacklist_repository.dart';
import '../services/repositories/salary_withdrawals_repository.dart';
import '../services/auth_local_store.dart';
import '../services/sync_guardian.dart';
import '../services/diagnostics/diagnostics_logger.dart';

import '../services/whatsapp_service.dart';
import '../utils/status_utils.dart';
import '../utils/time.dart';

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
final guestInfoRepoProvider = Provider<GuestInfosRepository>(
  (ref) => GuestInfosRepository(ref.read(databaseProvider)),
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
final whatsappSettingsProvider = FutureProvider<Map<String, String>>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return {
    'apiType': prefs.getString('wa_api_type') ?? 'custom',
    'baseUrl': prefs.getString('wa_api_base_url') ?? 'https://7103.api.greenapi.com',
    'instanceId': prefs.getString('wa_api_instance_id') ?? 'waInstance7103894450',
    'token': prefs.getString('wa_api_token') ?? 'a8856c55173047d6b2d3078380a16f5f5d088c1e146b4903b1',
    'customUrlTemplate': prefs.getString('wa_custom_url_template') ?? '',
  };
});

WhatsAppApiType _parseApiType(String? type) {
  switch (type) {
    case 'custom':
      return WhatsAppApiType.custom;
    default:
      return WhatsAppApiType.custom;
  }
}

final whatsappServiceProvider = Provider<WhatsAppService>(
  (ref) {
    final settingsAsync = ref.watch(whatsappSettingsProvider);
    final settings = settingsAsync.valueOrNull ?? const {
      'apiType': 'custom',
      'baseUrl': 'https://7103.api.greenapi.com',
      'instanceId': 'waInstance7103894450',
      'token': 'a8856c55173047d6b2d3078380a16f5f5d088c1e146b4903b1',
      'customUrlTemplate': '',
    };
    return WhatsAppService(
      apiType: _parseApiType(settings['apiType']),
      baseUrl: settings['baseUrl'],
      instanceId: settings['instanceId'],
      token: settings['token'],
      customUrlTemplate: settings['customUrlTemplate'],
    );
  },
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

final guestInfoListProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(guestInfoRepoProvider).watchAll(),
);

final expensesListProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(expensesRepoProvider).watchAll(),
);

final salaryWithdrawalsListProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(salaryWithdrawalsRepoProvider).listAll();
});

final cashTransactionsListProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(cashRepoProvider).watchAll(),
);

// Users count based on AuthLocalStore (fixed accounts + saved users)
final usersCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final store = AuthLocalStore();
  return store.getUsersCount();
});

// Daily Statistics Providers — تحديث فوري عبر Stream من قاعدة البيانات
final todayPaymentsProvider = StreamProvider.autoDispose<double>((ref) {
  final paymentsRepo = ref.watch(paymentsRepoProvider);
  final hotelDay = Time.hotelDayKey();
  return paymentsRepo.watchAll().map((payments) {
    double total = 0;
    for (final p in payments) {
      if (p.hotelDayKey == hotelDay) total += p.amount;
    }
    return total;
  });
});

final todayExpensesProvider = StreamProvider.autoDispose<double>((ref) {
  final expensesRepo = ref.watch(expensesRepoProvider);
  final hotelDay = Time.hotelDayKey();
  // Stream مباشر من DB مع فلترة hotelDayKey + fallback للتواريخ القديمة
  return expensesRepo.watchByHotelDayKey(hotelDay).map((expenses) {
    double total = 0;
    for (final e in expenses) {
      total += e.amount;
    }
    return total;
  });
});

final todayExpensesSummaryProvider = FutureProvider.autoDispose((ref) async {
  final hotelDay = Time.hotelDayKey();
  final repo = ref.watch(expensesRepoProvider);
  final total = await repo.getTotalByHotelDayKey(hotelDay);
  final expenses = await repo.listFiltered(from: hotelDay, to: hotelDay);
  return (count: expenses.length, total: total);
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
