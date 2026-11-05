// test/unit/fk_uuid_first_resolution_test.dart
//
// ✅ اختبار انحدار (2026-11-05) — وثيقة الربط §3.4/§5.1 بصيغة snake_case:
// «7 سجل مؤجل (أب غير محلول أو تعارض مفتاح فريد) — sync:pull-apply».
//
// الجذران المُصلحان في محلل FK (cloudflare_sync_manager + fk_rules):
//   1) salary_carry_over_logs: كانت قاعدة employee_id بلا
//      uuidCacheColumn → موظف موجود محلياً بـ local_uuid مطابق
//      (لكن ظلّ server_id ناقص/مائل) كان يُؤجَّل للأبد رغم أن العمود
//      العالمي employee_uuid موجود في D1 (worker/schema.sql:713)
//      وفي المخطط المحلي معاً. الآن يُحل من UUID أولاً.
//   2) booking_price_adjustments: المفتاح الطبيعي booking_local_uuid
//      قد يصل متقادماً (استعادة نسخة أعادت بناء local_uuid الأب) بينما
//      booking_uuid العالمي سليم — الشفاء من العمود العالمي مع إعادة
//      اشتقاق booking_local_id من UUID الأب (بلا أي تخمين).
//   3) اختلاف صيغة UUID (أحرف كبيرة) بين الأجهزة لا يعني اختلاف هوية —
//      محاولات lower() الاحتياطية في البحث عن الآباء.
//
// السيناريو المادّي لكل حالة: الأب هبط سابقاً (سجل محلي بمعرّف محلي
// مختلف عن فضاء D1)، ثم أُزيل ظلّ server_id محلياً (محاكاة موظف/حجز
// أُنشئ محلياً أو استُعيد بلا ظل مؤكد)، ثم يصل الابن من جهاز آخر
// يشير إلى الأب بمعرفاته الخادمية/العالمية — يجب أن يُطبَّق لا أن يُؤجَّل.

