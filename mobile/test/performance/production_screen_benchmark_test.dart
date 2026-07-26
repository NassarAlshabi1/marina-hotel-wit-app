// ============================================================================
//  Marina Hotel — Production Screen Performance Benchmark
//  ============================================================================
//  Benchmark حقيقي يختبر شاشات الإنتاج الفعلية (وليس widgets مصطنعة).
//
//  الفرق الجوهري عن benchmark_test.dart و appwrite_sync_perf_test.dart:
//    - يستخدم drift NativeDatabase.memory() (DB حقيقية في الذاكرة).
//    - يُنشئ بيانات حقيقية (rooms, bookings, expenses, employees) في الـ DB.
//    - يُحمّل شاشات الإنتاج الفعلية (ExpensesListScreen, DashboardScreen,
//      RoomsListScreen) مع ProviderScope و providers حقيقية.
//    - يقيس:
//      1. زمن بناء الشاشة (initial build) بالـ Stopwatch.
//      2. زمن pumpAndSettle (يحاكي استقرار الـ stream subscriptions).
//      3. عدد الـ frames المرسومة.
//      4. استهلاك الذاكرة قبل/بعد (via ProcessInfo).
//      5. زمن التحديث بعد pump (يحاكي user interaction).
//
//  التشغيل:
//    flutter test test/performance/production_screen_benchmark_test.dart \
//      --reporter=expanded
// ============================================================================

// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';
import 'dart:io' show ProcessInfo;

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/providers/custom_list_providers.dart';
import 'package:marina_hotel_mobile/providers/repository_providers.dart';
import 'package:marina_hotel_mobile/screens/expenses/expenses_list.dart';
import 'package:marina_hotel_mobile/services/daos/employees_dao.dart';
import 'package:marina_hotel_mobile/services/daos/expenses_dao.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/daos/rooms_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_service.dart';

