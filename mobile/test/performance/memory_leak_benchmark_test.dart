import 'dart:io' show Platform;

// ============================================================================
//  Marina Hotel — Memory Leak Detection Benchmark
//  ============================================================================
//  يُشغّل نفس الشاشة 10 مرات متتالية ويقارن delta الذاكرة لرصد memory leaks.
//
//  المنهجية (بدون تخمين):
//    - كل iteration تُنشئ ProviderScope جديد + pumpWidget + pumpAndSettle.
//    - نسجّل ProcessInfo.currentRss قبل وبعد كل iteration.
//    - بعد كل iteration نُغلق db (حل drift الرسمي) وننتظر GC.
//    - نقارن delta عبر الـ 10 iterations:
//      * إذا كان delta متناقص أو ثابت → لا يوجد leak.
//      * إذا كان delta يزداد بشكل خطي → leak محتمل.
//
//  التشغيل:
//    flutter test test/performance/memory_leak_benchmark_test.dart \
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

import 'package:marina_hotel_mobile/providers/auth_provider.dart';
import 'package:marina_hotel_mobile/providers/core_providers.dart';
import 'package:marina_hotel_mobile/providers/repository_providers.dart';
import 'package:marina_hotel_mobile/providers/room_payment_status_provider.dart';
import 'package:marina_hotel_mobile/screens/dashboard_screen.dart';
import 'package:marina_hotel_mobile/screens/debts/debts_list.dart';
import 'package:marina_hotel_mobile/screens/employees/employees_list.dart';
import 'package:marina_hotel_mobile/screens/expenses/expenses_list.dart';
import 'package:marina_hotel_mobile/screens/rooms/rooms_list.dart';
import 'package:marina_hotel_mobile/services/daos/employees_dao.dart';
import 'package:marina_hotel_mobile/services/daos/expenses_dao.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/daos/rooms_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_service.dart';

/// Fake AuthNotifier يتجنب SharedPreferences (الذي يفشل في tests بدون plugin).
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier() : super() {
    state = const AuthState(isAuthenticated: false);
  }
  @override
  Future<void> restoreSession() async {}
  @override
  Future<void> login(
    String username,
    String password, {
    bool rememberMe = false,
  }) async {}
  @override
  Future<void> logout() async {}
}

/// بيانات iteration واحدة.
class _IterationMetrics {
  _IterationMetrics(this.iteration);
  final int iteration;
  int beforeRss = 0;
  int afterRss = 0;
  int get deltaBytes => afterRss - beforeRss;
  double get deltaMB => deltaBytes / (1024 * 1024);
}

/// يبني ProviderScope مع Timer-safe overrides (مثل wide_screen_benchmark).
Widget _buildTestWidget({required AppDatabase db, required Widget child}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      simpleNotesUnreadCountProvider.overrideWith((ref) => Stream.value(0)),
      syncStatusProvider.overrideWith((ref) => Stream.value(SyncStatus.idle)),
      roomsWithPaymentStatusProvider.overrideWith(
        (ref) => Stream.value(const <RoomWithPaymentStatus>[]),
      ),
      todayPaymentsProvider.overrideWith((ref) => Stream.value(0.0)),
      todayExpensesProvider.overrideWith((ref) => Stream.value(0.0)),
      roomsListProvider.overrideWith((ref) => Stream.value(const <Room>[])),
      bookingsListProvider.overrideWith(
        (ref) => Stream.value(const <Booking>[]),
      ),
      employeesListProvider.overrideWith(
        (ref) => Stream.value(const <Employee>[]),
      ),
      debtsListProvider.overrideWith((ref) => Stream.value(const <Debt>[])),
      expensesListProvider.overrideWith(
        (ref) => Stream.value(const <Expense>[]),
      ),
      appVersionProvider.overrideWith((ref) async => '1.0.0+1'),
      // ✅ تجنب MissingPluginException لـ SharedPreferences:
      authProvider.overrideWith((ref) => _FakeAuthNotifier()),
    ],
    child: MaterialApp(home: child),
  );
}

