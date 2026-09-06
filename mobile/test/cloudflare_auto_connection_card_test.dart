import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/providers/appwrite_providers.dart';
import 'package:marina_hotel_mobile/providers/cloudflare_connection_providers.dart';
import 'package:marina_hotel_mobile/providers/repository_providers.dart'
    show databaseProvider;
import 'package:marina_hotel_mobile/services/cloudflare_d1_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/widgets/cloudflare_auto_connection_card.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// اختبارات تثبيت بطاقة «بيانات الاتصال التلقائي مع Cloudflare»:
/// تربط البطاقة بمصادرها الحقيقية (prefs بنفس مفاتيح شاشة الإعدادات،
/// sync_log عبر fetchRecentLogs، outbox عبر countUndeliveredToPrimary)
/// مع Connection Status مزوّر لضمان حتمية العرض.
void main() {
  // sqfliteFfiInit + databaseFactory تُهيّآن عالمياً في flutter_test_config.dart.
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildCard() {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        // بلا مؤقّت حقيقي في الاختبارات.
        connectionAutoRefreshProvider.overrideWith((ref) {}),
        connectionStatusProvider.overrideWith(_FakeConnectionNotifier.new),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [CloudflareAutoConnectionCard()],
          ),
        ),
      ),
    );
  }

  testWidgets(
    'يعرض حالة الاتصال والإعدادات وآخر مزامنة ناجحة والسجلات المعلقة',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        kCloudflareAutoSyncEnabledKey: true,
        kCloudflareAutoSyncIntervalKey: 10,
        'cf_d1_account_id': 'acc-test-123',
        'cf_d1_database_id': 'db-test-456',
      });
      FlutterSecureStorage.setMockInitialValues({
        'cf_d1_api_token': 'cfut_1234567890abcd',
      });

      final now = DateTime.now();
      await db
          .into(db.syncLog)
          .insert(
            SyncLogCompanion.insert(
              syncId: 'sync-1',
              direction: 'push',
              deviceId: 'device-1',
              metadata: '{}',
              createdAt: now.toIso8601String(),
              completedAt: Value(now.toIso8601String()),
              status: const Value('success'),
            ),
          );
      // سجل فاشل أحدث — يجب تجاهله واختيار آخر ناجح.
      await db
          .into(db.syncLog)
          .insert(
            SyncLogCompanion.insert(
              syncId: 'sync-2',
              direction: 'pull',
              deviceId: 'device-1',
              metadata: '{}',
              createdAt: now.add(const Duration(minutes: 1)).toIso8601String(),
              status: const Value('failed'),
            ),
          );
      await db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              entity: 'bookings',
              op: 'update',
              localUuid: 'uuid-1',
              payload: '{}',
              clientTs: now.millisecondsSinceEpoch,
            ),
          );

      await tester.pumpWidget(buildCard());
      await tester.pumpAndSettle();
      // العنوان.
      expect(find.text('الاتصال التلقائي مع Cloudflare'), findsOneWidget);
      // اتصال Worker (مزوّر: متصل).
      expect(find.text('متصل بسحابة Cloudflare'), findsOneWidget);
      // المزامنة التلقائية: مفعّلة كل 10 دقائق (من mock prefs).
      expect(find.text('المزامنة التلقائية: '), findsOneWidget);
      // المحرك غير مُشغَّل في بيئة الاختبار → تُلحق عبارة حالة المحرك.
      expect(find.textContaining('مفعّلة — كل 10 دقائق'), findsOneWidget);
      expect(find.textContaining('المحرك متوقف'), findsOneWidget);
      // آخر مزامنة ناجحة: رفع (سجل success الأحدث المتاح وليس failed).
      expect(find.text('آخر مزامنة ناجحة: '), findsOneWidget);
      expect(find.text('رفع — الآن'), findsOneWidget);
      expect(find.textContaining('سحب'), findsNothing);
      // سجلات outbox المعلقة: 1.
      expect(find.text('سجلات بانتظار الرفع: '), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    },
  );

  testWidgets('المزامنة التلقائية المتوقفة واللا سجلات تعرض رسائل صادقة', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kCloudflareAutoSyncEnabledKey: false,
      kCloudflareAutoSyncIntervalKey: 15,
    });

    await tester.pumpWidget(buildCard());
    await tester.pumpAndSettle();

    expect(find.text('متوقفة من الإعدادات'), findsOneWidget);
    expect(find.text('لا توجد بعد'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });
}

/// حالة اتصال ثابتة (متصل) بلا طلبات شبكة حقيقية.
class _FakeConnectionNotifier extends ConnectionStatusNotifier {
  _FakeConnectionNotifier(super.ref) {
    state = ConnectionState(isConnected: true);
  }
}
