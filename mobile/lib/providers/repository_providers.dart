import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marina_hotel_mobile/utils/prefs_cache.dart';

import '../services/auth_local_store.dart';
import '../services/diagnostics/diagnostics_logger.dart';
import '../services/local_db.dart';
import '../services/repositories/blacklist_repository.dart';
import '../services/repositories/bookings_repository.dart';
import '../services/repositories/cash_repository.dart';
import '../services/repositories/debts_repository.dart';
import '../services/repositories/employees_repository.dart';
import '../services/repositories/expenses_repository.dart';
import '../services/repositories/guest_infos_repository.dart';
import '../services/repositories/notes_repository.dart';
import '../services/repositories/payments_repository.dart';
import '../services/repositories/rooms_repository.dart';
import '../services/repositories/salary_withdrawals_repository.dart';
import '../services/repositories/shift_notes_repository.dart';
import '../services/repositories/simple_notes_repository.dart';
import '../services/salary_advance_installments_service.dart';
import '../services/sync_guardian.dart';
import '../services/whatsapp_service.dart';
import '../utils/env.dart';
import '../utils/hotel_time_engine.dart';
import '../utils/status_utils.dart';

// إضافة Auto Backup Providers
export '../providers/auto_backup_provider.dart';
// إضافة Backup Providers
export '../providers/backup_provider.dart';
// إضافة Smart Sync Providers
export '../providers/smart_sync_provider.dart';

final syncGuardianProvider = Provider.autoDispose<SyncGuardian>(
  (ref) => SyncGuardian.instance,
);
final syncHealthProvider = StreamProvider.autoDispose<SyncHealthSnapshot>(
  (ref) => ref.watch(syncGuardianProvider).watchHealth(),
);

final diagnosticsLoggerProvider = ChangeNotifierProvider.autoDispose<DiagnosticsLogger>(
  (ref) => DiagnosticsLogger.instance,
);

final databaseProvider = Provider.autoDispose<AppDatabase>(
  (ref) => DatabaseManager.instance,
);