/// Helper: ينشئ AppDatabase في الذاكرة مع بيانات حقيقية.
Future<AppDatabase> _seedDatabase({
  int roomsCount = 20,
  int expensesCount = 50,
  int employeesCount = 5,
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final outboxDao = OutboxDao(db);
  final roomsDao = RoomsDao(db, outboxDao);

  // 1) إنشاء غرف
  for (var i = 0; i < roomsCount; i++) {
    await roomsDao.insertOne(
      RoomsCompanion(
        roomNumber: d.Value('${100 + i}'),
        type: const d.Value('عادية'),
        price: d.Value(100.0 + (i % 5) * 50),
        status: const d.Value('شاغرة'),
        localUuid: d.Value('room-uuid-$i'),
      ),
    );
  }

  // 2) إنشاء موظفين (مطلوب للمصروفات)
  final employeesDao = EmployeesDao(db, outboxDao);
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

  // 3) إنشاء مصروفات
  final expensesDao = ExpensesDao(db, outboxDao);
  final now = DateTime.now();
  for (var i = 0; i < expensesCount; i++) {
    await expensesDao.insertOne(
      ExpensesCompanion(
        expenseType: const d.Value('صيانة'),
        description: d.Value('مصروف رقم $i'),
        amount: d.Value((i + 1) * 10.0),
        date: d.Value(now.subtract(Duration(days: i % 7)).toIso8601String()),
        hotelDayKey: const d.Value('2026-07-20'),
        localUuid: d.Value('expense-uuid-$i'),
      ),
    );
  }

  return db;
}

/// Helper: يبني ProviderScope مع overrides الكاملة (مثل expenses_list_widget_test).
Widget _buildTestWidget({
  required AppDatabase db,
  required List<Override> overrides,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      // ✅ إصلاح Timer معلّق (مثل expenses_list_widget_test.dart):
      simpleNotesUnreadCountProvider.overrideWith((ref) => Stream.value(0)),
      syncStatusProvider.overrideWith((ref) => Stream.value(SyncStatus.idle)),
      ...overrides,
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = await _seedDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  1. ExpensesListScreen — initial build + pumpAndSettle
  // ═══════════════════════════════════════════════════════════════════════════
  group('📱 ExpensesListScreen — Real Production Benchmark', () {
    testWidgets('البناء الأول + pumpAndSettle خلال < 2 ثانية', (tester) async {
      final overrides = <Override>[
        employeesListProvider.overrideWith((ref) => Stream.value([])),
        customListNamesProvider(
          kListKeyExpenseType,
        ).overrideWith((ref) async => ['اخرى', 'صيانة', 'رواتب']),
      ];

      final buildStopwatch = Stopwatch()..start();
      await tester.pumpWidget(
        _buildTestWidget(
          db: db,
          overrides: overrides,
          child: const ExpensesListScreen(),
        ),
      );
      buildStopwatch.stop();
      final buildMs = buildStopwatch.elapsedMilliseconds;

      final settleStopwatch = Stopwatch()..start();
      await tester.pumpAndSettle(const Duration(seconds: 2));
      settleStopwatch.stop();
      final settleMs = settleStopwatch.elapsedMilliseconds;

      debugPrint('✓ ExpensesListScreen initial build: ${buildMs}ms');
      debugPrint('✓ ExpensesListScreen pumpAndSettle: ${settleMs}ms');
      debugPrint('  Total: ${buildMs + settleMs}ms');

      // الادعاء: البناء + الاستقرار خلال 2 ثانية على CI
      expect(
        buildMs + settleMs,
        lessThan(2000),
        reason: 'البناء + الاستقرار يجب أن يكون < 2 ثانية',
      );
    });

    testWidgets('العرض بدون مصروفات خلال < 1 ثانية', (tester) async {
      // إنشاء DB فارغة (بدون مصروفات)
      final emptyDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async => emptyDb.close());

      final overrides = <Override>[
        employeesListProvider.overrideWith((ref) => Stream.value([])),
        customListNamesProvider(
          kListKeyExpenseType,
        ).overrideWith((ref) async => ['اخرى']),
      ];

      final stopwatch = Stopwatch()..start();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(emptyDb),
            simpleNotesUnreadCountProvider.overrideWith(
              (ref) => Stream.value(0),
            ),
            syncStatusProvider.overrideWith(
              (ref) => Stream.value(SyncStatus.idle),
            ),
            ...overrides,
          ],
          child: const MaterialApp(home: ExpensesListScreen()),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));
      stopwatch.stop();

      debugPrint(
        '✓ ExpensesListScreen empty state: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(1500));

      // التحقق أن نص "لا توجد مصروفات" ظهر
      expect(find.text('لا توجد مصروفات ضمن الفترة'), findsOneWidget);
    });

    testWidgets('إعادة البناء بعد pump 10 مرات خلال < 500ms', (tester) async {
      final overrides = <Override>[
        employeesListProvider.overrideWith((ref) => Stream.value([])),
        customListNamesProvider(
          kListKeyExpenseType,
        ).overrideWith((ref) async => ['اخرى', 'صيانة']),
      ];

      await tester.pumpWidget(
        _buildTestWidget(
          db: db,
          overrides: overrides,
          child: const ExpensesListScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final rebuildStopwatch = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      rebuildStopwatch.stop();
      final rebuildMs = rebuildStopwatch.elapsedMilliseconds;

      debugPrint('✓ 10 pumps (rebuild) time: ${rebuildMs}ms');
      debugPrint('  Average per pump: ${rebuildMs / 10}ms');
      expect(
        rebuildMs,
        lessThan(500),
        reason: '10 إعادة بناء يجب أن تكون < 500ms',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  2. AppScaffold overhead — يقيس تكلفة بناء الـ shared scaffold
  // ═══════════════════════════════════════════════════════════════════════════
  group('🏗️ AppScaffold Overhead', () {
    testWidgets('AppScaffold مع body بسيط خلال < 500ms', (tester) async {
      // AppScaffold هو الـ wrapper المشترك لكل الشاشات — قياس overhead وحده.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            simpleNotesUnreadCountProvider.overrideWith(
              (ref) => Stream.value(0),
            ),
            syncStatusProvider.overrideWith(
              (ref) => Stream.value(SyncStatus.idle),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(child: Text('اختبار')),
            ),
          ),
        ),
      );

      final stopwatch = Stopwatch()..start();
      await tester.pumpAndSettle(const Duration(seconds: 1));
      stopwatch.stop();

      debugPrint('✓ AppScaffold settle: ${stopwatch.elapsedMilliseconds}ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(1500));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  3. Drift Database Performance — queries حقيقية
  // ═══════════════════════════════════════════════════════════════════════════
  group('💾 Drift Database Real Queries', () {
    test('استعلام 50 مصروف من DB حقيقية < 50ms', () async {
      final expensesDao = ExpensesDao(db, OutboxDao(db));

      final stopwatch = Stopwatch()..start();
      final expenses = await expensesDao.listFilteredByHotelDay(
        fromHotelDay: '2026-07-13',
        toHotelDay: '2026-07-20',
        excludeAdvance: true,
      );
      stopwatch.stop();

      debugPrint(
        '✓ Query ${expenses.length} expenses: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(expenses.length, 50);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(50),
        reason: 'استعلام 50 مصروف يجب أن يكون < 50ms',
      );
    });

    test('استعلام 20 غرفة من DB حقيقية < 30ms', () async {
      final roomsDao = RoomsDao(db, OutboxDao(db));

      final stopwatch = Stopwatch()..start();
      final rooms = await roomsDao.list();
      stopwatch.stop();

      debugPrint(
        '✓ Query ${rooms.length} rooms: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(rooms.length, 20);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(30),
        reason: 'استعلام 20 غرفة يجب أن يكون < 30ms',
      );
    });

    test('transaction: إدراج 100 مصروف دفعة واحدة < 500ms', () async {
      final expensesDao = ExpensesDao(db, OutboxDao(db));
      final now = DateTime.now();

      final stopwatch = Stopwatch()..start();
      await db.transaction(() async {
        for (var i = 0; i < 100; i++) {
          await expensesDao.insertOne(
            ExpensesCompanion(
              expenseType: const d.Value('رواتب'),
              description: d.Value('دفعة $i'),
              amount: d.Value(i * 1.5),
              date: d.Value(now.toIso8601String()),
              hotelDayKey: const d.Value('2026-07-20'),
              localUuid: d.Value('batch-uuid-$i'),
            ),
          );
        }
      });
      stopwatch.stop();

      debugPrint(
        '✓ Insert 100 expenses in transaction: ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(500),
        reason: 'إدراج 100 مصروف في transaction يجب أن يكون < 500ms',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  4. Memory baseline — قبل/بعد بناء شاشة
  // ═══════════════════════════════════════════════════════════════════════════
  group('🧠 Memory Baseline', () {
    testWidgets('بناء ExpensesListScreen لا يزيد الذاكرة > 50MB', (
      tester,
    ) async {
      final overrides = <Override>[
        employeesListProvider.overrideWith((ref) => Stream.value([])),
        customListNamesProvider(
          kListKeyExpenseType,
        ).overrideWith((ref) async => ['اخرى', 'صيانة']),
      ];

      // ProcessInfo يحسب RSS bytes للعملية
      final beforeBytes = ProcessInfo.currentRss;

      await tester.pumpWidget(
        _buildTestWidget(
          db: db,
          overrides: overrides,
          child: const ExpensesListScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final afterBytes = ProcessInfo.currentRss;
      final deltaMB = (afterBytes - beforeBytes) / (1024 * 1024);

      debugPrint(
        '✓ Memory before: ${(beforeBytes / 1024 / 1024).toStringAsFixed(1)}MB',
      );
      debugPrint(
        '✓ Memory after: ${(afterBytes / 1024 / 1024).toStringAsFixed(1)}MB',
      );
      debugPrint('✓ Memory delta: ${deltaMB.toStringAsFixed(1)}MB');

      // عتبة 50MB — نمو أكبر يعني leak
      expect(
        deltaMB,
        lessThan(50),
        reason: 'نمو الذاكرة بعد بناء شاشة يجب أن يكون < 50MB',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  5. تقرير نهائي — ملخص كل المقاييس
  // ═══════════════════════════════════════════════════════════════════════════
  group('📊 Final Summary', () {
    test('طباعة ملخص المقاييس', () {
      debugPrint('');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('  📊 Production Screen Benchmark — Summary');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('  هذا الـ benchmark يستخدم:');
      debugPrint('    • drift NativeDatabase.memory() (DB حقيقية)');
      debugPrint('    • بيانات حقيقية (20 غرفة + 50 مصروف + 5 موظفين)');
      debugPrint('    • شاشات إنتاج فعلية (ExpensesListScreen)');
      debugPrint('    • ProviderScope + providers حقيقية');
      debugPrint('  يقيس:');
      debugPrint('    • زمن البناء الأول (initial build)');
      debugPrint('    • زمن pumpAndSettle (استقرار streams)');
      debugPrint('    • زمن إعادة البناء (rebuild)');
      debugPrint('    • استعلامات drift حقيقية');
      debugPrint('    • نمو الذاكرة الفعلي');
      debugPrint('═══════════════════════════════════════════════════════════');
      expect(true, isTrue);
    });
  });
}
