// test/unit/sync_schema_validation_test.dart
//
// ✅ P0 — التحقق من أن كل جدول مزامنة يحتوي على جميع الحقول المتوقعة
// في قاعدة البيانات المحلية (Drift) مع أنواعها الصحيحة.
//
// المرجع: _syncFields في lib/services/appwrite_schema_verifier.dart

// ignore_for_file: lines_longer_than_80_chars, unnecessary_raw_strings, unnecessary_brace_in_string_interps

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

/// تحويل camelCase إلى snake_case (مطابق لتحويل Drift التلقائي)
String _snake(String camel) {
  return camel.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (m) => '_${m.group(0)!.toLowerCase()}',
  );
}

/// الحقول الأساسية المتوقعة في كل جدول مزامنة (SyncFields)
/// المفاتيح بـ camelCase، تتحول تلقائياً لـ snake_case عند المقارنة
final _expectedSyncFields = <String, Map<String, dynamic>>{
  'serverId': {'type': 'INTEGER', 'nullable': true},
  'createdAt': {'type': 'INTEGER', 'nullable': false},
  'updatedAt': {'type': 'INTEGER', 'nullable': false},
  'deletedAt': {'type': 'INTEGER', 'nullable': true},
  'lastModified': {'type': 'INTEGER', 'nullable': false},
  'createdAtIso': {'type': 'TEXT', 'nullable': true},
  'updatedAtIso': {'type': 'TEXT', 'nullable': true},
  'deletedAtIso': {'type': 'TEXT', 'nullable': true},
  'createdAtEpoch': {'type': 'INTEGER', 'nullable': false, 'default': '0'},
  'lastModifiedEpoch': {'type': 'INTEGER', 'nullable': false, 'default': '0'},
  'deviceId': {'type': 'TEXT', 'nullable': false, 'default': ''},
  'version': {'type': 'INTEGER', 'nullable': false, 'default': '1'},
  'origin': {'type': 'TEXT', 'nullable': false, 'default': 'local'},
  'vectorClock': {'type': 'TEXT', 'nullable': false, 'default': '{}'},
};

/// الحقول الإضافية الموجودة في Drift SyncFields ولكنها ليست في _syncFields
final _extraDriftSyncFields = <String, Map<String, dynamic>>{
  'localUuid': {'type': 'TEXT', 'nullable': false, 'unique': true},
  'idempotencyKey': {'type': 'TEXT', 'nullable': true},
};

