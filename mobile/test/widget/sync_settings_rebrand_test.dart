// ✅ (2026-09-06) طلب المستخدم: «شاشة الإعدادات لا زالت هناك أماكن
// تشير إلى Appwrite يجب استبدالها بـ Cloudflare» — التطبيق يعمل على
// Cloudflare D1 فقط منذ 0bba3447، وأي ذكر لـ Appwrite في الواجهة
// علامة قديمة مضللة. هذا الاختبار يثبّت إعادة التسمية في شاشة
// إعدادات المزامنة ويمنع ارتدادها.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/providers/appwrite_providers.dart';
import 'package:marina_hotel_mobile/screens/settings/sync/unified_sync_settings_screen.dart';
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';

void main() {
  testWidgets('شاشة إعدادات المزامنة تعرض Cloudflare ولا تذكر Appwrite', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // المدير الحقيقي singleton — بلا initialize (لا HTTP في البناء).
          appwriteSyncManagerProvider.overrideWithValue(
            AppwriteSyncManager(),
          ),
          syncStatsProvider.overrideWith((ref) async => <String, dynamic>{}),
          outboxCountProvider.overrideWith(
            (ref) => const Stream<int>.empty(),
          ),
        ],
        child: const MaterialApp(home: UnifiedSyncSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // القسم أسفل قائمة طويلة (lazy ListView) — مرّر حتى يُبنى ويظهر.
    await tester.scrollUntilVisible(
      find.text('Cloudflare Sync'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // التسميات الجديدة من لقطات المستخدم (كانت: Appwrite Sync /
    // تفعيل مزامنة Appwrite / مزامنة البيانات مع سحابة Appwrite).
    expect(find.text('Cloudflare Sync'), findsOneWidget);
    expect(find.text('تفعيل مزامنة Cloudflare'), findsOneWidget);
    expect(find.text('مزامنة البيانات مع سحابة Cloudflare'), findsOneWidget);

    // ⛔ لا ذكر لـ Appwrite في أي نص ظاهر على الشاشة كلها.
    expect(
      find.textContaining('Appwrite'),
      findsNothing,
      reason:
          'التطبيق Cloudflare-only منذ 0bba3447 — أي ذكر لـ '
          'Appwrite في الواجهة علامة قديمة يجب ألا تعود',
    );
  });
}
