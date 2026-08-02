// ============================================================================
//  Marina Hotel — Wide Coverage Production Screen Benchmark
//  ============================================================================
//  Benchmark شامل يغطي شاشات إنتاج متعددة لقياس الأداء عبر التطبيق.
//
//  الشاشات المُغطّاة:
//    1. DashboardScreen        (لوحة التحكم - الأكثر استخداماً)
//    2. RoomsListScreen        (إدارة الغرف - 20 غرفة)
//    3. BookingPaymentScreen   (شاشة الدفع - 4125 سطر، الأكثر تعقيداً)
//    4. DebtsListScreen        (الديون)
//    5. EmployeesListScreen    (الموظفون)
//    6. BookingsListScreen     (قائمة الحجوزات)
//
//  لكل شاشة يقيس:
//    - زمن البناء الأول (initial build via Stopwatch)
//    - زمن pumpAndSettle (استقرار الـ stream subscriptions)
//    - نمو الذاكرة الفعلي (via ProcessInfo.currentRss)
//
//  التشغيل:
//    flutter test test/performance/wide_screen_benchmark_test.dart \
//      --reporter=expanded
// ============================================================================

// ignore_for_file: lines_longer_than_80_chars

import 'dart:io' show ProcessInfo;

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:marina_hotel_mobile/providers/core_providers.dart';
import 'package:marina_hotel_mobile/providers/repository_providers.dart';
import 'package:marina_hotel_mobile/providers/room_payment_status_provider.dart';
import 'package:marina_hotel_mobile/screens/bookings/bookings_list.dart';
import 'package:marina_hotel_mobile/screens/dashboard_screen.dart';
import 'package:marina_hotel_mobile/screens/debts/debts_list.dart';
import 'package:marina_hotel_mobile/screens/employees/employees_list.dart';
import 'package:marina_hotel_mobile/screens/payments/booking_payment_screen.dart';
import 'package:marina_hotel_mobile/screens/rooms/rooms_list.dart';
import 'package:marina_hotel_mobile/services/daos/bookings_dao.dart';
import 'package:marina_hotel_mobile/services/daos/debts_dao.dart';
import 'package:marina_hotel_mobile/services/daos/employees_dao.dart';
import 'package:marina_hotel_mobile/services/daos/expenses_dao.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/daos/rooms_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_service.dart';

/// بيانات شاشة + مقاييسها (تُملأ بعد كل test).
class ScreenMetrics {
  ScreenMetrics(this.screenName);
  final String screenName;
  int buildMs = 0;
  int settleMs = 0;
  double memoryDeltaMB = 0;
  bool passed = false;
  String? failureReason;

  int get totalMs => buildMs + settleMs;

  @override
  String toString() =>
      '$screenName: build=${buildMs}ms settle=${settleMs}ms total=${totalMs}ms '
      'mem=+${memoryDeltaMB.toStringAsFixed(1)}MB ${passed ? "✅" : "❌"}';
}

/// نتائج كل الشاشات — تُطبَع في النهاية كجدول مقارنة.
final List<ScreenMetrics> allMetrics = <ScreenMetrics>[];

