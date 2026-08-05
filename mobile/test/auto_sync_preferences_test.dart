// ============================================================================
//  AutoSyncPreferences — Unit Tests
//  ============================================================================
//  اختبارات migrateAutoSyncPreference:
//    - ترحيل القيم من legacy key إلى new key
//    - دعم int و bool
//    - رفض الأنواع غير المدعومة
//    - تطبيق القيمة عبر callback
// ============================================================================

library marina_hotel_mobile.test.auto_sync_preferences_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/auto_sync_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // تهيئة SharedPreferences للـ testing
    SharedPreferences.setMockInitialValues({});
  });

  group('migrateAutoSyncPreference<int>', () {
    test('يُهاجر القيمة من legacy key عند عدم وجود new key', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('legacy_key', 42);

      int? appliedValue;
      final result = await migrateAutoSyncPreference<int>(
        prefs: prefs,
        newKey: 'new_key',
        legacyKey: 'legacy_key',
        defaultValue: 0,
        apply: (value) async {
          appliedValue = value;
        },
      );

      expect(result, 42);
      expect(appliedValue, 42);
      // يجب أن تُكتب القيمة في new_key
      expect(prefs.getInt('new_key'), 42);
    });

    test('يستخدم default value عند عدم وجود أي مفتاح', () async {
      final prefs = await SharedPreferences.getInstance();

      int? appliedValue;
      final result = await migrateAutoSyncPreference<int>(
        prefs: prefs,
        newKey: 'new_key',
        legacyKey: 'legacy_key',
        defaultValue: 99,
        apply: (value) async {
          appliedValue = value;
        },
      );

      expect(result, 99);
      expect(appliedValue, 99);
      expect(prefs.getInt('new_key'), 99);
    });

    test('يستخدم new key عند وجوده (يفضّله على legacy)', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('new_key', 100);
      await prefs.setInt('legacy_key', 200);

      final result = await migrateAutoSyncPreference<int>(
        prefs: prefs,
        newKey: 'new_key',
        legacyKey: 'legacy_key',
        defaultValue: 0,
        apply: (_) async {},
      );

      expect(result, 100);
    });
  });

  group('migrateAutoSyncPreference<bool>', () {
    test('يُهاجر القيمة bool من legacy key', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('legacy_bool', true);

      bool? appliedValue;
      final result = await migrateAutoSyncPreference<bool>(
        prefs: prefs,
        newKey: 'new_bool',
        legacyKey: 'legacy_bool',
        defaultValue: false,
        apply: (value) async {
          appliedValue = value;
        },
      );

      expect(result, isTrue);
      expect(appliedValue, isTrue);
      expect(prefs.getBool('new_bool'), isTrue);
    });

    test('يستخدم default value bool عند عدم وجود أي مفتاح', () async {
      final prefs = await SharedPreferences.getInstance();

      final result = await migrateAutoSyncPreference<bool>(
        prefs: prefs,
        newKey: 'new_bool',
        legacyKey: 'legacy_bool',
        defaultValue: true,
        apply: (_) async {},
      );

      expect(result, isTrue);
      expect(prefs.getBool('new_bool'), isTrue);
    });
  });

  group('migrateAutoSyncPreference — أنواع غير مدعومة', () {
    test('يرفض String', () async {
      final prefs = await SharedPreferences.getInstance();

      expect(
        () => migrateAutoSyncPreference<String>(
          prefs: prefs,
          newKey: 'str',
          legacyKey: 'str_legacy',
          defaultValue: 'hello',
          apply: (_) async {},
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('يرفض double', () async {
      final prefs = await SharedPreferences.getInstance();

      expect(
        () => migrateAutoSyncPreference<double>(
          prefs: prefs,
          newKey: 'dbl',
          legacyKey: 'dbl_legacy',
          defaultValue: 1.5,
          apply: (_) async {},
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