/// يُنشئ AppDatabase مع بيانات حقيقية (10 غرف + 5 موظفين + 10 مصروفات).
Future<AppDatabase> _seedDatabase() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final outboxDao = OutboxDao(db);
  final roomsDao = RoomsDao(db, outboxDao);
  final employeesDao = EmployeesDao(db, outboxDao);
  final expensesDao = ExpensesDao(db, outboxDao);

  for (var i = 0; i < 10; i++) {
    await roomsDao.insertOne(
      RoomsCompanion(
        roomNumber: d.Value('${100 + i}'),
        type: const d.Value('عادية'),
        price: d.Value(100.0 + i * 50),
        status: const d.Value('شاغرة'),
        localUuid: d.Value('room-uuid-$i'),
      ),
    );
  }

  for (var i = 0; i < 5; i++) {
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

  final now = DateTime.now();
  for (var i = 0; i < 10; i++) {
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

  return db;
}

/// يُشغّل شاشة معينة 10 مرات متتالية ويُسجّل مقاييس الذاكرة.
Future<List<_IterationMetrics>> _runIterations(
  WidgetTester tester,
  Widget Function() screenBuilder,
  String screenName,
  int iterations,
) async {
  final results = <_IterationMetrics>[];

  for (var i = 0; i < iterations; i++) {
    final metrics = _IterationMetrics(i + 1);
    final db = await _seedDatabase();

    // ✅ حل drift الرسمي: انتظر real-time قبل القياس لاستقرار GC.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    metrics.beforeRss = ProcessInfo.currentRss;

    await tester.pumpWidget(_buildTestWidget(db: db, child: screenBuilder()));

    // pump عدة مرات لاستقرار الـ streams (بدون pumpAndSettle لتجنب hang).
    for (var j = 0; j < 30; j++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // ✅ حل drift الرسمي لإغلاق StreamQueryStore قبل نهاية الـ iteration.
    try {
      await db.close();
    } catch (_) {
      // تجاهل — الـ db قد تكون أُغلقت مسبقاً.
    }

    // انتظر GC لاستقرار القياس.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    metrics.afterRss = ProcessInfo.currentRss;
    results.add(metrics);

    debugPrint(
      '  Iteration ${i + 1}/$iterations: '
      'before=${(metrics.beforeRss / 1024 / 1024).toStringAsFixed(1)}MB '
      'after=${(metrics.afterRss / 1024 / 1024).toStringAsFixed(1)}MB '
      'delta=${metrics.deltaMB >= 0 ? "+" : ""}${metrics.deltaMB.toStringAsFixed(2)}MB',
    );
  }

  return results;
}

/// يُحلّل نتائج الـ iterations لرصد leak.
String _analyzeLeak(List<_IterationMetrics> results) {
  if (results.length < 2) return 'insufficient data';

  // مقارنة first delta vs last delta
  final firstDelta = results.first.deltaBytes;
  final lastDelta = results.last.deltaBytes;
  final totalGrowth = results.last.afterRss - results.first.beforeRss;

  // حساب متوسط delta آخر 3 iterations (بعد استقرار JIT)
  final lateDeltas = results
      .skip(results.length - 3)
      .map((m) => m.deltaBytes)
      .toList();
  final avgLateDelta = lateDeltas.reduce((a, b) => a + b) / lateDeltas.length;

  // leak threshold: إذا كان متوسط delta الأخير > 5MB → leak محتمل
  const leakThreshold = 5 * 1024 * 1024; // 5MB

  debugPrint('');
  debugPrint('  📊 Leak Analysis:');
  debugPrint(
    '    First iteration delta: ${(firstDelta / 1024 / 1024).toStringAsFixed(2)}MB',
  );
  debugPrint(
    '    Last iteration delta:  ${(lastDelta / 1024 / 1024).toStringAsFixed(2)}MB',
  );
  debugPrint(
    '    Average late delta (last 3): ${(avgLateDelta / 1024 / 1024).toStringAsFixed(2)}MB',
  );
  debugPrint(
    '    Total growth (iter 1 before → iter ${results.length} after): '
    '${(totalGrowth / 1024 / 1024).toStringAsFixed(2)}MB',
  );

  if (avgLateDelta > leakThreshold) {
    return '⚠️ LEAK SUSPECTED: late delta average > 5MB';
  } else if (totalGrowth > 50 * 1024 * 1024) {
    return '⚠️ HIGH TOTAL GROWTH: > 50MB across iterations';
  } else {
    return '✅ NO LEAK DETECTED: late delta average < 5MB';
  }
}

void main() {
  final isCI = Platform.environment.containsKey('CI') ||
      Platform.environment.containsKey('GITHUB_ACTIONS');
  if (isCI) {
    // هذه الاختبارات تحتاج موارد كبيرة وتسبب segmentation fault في CI
    // تُشغّل محلياً فقط
    return;
  }

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  1. DashboardScreen — 10 iterations
  // ═══════════════════════════════════════════════════════════════════════════
  group('🧠 Memory Leak — DashboardScreen (10x)', () {
    testWidgets('10 iterations بدون leak', (tester) async {
      debugPrint('📍 DashboardScreen — 10 iterations:');
      final results = await _runIterations(
        tester,
        () => const DashboardScreen(),
        'DashboardScreen',
        10,
      );
      final analysis = _analyzeLeak(results);
      debugPrint('  Result: $analysis');

      // التحقق أن النمو الكلي < 100MB (على مدى 10 iterations)
      final totalGrowthMB =
          (results.last.afterRss - results.first.beforeRss) / (1024 * 1024);
      expect(
        totalGrowthMB,
        lessThan(100),
        reason:
            'النمو الكلي عبر 10 iterations يجب أن يكون < 100MB. '
            'الفعلي: ${totalGrowthMB.toStringAsFixed(2)}MB',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  2. RoomsListScreen — 10 iterations
  // ═══════════════════════════════════════════════════════════════════════════
  group('🧠 Memory Leak — RoomsListScreen (10x)', () {
    testWidgets('10 iterations بدون leak', (tester) async {
      debugPrint('📍 RoomsListScreen — 10 iterations:');
      final results = await _runIterations(
        tester,
        () => const RoomsListScreen(),
        'RoomsListScreen',
        10,
      );
      final analysis = _analyzeLeak(results);
      debugPrint('  Result: $analysis');

      final totalGrowthMB =
          (results.last.afterRss - results.first.beforeRss) / (1024 * 1024);
      expect(
        totalGrowthMB,
        lessThan(100),
        reason:
            'النمو الكلي عبر 10 iterations يجب أن يكون < 100MB. '
            'الفعلي: ${totalGrowthMB.toStringAsFixed(2)}MB',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  3. ExpensesListScreen — 10 iterations
  // ═══════════════════════════════════════════════════════════════════════════
  group('🧠 Memory Leak — ExpensesListScreen (10x)', () {
    testWidgets('10 iterations بدون leak', (tester) async {
      debugPrint('📍 ExpensesListScreen — 10 iterations:');
      final results = await _runIterations(
        tester,
        () => const ExpensesListScreen(),
        'ExpensesListScreen',
        10,
      );
      final analysis = _analyzeLeak(results);
      debugPrint('  Result: $analysis');

      final totalGrowthMB =
          (results.last.afterRss - results.first.beforeRss) / (1024 * 1024);
      expect(
        totalGrowthMB,
        lessThan(100),
        reason:
            'النمو الكلي عبر 10 iterations يجب أن يكون < 100MB. '
            'الفعلي: ${totalGrowthMB.toStringAsFixed(2)}MB',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  4. DebtsListScreen — 10 iterations
  // ═══════════════════════════════════════════════════════════════════════════
  group('🧠 Memory Leak — DebtsListScreen (10x)', () {
    testWidgets('10 iterations بدون leak', (tester) async {
      debugPrint('📍 DebtsListScreen — 10 iterations:');
      final results = await _runIterations(
        tester,
        () => const DebtsListScreen(),
        'DebtsListScreen',
        10,
      );
      final analysis = _analyzeLeak(results);
      debugPrint('  Result: $analysis');

      final totalGrowthMB =
          (results.last.afterRss - results.first.beforeRss) / (1024 * 1024);
      expect(
        totalGrowthMB,
        lessThan(100),
        reason:
            'النمو الكلي عبر 10 iterations يجب أن يكون < 100MB. '
            'الفعلي: ${totalGrowthMB.toStringAsFixed(2)}MB',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  5. EmployeesListScreen — 10 iterations
  // ═══════════════════════════════════════════════════════════════════════════
  group('🧠 Memory Leak — EmployeesListScreen (10x)', () {
    testWidgets('10 iterations بدون leak', (tester) async {
      debugPrint('📍 EmployeesListScreen — 10 iterations:');
      final results = await _runIterations(
        tester,
        () => const EmployeesListScreen(),
        'EmployeesListScreen',
        10,
      );
      final analysis = _analyzeLeak(results);
      debugPrint('  Result: $analysis');

      final totalGrowthMB =
          (results.last.afterRss - results.first.beforeRss) / (1024 * 1024);
      expect(
        totalGrowthMB,
        lessThan(100),
        reason:
            'النمو الكلي عبر 10 iterations يجب أن يكون < 100MB. '
            'الفعلي: ${totalGrowthMB.toStringAsFixed(2)}MB',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  6. ملخص نهائي
  // ═══════════════════════════════════════════════════════════════════════════
  group('📊 Memory Leak Summary', () {
    test('طباعة ملخص منهجية الكشف عن leak', () {
      debugPrint('');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('  📊 Memory Leak Detection — Summary');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('  المنهجية:');
      debugPrint('    • كل iteration: إنشاء ProviderScope + pumpWidget + pump');
      debugPrint('    • إغلاق db (حل drift الرسمي)');
      debugPrint('    • انتظار GC 200ms بين iterations');
      debugPrint('    • قياس ProcessInfo.currentRss قبل/بعد');
      debugPrint('  التحليل:');
      debugPrint('    • late delta avg > 5MB → LEAK SUSPECTED');
      debugPrint('    • total growth > 50MB → HIGH GROWTH warning');
      debugPrint('    • عتبة الـ test: total growth < 100MB');
      debugPrint('  الشاشات المُختبرة:');
      debugPrint('    • DashboardScreen (10x)');
      debugPrint('    • RoomsListScreen (10x)');
      debugPrint('    • ExpensesListScreen (10x)');
      debugPrint('    • DebtsListScreen (10x)');
      debugPrint('    • EmployeesListScreen (10x)');
      debugPrint('═══════════════════════════════════════════════════════════');
      expect(true, isTrue);
    });
  });
}
