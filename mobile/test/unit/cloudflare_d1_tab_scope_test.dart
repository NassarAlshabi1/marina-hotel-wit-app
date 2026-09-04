import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/screens/settings/backup/tabs/cloudflare_d1_tab.dart';
import 'package:marina_hotel_mobile/services/cloudflare_config.dart';

/// ✅ نطاق تبويب رفع D1 = جداول المزامنة المطابقة لمجموعات Appwrite Cloud
/// فقط (طلب المستخدم) — لا يُرفع قاعدة البيانات المحلية كاملة.
///
/// الأدلة:
/// - عقد Appwrite = 27 مجموعة (appwrite_sync_utils validFieldsPerCollection
///   / schema_extract.json)، منها 5 سحابية بلا جدول Drift محلي
///   (app_users/app_settings/devices/sync_logs/sync_state) + blacklist
///   سحابية فقط = 21 جدولاً محلياً مطابقاً.
/// - hotel_day_ledger يحمل SyncFields لكنه محلي-فقط بالتصميم
///   (manager:1970) — لا يقابل collection في Appwrite Cloud.
/// - CloudflareConfig.migrationOrder = خطة D7 (نفس ENTITY_TABLES في
///   worker/src/database.ts — 22 كياناً بلا hotel_day_ledger).
void main() {
  /// كل ما قد يظهر في sqlite_master المحلي: كيانات العقد + جداول البنية
  /// المحلية + الداخلية — لنثبت أن الحصر يرفضها كلها.
  final allLocalTables = [
    ...CloudflareConfig.migrationOrder,
    // جداول بلا مقابل في عقد Appwrite Cloud:
    'hotel_day_ledger', // محلي-فقط بالتصميم
    'outbox',
    'sync_remote_meta',
    'sync_state', // مؤشر المحرك المحلي (V-1) — ليس مرآة مجموعة
    'sync_log',
    'sync_conflicts',
    'custom_list_items',
    'ancestor_cache',
    'auto_fix_runs',
    'app_sessions',
    'restore_fix_log',
    'sync_queue',
    'integrity_violations',
    // داخلية:
    'android_metadata',
    'room_master_table',
    'sqlite_sequence',
  ];

  group('CloudflareD1Tab.scopeSyncTables', () {
    test('يحصر النطاق على كيانات عقد Appwrite فقط — بنفس الترتيب FK-الآمن', () {
      final scoped = CloudflareD1Tab.scopeSyncTables(allLocalTables);
      expect(scoped, CloudflareConfig.migrationOrder);
    });

    test(
      'لا يتضمن أبداً جداول البنية المحلية حتى لو وُجدت في sqlite_master',
      () {
        final scoped = CloudflareD1Tab.scopeSyncTables(allLocalTables);
        const infra = [
          'outbox',
          'sync_remote_meta',
          'sync_state',
          'sync_log',
          'sync_conflicts',
          'hotel_day_ledger',
          'custom_list_items',
          'ancestor_cache',
          'room_master_table',
          'android_metadata',
          'sqlite_sequence',
        ];
        for (final t in infra) {
          expect(scoped, isNot(contains(t)), reason: 'يجب استبعاد $t');
        }
      },
    );

    test('يتخطى blacklist تلقائياً حين لا يوجد جدول محلي لها (سحابية فقط)', () {
      final withoutBlacklist = allLocalTables
          .where((t) => t != 'blacklist')
          .toList();
      final scoped = CloudflareD1Tab.scopeSyncTables(withoutBlacklist);
      expect(scoped, isNot(contains('blacklist')));
      // 22 كياناً في العقد − blacklist = 21 جدولاً محلياً فعلياً
      expect(scoped.length, CloudflareConfig.migrationOrder.length - 1);
      expect(scoped.length, 21);
    });

    test('قائمة موجودة فارغة (قاعدة أول تشغيل) → نتيجة فارغة', () {
      expect(CloudflareD1Tab.scopeSyncTables(const <String>[]), isEmpty);
    });

    test(
      'عقد المزامنة نفسه مطابق لقرار D7: 22 كياناً بلا hotel_day_ledger',
      () {
        expect(CloudflareConfig.migrationOrder.length, 22);
        expect(
          CloudflareConfig.migrationOrder,
          isNot(contains('hotel_day_ledger')),
        );
        // تكرار: لا يقبل كيانات غير معروفة
        expect(
          CloudflareConfig.migrationOrder.toSet().length,
          CloudflareConfig.migrationOrder.length,
        );
      },
    );
  });
}
