import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

/// ✅ (2026-09-05) landing zone السحب لكيان app_users — النطاق الافتراضي
/// للمزامنة يشمل user_app مع pull/push وoutbox delta sync (تعليمات
/// المستخدم).
///
/// السحب (cloudflare_sync_manager._applyChange) يكتب صفوف D1 القادمة
/// بأعمدتها الحرفية (INSERT/UPDATE بيتان مولّدان من مفاتيح السجل) —
/// لذا يجب أن يقبل الجدول المحلي قائمة أعمدة D1 حرفياً وإلا سقط كل
/// صف سحب في catch وتقدّم الـ cursor فوق بيانات مفقودة. هذه الاختبارات
/// تثبت القبول الحرفي على قاعدة بيانات حقيقية (in-memory).
void main() {
  /// أعمدة جدول app_users في D1 (worker/schema.sql + migrations/
  /// 0003_app_users.sql) — بدون id (المولّد خادمياً ويُحذف قبل التطبيق).
  const d1Columns = [
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
    // SyncFields (Drift mixin mirror)
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
  ];

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('schemaVersion = 66 (ترحيل إنشاء app_users)', () {
    expect(db.schemaVersion, 66);
  });

  test('جدول app_users موجود في قاعدة جديدة', () async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND "
          "name = 'app_users'",
        )
        .get();
    expect(tables, hasLength(1));
  });

  test(
    'يقبل صف D1 حرفياً بكل أعمدته (INSERT OR IGNORE مثل _applyChange)',
    () async {
      final row = <String, dynamic>{
        'local_uuid': 'user_admin',
        'username': 'admin',
        'password': 'pbkdf2\$hash',
        'full_name': 'مدير النظام',
        'user_type': 'admin',
        'permissions': '["dashboard","rooms"]',
        'active': 1,
        'last_login': 0,
        'credentials_version': 3,
        'role': 'admin',
        'server_id': null,
        'created_at': 1700000000,
        'updated_at': 1700000100,
        'deleted_at': null,
        'last_modified': 1700000100,
        'created_at_iso': null,
        'updated_at_iso': null,
        'deleted_at_iso': null,
        'created_at_epoch': 0,
        'last_modified_epoch': 1700000100,
        'version': 5,
        'origin': 'cloud',
        'vector_clock': '{"dev-1":7}',
        'device_id': 'dev-1',
        'idempotency_key': null,
      };
      expect(row.keys.toSet(), d1Columns.toSet());

      final columns = row.keys.join(', ');
      final placeholders = row.keys.map((_) => '?').join(', ');
      await db.customStatement(
        'INSERT OR IGNORE INTO app_users ($columns) VALUES ($placeholders)',
        row.values.toList(),
      );

      final result = await db
          .customSelect(
            'SELECT * FROM app_users WHERE local_uuid = ?',
            variables: [Variable.withString('user_admin')],
          )
          .getSingle();
      expect(result.data['username'], 'admin');
      expect(result.data['credentials_version'], 3);
      expect(result.data['active'], 1);
      expect(result.data['version'], 5);
      expect(result.data['origin'], 'cloud');
    },
  );

  test('تحديث جزئي مثل updateRecord في worker (SET بأعمدة الحمولة)', () async {
    await db.customStatement(
      "INSERT INTO app_users (local_uuid, username, full_name, user_type, "
      "active, credentials_version, created_at, updated_at, last_modified, "
      "version, origin, vector_clock) VALUES "
      "('user_a', 'a', 'A', 'staff', 1, 1, 100, 100, 100, 1, 'local', '{}')",
    );

    // حمولة تحديث صلاحيات (نفس شكل outbox snake_case)
    final update = <String, dynamic>{
      'permissions': '["dashboard"]',
      'credentials_version': 2,
      'updated_at': 200,
      'last_modified': 200,
      'last_modified_epoch': 200,
      'version': 2,
      'vector_clock': '{"dev-2":1}',
      'device_id': 'dev-2',
    };
    final setClauses = update.keys.map((c) => '$c = ?').join(', ');
    await db.customStatement(
      'UPDATE app_users SET $setClauses WHERE local_uuid = ?',
      [...update.values, 'user_a'],
    );

    final result = await db
        .customSelect(
          'SELECT * FROM app_users WHERE local_uuid = ?',
          variables: [Variable.withString('user_a')],
        )
        .getSingle();
    expect(result.data['permissions'], '["dashboard"]');
    expect(result.data['credentials_version'], 2);
    expect(result.data['version'], 2);
    expect(result.data['username'], 'a'); // لم يُمس
    expect(result.data['active'], 1); // لم يُمس
  });

  test('local_uuid UNIQUE — هوية docId الحتمية تحمي من التكرار', () async {
    final base =
        "INSERT OR IGNORE INTO app_users "
        "(local_uuid, username, full_name, user_type, active, created_at, "
        "updated_at, last_modified, version, origin, vector_clock) VALUES "
        "('user_dup', '%s', 'D', 'staff', 1, 100, 100, 100, 1, 'local', '{}')";
    await db.customStatement(base.replaceAll('%s', 'first'));
    await db.customStatement(base.replaceAll('%s', 'second'));

    final result = await db
        .customSelect(
          'SELECT username FROM app_users WHERE local_uuid = ?',
          variables: [Variable.withString('user_dup')],
        )
        .get();
    expect(result, hasLength(1)); // الثاني أُهمل idempotently
    expect(result.single.data['username'], 'first');
  });
}
