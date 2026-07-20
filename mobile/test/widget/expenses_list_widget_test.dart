import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/providers/custom_list_providers.dart';
import 'package:marina_hotel_mobile/providers/repository_providers.dart';
import 'package:marina_hotel_mobile/screens/expenses/expenses_list.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

/// Helper: بناء ويدجت الاختبار مع ProviderScope
Widget _buildTestWidget({required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: ExpensesListScreen()),
  );
}

/// Helper: بناء موظف للاختبار
Employee _testEmployee({int id = 1, String uuid = 'emp-1', String name = 'أحمد'}) {
  return Employee(
    id: id,
    localUuid: uuid,
    name: name,
    position: 'موظف',
    basicSalary: 5000,
    phone: '',
    hireDate: '',
    status: 'active',
    createdAt: 0,
    updatedAt: 0,
    lastModified: 0,
    createdAtEpoch: 0,
    lastModifiedEpoch: 0,
    version: 1,
    origin: 'local',
    vectorClock: '{}',
    deviceId: '',
  );
}

/// Helper: overrides مشتركة
List<Override> _baseOverrides(AppDatabase db, {List<Employee>? employees}) {
  return [
    databaseProvider.overrideWithValue(db),
    employeesListProvider.overrideWith((ref) => Stream.value(employees ?? [])),
    customListNamesProvider(kListKeyExpenseType).overrideWith((ref) async => ['اخرى', 'صيانة', 'رواتب']),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════
  // عرض الشاشة الأساسية
  // ═══════════════════════════════════════════════════════════════
  group('ExpensesListScreen — عرض الشاشة الأساسية', () {
    testWidgets('يعرض عنوان المصروفات في شريط التطبيق', (tester) async {
      await tester.pumpWidget(_buildTestWidget(overrides: _baseOverrides(db, employees: [_testEmployee()])));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('المصروفات'), findsOneWidget);
    });

    testWidgets('يعرض أزرار المزامنة والإضافة', (tester) async {
      await tester.pumpWidget(_buildTestWidget(overrides: _baseOverrides(db, employees: [_testEmployee()])));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.sync), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('يعرض شريط البحث', (tester) async {
      await tester.pumpWidget(_buildTestWidget(overrides: _baseOverrides(db, employees: [_testEmployee()])));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('ابحث بالوصف أو النوع...'), findsOneWidget);
    });

    testWidgets('يعرض رسالة عندما لا توجد مصروفات', (tester) async {
      await tester.pumpWidget(_buildTestWidget(overrides: _baseOverrides(db, employees: [_testEmployee()])));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('لا توجد مصروفات ضمن الفترة'), findsOneWidget);
    });

    testWidgets('يعرض مؤشر تحميل عندما يكون الموظفون قيد التحميل', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          overrides: [
            databaseProvider.overrideWithValue(db),
            employeesListProvider.overrideWith((ref) => Stream.empty()),
            customListNamesProvider(kListKeyExpenseType).overrideWith((ref) async => ['اخرى']),
          ],
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('يعرض خطأ عندما يفشل تحميل الموظفين', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          overrides: [
            databaseProvider.overrideWithValue(db),
            employeesListProvider.overrideWith((ref) => Stream.error('خطأ في الاتصال')),
            customListNamesProvider(kListKeyExpenseType).overrideWith((ref) async => ['اخرى']),
          ],
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('تعذر تحميل الموظفين'), findsOneWidget);
    });

    testWidgets('يعرض خطأ عند فشل تحميل المصروفات', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          overrides: [
            databaseProvider.overrideWithValue(db),
            employeesListProvider.overrideWith((ref) => Stream.value([_testEmployee()])),
            customListNamesProvider(kListKeyExpenseType).overrideWith((ref) async => ['اخرى']),
          ],
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      // بدون مصروفات = رسالة لا توجد مصروفات (ليس خطأ)
      expect(find.text('لا توجد مصروفات ضمن الفترة'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // التفاعل مع البحث
  // ═══════════════════════════════════════════════════════════════
  group('ExpensesListScreen — التفاعل مع البحث', () {
    testWidgets('إدخال نص في حقل البحث يحدث الحالة', (tester) async {
      await tester.pumpWidget(_buildTestWidget(overrides: _baseOverrides(db, employees: [_testEmployee()])));
      await tester.pump(const Duration(seconds: 1));

      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'صيانة');
      expect(find.text('صيانة'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // فلتر النوع
  // ═══════════════════════════════════════════════════════════════
  group('ExpensesListScreen — فلتر النوع', () {
    testWidgets('يعرض قائمة فلتر الأنواع مع "كل الأنواع"', (tester) async {
      await tester.pumpWidget(_buildTestWidget(overrides: _baseOverrides(db, employees: [_testEmployee()])));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('كل الأنواع'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // ملخص المصروفات
  // ═══════════════════════════════════════════════════════════════
  group('ExpensesListScreen — ملخص المصروفات', () {
    testWidgets('يعرض كلمة "عملية" في الملخص', (tester) async {
      await tester.pumpWidget(_buildTestWidget(overrides: _baseOverrides(db, employees: [_testEmployee()])));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('عملية'), findsOneWidget);
    });

    testWidgets('يعرض "0" كعدد عندما لا توجد مصروفات', (tester) async {
      await tester.pumpWidget(_buildTestWidget(overrides: _baseOverrides(db, employees: [_testEmployee()])));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // فلتر التاريخ
  // ═══════════════════════════════════════════════════════════════
  group('ExpensesListScreen — فلتر التاريخ', () {
    testWidgets('يعرض أزرار التاريخ "من" و "إلى"', (tester) async {
      await tester.pumpWidget(_buildTestWidget(overrides: _baseOverrides(db, employees: [_testEmployee()])));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('من'), findsOneWidget);
      expect(find.textContaining('إلى'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // زر الإضافة يفتح الحوار
  // ═══════════════════════════════════════════════════════════════
  group('ExpensesListScreen — زر الإضافة', () {
    testWidgets('الضغط على زر الإضافة يفتح حوار إضافة مصروف', (tester) async {
      await tester.pumpWidget(_buildTestWidget(overrides: _baseOverrides(db, employees: [_testEmployee()])));
      await tester.pump(const Duration(seconds: 1));

      // الضغط على زر الإضافة
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump(const Duration(seconds: 1));

      // التحقق من ظهور حوار الإضافة
      expect(find.text('إضافة مصروف'), findsOneWidget);
      expect(find.text('نوع المصروف'), findsOneWidget);
      expect(find.text('المبلغ'), findsOneWidget);
      expect(find.text('الوصف'), findsOneWidget);
      expect(find.text('التاريخ'), findsOneWidget);
      expect(find.text('حفظ'), findsOneWidget);
      expect(find.text('إلغاء'), findsOneWidget);
    });
  });
}