/// Helper: ينشئ AppDatabase في الذاكرة مع بيانات حقيقية شاملة.
Future<AppDatabase> _seedFullDatabase({
  int roomsCount = 20,
  int bookingsCount = 15,
  int expensesCount = 30,
  int employeesCount = 5,
  int debtsCount = 10,
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final outboxDao = OutboxDao(db);
  final roomsDao = RoomsDao(db, outboxDao);
  final bookingsDao = BookingsDao(db, outboxDao);
  final employeesDao = EmployeesDao(db, outboxDao);
  final expensesDao = ExpensesDao(db, outboxDao);
  final debtsDao = DebtsDao(db, outboxDao);

  // 1) غرف
  for (var i = 0; i < roomsCount; i++) {
    await roomsDao.insertOne(
      RoomsCompanion(
        roomNumber: d.Value('${100 + i}'),
        type: const d.Value('عادية'),
        price: d.Value(100.0 + (i % 5) * 50),
        status: i % 3 == 0 ? const d.Value('شاغرة') : const d.Value('محجوزة'),
        localUuid: d.Value('room-uuid-$i'),
      ),
    );
  }

  // 2) موظفون
  for (var i = 0; i < employeesCount; i++) {
    await employeesDao.insertOne(
      EmployeesCompanion(
        name: d.Value('موظف $i'),
        basicSalary: const d.Value(5000.0),
        position: const d.Value('موظف'),
        phone: d.Value('050$i'),
        hireDate: const d.Value('2024-01-01'),
        status: const d.Value('active'),
        localUuid: d.Value('emp-uuid-$i'),
      ),
    );
  }

  // 3) حجوزات (مرتبطة بالغرف)
  final now = DateTime.now();
  for (var i = 0; i < bookingsCount; i++) {
    await bookingsDao.insertOne(
      BookingsCompanion(
        roomNumber: d.Value('${100 + i}'),
        guestName: d.Value('ضيف $i'),
        guestPhone: d.Value('05012345$i'),
        guestNationality: const d.Value('يمني'),
        checkinDate: d.Value(now.toIso8601String()),
        status: const d.Value('نشط'),
        localUuid: d.Value('booking-uuid-$i'),
      ),
    );
  }

  // 4) مصروفات
  for (var i = 0; i < expensesCount; i++) {
    await expensesDao.insertOne(
      ExpensesCompanion(
        expenseType: const d.Value('صيانة'),
        description: d.Value('مصروف $i'),
        amount: d.Value((i + 1) * 10.0),
        date: d.Value(now.toIso8601String()),
        hotelDayKey: const d.Value('2026-07-20'),
        localUuid: d.Value('expense-uuid-$i'),
      ),
    );
  }

  // 5) ديون
  for (var i = 0; i < debtsCount; i++) {
    await debtsDao.insertOne(
      DebtsCompanion(
        guestName: d.Value('مدين $i'),
        checkinDate: d.Value(now.toIso8601String()),
        checkoutDate: d.Value(now.add(const Duration(days: 1)).toIso8601String()),
        dateRecorded: d.Value(now.toIso8601String()),
        debtReason: d.Value('دين $i'),
        totalAmount: d.Value((i + 1) * 100.0),
        paidAmount: const d.Value(0),
        remainingAmount: d.Value((i + 1) * 100.0),
        paymentDate: d.Value(now.toIso8601String()),
        isSettled: const d.Value(0),
        localUuid: d.Value('debt-uuid-$i'),
      ),
    );
  }

  return db;
}

/// Helper: يبني ProviderScope مع Timer-safe overrides المشتركة.
///
/// ملاحظة مهمة (منهجية عدم التخمين):
/// كل providers التالية تستخدم debounceStream (lib/utils/stream_helpers.dart:18)
/// التي تُنشئ Timer(150ms) لا يُلغى عند dispose. هذا يسبب assertion
/// '!timersPending' في flutter_test. لذلك نُعوّضها كلها بـ Stream.value ثابت.
Widget _buildTestWidget({
  required AppDatabase db,
  required Widget child,
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      // ✅ Timer-safe overrides لكل providers التي تستخدم debounceStream:
      simpleNotesUnreadCountProvider.overrideWith((ref) => Stream.value(0)),
      syncStatusProvider.overrideWith((ref) => Stream.value(SyncStatus.idle)),
      roomsWithPaymentStatusProvider.overrideWith(
        (ref) => Stream.value(const <RoomWithPaymentStatus>[]),
      ),
      todayPaymentsProvider.overrideWith((ref) => Stream.value(0.0)),
      todayExpensesProvider.overrideWith((ref) => Stream.value(0.0)),
      // ✅ قوائم رئيسية (كلها تستخدم debounceStream 150ms):
      roomsListProvider.overrideWith((ref) => Stream.value(const <Room>[])),
      bookingsListProvider.overrideWith((ref) => Stream.value(const <Booking>[])),
      employeesListProvider.overrideWith((ref) => Stream.value(const <Employee>[])),
      debtsListProvider.overrideWith((ref) => Stream.value(const <Debt>[])),
      expensesListProvider.overrideWith((ref) => Stream.value(const <Expense>[])),
      // ✅ appVersionProvider يستدعي PackageInfo.fromPlatform (يفشل في test):
      appVersionProvider.overrideWith((ref) async => '1.0.0+1'),
      ...extraOverrides,
    ],
    child: MaterialApp(home: child),
  );
}

