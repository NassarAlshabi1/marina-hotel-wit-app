import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/providers/appwrite_providers.dart' as ap;
import 'package:marina_hotel_mobile/screens/settings/appwrite_connection_settings_screen.dart';
import 'package:marina_hotel_mobile/screens/settings/appwrite_settings_screen.dart';
import 'package:marina_hotel_mobile/services/appwrite_cache_manager.dart';
import 'package:marina_hotel_mobile/services/appwrite_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeConnectionStatusNotifier extends ap.ConnectionStatusNotifier {
  _FakeConnectionStatusNotifier(super.ref);

  @override
  Future<void> checkConnection() async {}
}

Widget _buildSettingsScreen() {
  return ProviderScope(
    overrides: [
      ap.connectionStatusProvider.overrideWith(
        (ref) => _FakeConnectionStatusNotifier(ref),
      ),
      ap.syncStatsProvider.overrideWith(
        (ref) async => <String, dynamic>{
          'totalSyncs': 0,
          'successfulSyncs': 0,
          'failedSyncs': 0,
          'totalRecordsPushed': 0,
          'totalRecordsPulled': 0,
          'totalConflicts': 0,
        },
      ),
      ap.cacheStatsProvider.overrideWithValue(
        CacheStatistics(
          totalEntries: 0,
          validEntries: 0,
          expiredEntries: 0,
          totalSizeBytes: 0,
          maxSizeBytes: 20 * 1024 * 1024,
          hitRate: 0,
          hits: 0,
          misses: 0,
        ),
      ),
      ap.logStatsProvider.overrideWithValue(const <String, int>{}),
      ap.projectInfoProvider.overrideWithValue(const <String, String>{}),
      ap.devicesListProvider.overrideWith((ref) async => <AppwriteDevice>[]),
    ],
    child: const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: AppwriteSettingsScreen(),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('يعرض أزرار إدارة Appwrite الأساسية', (tester) async {
    await tester.pumpWidget(_buildSettingsScreen());
    await tester.pump();
    final scrollable = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    for (final label in const [
      'إنشاء النسخة',
      'بدء الرفع',
      'بدء السحب',
      'إعادة تعيين المزامنة',
      'اختبار المزامنة',
      'اختبار الذاكرة المؤقتة',
    ]) {
      await tester.scrollUntilVisible(
        find.text(label, skipOffstage: false),
        500,
        scrollable: scrollable,
      );
    }

    expect(find.text('إنشاء النسخة', skipOffstage: false), findsOneWidget);
    expect(find.text('بدء الرفع', skipOffstage: false), findsOneWidget);
    expect(find.text('بدء السحب', skipOffstage: false), findsOneWidget);
    expect(
      find.text('إعادة تعيين المزامنة', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('اختبار المزامنة', skipOffstage: false), findsOneWidget);
    expect(
      find.text('اختبار الذاكرة المؤقتة', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('لا ينفذ إجراءات البيانات قبل تأكيد المستخدم', (tester) async {
    await tester.pumpWidget(_buildSettingsScreen());
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('إنشاء النسخة'),
      500,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );

    await tester.tap(find.text('إنشاء النسخة'));
    await tester.pump();
    expect(find.text('نسخة احتياطية شاملة من Appwrite'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pump();
    expect(find.text('نسخة احتياطية شاملة من Appwrite'), findsNothing);

    await tester.tap(find.text('بدء الرفع'));
    await tester.pump();
    expect(find.text('تأكيد الرفع'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pump();
    expect(find.text('تأكيد الرفع'), findsNothing);

    await tester.tap(find.text('بدء السحب'));
    await tester.pump();
    expect(find.text('تأكيد السحب'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pump();
    expect(find.text('تأكيد السحب'), findsNothing);

    await tester.tap(find.text('إعادة تعيين المزامنة'));
    await tester.pump();
    expect(find.text('هل تريد إعادة تعيين حالة المزامنة؟'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pump();
    expect(find.text('هل تريد إعادة تعيين حالة المزامنة؟'), findsNothing);
  });

  testWidgets('اختبار الاتصال يتحقق من المدخلات قبل أي طلب شبكي', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        overrides: [],
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: AppwriteConnectionSettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).first, 'not-a-url');
    await tester.scrollUntilVisible(
      find.text('اختبار الاتصال'),
      500,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('اختبار الاتصال'));
    await tester.pump();

    expect(
      find.text('يجب أن يبدأ العنوان بـ http:// أو https://'),
      findsOneWidget,
    );
    expect(
      find.text(
        'اختبار الاتصال: يرجى حفظ الإعدادات أولاً ثم إعادة تشغيل التطبيق',
      ),
      findsNothing,
    );
  });
}
