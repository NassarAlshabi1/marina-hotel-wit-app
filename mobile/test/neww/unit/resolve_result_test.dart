import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/resolve_result.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════
  // ResolveResult — القيم الافتراضية
  // ═══════════════════════════════════════════════════════════════
  group('ResolveResult — القيم الافتراضية', () {
    test('القيم الافتراضية كلها null أو false', () {
      const result = ResolveResult();
      expect(result.bookingLocalId, isNull);
      expect(result.bookingUuidCache, isNull);
      expect(result.employeeLocalId, isNull);
      expect(result.employeeRelatedId, isNull);
      expect(result.salaryCycleLocalId, isNull);
      expect(result.createdAtEpoch, isNull);
      expect(result.lastModifiedEpoch, isNull);
      expect(result.shouldSkip, isFalse);
      expect(result.skipReason, isNull);
    });

    test('empty ثابت يحمل القيم الافتراضية', () {
      const empty = ResolveResult.empty;
      expect(empty.bookingLocalId, isNull);
      expect(empty.shouldSkip, isFalse);
      expect(empty.skipReason, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // ResolveResult — البناء مع قيم
  // ═══════════════════════════════════════════════════════════════
  group('ResolveResult — البناء مع قيم', () {
    test('يمكن تمرير جميع الحقول', () {
      const result = ResolveResult(
        bookingLocalId: 5,
        bookingUuidCache: 'uuid-123',
        employeeLocalId: 10,
        employeeRelatedId: 10,
        salaryCycleLocalId: 3,
        createdAtEpoch: 1000,
        lastModifiedEpoch: 2000,
        shouldSkip: true,
        skipReason: 'test reason',
      );
      expect(result.bookingLocalId, 5);
      expect(result.bookingUuidCache, 'uuid-123');
      expect(result.employeeLocalId, 10);
      expect(result.salaryCycleLocalId, 3);
      expect(result.createdAtEpoch, 1000);
      expect(result.lastModifiedEpoch, 2000);
      expect(result.shouldSkip, isTrue);
      expect(result.skipReason, 'test reason');
    });

    test('shouldSkip = true مع skipReason يصف السبب', () {
      const result = ResolveResult(
        shouldSkip: true,
        skipReason: 'salary_cycle: لا يمكن العثور على الموظف المرتبط',
      );
      expect(result.shouldSkip, isTrue);
      expect(result.skipReason, contains('لا يمكن العثور'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // ResolveResult — copyWith
  // ═══════════════════════════════════════════════════════════════
  group('ResolveResult — copyWith', () {
    test('copyWith يحتفظ بالقيم الأصلية عند عدم التحديد', () {
      const original = ResolveResult(
        bookingLocalId: 5,
        employeeLocalId: 10,
        shouldSkip: false,
      );
      final copy = original.copyWith();
      expect(copy.bookingLocalId, 5);
      expect(copy.employeeLocalId, 10);
      expect(copy.shouldSkip, isFalse);
    });

    test('copyWith يستبدل القيم المحددة فقط', () {
      const original = ResolveResult(
        bookingLocalId: 5,
        employeeLocalId: 10,
        shouldSkip: false,
      );
      final copy = original.copyWith(shouldSkip: true, skipReason: 'orphan');
      expect(copy.bookingLocalId, 5);
      expect(copy.employeeLocalId, 10);
      expect(copy.shouldSkip, isTrue);
      expect(copy.skipReason, 'orphan');
    });

    test('copyWith لا يمكنه مسح قيمة إلى null (سلوك ??)', () {
      const original = ResolveResult(
        bookingLocalId: 5,
        skipReason: 'old reason',
      );
      // copyWith يستخدم ?? لذا لا يمكن مسح قيمة إلى null
      final copy = original.copyWith(skipReason: 'new reason');
      expect(copy.skipReason, 'new reason');
    });

    test('copyWith يضيف shouldSkip و skipReason للنتيجة الفارغة', () {
      final copy = ResolveResult.empty.copyWith(
        shouldSkip: true,
        skipReason: 'booking not found',
      );
      expect(copy.shouldSkip, isTrue);
      expect(copy.skipReason, 'booking not found');
      expect(copy.bookingLocalId, isNull);
    });
  });
}