import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoNetworkClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    fail('السحب العكسي لا يجوز أن يلمس الشبكة: ${request.url}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase dbB;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
      'cf_device_id': 'fk-resolution-device-B',
    });
    dbB = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await dbB.close();
  });

  CloudflareSyncManager _managerFor(AppDatabase db) {
    final manager = CloudflareSyncManager();
    manager.reset();
    manager.configureForTesting(
      database: db,
      httpClient: _NoNetworkClient(),
      token: 'test-token',
      deviceId: 'fk-resolution-device-B',
    );
    return manager;
  }

  /// صف أب مسحوب (موظف/حجز) بصيغة D1 الخام — كما يبثه الـ worker.
  Map<String, dynamic> _parentRow({
    required String table,
    required int wireId,
    required String localUuid,
    required Map<String, dynamic> data,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return <String, dynamic>{
      ...data,
      'id': wireId,
      'local_uuid': localUuid,
      'server_id': null,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'version': 1,
      'origin': 'cloud',
      'device_id': 'fk-resolution-device-A',
      'vector_clock': jsonEncode({'fk-resolution-device-A': 1}),
      'last_modified': now,
      'created_at_epoch': 0,
      'last_modified_epoch': 0,
      'sync_timestamp': now,
    };
  }

  test(
    'salary_carry_over_logs يُحل موظفه من employee_uuid رغم غياب ظل server_id',
    () async {
      const employeeUuid = 'e1b16318-4dd1-445c-bcd2-32813fea52bf';
      const carryUuid = 'carry-e2b1-4c01-9a00-000000000001';

      // 1) الأب (الموظف) هبط سابقاً — جهاز B يحمله بمعرّف محلي مختلف
      //    عن فضاء D1 (wire id=77).
      final manager = _managerFor(dbB);
      final employeeReport = await manager.applyPulledRecords([
        (
          entity: 'employees',
          record: _parentRow(
            table: 'employees',
            wireId: 77,
            localUuid: employeeUuid,
            data: {
              'name': 'موظف الترحيل',
              'basic_salary': 1500.0,
              'status': 'نشط',
              'employee_uuid': employeeUuid,
            },
          ),
        ),
      ]);
      expect(employeeReport.unresolvable, isEmpty);
      expect(employeeReport.errors, isEmpty);

      // 2) محاكاة الموقف المُبلَّغ: ظلّ server_id محلياً غير مطابق
      //    (استعادة/موظف محلي لم يُكدَّس رفعه بعد).
      await dbB.customStatement(
        'UPDATE employees SET server_id = NULL WHERE local_uuid = ?',
        [employeeUuid],
      );

      // 3) يصل سجل ترحيل من جهاز آخر يشير للموظف بمعرّفيه الخادمي
      //    والعالمي معاً.
      final carryRow = _parentRow(
        table: 'salary_carry_over_logs',
        wireId: 900,
        localUuid: carryUuid,
        data: {
          'employee_id': 77, // id فضاء D1 — لا يطابق المحلي (1)
          'employee_uuid': employeeUuid, // المفتاح العالمي — الحاسم
          'amount': 250.0,
          'previous_cycle_start': '2026-09-01',
          'previous_cycle_end': '2026-09-30',
          'new_cycle_start': '2026-10-01',
          'new_cycle_end': '2026-10-31',
          'reason': 'تجاوز الراتب',
          'carried_at': 1750000000,
          'hotel_day_key': '2026-10-01',
        },
      );

      final report = await manager.applyPulledRecords([
        (entity: 'salary_carry_over_logs', record: carryRow),
      ]);

      expect(
        report.unresolvable,
        isEmpty,
        reason:
            'سجل الترحيل يجب أن يُحل من employee_uuid وليس أن يُؤجَّل: '
            '${report.unresolvable.join(', ')}',
      );
      expect(report.errors, isEmpty);

      final row = await dbB
          .customSelect(
            'SELECT employee_id, employee_uuid FROM salary_carry_over_logs '
            'WHERE local_uuid = ?',
            variables: [d.Variable.withString(carryUuid)],
          )
          .getSingle();
      expect(
        row.data['employee_id'],
        1,
        reason: 'employee_id يُحل للمعرّف المحلي للموظف',
      );
      expect(row.data['employee_uuid'], employeeUuid);
    },
  );

  test(
    'booking_price_adjustments يُشفى booking_local_uuid المتقادم من booking_uuid',
    () async {
      const bookingUuid = '5d874384-80ad-444e-a913-31506874e017';
      const staleBookingUuid = '00000000-stale-4bad-9000-00000000000b';
      const adjustmentUuid = 'adj-e2b1-4c01-9a00-000000000001';

      final manager = _managerFor(dbB);

      // 0) الغرفة تهبط أولاً — bookings.room_number مفتاح طبيعي على
      //    الغرف (سلسلة الآباء: غرفة → حجز → تسوية).
      final roomReport = await manager.applyPulledRecords([
        (
          entity: 'rooms',
          record: _parentRow(
            table: 'rooms',
            wireId: 9,
            localUuid: 'room-701-uuid',
            data: {
              'room_number': '701',
              'type': 'standard',
              'price': 150.0,
              'status': 'شاغرة',
            },
          ),
        ),
      ]);
      expect(roomReport.unresolvable, isEmpty);
      expect(roomReport.errors, isEmpty);

      // 1) الحجز هبط سابقاً بـ local_uuid العالمي الحالي.
      final bookingReport = await manager.applyPulledRecords([
        (
          entity: 'bookings',
          record: _parentRow(
            table: 'bookings',
            wireId: 55,
            localUuid: bookingUuid,
            data: {
              'room_number': '701',
              'guest_name': 'ضيف الشفاء',
              'guest_phone': '0555555555',
              'guest_nationality': 'يمني',
              'checkin_date': '2026-10-01',
              'checkout_date': '2026-10-05',
              'status': 'نشط',
            },
          ),
        ),
      ]);
      expect(bookingReport.unresolvable, isEmpty);
      expect(bookingReport.errors, isEmpty);

      // 2) يصل تسوية سعر من جهاز آخر: booking_local_uuid قديم (نسخة
      //    أقدم من الحجز) بينما booking_uuid العالمي سليم.
      final adjustmentRow = _parentRow(
        table: 'booking_price_adjustments',
        wireId: 910,
        localUuid: adjustmentUuid,
        data: {
          'booking_local_uuid': staleBookingUuid, // متقادم
          'booking_local_id': 55, // فضاء D1
          'booking_uuid': bookingUuid, // العالمي — الحاسم
          'amount': 5000.0,
          'adjustment_type': 0,
          'adjustment_mode': 'per_night',
          'effective_hotel_day': '2026-10-02',
          'is_active': 1,
          'reason': 'تفاوض سعر',
        },
      );

      final report = await manager.applyPulledRecords([
        (entity: 'booking_price_adjustments', record: adjustmentRow),
      ]);

      expect(
        report.unresolvable,
        isEmpty,
        reason:
            'التسوية يجب أن تُشفى من booking_uuid العالمي لا أن تُؤجَّل: '
            '${report.unresolvable.join(', ')}',
      );
      expect(report.errors, isEmpty);

      final row = await dbB
          .customSelect(
            'SELECT booking_local_id, booking_local_uuid, amount '
            'FROM booking_price_adjustments WHERE local_uuid = ?',
            variables: [d.Variable.withString(adjustmentUuid)],
          )
          .getSingle();
      expect(
        row.data['booking_local_uuid'],
        bookingUuid,
        reason: 'المفتاح الطبيعي يُعاد اشتقاقه من UUID الأب الفعلي',
      );
      expect(
        row.data['booking_local_id'],
        1,
        reason: 'المؤشر الرقمي يُحل إلى المعرّف المحلي للحجز',
      );
      expect(row.data['amount'], 5000.0);
    },
  );

  test(
    'اختلاف صيغة UUID (أحرف كبيرة) بين الأجهزة لا يؤجل سجل الترحيل',
    () async {
      const employeeUuidLower = 'e1b16318-4dd1-445c-bcd2-32813fea52bf';
      const employeeUuidUpper = 'E1B16318-4DD1-445C-BCD2-32813FEA52BF';
      const carryUuid = 'carry-e2b1-4c01-9a00-000000000002';

      final manager = _managerFor(dbB);
      await manager.applyPulledRecords([
        (
          entity: 'employees',
          record: _parentRow(
            table: 'employees',
            wireId: 77,
            localUuid: employeeUuidLower,
            data: {
              'name': 'موظف الصيغة',
              'basic_salary': 1200.0,
              'status': 'نشط',
              'employee_uuid': employeeUuidLower,
            },
          ),
        ),
      ]);

      final report = await manager.applyPulledRecords([
        (
          entity: 'salary_carry_over_logs',
          record: _parentRow(
            table: 'salary_carry_over_logs',
            wireId: 901,
            localUuid: carryUuid,
            data: {
              'employee_id': 77,
              'employee_uuid': employeeUuidUpper,
              'amount': 100.0,
              'previous_cycle_start': '2026-09-01',
              'previous_cycle_end': '2026-09-30',
              'new_cycle_start': '2026-10-01',
              'new_cycle_end': '2026-10-31',
              'reason': 'ترحيل بصيغة مختلفة',
              'carried_at': 1750000000,
            },
          ),
        ),
      ]);

      expect(report.unresolvable, isEmpty);
      expect(report.errors, isEmpty);
      final row = await dbB
          .customSelect(
            'SELECT employee_id FROM salary_carry_over_logs WHERE local_uuid = ?',
            variables: [d.Variable.withString(carryUuid)],
          )
          .getSingle();
      expect(row.data['employee_id'], 1);
    },
  );

  test(
    'أب غائب فعلاً خادمياً يبقى مؤجلاً (يتيم بنيوي — لا اختراع روابط)',
    () async {
      const ghostUuid = '99999999-ghost-4bad-9000-000000000009';
      final manager = _managerFor(dbB);

      // لا موظف محلي إطلاقاً — أي حل كان سيكون تخميناً ممنوعاً (وثيقة §1.3).
      final report = await manager.applyPulledRecords([
        (
          entity: 'salary_carry_over_logs',
          record: _parentRow(
            table: 'salary_carry_over_logs',
            wireId: 902,
            localUuid: 'carry-e2b1-4c01-9a00-000000000003',
            data: {
              'employee_id': 77,
              'employee_uuid': ghostUuid,
              'amount': 50.0,
              'previous_cycle_start': '2026-09-01',
              'previous_cycle_end': '2026-09-30',
              'new_cycle_start': '2026-10-01',
              'new_cycle_end': '2026-10-31',
              'reason': 'يتيم بنيوي',
              'carried_at': 1750000000,
            },
          ),
        ),
      ]);

      expect(
        report.unresolvable,
        hasLength(1),
        reason: 'الأب الغائب فعلاً = تأجيل (حجر لاحقاً) وليس ربطاً تخمينياً',
      );
      expect(report.errors, isEmpty);
    },
  );
}
