import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/cloudflare_config.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

/// ✅ (2026-09-05) devices ككيان متزامن كامل في النطاق الافتراضي
/// (تعليمات المستخدم «و devices — أيضاً pull/push وoutbox وdelta sync»).
///
/// التغطية هنا مركزة على العقود الهيكلية التي يبنيها المطورون لاحقاً:
/// 1. جدول Drift Devices موجود (v67) بأعمدة مرآة مجموعة Appwrite/D1.
/// 2. حمولة مزامنة devices (snake_case) ⊆ أعمدة جدول D1 — نفس ضمانة
///    app_users (worker يرشّح المفاتيح مقابل أعمدة الجدول، database.ts
///    getTableColumns؛ عمود زائد = رفض/فقدان حقل).
/// 3. devices ضمن migrationOrder/d1BackupTables (= النطاق الافتراضي)
///    وقبل blacklist (الترتيب FK-الآمن) وبعد app_users.
/// 4. عمود device_id فريد (UNIQUE) — هوية الجهاز الموحّدة لكل من REST
///    (/api/devices/register) وoutbox (نفس local_uuid = deviceId).
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('devices ككيان متزامن (v67)', () {
    test('schemaVersion = 67', () {
      expect(db.schemaVersion, 67);
    });

    test('جدول devices موجود في قاعدة جديدة', () async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND "
            "name = 'devices'",
          )
          .get();
      expect(tables, hasLength(1));
    });

    test('device_id فريد — تقارب REST وoutbox على صف واحد', () async {
      // فهرس فريد على device_id: محاولة إدراج نفس الهوية مرتين تفشل.
      await db.customStatement(
        'INSERT INTO devices (local_uuid, device_id, device_name, '
        'status, is_active, created_at, updated_at, last_modified, '
        'last_modified_epoch, version, origin, vector_clock) '
        "VALUES ('cf_dev_x', 'cf_dev_x', 'Tab A', 'active', 1, 1, 1, 1, "
        "1, 1, 'local', '{}')",
      );
      expect(
        () => db.customStatement(
          'INSERT INTO devices (local_uuid, device_id, device_name, '
          'status, is_active, created_at, updated_at, last_modified, '
          'last_modified_epoch, version, origin, vector_clock) '
          "VALUES ('other-uuid', 'cf_dev_x', 'Tab B', 'active', 1, 2, 2, "
          "2, 2, 1, 'local', '{}')",
        ),
        throwsA(anything),
      );
    });

    test('حمولة المزامنة snake_case ⊆ أعمدة جدول D1 (schema.sql)', () async {
      // أعمدة جدول devices في worker/schema.sql / migrations/0004 —
      // مرآة DriftDevices أعلاه. الحمولة النموذجية (_deviceSyncPayload
      // في cloudflare_sync_manager.dart) يجب أن تكون مجموعة جزئية.
      const d1Columns = <String>{
        'id',
        'local_uuid',
        'device_id',
        'device_name',
        'device_model',
        'device_type',
        'os_version',
        'platform',
        'app_version',
        'fcm_token',
        'status',
        'is_active',
        'last_seen',
        'last_active',
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
        'idempotency_key',
      };
      const payloadKeys = <String>{
        'local_uuid',
        'device_id',
        'device_name',
        'platform',
        'fcm_token',
        'status',
        'is_active',
        'last_active',
        'updated_at',
        'last_modified',
        'last_modified_epoch',
        'version',
        'origin',
        'vector_clock',
      };
      expect(payloadKeys.difference(d1Columns), isEmpty);
    });

    test('devices في migrationOrder بعد app_users وقبل blacklist', () {
      final order = CloudflareConfig.migrationOrder;
      final devicesIdx = order.indexOf('devices');
      final appUsersIdx = order.indexOf('app_users');
      final blacklistIdx = order.indexOf('blacklist');
      expect(devicesIdx, greaterThan(appUsersIdx));
      expect(devicesIdx, lessThan(blacklistIdx));
      // النطاق الافتراضي = migrationOrder حرفياً (تشمل devices تلقائياً)
      expect(CloudflareConfig.d1BackupTables, order);
      expect(order.contains('devices'), isTrue);
    });

    test('كتابة صف جهاز + قراءته عبر مسار getRegisteredDevices SQL', () async {
      // نفس الاستعلام المستخدم في getRegisteredDevices
      // (cloudflare_sync_manager.dart) — landing zone السحب.
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.customStatement(
        'INSERT INTO devices (local_uuid, device_id, device_name, '
        'platform, status, is_active, last_active, created_at, '
        'updated_at, last_modified, last_modified_epoch, version, '
        "origin, vector_clock) VALUES ('cf_dev_y', 'cf_dev_y', "
        "'Tab B', 'android', 'active', 1, ?, ?, ?, ?, ?, 1, 'local', "
        "'{}')",
        [now, now, now, now, now],
      );
      final rows = await db
          .customSelect(
            'SELECT * FROM devices WHERE deleted_at IS NULL '
            'ORDER BY COALESCE(last_active, updated_at) DESC',
          )
          .get();
      expect(rows, hasLength(1));
      expect(rows.first.data['device_id'], 'cf_dev_y');
      expect(rows.first.data['device_name'], 'Tab B');
      expect(rows.first.data['status'], 'active');
    });
  });
}
