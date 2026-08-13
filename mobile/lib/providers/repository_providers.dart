import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/adapters/adapter_registry.dart';
import '../services/auth_local_store.dart';
import '../services/daos/bookings_dao.dart';
import '../services/daos/debts_dao.dart';
import '../services/daos/employees_dao.dart';
import '../services/daos/expenses_dao.dart';
import '../services/daos/outbox_dao.dart';
// ✅ P2 Performance Fix (2026-08-10): استيراد WeakDeviceOptimizer
// لاستخدام maxListItemsBeforePagination في تقييد القوائم على الأجهزة الضعيفة.
import '../utils/weak_device_optimizer.dart';
import '../services/daos/payments_dao.dart';
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
import '../utils/stream_helpers.dart';

// إضافة Auto Backup Providers
export '../providers/auto_backup_provider.dart';
// إضافة Backup Providers
export '../providers/backup_provider.dart';
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
final adapterRegistryProvider = Provider<AdapterRegistry>(
  (ref) => AdapterRegistry.instance,
);

final outboxDaoProvider = Provider<OutboxDao>(
  (ref) =>
      OutboxDao(ref.read(databaseProvider), ref.read(adapterRegistryProvider)),
);
final bookingsDaoProvider = Provider<BookingsDao>(
  (ref) => BookingsDao(
    ref.read(databaseProvider),
    ref.read(outboxDaoProvider),
    ref.read(adapterRegistryProvider),
  ),
);
final paymentsDaoProvider = Provider<PaymentsDao>(
  (ref) => PaymentsDao(
    ref.read(databaseProvider),
    ref.read(outboxDaoProvider),
    ref.read(adapterRegistryProvider),
  ),
);
final expensesDaoProvider = Provider<ExpensesDao>(
  (ref) => ExpensesDao(
    ref.read(databaseProvider),
    ref.read(outboxDaoProvider),
    ref.read(adapterRegistryProvider),
  ),
);
final debtsDaoProvider = Provider<DebtsDao>(
  (ref) => DebtsDao(
    ref.read(databaseProvider),
    ref.read(outboxDaoProvider),
    ref.read(adapterRegistryProvider),
  ),
);
final employeesDaoProvider = Provider<EmployeesDao>(
  (ref) => EmployeesDao(
    ref.read(databaseProvider),
    ref.read(outboxDaoProvider),
    ref.read(adapterRegistryProvider),
  ),
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
final salaryAdvanceInstallmentsServiceProvider =
    Provider<SalaryAdvanceInstallmentsService>(
      (ref) => SalaryAdvanceInstallmentsService(
        ref.read(databaseProvider),
        ref.read(expensesRepoProvider),
        ref.read(salaryWithdrawalsRepoProvider),
      ),
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
final whatsappSettingsProvider = FutureProvider<Map<String, String>>((
  ref,
) async {
  final prefs = await SharedPreferences.getInstance();
  return {
    'apiType': prefs.getString('wa_api_type') ?? 'custom',
    'baseUrl':
        prefs.getString('wa_api_base_url') ?? 'https://7103.api.greenapi.com',
    'instanceId':
        prefs.getString('wa_api_instance_id') ?? Env.whatsappInstanceId,
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

final whatsappServiceProvider = Provider<WhatsAppService>((ref) {
  final settingsAsync = ref.watch(whatsappSettingsProvider);
  final settings =
      settingsAsync.valueOrNull ??
      const {
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
});

final roomsListProvider = StreamProvider.autoDispose<List<Room>>(
  (ref) => debounceStream(
    ref
        .watch(roomsRepoProvider)
        .watchAll(
          limit: WeakDeviceOptimizer.instance.maxListItemsBeforePagination,
        ),
    const Duration(milliseconds: 150),
  ),
);
final availableRoomsProvider = StreamProvider.autoDispose(
  (ref) =>
      debounceStream(
        ref
            .watch(roomsRepoProvider)
            .watchAll(
              limit: WeakDeviceOptimizer.instance.maxListItemsBeforePagination,
            ),
        const Duration(milliseconds: 150),
      ).map(
        (rooms) => rooms
            .where((room) => StatusUtils.isRoomAvailable(room.status))
            .toList(),
      ),
);

final bookingsListProvider = StreamProvider.autoDispose<List<Booking>>(
  (ref) => debounceStream(
    // ✅ P2 Performance Fix (2026-08-10): تقييد عدد الحجوزات على الأجهزة الضعيفة.
    // نستخدم BookingsDao مباشرة لتطبيق LIMIT في SQL.
    BookingsDao(
      ref.watch(databaseProvider),
      ref.watch(outboxDaoProvider),
    ).watchList(
      limit: WeakDeviceOptimizer.instance.maxListItemsBeforePagination,
    ),
    const Duration(milliseconds: 150),
  ),
);
final activeNotesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(notesRepoProvider).listAllActive(),
);

// Simple Notes Providers
final simpleNotesListProvider = StreamProvider.autoDispose(
  (ref) => debounceStream(
    ref.watch(simpleNotesRepoProvider).watchAllNotes(),
    const Duration(milliseconds: 150),
  ),
);
final simpleNotesUnreadCountProvider = StreamProvider.autoDispose(
  (ref) => debounceStream(
    ref.watch(simpleNotesRepoProvider).watchUnreadCount(),
    const Duration(milliseconds: 150),
  ),
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
  (ref) => debounceStream(
    ref
        .watch(employeesRepoProvider)
        .watchAll(
          limit: WeakDeviceOptimizer.instance.maxListItemsBeforePagination,
        ),
    const Duration(milliseconds: 150),
  ),
);

final guestInfoListProvider = StreamProvider.autoDispose(
  (ref) => debounceStream(
    ref
        .watch(guestInfoRepoProvider)
        .watchAll(
          limit: WeakDeviceOptimizer.instance.maxListItemsBeforePagination,
        ),
    const Duration(milliseconds: 150),
  ),
);

final expensesListProvider = StreamProvider.autoDispose(
  (ref) => debounceStream(
    // ✅ P2 Performance Fix: LIMIT في SQL على الأجهزة الضعيفة.
    ExpensesDao(
      ref.watch(databaseProvider),
      ref.watch(outboxDaoProvider),
    ).watchList(
      limit: WeakDeviceOptimizer.instance.maxListItemsBeforePagination,
    ),
    const Duration(milliseconds: 150),
  ),
);

final salaryWithdrawalsListProvider = FutureProvider.autoDispose((ref) {
  return ref
      .watch(salaryWithdrawalsRepoProvider)
      .listActive(
        limit: WeakDeviceOptimizer.instance.maxListItemsBeforePagination,
      );
});

final cashTransactionsListProvider = StreamProvider.autoDispose(
  (ref) => debounceStream(
    ref
        .watch(cashRepoProvider)
        .watchAll(
          limit: WeakDeviceOptimizer.instance.maxListItemsBeforePagination,
        ),
    const Duration(milliseconds: 150),
  ),
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
  // ✅ SQL SUM() على مستوى قاعدة البيانات بدلاً من تحميل جميع المصروفات
  // وجمعها في Dart. أداء أفضل بشكل ملحوظ خاصةً مع نمو البيانات.
  return expensesRepo.watchTotalByHotelDayKey(hotelDay);
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
final bookingPaymentsProvider = StreamProvider.family
    .autoDispose<List<Payment>, int>((ref, bookingId) {
      final paymentsRepo = ref.watch(paymentsRepoProvider);
      return debounceStream(
        paymentsRepo.paymentsByBooking(bookingId),
        const Duration(milliseconds: 150),
      );
    });

/// إجمالي المدفوع لحجز محدد عبر SQL SUM() — بديل خفيف الوزن لـ [bookingPaymentsProvider]
/// عندما يحتاج المستهلك فقط للمجموع (مثل بطاقة الحجز في القائمة). يتجنب تحميل
/// جميع صفوف المدفوعات (38 عمود لكل صف) وفك تشفيرها فقط لجمع `amount`.
/// استخدم [bookingPaymentsProvider] إذا كنت تحتاج لتفاصيل كل دفعة.
final bookingPaidAmountProvider = StreamProvider.family
    .autoDispose<double, int>((ref, bookingId) {
      final paymentsRepo = ref.watch(paymentsRepoProvider);
      return paymentsRepo.watchTotalPaidForBooking(bookingId);
    });

final debtsListProvider = StreamProvider.autoDispose(
  (ref) => debounceStream(
    // ✅ P2 Performance Fix: LIMIT في SQL على الأجهزة الضعيفة.
    DebtsDao(
      ref.watch(databaseProvider),
      ref.watch(outboxDaoProvider),
    ).watchList(
      limit: WeakDeviceOptimizer.instance.maxListItemsBeforePagination,
    ),
    const Duration(milliseconds: 150),
  ),
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

// ═══════════════════════════════════════════════════════════════════════════
// Providers لـ BookingPaymentScreen — بديل Riverpod للـ StreamBuilders
// ═══════════════════════════════════════════════════════════════════════════
// قبل الإصلاح: كانت الشاشة تستخدم 5 StreamBuilders متداخلة (pyramid of doom):
//   StreamBuilder<Booking?> → StreamBuilder<Room?> → StreamBuilder<...Adjustment>
//     → StreamBuilder<...Night> → StreamBuilder<...Payment>
// كل stream يُعيد بناء كل الـ children عند أي تغيير → أداء سيء.
//
// بعد الإصلاح: كل stream يُدار عبر Riverpod provider مستقل. الشاشة تستخدم
// ref.watch لقراءة AsyncValue لكل provider بشكل مسطح (flat) — لا تداخل.

/// بيانات الحجز المباشرة (بديل StreamBuilder<Booking?>).
final liveBookingProvider = StreamProvider.autoDispose.family<Booking?, int>((
  ref,
  bookingId,
) {
  final repo = ref.watch(bookingsRepoProvider);
  return repo.watchOne(bookingId);
});

/// بيانات الغرفة بالرقم (بديل StreamBuilder<Room?>).
final liveRoomByNumberProvider = StreamProvider.autoDispose
    .family<Room?, String>((ref, roomNumber) {
      final repo = ref.watch(roomsRepoProvider);
      return repo.watchByNumber(roomNumber);
    });

/// تعديلات الأسعار النشطة لحجز محدد (بديل StreamBuilder<List<BookingPriceAdjustment>>).
final bookingPriceAdjustmentsProvider = StreamProvider.autoDispose
    .family<List<BookingPriceAdjustment>, int>((ref, bookingId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.bookingPriceAdjustments)
            ..where((a) => a.bookingLocalId.equals(bookingId))
            ..where((a) => a.isActive.equals(true))
            ..where((a) => a.deletedAt.isNull()))
          .watch();
    });

/// ليالي الحجز (بديل StreamBuilder<List<BookingNight>>).
final bookingNightsProvider = StreamProvider.autoDispose
    .family<List<BookingNight>, int>((ref, bookingId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.bookingNights)
            ..where((n) => n.bookingLocalId.equals(bookingId))
            ..where((n) => n.deletedAt.isNull()))
          .watch();
    });

/// مدفوعات الحجز (بديل StreamBuilder<List<Payment>>).
/// ملاحظة: bookingPaymentsProvider موجود بالفعل (line 220) لكنه يستخدم
/// debounceStream. هذا الـ provider بديل مباشر بدون debounce.
final bookingPaymentsDirectProvider = StreamProvider.autoDispose
    .family<List<Payment>, int>((ref, bookingId) {
      final repo = ref.watch(paymentsRepoProvider);
      return repo.paymentsByBooking(bookingId);
    });
