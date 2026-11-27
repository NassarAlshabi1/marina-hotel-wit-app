import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_constants.dart';
import 'package:marina_hotel_mobile/services/sync_pull_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// اختبارات نطاق السحب (SyncPullScope):
/// اختيار الجداول المسحوبة من Appwrite من شاشة الإعدادات.
///
/// الفلترة الفعلية تتم في AppwriteSyncManager._buildPullTasks عبر
/// [SyncPullScope.isDisabled] — هذه الاختبارات تضمن صحة الحالة والتخزين
/// واكتمال الكتالوج مقابل قائمة مهام السحب الفعلية.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// أسماء مهام السحب الفعلية كما في _buildPullTasks
  /// (باستثناء app_settings المشروط بـ SyncConstants.appSettingsSyncEnabled).
  const buildPullTaskNames = <String>{
    'rooms',
    'employees',
    'inventory_items',
    'inventory_transactions',
    'bookings',
    'cash_transactions',
    'expenses',
    'booking_nights',
    'booking_notes',
    'payments',
    'debts',
    'salary_cycles',
    'salary_payments',
    'salary_withdrawals',
    'guest_infos',
    'booking_price_adjustments',
    'shift_notes',
    'blacklist',
    'price_adjustments',
    'audit_logs',
    'payment_voids',
    'salary_carry_over_logs',
    if (SyncConstants.appSettingsSyncEnabled) 'app_settings',
  };

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SyncPullScope.resetForTesting();
  });

  group('SyncPullScope — الحالة الافتراضية', () {
    test('قبل التحميل كل الجداول مفعّلة (سلوك آمن مطابق لما قبل الميزة)', () {
      expect(SyncPullScope.isDisabled('guest_infos'), isFalse);
      expect(SyncPullScope.isDisabled('payments'), isFalse);
      expect(SyncPullScope.disabledCount, 0);
    });

    test('بعد التحميل بقائمة فارغة كل الجداول مفعّلة', () async {
      await SyncPullScope.load();
      for (final name in buildPullTaskNames) {
        expect(SyncPullScope.isDisabled(name), isFalse, reason: name);
      }
    });
  });

  group('SyncPullScope — التعطيل والتخزين', () {
    test('setDisabled يعطّل الجداول المحددة فقط ويحفظ في التخزين', () async {
      await SyncPullScope.setDisabled({'guest_infos', 'salary_withdrawals'});

      expect(SyncPullScope.isDisabled('guest_infos'), isTrue);
      expect(SyncPullScope.isDisabled('salary_withdrawals'), isTrue);
      expect(SyncPullScope.isDisabled('payments'), isFalse);
      expect(SyncPullScope.disabledCount, 2);

      // التحقق من الاستمرارية: قراءة جديدة من التخزين تُرجع نفس الحالة
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(SyncPullScope.prefsKey), [
        'guest_infos',
        'salary_withdrawals',
      ]);
    });

    test('load يستعيد الحالة المحفوظة عبر دورة حياة التطبيق', () async {
      await SyncPullScope.setDisabled({'audit_logs'});
      SyncPullScope.resetForTesting();

      // قبل التحميل: الافتراضي الآمن
      expect(SyncPullScope.isDisabled('audit_logs'), isFalse);

      await SyncPullScope.load();
      expect(SyncPullScope.isDisabled('audit_logs'), isTrue);
      expect(SyncPullScope.isDisabled('rooms'), isFalse);
    });

    test(
      'setDisabled يتجاهل الأسماء غير الموجودة في الكتالوج (تنظيف)',
      () async {
        await SyncPullScope.setDisabled({'ghost_collection', 'rooms'});

        expect(SyncPullScope.isDisabled('rooms'), isTrue);
        expect(SyncPullScope.isDisabled('ghost_collection'), isFalse);
        expect(SyncPullScope.disabledCount, 1);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList(SyncPullScope.prefsKey), ['rooms']);
      },
    );

    test(
      'إعادة التفعيل: setDisabled بمجموعة أصغر يلغي التعطيل السابق',
      () async {
        await SyncPullScope.setDisabled({'guest_infos', 'debts'});
        expect(SyncPullScope.isDisabled('guest_infos'), isTrue);

        // المستخدم أعاد تفعيل guest_infos من الإعدادات
        await SyncPullScope.setDisabled({'debts'});
        expect(SyncPullScope.isDisabled('guest_infos'), isFalse);
        expect(SyncPullScope.isDisabled('debts'), isTrue);
      },
    );
  });

  group('SyncPullScope — اكتمال الكتالوج', () {
    test('الكتالوج يطابق أسماء مهام _buildPullTasks تماماً', () {
      expect(SyncPullScope.catalogNames, buildPullTaskNames);
    });

    test('كل عنصر في الكتالوج يحمل اسماً وعرضاً وفئة غير فارغة', () {
      for (final meta in SyncPullScope.catalog) {
        expect(meta.name, isNotEmpty, reason: 'name فارغ');
        expect(meta.label, isNotEmpty, reason: 'label فارغ لـ ${meta.name}');
        expect(
          meta.category,
          isNotEmpty,
          reason: 'category فارغ لـ ${meta.name}',
        );
      }
    });

    test('لا توجد أسماء مكررة في الكتالوج', () {
      final names = SyncPullScope.catalog.map((m) => m.name).toList();
      expect(names.length, names.toSet().length);
    });

    test('الجداول الأصلية المرجعية (core) تشمل rooms وbookings وemployees', () {
      final coreNames = SyncPullScope.catalog
          .where((m) => m.core)
          .map((m) => m.name)
          .toSet();
      expect(
        coreNames,
        containsAll(<String>{'rooms', 'bookings', 'employees'}),
      );
    });

    test('التجميع حسب الفئة يغطي كل عناصر الكتالوج بلا فقد', () {
      final grouped = SyncPullScope.catalogByCategory;
      final groupedTotal = grouped.values.fold<int>(
        0,
        (sum, list) => sum + list.length,
      );
      expect(groupedTotal, SyncPullScope.catalog.length);
      expect(grouped.keys, isNotEmpty);
    });
  });
}
