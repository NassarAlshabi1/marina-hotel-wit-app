import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/cloudflare_config.dart';
import 'package:marina_hotel_mobile/services/cloudflare_d1_service.dart';

/// ✅ اختبار تحويل صفوف القائمة السوداء من تخزينها المحلي (shift_notes
/// الموسومة created_by='blacklist' — الاسم في title والحقول JSON في
/// content) إلى أعمدة جدول blacklist في D1 (worker/schema.sql).
///
/// الاتجاه مطابق لمسار المزامنة: outbox entity='blacklist' → جدول
/// blacklist. القيم الافتراضية مطابقة لسلوك BlacklistRepository
/// (reportedBy='police'، active=true).
void main() {
  Map<String, Object?> shiftNoteRow({
    Object? title = 'ضيف ممنوع',
    Object? content,
    Object? localUuid = 'uuid-bl-1',
    Object? serverId,
    Object? createdAt = 1700000000,
    Object? updatedAt = 1700000100,
    Object? deletedAt,
    Object? lastModified = 1700000100,
    Object? version = 3,
    Object? origin = 'local',
    Object? vectorClock = '{"d1":5}',
    Object? deviceId = 'device-a',
    Object? idempotencyKey = 'idem-1',
    Object? createdAtEpoch = 1700000000,
    Object? lastModifiedEpoch = 1700000100,
    Object? createdAtIso = '2023-11-14T22:13:20.000Z',
  }) => <String, Object?>{
    'id': 7,
    'title': title,
    'content': content ?? jsonEncode(<String, dynamic>{}),
    'local_uuid': localUuid,
    'server_id': serverId,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
    'last_modified': lastModified,
    'created_at_iso': createdAtIso,
    'created_at_epoch': createdAtEpoch,
    'last_modified_epoch': lastModifiedEpoch,
    'version': version,
    'origin': origin,
    'vector_clock': vectorClock,
    'device_id': deviceId,
    'idempotency_key': idempotencyKey,
  };

  group('CloudflareD1Service.blacklistRowFromShiftNote', () {
    test('يحوّل كل الحقول من التخزين المحلي إلى أعمدة جدول D1', () {
      final row = shiftNoteRow(
        content: jsonEncode(<String, dynamic>{
          'nationality': 'يمني',
          'nationalId': '1234567890',
          'phone': '777123456',
          'reason': 'تخريب غرفة',
          'notes': 'ممنوع الدخول',
          'reportedBy': 'reception',
          'active': false,
        }),
        serverId: 42,
      );

      final out = CloudflareD1Service.blacklistRowFromShiftNote(row);

      expect(out['local_uuid'], 'uuid-bl-1');
      expect(out['name'], 'ضيف ممنوع');
      expect(out['nationality'], 'يمني');
      expect(out['national_id'], '1234567890');
      expect(out['phone'], '777123456');
      expect(out['reason'], 'تخريب غرفة');
      expect(out['notes'], 'ممنوع الدخول');
      expect(out['reported_by'], 'reception');
      expect(out['active'], 0); // false → 0 (INTEGER في D1)
      expect(out['server_id'], 42);
      expect(out['created_at'], 1700000000);
      expect(out['updated_at'], 1700000100);
      expect(out['deleted_at'], isNull);
      expect(out['last_modified'], 1700000100);
      expect(out['version'], 3);
      expect(out['origin'], 'local');
      expect(out['vector_clock'], '{"d1":5}');
      expect(out['device_id'], 'device-a');
      expect(out['idempotency_key'], 'idem-1');
      // SyncFields الإضافية تُنقل كما هي
      expect(out['created_at_epoch'], 1700000000);
      expect(out['last_modified_epoch'], 1700000100);
      // المفتاح المحلي id لا يُنقل (عمود D1 AUTOINCREMENT مستقل)
      expect(out.containsKey('id'), isFalse);
      // أعمدة D1 NOT NULL المطلوبة موجودة
      expect(out.containsKey('nationality'), isTrue);
    });

    test(
      'القيم الافتراضية مطابقة لسلوك BlacklistRepository عند حقول ناقصة',
      () {
        final out = CloudflareD1Service.blacklistRowFromShiftNote(
          shiftNoteRow(content: jsonEncode(<String, dynamic>{})),
        );
        expect(out['nationality'], '');
        expect(out['reported_by'], 'police');
        expect(out['active'], 1); // الافتراضي true
        expect(out['national_id'], isNull);
        expect(out['phone'], isNull);
      },
    );

    test('content غير صالح أو فارغ لا يُسقط الصف — قيم افتراضية', () {
      for (final bad in <Object?>['ليس json', '', null, '{invalid']) {
        final out = CloudflareD1Service.blacklistRowFromShiftNote(
          shiftNoteRow(content: bad),
        );
        expect(out['name'], 'ضيف ممنوع', reason: 'content=$bad');
        expect(out['reported_by'], 'police', reason: 'content=$bad');
        expect(out['active'], 1, reason: 'content=$bad');
      }
    });

    test('قبر الحذف الناعم (deleted_at) يُنقل — نسخة احتياطية أمينة', () {
      final out = CloudflareD1Service.blacklistRowFromShiftNote(
        shiftNoteRow(deletedAt: 1700000200),
      );
      expect(out['deleted_at'], 1700000200);
    });

    test('مجموعة مفاتيح المخرجات ثابتة (استقرار بناء INSERT)', () {
      final out = CloudflareD1Service.blacklistRowFromShiftNote(
        shiftNoteRow(),
      );
      expect(out.keys.toSet(), <String>{
        'local_uuid',
        'name',
        'nationality',
        'national_id',
        'phone',
        'reason',
        'notes',
        'reported_by',
        'active',
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
      });
    });

    test('استعلاما المصدر يطابقان وسم التخزين في BlacklistRepository', () {
      expect(
        CloudflareD1Service.blacklistSourceSql,
        "SELECT * FROM shift_notes WHERE created_by = 'blacklist'",
      );
      expect(
        CloudflareD1Service.shiftNotesSourceSql,
        "SELECT * FROM shift_notes WHERE created_by != 'blacklist'",
      );
      expect(CloudflareConfig.blacklistStorageTag, 'blacklist');
    });
  });
}
