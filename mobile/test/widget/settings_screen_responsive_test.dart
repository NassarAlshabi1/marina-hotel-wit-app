import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/providers/repository_providers.dart';
import 'package:marina_hotel_mobile/screens/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAtSize(WidgetTester tester, Size size) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomsListProvider.overrideWith((ref) => Stream.value(const [])),
          bookingsListProvider.overrideWith((ref) => Stream.value(const [])),
          employeesListProvider.overrideWith((ref) => Stream.value(const [])),
          usersCountProvider.overrideWith((ref) async => 0),
          simpleNotesUnreadCountProvider.overrideWith((ref) => Stream.value(0)),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// ✅ (2026-09-10) UI/UX Refactoring: الأقسام الآن ExpansionTile
  /// قابلة للطي — العناوين ظاهرة دائماً، لكن البطاقات داخل القسم
  /// تُبنى عند التوسعة. هذه المساعدة تفتح قسماً مطوياً قبل فحص بطاقاته
  /// (نفس ما يفعله المستخدم فعلياً).
  Future<void> expandSection(WidgetTester tester, String title) async {
    final finder = find.text(title);
    // القسم قد يكون أسفل الشاشة — مرّر إليه أولاً ثم افتحه.
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.implicitView;
    view?.resetPhysicalSize();
    view?.resetDevicePixelRatio();
  });

  testWidgets('لا يحدث overflow في الهاتف وتبقى الأقسام قابلة للوصول', (
    tester,
  ) async {
    await pumpAtSize(tester, const Size(360, 800));

    expect(find.text('الوصول السريع'), findsNothing);
    expect(find.text('إدارة البيانات'), findsOneWidget);
    expect(find.text('المزامنة والنسخ الاحتياطي'), findsOneWidget);
    expect(find.text('الإشعارات والتقارير'), findsOneWidget);
    expect(find.text('التطبيق والخدمات'), findsOneWidget);
    expect(find.text('إدارة الموظفين'), findsOneWidget);
    expect(find.text('إدارة الضيوف'), findsOneWidget);
    expect(find.text('القائمة السوداء'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('يبقى التخطيط مستقراً على اللوحي وWindows', (tester) async {
    for (final size in <Size>[
      const Size(800, 600),
      const Size(1366, 768),
      const Size(1920, 1080),
    ]) {
      await pumpAtSize(tester, size);
      expect(find.text('الوصول السريع'), findsNothing, reason: 'size=$size');
      expect(find.text('إدارة البيانات'), findsOneWidget, reason: 'size=$size');
      expect(
        find.text('المزامنة والنسخ الاحتياطي'),
        findsOneWidget,
        reason: 'size=$size',
      );
      expect(
        find.text('الإشعارات والتقارير'),
        findsOneWidget,
        reason: 'size=$size',
      );
      expect(
        find.text('التطبيق والخدمات'),
        findsOneWidget,
        reason: 'size=$size',
      );
      // ✅ (2026-09-10) بطاقات الأقسام المطوية تُفحص في اختبار
      // «كل خيارات الإعدادات الـ22 تبقى قابلة للوصول» (حجم واحد مستقر) —
      // هنا يكفي التأكد أن رؤوس الأقسام ظاهرة في كل الأحجام.
      // ✅ (2026-09-09) تحديث التوقع بعد ac64ba14: خيار 'المزامنة السحابية'
      // أُزيل من شاشة الإعدادات لكونه مكرراً ('المزامنة بين الأجهزة'
      // يفتح نفس الشاشة) — يجب ألا يظهر مرة أخرى (حماية من التراجع).
      expect(
        find.text('المزامنة السحابية'),
        findsNothing,
        reason: 'size=$size',
      );
      expect(tester.takeException(), isNull, reason: 'size=$size');
    }
  });

  /// ✅ (2026-09-10) اختبار فحص الانحدار لكل الخيارات: كل بطاقة في
  /// الأقسام الأربعة يجب أن تكون قابلة للوصول بعد فتح قسمها — لا
  /// خيار فقد بعد إعادة التنظيم (Progressive Disclosure).
  testWidgets('كل خيارات الإعدادات الـ22 تبقى قابلة للوصول', (tester) async {
    await pumpAtSize(tester, const Size(800, 600));

    // قسم إدارة البيانات — مفتوح افتراضياً.
    for (final title in <String>[
      'إدارة الموظفين',
      'إدارة المستخدمين',
      'إدارة الضيوف',
      'القوائم المنسدلة',
      'صيانة النظام',
      'القائمة السوداء',
      'المخزون',
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'data/$title');
    }

    // الأقسام المتبقية — تُفتح كلٌّ على حدة ثم تُفحص بطاقاتها.
    final sections = <String, List<String>>{
      'المزامنة والنسخ الاحتياطي': [
        'المزامنة بين الأجهزة',
        'النسخ الاحتياطي والاستعادة',
        'حالة المزامنة',
        'النسخ الاحتياطي - Google Drive',
      ],
      'الإشعارات والتقارير': [
        'إقفال اليوم',
        'تذكير المتبقي',
        'تنبيه تأخر الدفع',
        'ربط وقوالب WhatsApp',
        'إشعارات وتقارير WhatsApp',
        'Telegram',
      ],
      'التطبيق والخدمات': [
        'المظهر',
        'المساعد الذكي',
        'تتبع الأخطاء والأعطال',
        'مركز أخطاء المزامنة',
        'Remote Config',
        'معلومات التطبيق',
      ],
    };
    for (final entry in sections.entries) {
      await expandSection(tester, entry.key);
      for (final item in entry.value) {
        expect(find.text(item), findsOneWidget, reason: '${entry.key}/$item');
      }
    }
    expect(tester.takeException(), isNull);
  });
}
