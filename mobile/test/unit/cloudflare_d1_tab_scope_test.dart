import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/screens/settings/backup/tabs/cloudflare_d1_tab.dart';
import 'package:marina_hotel_mobile/services/auth_local_store.dart';
import 'package:marina_hotel_mobile/services/cloudflare_config.dart';

/// ✅ النطاق الافتراضي للمزامنة (تعليمات المستخدم 2026-09-05):
/// rooms, bookings, booking_nights, booking_notes, payments,
/// payment_voids, user_app (app_users), price_adjustments,
/// booking_price_adjustments, expenses, debts, employees, guest_infos,
/// cash_transactions, shift_notes, salary_cycles, salary_payments,
/// salary_withdrawals, salary_carry_over_logs, audit_logs,
/// inventory_items, inventory_transactions — ومعها blacklist (طلب
/// صريح سابق لم يُسحب) = 23 كياناً في migrationOrder/d1BackupTables.
///
/// - app_users أُضيف ككيان متزامن كامل (pull/push + outbox delta sync):
///   جدول Drift محلي (AppUsers، schemaVersion 66) + جدول D1
///   (worker/schema.sql + migrations/0003_app_users.sql) + إدخال
///   ENTITY_TABLES. كان يُزامَن عبر Appwrite فقط (appwrite_config.dart:116
///   وoutbox_dao.dart _entityTableMap وauth_local_store) وسقط كلياً من
///   طبقة Cloudflare.
/// - hotel_day_ledger مستبعد عمداً بتأكيد المستخدم (2026-09-05:
///   «جدول محلي لا أريد أن يتم مزامنته») — محلي-فقط بالتصميم (D8).
/// - blacklist تُخزَّن في shift_notes بوسم created_by='blacklist'
///   (blacklist_repository.dart) — لا جدول sqlite_master لها.
void main() {
  /// كل ما قد يظهر في sqlite_master المحلي: كيانات النطاق + جداول
  /// البنية المحلية + الداخلية — لنثبت أن الحصر يرفضها كلها.
  final allLocalTables = [
    ...CloudflareConfig.migrationOrder.where((t) => t != 'blacklist'),
    // جداول بلا مقابل في النطاق الافتراضي للمزامنة:
    'hotel_day_ledger', // محلي-فقط — استبعاد صريح بتأكيد المستخدم
    'outbox',
    'sync_remote_meta',
    'sync_state', // مؤشر المحرك المحلي (V-1) — ليس مرآة كيان متزامن
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

  group('النطاق الافتراضي للمزامنة (تعليمات المستخدم 2026-09-05)', () {
    test('d1BackupTables = migrationOrder حرفياً — 23 كياناً', () {
      expect(CloudflareConfig.d1BackupTables, CloudflareConfig.migrationOrder);
      expect(CloudflareConfig.d1BackupTables.length, 23);
      // لا تكرار
      expect(
        CloudflareConfig.d1BackupTables.toSet().length,
        CloudflareConfig.d1BackupTables.length,
      );
    });

    test('قائمة المستخدم الـ22 + blacklist — بالأسماء حرفياً', () {
      const userScope = [
        'rooms',
        'bookings',
        'booking_nights',
        'booking_notes',
        'payments',
        'payment_voids',
        'user_app', // app_users — «user_app» في رسالة المستخدم
        'price_adjustments',
        'booking_price_adjustments',
        'expenses',
        'debts',
        'employees',
        'guest_infos',
        'cash_transactions',
        'shift_notes',
        'salary_cycles',
        'salary_payments',
        'salary_withdrawals',
        'salary_carry_over_logs',
        'audit_logs',
        'inventory_items',
        'inventory_transactions',
      ];
      for (final entity in userScope) {
        final mapped = entity == 'user_app' ? 'app_users' : entity;
        expect(
          CloudflareConfig.d1BackupTables,
          contains(mapped),
          reason: '$entity ($mapped) من النطاق الافتراضي للمستخدم',
        );
      }
      // blacklist محفوظة (طلب صريح سابق ولم يُسحب صراحة)
      expect(CloudflareConfig.d1BackupTables, contains('blacklist'));
    });

    test(
      'app_users كيان متزامن كامل — mapping وترتيب ترحيل بلا FK',
      () {
        expect(CloudflareConfig.entityToTable['app_users'], 'app_users');
        expect(CloudflareConfig.migrationOrder, contains('app_users'));
        // يستقبل بين inventory_transactions وblacklist (بلا تبعيات FK)
        final idx = CloudflareConfig.migrationOrder.indexOf('app_users');
        expect(
          CloudflareConfig.migrationOrder[idx - 1],
          'inventory_transactions',
        );
        expect(CloudflareConfig.migrationOrder.last, 'blacklist');
      },
    );

    test('hotel_day_ledger يبقى مستبعداً نهائياً', () {
      expect(
        CloudflareConfig.d1BackupTables,
        isNot(contains('hotel_day_ledger')),
        reason: 'جدول محلي-فقط — المستخدم لا يريد مزامنته (2026-09-05)',
      );
    });
  });

  group('CloudflareD1Tab.scopeSyncTables', () {
    test('يحصر النطاق على الكيانات الفيزيائية — بنفس الترتيب', () {
      final scoped = CloudflareD1Tab.scopeSyncTables(allLocalTables);
      // 23 كيان − blacklist (بلا جدول فيزيائي) = 22 جدولاً فيزيائياً
      expect(scoped.length, 22);
      expect(
        scoped,
        CloudflareConfig.migrationOrder.where((t) => t != 'blacklist').toList(),
      );
      expect(scoped, contains('app_users'));
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
      'كيان النطاق الفيزيائي يمرّ، والغياب يسقطه (التجسيد مسؤولية التبويب)',
      () {
        // لو وُجد جدول فيزيائي اسمه blacklist (لا ينبغي) — القائمة
        // الفيزيائية تمرره لأنه كيان نطاق؛ والغيابه عن sqlite_master يعني
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

  group('AuthLocalStore.appUsersSyncPayload — حمولة snake_case لـ D1', () {
    test('مفاتيح snake_case فقط + local_uuid إلزامي (requireEntityId)', () {
      final payload = AuthLocalStore.appUsersSyncPayload(
        localUuid: 'user_admin',
        username: 'admin',
        password: 'pbkdf2\$hash',
        fullName: 'مدير النظام',
        userType: 'admin',
        permissionsJson: '["dashboard"]',
        active: true,
        lastLogin: 0,
        credentialsVersion: 1,
        role: 'admin',
        now: 1700000000,
        version: 1,
        deviceId: 'dev-1',
      );
      // كل المفاتيح snake_case — لا مفتاح camelCase يُرشَّح في worker
      for (final key in payload.keys) {
        expect(key, key.toLowerCase(), reason: 'مفتاح camelCase: $key');
      }
      expect(payload['local_uuid'], 'user_admin');
      expect(payload['username'], 'admin');
      expect(payload['full_name'], 'مدير النظام');
      expect(payload['user_type'], 'admin');
      expect(payload['permissions'], '["dashboard"]');
      expect(payload['active'], 1); // bool → INTEGER
      expect(payload['last_login'], 0);
      expect(payload['credentials_version'], 1);
      expect(payload['role'], 'admin');
      expect(payload['vector_clock'], '{"dev-1":1}');
      expect(payload['device_id'], 'dev-1');
      expect(payload['origin'], 'local');
      expect(payload.containsKey('deleted_at'), isFalse);
      // الحقول المطلوبة في sync.ts requireEntityId
      expect(payload['local_uuid'], isNotEmpty);
    });

    test('tombstone يضيف deleted_at وactive=true→1/فحص', () {
      final tombstone = AuthLocalStore.appUsersSyncPayload(
        localUuid: 'user_x',
        now: 1700000001,
        tombstone: true,
      );
      expect(tombstone['deleted_at'], 1700000001);
      expect(tombstone.containsKey('username'), isFalse);

      final inactive = AuthLocalStore.appUsersSyncPayload(
        localUuid: 'user_x',
        now: 1700000002,
        active: false,
      );
      expect(inactive['active'], 0);
    });

    test('مفاتيح الحمولة ⊆ أعمدة جدول D1 app_users (المرآة الحرفية)', () {
      // أعمدة worker/schema.sql (app_users) — بدون id
      const d1Columns = {
        'local_uuid',
        'username',
        'password',
        'full_name',
        'user_type',
        'permissions',
        'active',
        'last_login',
        'credentials_version',
        'role',
        // SyncFields mirror
        'server_id',
        'created_at',
        'updated_at',
        'deleted_at',
        'last_modified',
        'created_at_iso',
        'updated_at_iso',
        'deleted_at_iso',
        'created_at_epoch',
        'last_modified_epoch',
        'version',
        'origin',
        'vector_clock',
        'device_id',
        'idempotency_key',
      };
      final payload = AuthLocalStore.appUsersSyncPayload(
        localUuid: 'u',
        username: 'u',
        password: 'p',
        fullName: 'f',
        userType: 'admin',
        permissionsJson: '[]',
        active: true,
        lastLogin: 0,
        credentialsVersion: 1,
        role: 'admin',
        now: 1,
        version: 1,
        deviceId: 'd',
        tombstone: true,
      );
      for (final key in payload.keys) {
        expect(d1Columns, contains(key), reason: 'مفتاح بلا عمود D1: $key');
      }
    });
  });
}