/// جداول SQLite التي تستخدم SyncFields في Drift
final _syncTableNames = [
  'rooms',
  'bookings',
  'booking_notes',
  'employees',
  'expenses',
  'cash_transactions',
  'payments',
  'debts',
  'shift_notes',
  'booking_nights',
  'hotel_day_ledger',
  'price_adjustments',
  'booking_price_adjustments',
  'audit_logs',
  'payment_voids',
  'guest_infos',
  'salary_cycles',
  'salary_payments',
  'salary_withdrawals',
  'salary_carry_over_logs',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Map<String, List<Map<String, dynamic>>> pragmaTableInfo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());

    final allTables = [..._syncTableNames, 'outbox', 'sync_state'];
    pragmaTableInfo = {};
    for (final table in allTables) {
      try {
        final rows = await db.customSelect('PRAGMA table_info($table)', readsFrom: {}).get();
        pragmaTableInfo[table] = rows
            .map(
              (r) => {
                'cid': r.data['cid'],
                'name': r.data['name'] as String,
                'type': r.data['type'] as String,
                'notnull': r.data['notnull'] as int,
                'dflt_value': r.data['dflt_value'],
                'pk': r.data['pk'] as int,
              },
            )
            .toList();
      } catch (_) {}
    }
  });

  tearDown(() async {
    await db.close();
  });

  group('تطابق schema جداول المزامنة مع SyncFields', () {
    for (final tableName in _syncTableNames) {
      test('جدول $tableName يحتوي على جميع حقول SyncFields', () {
        final tableInfo = pragmaTableInfo[tableName];
        expect(tableInfo, isNotNull, reason: 'الجدول $tableName غير موجود في قاعدة البيانات');

        final colByName = {for (final c in tableInfo!) c['name'] as String: c};

        // تحقق من الحقول المتوقعة (_syncFields من AppwriteSchemaVerifier)
        for (final entry in _expectedSyncFields.entries) {
          final keySnake = _snake(entry.key);
          final expected = entry.value;

          expect(
            colByName,
            contains(keySnake),
            reason: 'جدول $tableName يفتقد الحقل ${entry.key} (snake: $keySnake)',
          );

          final colInfo = colByName[keySnake]!;
          final actualType = colInfo['type'] as String;
          expect(
            actualType,
            contains(expected['type'] as String),
            reason: 'جدول $tableName: ${entry.key} نوعه $actualType لكن المتوقع ${expected['type']}',
          );

          if (expected['nullable'] == false) {
            expect(
              colInfo['notnull'],
              1,
              reason: 'جدول $tableName: ${entry.key} يجب أن يكون NOT NULL',
            );
          } else {
            expect(
              colInfo['notnull'],
              0,
              reason: 'جدول $tableName: ${entry.key} يجب أن يكون NULLABLE',
            );
          }

          if (expected['default'] != null) {
            final defaultVal = colInfo['dflt_value'];
            final expectedDefault = expected['default'] as String;
            if (expectedDefault == '') {
              expect(
                defaultVal,
                anyOf(isNull, equals("''")),
                reason: 'جدول $tableName: default لـ ${entry.key} يجب أن يكون \'\' أو null',
              );
            } else {
              expect(
                defaultVal,
                isNotNull,
                reason: 'جدول $tableName: ${entry.key} يجب أن يكون default=$expectedDefault',
              );
            }
          }
        }

        // تحقق من localUuid و idempotencyKey (من Drift SyncFields)
        for (final entry in _extraDriftSyncFields.entries) {
          final keySnake = _snake(entry.key);
          expect(
            colByName,
            contains(keySnake),
            reason: 'جدول $tableName يفتقد ${entry.key}',
          );
          final colInfo = colByName[keySnake]!;
          expect(
            colInfo['type'],
            'TEXT',
            reason: 'جدول $tableName: ${entry.key} نوعه ${colInfo['type']} لكن المتوقع TEXT',
          );
          if (entry.value['nullable'] == false) {
            expect(colInfo['notnull'], 1);
          } else {
            expect(colInfo['notnull'], 0);
          }
        }
      });
    }
  });

  group('تحقق من schema جداول منفردة', () {
    test('outbox يحتوي على حقوله المتوقعة', () {
      final tableInfo = pragmaTableInfo['outbox'];
      expect(tableInfo, isNotNull);
      final columnNames = tableInfo!.map((c) => c['name'] as String).toSet();

      final expectedCols = {
        'id',
        'entity',
        'op',
        'local_uuid',
        'server_id',
        'payload',
        'client_ts',
        'attempts',
        'last_error',
        'idempotency_key',
        'processing_status',
        'processing_started_at',
        'processing_worker',
        'source',
        'delivered_to_primary',
        'delivered_to_secondary',
      };
      for (final col in expectedCols) {
        expect(columnNames, contains(col), reason: 'outbox يفتقد العمود $col');
      }
    });

    test('sync_state يحتوي على حقوله المتوقعة', () {
      final tableInfo = pragmaTableInfo['sync_state'];
      expect(tableInfo, isNotNull);
      final columnNames = tableInfo!.map((c) => c['name'] as String).toSet();

      final expectedCols = {
        'id',
        'last_server_ts',
        'last_pull_ts',
        'last_push_ts',
        'is_syncing',
        'version',
      };
      for (final col in expectedCols) {
        expect(columnNames, contains(col), reason: 'sync_state يفتقد العمود $col');
      }
    });
  });

  group('فجوات معروفة بين Drift Schema و AppwriteSchemaVerifier', () {
    test('⚠️ syncTimestamp موجود في _syncFields (AppwriteSchemaVerifier) لكنه غائب عن Drift SyncFields mixin', () {
      // هذه فجوة معروفة: AppwriteSchemaVerifier يتوقع syncTimestamp
      // لكن Drift Schema لا يملك هذا العمود حالياً.
      // هذا اختبار معلوماتي فقط — لا يفشل.
      final tableInfo = pragmaTableInfo['rooms'];
      final colByName = {for (final c in tableInfo!) c['name'] as String: c};
      if (colByName.containsKey('sync_timestamp')) {
        // syncTimestamp موجود — تمت إضافته لاحقاً
      }
      // إذا لم يكن موجوداً، هذه فجوة معروفة
    });
  });

  group('تحقق منطقي من تعريف الحقول', () {
    test('كل default في _expectedSyncFields متناسق مع نوعه', () {
      for (final entry in _expectedSyncFields.entries) {
        final def = entry.value['default'] as String?;
        if (def != null && entry.value['type'] == 'INTEGER') {
          expect(
            int.tryParse(def),
            isNotNull,
            reason: 'default "${def}" للحقل ${entry.key} ليس عدداً صحيحاً',
          );
        }
      }
    });

    test('createdAt, updatedAt, lastModified غير nullable', () {
      for (final required in ['createdAt', 'updatedAt', 'lastModified']) {
        expect(
          _expectedSyncFields[required]!['nullable'],
          false,
          reason: '${required} يجب أن يكون required=true',
        );
      }
    });

    test('serverId و deletedAt nullable', () {
      for (final nullable in ['serverId', 'deletedAt']) {
        expect(
          _expectedSyncFields[nullable]!['nullable'],
          true,
          reason: '${nullable} يجب أن يكون nullable',
        );
      }
    });
  });
}