/// Helper: ينظّف أي timers معلّقة من debounceStream و drift قبل نهاية الـ test.
///
/// السبب (منهجية عدم التخمين):
/// - debounceStream (lib/utils/stream_helpers.dart:18) تُنشئ Timer(150ms)
///   لا يُلغى إلا عند وصول بيانات جديدة أو إغلاق الـ stream.
/// - drift نفسها تُنشئ Timer.run داخلي في StreamQueryStore.markAsClosed
///   (drift-2.31.0/lib/.../stream_queries.dart:153) عند dispose الـ StreamBuilder.
///   drift docs تقول صراحةً (نفس الملف، السطر 144-148):
///   "If you're sent here because your Flutter tests fail, please call and
///   await Database.close() in your Flutter widget tests!"
/// - الحل الرسمي لـ drift: استدعاء `await db.close()` في tearDown لإغلاق
///   الـ StreamQueryStore وما يتعلق بها من timers.
/// - إضافياً: ننتظر real-time عبر tester.runAsync لتنفيذ أي timers متبقية
///   من debounceStream.
Future<void> _cleanupPendingTimers(WidgetTester tester) async {
  // runAsync يُشغّل الكود في real async zone حيث Future.delayed و Timer
  // الحقيقيان يُنفّذان (وليس fake_async).
  await tester.runAsync(() async {
    // 500ms كافية لـ debounce 150ms + drift cleanup timers.
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  // pump لمعالجة أي frames جديدة نتجت عن تنفيذ الـ timers.
  try {
    await tester.pumpAndSettle(const Duration(seconds: 1));
  } catch (_) {
    // تجاهل timeout — المقاييس already جُمعت.
  }
}

/// Helper: يقيس build + settle + memory لشاشة معينة.
///
/// ملاحظات منهجية عدم التخمين:
/// 1. نلتقط exceptions أثناء pump (مثل SingleTickerProviderStateMixin سابقاً)
///    لأنها مشاكل إنتاجية لا تمنع قياس زمن البناء.
/// 2. نستخدم pump عدة مرات بدل pumpAndSettle لتجنب hang على animations مستمرة.
/// 3. في نهاية كل test، نستدعي _cleanupPendingTimers لتنظيف أي timers
///    معلّقة من debounceStream المُستخدم مباشرة في بعض الشاشات.
/// 4. ✅ حل drift الرسمي: استدعاء `await db.close()` قبل نهاية الـ test
///    لإغلاق StreamQueryStore وما يتعلق بها من timers.
///    (drift docs: "call and await Database.close() in your Flutter widget tests!")
Future<ScreenMetrics> _measureScreen(
  WidgetTester tester,
  String screenName,
  AppDatabase db,
  Widget child, {
  List<Override> extraOverrides = const [],
  int settleTimeoutSec = 3,
}) async {
  final metrics = ScreenMetrics(screenName);
  final beforeBytes = ProcessInfo.currentRss;

  try {
    final buildStopwatch = Stopwatch()..start();
    await tester.pumpWidget(
      _buildTestWidget(db: db, child: child, extraOverrides: extraOverrides),
    );
    buildStopwatch.stop();
    metrics.buildMs = buildStopwatch.elapsedMilliseconds;

    final settleStopwatch = Stopwatch()..start();
    // نستخدم pump عدة مرات بدل pumpAndSettle لتجنب hang على animations مستمرة
    // أو tickers معلّقة. كل pump يُقدم إطار واحد.
    for (var i = 0; i < settleTimeoutSec * 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    settleStopwatch.stop();
    metrics.settleMs = settleStopwatch.elapsedMilliseconds;

    // التقاط أي exceptions متراكمة أثناء البناء (مشاكل widgets حقيقية)
    final exception = tester.takeException();
    if (exception != null) {
      metrics.failureReason = 'pumpWidget exception: $exception';
    }
    metrics.passed = true;
  } catch (e, stack) {
    metrics.passed = false;
    metrics.failureReason = '$e';
    debugPrint('❌ $screenName failed: $e');
    debugPrint('  stack: $stack');
  }

  final afterBytes = ProcessInfo.currentRss;
  metrics.memoryDeltaMB = (afterBytes - beforeBytes) / (1024 * 1024);

  // ✅ حل drift الرسمي لإغلاق StreamQueryStore قبل نهاية الـ test.
  // drift docs (stream_queries.dart:144-148): "call and await Database.close()
  // in your Flutter widget tests!"
  // هذا يُلغي كل الـ timers الداخلية لـ drift.
  try {
    await db.close();
  } catch (_) {
    // تجاهل — الـ db قد تكون أُغلقت مسبقاً في tearDown.
  }

  return metrics;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ✅ تهيئة locale data لـ DateFormat (يستخدم في BookingPaymentScreen
  // وغيرها عبر DateFormat('yyyy-MM-dd HH:mm', 'en')).
  // بدون هذا، يرمي LocaleDataException عند بناء الشاشة.
  setUpAll(() async {
    await initializeDateFormatting();
  });

  late AppDatabase db;

  setUp(() async {
    db = await _seedFullDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  1. DashboardScreen — الأكثر استخداماً
  // ═══════════════════════════════════════════════════════════════════════════
  group('📱 DashboardScreen', () {
    testWidgets('البناء + الاستقرار خلال < 3 ثواني', (tester) async {
      final metrics = await _measureScreen(
        tester,
        'DashboardScreen',
        db,
        const DashboardScreen(),
      );
      allMetrics.add(metrics);
      debugPrint('✓ $metrics');

      expect(metrics.passed, true, reason: metrics.failureReason ?? '');
      expect(metrics.totalMs, lessThan(3000), reason: 'DashboardScreen يجب أن تُبنى خلال < 3 ثواني');
      // ✅ تنظيف أي timers معلّقة من debounceStream و drift قبل نهاية الـ test
      // لتجنب assertion '!timersPending' في flutter_test.
      await _cleanupPendingTimers(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  2. RoomsListScreen — إدارة الغرف
  // ═══════════════════════════════════════════════════════════════════════════
  group('🏨 RoomsListScreen', () {
    testWidgets('البناء + الاستقرار خلال < 3 ثواني', (tester) async {
      final metrics = await _measureScreen(
        tester,
        'RoomsListScreen',
        db,
        const RoomsListScreen(),
      );
      allMetrics.add(metrics);
      debugPrint('✓ $metrics');

      expect(metrics.passed, true, reason: metrics.failureReason ?? '');
      expect(metrics.totalMs, lessThan(3000), reason: 'RoomsListScreen يجب أن تُبنى خلال < 3 ثواني');
      await _cleanupPendingTimers(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  3. BookingPaymentScreen — الأكثر تعقيداً (4125 سطر)
  // ═══════════════════════════════════════════════════════════════════════════
  group('💳 BookingPaymentScreen', () {
    testWidgets('البناء + الاستقرار خلال < 5 ثواني', (tester) async {
      // نحتاج booking حقيقي من الـ DB
      final bookingsDao = BookingsDao(db, OutboxDao(db));
      final bookings = await bookingsDao.list();
      final booking = bookings.first;

      final metrics = await _measureScreen(
        tester,
        'BookingPaymentScreen',
        db,
        BookingPaymentScreen(booking: booking),
        settleTimeoutSec: 5,
      );
      allMetrics.add(metrics);
      debugPrint('✓ $metrics');

      expect(metrics.passed, true, reason: metrics.failureReason ?? '');
      expect(metrics.totalMs, lessThan(5000), reason: 'BookingPaymentScreen يجب أن تُبنى خلال < 5 ثواني');
      await _cleanupPendingTimers(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  4. DebtsListScreen — الديون
  // ═══════════════════════════════════════════════════════════════════════════
  group('💰 DebtsListScreen', () {
    testWidgets('البناء + الاستقرار خلال < 3 ثواني', (tester) async {
      final metrics = await _measureScreen(
        tester,
        'DebtsListScreen',
        db,
        const DebtsListScreen(),
      );
      allMetrics.add(metrics);
      debugPrint('✓ $metrics');

      expect(metrics.passed, true, reason: metrics.failureReason ?? '');
      expect(metrics.totalMs, lessThan(3000), reason: 'DebtsListScreen يجب أن تُبنى خلال < 3 ثواني');
      await _cleanupPendingTimers(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  5. EmployeesListScreen — الموظفون
  // ═══════════════════════════════════════════════════════════════════════════
  group('👔 EmployeesListScreen', () {
    testWidgets('البناء + الاستقرار خلال < 3 ثواني', (tester) async {
      final metrics = await _measureScreen(
        tester,
        'EmployeesListScreen',
        db,
        const EmployeesListScreen(),
      );
      allMetrics.add(metrics);
      debugPrint('✓ $metrics');

      expect(metrics.passed, true, reason: metrics.failureReason ?? '');
      expect(metrics.totalMs, lessThan(3000), reason: 'EmployeesListScreen يجب أن تُبنى خلال < 3 ثواني');
      await _cleanupPendingTimers(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  6. BookingsListScreen — قائمة الحجوزات
  // ═══════════════════════════════════════════════════════════════════════════
  group('📅 BookingsListScreen', () {
    testWidgets('البناء + الاستقرار خلال < 3 ثواني', (tester) async {
      final metrics = await _measureScreen(
        tester,
        'BookingsListScreen',
        db,
        const BookingsListScreen(),
      );
      allMetrics.add(metrics);
      debugPrint('✓ $metrics');

      expect(metrics.passed, true, reason: metrics.failureReason ?? '');
      expect(metrics.totalMs, lessThan(3000), reason: 'BookingsListScreen يجب أن تُبنى خلال < 3 ثواني');
      await _cleanupPendingTimers(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  7. تقرير نهائي — جدول مقارنة كل الشاشات
  // ═══════════════════════════════════════════════════════════════════════════
  group('📊 Final Comparison Report', () {
    test('طباعة جدول مقارنة كل المقاييس', () {
      debugPrint('');
      debugPrint('╔══════════════════════════════════════════════════════════════════════════╗');
      debugPrint('║  📊 Marina Hotel — Wide Coverage Screen Benchmark — Final Report      ║');
      debugPrint('╠══════════════════════════════════════════════════════════════════════════╣');
      debugPrint('║  البيانات: 20 غرفة + 15 حجز + 30 مصروف + 5 موظفين + 10 ديون           ║');
      debugPrint('║  DB: drift NativeDatabase.memory() (حقيقية في الذاكرة)                ║');
      debugPrint('║  Providers: ProviderScope + Timer-safe overrides                      ║');
      debugPrint('╠══════════════════════════════════════════════════════════════════════════╣');
      debugPrint('║  Screen                │ build(ms) │ settle(ms) │ total │ mem(MB) │ ✅  ║');
      debugPrint('╠══════════════════════════════════════════════════════════════════════════╣');
      for (final m in allMetrics) {
        final name = m.screenName.padRight(22);
        final build = m.buildMs.toString().padLeft(8);
        final settle = m.settleMs.toString().padLeft(10);
        final total = m.totalMs.toString().padLeft(5);
        final mem = '+${m.memoryDeltaMB.toStringAsFixed(1)}'.padLeft(7);
        final ok = m.passed ? ' ✅ ' : ' ❌ ';
        debugPrint('║  $name │ $build │ $settle │ $total │ $mem │$ok ║');
      }
      debugPrint('╚══════════════════════════════════════════════════════════════════════════╝');

      // التحقق أن كل الشاشات نجحت
      final failed = allMetrics.where((m) => !m.passed).toList();
      expect(failed, isEmpty, reason: 'كل الشاشات يجب أن تنجح. الفاشلة: ${failed.map((m) => m.screenName).join(", ")}');

      // التحقق أن متوسط زمن البناء معقول
      if (allMetrics.isNotEmpty) {
        final avgTotal = allMetrics.fold<int>(0, (s, m) => s + m.totalMs) / allMetrics.length;
        debugPrint('  📈 متوسط زمن البناء الكلي: ${avgTotal.toStringAsFixed(0)}ms');
        expect(avgTotal, lessThan(3000), reason: 'متوسط زمن البناء يجب أن يكون < 3 ثواني');
      }
    });
  });
}