final roomsRepoProvider = Provider.autoDispose<RoomsRepository>(
  (ref) => RoomsRepository(ref.read(databaseProvider)),
);
final bookingsRepoProvider = Provider.autoDispose<BookingsRepository>(
  (ref) => BookingsRepository(ref.read(databaseProvider)),
);
final employeesRepoProvider = Provider.autoDispose<EmployeesRepository>(
  (ref) => EmployeesRepository(ref.read(databaseProvider)),
);
final guestInfoRepoProvider = Provider.autoDispose<GuestInfosRepository>(
  (ref) => GuestInfosRepository(ref.read(databaseProvider)),
);
final expensesRepoProvider = Provider.autoDispose<ExpensesRepository>(
  (ref) => ExpensesRepository(ref.read(databaseProvider)),
);
final cashRepoProvider = Provider.autoDispose<CashRepository>(
  (ref) => CashRepository(ref.read(databaseProvider)),
);
final paymentsRepoProvider = Provider.autoDispose<PaymentsRepository>(
  (ref) => PaymentsRepository(ref.read(databaseProvider)),
);
final debtsRepoProvider = Provider.autoDispose<DebtsRepository>(
  (ref) => DebtsRepository(ref.read(databaseProvider)),
);
final notesRepoProvider = Provider.autoDispose<NotesRepository>(
  (ref) => NotesRepository(ref.read(databaseProvider)),
);
final salaryWithdrawalsRepoProvider = Provider.autoDispose<SalaryWithdrawalsRepository>(
  (ref) => SalaryWithdrawalsRepository(ref.read(databaseProvider)),
);
final salaryAdvanceInstallmentsServiceProvider =
    Provider<SalaryAdvanceInstallmentsService>(
  (ref) => SalaryAdvanceInstallmentsService(
    ref.read(databaseProvider),
    ref.read(expensesRepoProvider),
    ref.read(salaryWithdrawalsRepoProvider),
  ),
);
final simpleNotesRepoProvider = Provider.autoDispose<SimpleNotesRepository>(
  (ref) => SimpleNotesRepository(ref.read(databaseProvider)),
);
final shiftNotesRepoProvider = Provider.autoDispose<ShiftNotesRepository>(
  (ref) => ShiftNotesRepository(ref.read(databaseProvider)),
);
final blacklistRepoProvider = Provider.autoDispose<BlacklistRepository>(
  (ref) => BlacklistRepository(ref.read(databaseProvider)),
);
final whatsappSettingsProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final prefs = getSharedPrefs();
  return {
    'apiType': prefs.getString('wa_api_type') ?? 'custom',
    'baseUrl': prefs.getString('wa_api_base_url') ?? 'https://7103.api.greenapi.com',
    'instanceId': prefs.getString('wa_api_instance_id') ?? Env.whatsappInstanceId,
    'token': prefs.getString('wa_api_token') ?? Env.whatsappApiToken,
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

final whatsappServiceProvider = Provider.autoDispose<WhatsAppService>(
  (ref) {
    final settingsAsync = ref.watch(whatsappSettingsProvider);
    final settings = settingsAsync.valueOrNull ?? const {
      'apiType': 'custom',
      'baseUrl': 'https://7103.api.greenapi.com',
      'instanceId': Env.whatsappInstanceId,
      'token': Env.whatsappApiToken,
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

final roomsListProvider = StreamProvider.autoDispose<List<Room>>(
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

final bookingsListProvider = StreamProvider.autoDispose<List<Booking>>(
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

final employeesListProvider = StreamProvider.autoDispose<List<Employee>>(
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
  // ✅ استخدام HotelTimeEngine للتوافق مع البيانات المُخزنة
  final hotelDay = HotelTimeEngine.getHotelDayKey();
  // الفلتر على مستوى قاعدة البيانات بدلاً من تحميل كل المدفوعات
  return paymentsRepo.watchTotalByHotelDayKey(hotelDay);
});

final todayExpensesProvider = StreamProvider.autoDispose<double>((ref) {
  final expensesRepo = ref.watch(expensesRepoProvider);
  // ✅ استخدام HotelTimeEngine للتوافق مع البيانات المُخزنة
  final hotelDay = HotelTimeEngine.getHotelDayKey();
  // الفلتر على مستوى قاعدة البيانات — لا نحمّل جميع المصروفات
  return expensesRepo.watchByHotelDayKey(hotelDay).map((expenses) {
    return expenses.fold<double>(0, (sum, e) => sum + e.amount);
  });
});

final todayExpensesSummaryProvider = FutureProvider.autoDispose((ref) async {
  // ✅ استخدام HotelTimeEngine للتوافق مع البيانات المُخزنة
  final hotelDay = HotelTimeEngine.getHotelDayKey();
  final repo = ref.watch(expensesRepoProvider);
  // ✅ استبعاد السلفة — تسبب تكرار بيانات
  final expenses = await repo.listFilteredByHotelDay(
    fromHotelDay: hotelDay,
    toHotelDay: hotelDay,
    excludeAdvance: true,
  );
  final total = expenses.fold<double>(0, (sum, e) => sum + e.amount);
  return (count: expenses.length, total: total);
});
final bookingPaymentsProvider = StreamProvider.family.autoDispose<List<Payment>, int>(
  (ref, bookingId) {
    final paymentsRepo = ref.watch(paymentsRepoProvider);
    return paymentsRepo.paymentsByBooking(bookingId);
  },
);

final debtsListProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(debtsRepoProvider).watchAll(),
);
final pendingDebtsProvider = Provider.autoDispose<List<Debt>>((ref) {
  final allDebts = ref.watch(debtsListProvider).valueOrNull ?? [];
  return allDebts
      .where((debt) => debt.isSettled == 0 && debt.remainingAmount > 0)
      .toList();
});
final settledDebtsProvider = Provider.autoDispose<List<Debt>>((ref) {
  final allDebts = ref.watch(debtsListProvider).valueOrNull ?? [];
  return allDebts
      .where((debt) => debt.isSettled == 1 || debt.remainingAmount <= 0)
      .toList();
});

// دالة للحصول على Database instance (singleton)
AppDatabase getDatabase() => DatabaseManager.instance;
