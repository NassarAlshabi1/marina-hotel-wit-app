// ✅ (2026-09-06) طلب المستخدم: «زر سحب التغييرات في شاشة dashboard» —
// الزر موجود فعلاً في ترويسة الـ dashboard (DashboardScreen._buildHeader
// يركّب DashboardSyncButton)؛ هذا الاختبار يثبّت وجود الزرين وتسمياتهما
// (سحب التغييرات / رفع التغييرات) وشريط الحالة، فيمنع أي حذف أو تعديل
// تسمية غير مقصود مستقبلاً.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/providers/repository_providers.dart';
import 'package:marina_hotel_mobile/providers/smart_sync_provider.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/widgets/dashboard_sync_button.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpButton(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          smartSyncGoogleDriveSignInStatusProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(
          localizationsDelegates: [],
          home: Scaffold(body: DashboardSyncButton()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'dashboard يعرض زر «سحب التغييرات» وحالة الرفع الخاملة «محدّث»',
    (tester) async {
      await pumpButton(tester);

      expect(
        find.text('سحب التغييرات'),
        findsOneWidget,
        reason: 'زر السحب المطلوب من المستخدم موجود في ترويسة الـ dashboard',
      );
      // زر الرفع في حالة لا تغييرات محلية يعرض «محدّث» (رمادي)،
      // ويعرض «رفع التغييرات» فقط عند وجود outbox معلق (dashboard_sync_button.dart
      // _buildPushButton: hasChanges ? 'رفع التغييرات' : 'محدّث') — قاعدة
      // اختبار فارغة ⇒ محادثتان «محدّث»: زر الرفع + شريط الحالة.
      expect(
        find.text('محدّث'),
        findsNWidgets(2),
        reason: 'زر الرفع الخامل + شريط الحالة كلاهما «محدّث» بلا تغييرات',
      );
    },
  );

  testWidgets('تسمية زر الرفع تتحول إلى «رفع التغييرات» مع تغييرات معلقة', (
    tester,
  ) async {
    // محاكاة outbox معلق: صف واحد غير مُسلَّم للرئيسي (الأعمدة الإلزامية
    // فقط: entity/op/local_uuid/payload/client_ts — processing_status
    // افتراضه 'pending' وdelivered_to_primary افتراضه false).
    await db.customStatement(
      "INSERT INTO outbox (entity, op, local_uuid, payload, client_ts) "
      "VALUES ('rooms', 'INSERT', 'test-uuid-1', '{}', 0)",
    );
    await pumpButton(tester);

    expect(find.text('رفع التغييرات'), findsOneWidget);
    // شريط الحالة أيضاً يتبدل: «N تغيير محلي معلق» بدل «محدّث» —
    // فلا يبقى أي «محدّث» على الشاشة (dashboard_sync_button.dart build).
    expect(find.text('محدّث'), findsNothing);
  });

  testWidgets(
    'زر السحب مفعّل بلا تغييرات معلقة (pending=0) — قابل للضغط للسحب الكامل',
    (tester) async {
      await pumpButton(tester);

      // سياسة Offline-first: السحب معطّل فقط عند وجود سجلات outbox غير
      // مُسلَّمة. قاعدة اختبار فارغة ⇒ pending=0 ⇒ الزر مفعّل (onTap غير
      // null داخل InkWell).
      final inkWell = tester.widget<InkWell>(
        find
            .ancestor(
              of: find.text('سحب التغييرات'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(inkWell.onTap, isNotNull);
    },
  );
}
