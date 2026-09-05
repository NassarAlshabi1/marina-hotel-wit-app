import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/screens/settings/backup/tabs/cloudflare_d1_tab.dart';
import 'package:marina_hotel_mobile/services/cloudflare_config.dart';

/// ✅ نطاق تبويب رفع D1 = [CloudflareConfig.d1BackupTables]:
/// كيانات عقد Appwrite Cloud (migrationOrder — خطة D7) + جدول
/// hotel_day_ledger المطلوب صراحةً من المستخدم (2026-09-05)، مع تجسيد
/// كيان blacklist افتراضياً من shift_notes الموسومة (بلا جدول Drift
/// محلي). لا يُرفع قاعدة البيانات المحلية كاملة.
///
/// الأدلة:
/// - عقد Appwrite = 22 مجموعة typed (schema_extract.json
///   collectionSchema) — blacklist ضمنها صراحةً.
/// - hotel_day_ledger: طلب صريح؛ جدوله المحلي (local_db.dart
///   HotelDayLedger) مطابق 1:1 لجدول D1 (worker/schema.sql) — يُرفع
///   خاماً في مسار النسخ الاحتياطي فقط ويبقى خارج عقد المزامنة (D8).
/// - blacklist تُخزَّن في shift_notes بوسم created_by='blacklist'
///   (blacklist_repository.dart) — لا جدول sqlite_master لها.
void main() {
  /// كل ما قد يظهر في sqlite_master المحلي: كيانات العقد + جداول البنية
  /// المحلية + الداخلية — لنثبت أن الحصر يرفضها كلها.
  final allLocalTables = [
    ...CloudflareConfig.migrationOrder.where((t) => t != 'blacklist'),
    'hotel_day_ledger',
    // جداول بلا مقابل في نطاق النسخ الاحتياطي:
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

  group('CloudflareConfig.d1BackupTables (عقد نطاق النسخ الاحتياطي)', () {
    test(
      '= migrationOrder (22 كيان عقد Appwrite) + hotel_day_ledger آخراً',
      () {
        expect(CloudflareConfig.d1BackupTables.length, 23);
        expect(
          CloudflareConfig.d1BackupTables.take(22),
          CloudflareConfig.migrationOrder,
        );
        expect(CloudflareConfig.d1BackupTables.last, 'hotel_day_ledger');
        // لا تكرار
        expect(
          CloudflareConfig.d1BackupTables.toSet().length,
          CloudflareConfig.d1BackupTables.length,
        );
      },
    );

    test('migrationOrder نفسه لم يتغير: 22 كياناً بلا hotel_day_ledger', () {
      expect(CloudflareConfig.migrationOrder.length, 22);
      expect(
        CloudflareConfig.migrationOrder,
        contains('blacklist'),
        reason: 'blacklist كيان من عقد Appwrite (schema_extract.json)',
      );
      expect(
        CloudflareConfig.migrationOrder,
        isNot(contains('hotel_day_ledger')),
        reason: 'عقد المزامنة D8 يبقى محلي-فقط لـ hotel_day_ledger',
      );
    });
  });

  group('CloudflareD1Tab.scopeSyncTables', () {
    test('يحصر النطاق على d1BackupTables الفيزيائية — بنفس الترتيب', () {
      final scoped = CloudflareD1Tab.scopeSyncTables(allLocalTables);
      // 22 كيان عقد − blacklist (بلا جدول فيزيائي) + hotel_day_ledger
      expect(scoped.length, 22);
      expect(scoped, contains('hotel_day_ledger'));
      expect(scoped, isNot(contains('blacklist')));
      for (final t in CloudflareConfig.migrationOrder) {
        if (t == 'blacklist') continue;
        expect(scoped, contains(t));
      }
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

    test(
      'blacklist الفيزيائية تُتخطى (التجسيد الافتراضي مسؤولية _loadLocalTables)',
      () {
        // حتى لو وُجد جدول فيزيائي اسمه blacklist (لا ينبغي) — القائمة
        // الفيزيائية تمرره لأنه كيان عقد؛ والغيابه عن sqlite_master يعني
        // سقوطه من الفلترة ثم إضافته افتراضياً في التبويب.
        final scoped = CloudflareD1Tab.scopeSyncTables(<String>['blacklist']);
        expect(scoped, <String>['blacklist']);
        final withoutBlacklist = CloudflareD1Tab.scopeSyncTables(<String>[
          'rooms',
        ]);
        expect(withoutBlacklist, <String>['rooms']);
      },
    );

    test('قائمة موجودة فارغة (قاعدة أول تشغيل) → نتيجة فارغة', () {
      expect(CloudflareD1Tab.scopeSyncTables(const <String>[]), isEmpty);
    });
  });
}
