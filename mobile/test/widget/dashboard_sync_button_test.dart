// ✅ (2026-09-06) طلب المستخدم: «زر سحب التغييرات في شاشة dashboard» —
// الزر موجود فعلاً في ترويسة الـ dashboard (DashboardScreen._buildHeader
// يركّب DashboardSyncButton)؛ هذا الاختبار يثبّت وجود الزرين وتسمياتهما
// (سحب التغييرات / رفع التغييرات) وشريط الحالة، فيمنع أي حذف أو تعديل
// تسمية غير مقصود مستقبلاً.
//
// ✅ (2026-09-06) طلب المستخدم: «زر رفع التغييرات outbox في شاشة dashboard» —
// أضيف اختباران انحداريان لسلوك الرفع:
//  1) صف 'processing' عالق يُحسب معلقاً ويُبقي زر الرفع مفعّلاً (كان سيضيع
//     لولا countUndeliveredToPrimary — وreclaimForPush في _pushOutbox هو
//     الذي يتيح تفريغه فعلياً عند الضغط).
//  2) الضغط على «رفع التغييرات» مع backend غير متاح يُظهر snackbar أحمر
//     «❌ فشل رفع التغييرات» — وليس النجاح الزائف الأخضر الذي كان يظهر
//     قبل إصلاح عقد pushLocalChanges (كان يقارن pushedCount >= 0 وهو
//     صادق دائماً حتى عند فشل الدورة).
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/providers/appwrite_providers.dart'
    as sync_providers;
import 'package:marina_hotel_mobile/providers/repository_providers.dart';
import 'package:marina_hotel_mobile/providers/smart_sync_provider.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/widgets/dashboard_sync_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Notifier يزوّر فحص الاتصال ليُرجع «متصل» دائماً — حتى يصل مسار الضغط
/// فعلياً إلى استدعاء المدير (وإلا توقف مبكراً عند «لا يوجد اتصال»).
class _AlwaysConnectedNotifier extends sync_providers.ConnectionStatusNotifier {
  _AlwaysConnectedNotifier(super.ref);

  @override
  Future<void> checkConnection() async {
    state = sync_providers.ConnectionState(isConnected: true);
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
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

  /// نفس pumpButton لكن مع اتصال مزوّر «متصل دائماً» — لتجاوز حارس
  /// checkConnection في مسار الرفع والوصول إلى استدعاء المدير نفسه.
  Future<void> pumpButtonConnected(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          smartSyncGoogleDriveSignInStatusProvider.overrideWithValue(false),
          sync_providers.connectionStatusProvider.overrideWith(
            (ref) => _AlwaysConnectedNotifier(ref),
          ),
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

  testWidgets(
    "صف outbox عالق في 'processing' يُحسب معلقاً ويُبقي زر الرفع مفعّلاً",
    (tester) async {
      // عدّاد الزر countUndeliveredToPrimary يشمل processing (عالق) —
      // عكس countPendingPushable. هذه السجلات كانت ستختفي من العدّاد في
      // نسخة أقدم فيظنّ المستخدم أن الرفع نجح. processing_started_at
      // قبل 60 ثانية (عتبة reclaimForPush 30 ثانية) — أي أنه قابل
      // للاسترجاع وإعادة الرفع عند الضغط على الزر.
      final stuckTs = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 60;
      await db.customStatement(
        "INSERT INTO outbox (entity, op, local_uuid, payload, client_ts, "
        "processing_status, processing_started_at) "
        "VALUES ('rooms', 'UPDATE', 'stuck-processing-uuid', '{}', 0, "
        "'processing', $stuckTs)",
      );
      await pumpButton(tester);

      expect(
        find.text('رفع التغييرات'),
        findsOneWidget,
        reason: 'الصف العالق في processing يُحسب في عدّاد التغييرات المعلقة',
      );
      final inkWell = tester.widget<InkWell>(
        find
            .ancestor(
              of: find.text('رفع التغييرات'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(
        inkWell.onTap,
        isNotNull,
        reason:
            'زر الرفع يبقى مفعّلاً للسجلات العالقة — reclaimForPush في '
            'بداية _pushOutbox هو الذي يسترجعها ويفرّغ العداد عند الضغط',
      );
    },
  );

  testWidgets(
    'الضغط على «رفع التغييرات» مع backend غير متاح يُظهر فشلاً صادقاً لا نجاحاً زائفاً',
    (tester) async {
      await db.customStatement(
        "INSERT INTO outbox (entity, op, local_uuid, payload, client_ts) "
        "VALUES ('rooms', 'INSERT', 'test-uuid-push', '{}', 0)",
      );
      await pumpButtonConnected(tester);

      // المدير غير مهيأ في بيئة الاختبار (_token == null) → sync(pull:false)
      // يُعيد failed 'Not initialized' → العقد الصادق (2026-09-06) يرمي
      // StateError → يُلتقط في try/catch هدف Cloudflare → snackbar أحمر.
      // قبل الإصلاح: pushedCount=0 وكان `0 >= 0` صادقاً → snackbar أخضر
      // «تم رفع التغييرات بنجاح!» مع بقاء الصف في outbox — تضليل إنتاجي.
      await tester.tap(find.text('رفع التغييرات'));
      // تفريغ سلسلة async كاملة (prefs/dao/manager كلها في الذاكرة) —
      // لا pumpAndSettle لأن repeat() للأنيميشن لا يستقر إلا بعد الـ finally.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.text('❌ فشل رفع التغييرات'),
        findsOneWidget,
        reason: 'الفشل الصادق المطلوب: snackbar أحمر مع زر إعادة',
      );
      expect(
        find.text('✅ تم رفع التغييرات بنجاح!'),
        findsNothing,
        reason:
            'يُحظر النجاح الزائف: قبل إصلاح العقد كان يظهر نجاح أخضر '
            'مع «أُرسل: 0» بينما الـ outbox ما زال معلقاً',
      );

      // تصريف مؤقّت الإخفاء التلقائي (4 ثوانٍ) + أنيميشن الخروج —
      // حتى لا يبقى Timer معلّقاً في نهاية الاختبار.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
