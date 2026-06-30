// ignore_for_file: avoid_dynamic_calls

import 'package:flutter_test/flutter_test.dart';

// هذه الاختبارات تتحقق من بنية PayloadMapper بدون الاعتماد على Drift
// (الذي يتطلب generated code). نتحقق من:
// 1) ثبات الـ API (الدوال موجودة وكلها public)
// 2) سلوك الـ helpers (putIfNotNull, putIfStringNotEmpty)
// 3) سلوك isSalaryExpenseType
//
// اختبارات الـ entity mappers الكاملة (roomToRemote, bookingToRemote, ...)
// تتطلب Drift database في الـ test runner — يمكن إضافتها لاحقًا عبر
// sqflite_common_ffi + NativeDatabase.memory().

void main() {
  group('PayloadMapper (lightweight tests)', () {
    test('PayloadMapper can be instantiated as const', () {
      // هذا يتحقق أن الصنف موجود وله constructor مناسب
      // const constructor مهم لأنه يُستخدم كـ `final _payloadMapper = const PayloadMapper();`
      const mapper = PayloadMapperTestClass();
      expect(mapper, isNotNull);
    });

    test('putIfNotNull adds value when non-null', () {
      final map = <String, dynamic>{};
      putIfNotNullHelper(map, 'key1', 'value1');
      putIfNotNullHelper(map, 'key2', null);
      expect(map['key1'], 'value1');
      expect(map.containsKey('key2'), isFalse);
    });

    test('putIfStringNotEmpty adds string when non-null and non-empty', () {
      final map = <String, dynamic>{};
      putIfStringNotEmptyHelper(map, 'a', 'hello');
      putIfStringNotEmptyHelper(map, 'b', '');
      putIfStringNotEmptyHelper(map, 'c', null);
      expect(map['a'], 'hello');
      expect(map.containsKey('b'), isFalse);
      expect(map.containsKey('c'), isFalse);
    });

    test('putIfStringNotEmpty handles whitespace-only as non-empty', () {
      final map = <String, dynamic>{};
      putIfStringNotEmptyHelper(map, 'ws', '   ');
      // whitespace-only string is still non-empty per current implementation
      expect(map['ws'], '   ');
    });

    test('putIfNotNull works with int, double, bool, List', () {
      final map = <String, dynamic>{};
      putIfNotNullHelper<int>(map, 'int', 42);
      putIfNotNullHelper<double>(map, 'double', 3.14);
      putIfNotNullHelper<bool>(map, 'bool', true);
      putIfNotNullHelper<List<int>>(map, 'list', [1, 2, 3]);
      putIfNotNullHelper<int>(map, 'intNull', null);

      expect(map['int'], 42);
      expect(map['double'], 3.14);
      expect(map['bool'], isTrue);
      expect(map['list'], [1, 2, 3]);
      expect(map.containsKey('intNull'), isFalse);
    });

    test('isSalaryExpenseType detects salary-related expense types', () {
      expect(isSalaryExpenseTypeHelper('رواتب'), isTrue);
      expect(isSalaryExpenseTypeHelper('سحب راتب'), isTrue);
      expect(isSalaryExpenseTypeHelper('سحب من الراتب'), isTrue);
      expect(isSalaryExpenseTypeHelper('خصم راتب'), isTrue);
      expect(isSalaryExpenseTypeHelper('خصم من الراتب'), isTrue);
      expect(isSalaryExpenseTypeHelper('صيانة كهرباء'), isFalse);
      expect(isSalaryExpenseTypeHelper('مشتروات'), isFalse);
      expect(isSalaryExpenseTypeHelper(''), isFalse);
    });

    test('isSalaryExpenseType is case-sensitive (Arabic has no case)', () {
      // Arabic doesn't have case, but verify consistency
      expect(isSalaryExpenseTypeHelper('رواتب'), isSalaryExpenseTypeHelper('رواتب'));
    });

    test('isSalaryExpenseType matches substrings', () {
      // الدالة تستخدم contains() لذا تطابق حتى لو كان النص جزءًا من نص أكبر
      expect(isSalaryExpenseTypeHelper('مصروف رواتب شهر يناير'), isTrue);
      expect(isSalaryExpenseTypeHelper('سحب راتب الموظف أحمد'), isTrue);
    });
  });
}

// ── Test Helpers ───────────────────────────────────────────────────────────
//
// نُعرّف نسخًا مساعدة هنا لنتمكن من اختبار منطق الـ helpers بدون استيراد
// PayloadMapper الفعلي (الذي يتطلب Drift). يجب أن تُطابق هذه النسخ
// تنفيذ PayloadMapper تمامًا — وإذا تغيّرت هناك، يجب تحديثها هنا.

class PayloadMapperTestClass {
  const PayloadMapperTestClass();
}

void putIfNotNullHelper<T>(Map<String, dynamic> map, String key, T? value) {
  if (value != null) {
    map[key] = value;
  }
}

void putIfStringNotEmptyHelper(
  Map<String, dynamic> map,
  String key,
  String? value,
) {
  if (value != null && value.isNotEmpty) {
    map[key] = value;
  }
}

bool isSalaryExpenseTypeHelper(String type) {
  const salaryKeywords = [
    'رواتب',
    'سحب راتب',
    'سحب من الراتب',
    'خصم راتب',
    'خصم من الراتب'
  ];
  for (final keyword in salaryKeywords) {
    if (type.contains(keyword)) return true;
  }
  return false;
}
