import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/screens/settings/backup/tabs/cloudflare_d1_tab.dart';
import 'package:marina_hotel_mobile/services/cloudflare_config.dart';

/// ✅ نطاق تبويب رفع D1 = [CloudflareConfig.d1BackupTables] = كيانات
/// عقد Appwrite Cloud حصراً (migrationOrder — خطة D7)، مع تجسيد كيان
/// blacklist افتراضياً من shift_notes الموسومة (بلا جدول Drift محلي).
/// لا يُرفع قاعدة البيانات المحلية كاملة.
///
/// الأدلة:
/// - عقد Appwrite = 22 مجموعة typed (schema_extract.json
///   collectionSchema) — blacklist ضمنها صراحةً.
/// - hotel_day_ledger مستبعد عمداً بتأكيد المستخدم (2026-09-05:
///   «جدول محلي لا أريد أن يتم مزامنته») — محلي-فقط بالتصميم (D8،
///   manager) ولا مقابل له في Appwrite Cloud.
/// - blacklist تُخزَّن في shift_notes بوسم created_by='blacklist'
///   (blacklist_repository.dart) — لا جدول sqlite_master لها.
void main() {
  /// كل ما قد يظهر في sqlite_master المحلي: كيانات العقد + جداول البنية
  /// المحلية + الداخلية — لنثبت أن الحصر يرفضها كلها.
  final allLocalTables = [
    ...CloudflareConfig.migrationOrder.where((t) => t != 'blacklist'),
    // جداول بلا مقابل في عقد Appwrite Cloud:
    'hotel_day_ledger', // محلي-فقط — استبعاد صريح بتأكيد المستخدم
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
    test('= migrationOrder حرفياً — 22 كيان عقد Appwrite', () {
      expect(CloudflareConfig.d1BackupTables, CloudflareConfig.migrationOrder);
      expect(CloudflareConfig.d1BackupTables.length, 22);
      // لا تكرار
      expect(
        CloudflareConfig.d1BackupTables.toSet().length,
        CloudflareConfig.d1BackupTables.length,
      );
    });

    test('العقد يتضمن blacklist ويستبعد hotel_day_ledger نهائياً', () {
      expect(
        CloudflareConfig.d1BackupTables,
        contains('blacklist'),
        reason: 'blacklist كيان من عقد Appwrite (schema_extract.json)',
      );
      expect(
        CloudflareConfig.d1BackupTables,
        isNot(contains('hotel_day_ledger')),
        reason: 'جدول محلي-فقط — المستخدم لا يريد مزامنته (2026-09-05)',
      );
    });
  });

  group('CloudflareD1Tab.scopeSyncTables', () {
    test('يحصر النطاق على كيانات العقد الفيزيائية — بنفس الترتيب', () {
      final scoped = CloudflareD1Tab.scopeSyncTables(allLocalTables);
      // 22 كيان عقد − blacklist (بلا جدول فيزيائي) = 21 جدولاً
      expect(scoped.length, 21);
      expect(
        scoped,
        CloudflareConfig.migrationOrder.where((t) => t != 'blacklist').toList(),
      );
      expect(scoped, isNot(contains('hotel_day_ledger')));
      expect(scoped, isNot(contains('blacklist')));
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
          'hotel_day_ledger', // استبعاد صريح — تأكيد المستخدم
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
      'كيان العقد الفيزيائي يمرّ، والغياب يسقطه (التجسيد مسؤولية التبويب)',
      () {
        // لو وُجد جدول فيزيائي اسمه blacklist (لا ينبغي) — القائمة
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
