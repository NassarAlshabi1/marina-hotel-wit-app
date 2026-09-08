// ═══════════════════════════════════════════════════════════════
//  sync_pull_fk_contract_test.dart — 2026-09-09 الجذران الثالث والرابع
//
//  اختبارات عقدية لمسار السحب على طرف العميل، تُثبّت إصلاح الجذرين
//  المؤكدين من جهاز حقيقي («لم يتم سحب كل البيانات»):
//
//  الجذر (أ) — أعمدة خادمية غريبة عن المخطط المحلي (sync_timestamp
//  من مخطط D1 القديم): كانت تُفشل INSERT بكامل الصف بـ «no such
//  column» صمتاً بينما المؤشر يتقدم. العقد: تُفلتر ويُطبَّق الصف.
//
//  الجذر (ب) — مؤشرات FK رقمية تحمل id خادم D1 (autoincrement):
//  كانت تُكتب كما هي محلياً = 31 انتهاك FK حقيقياً (علاقات الحجوزات
//  بلياليها ومدفوعاتها كلها معطوبة). العقد:
//    • ظلّ هوية الخادم: id D1 يُخزَّن في server_id المحلي.
//    • ترجمة FK: uuid-cache → ظلّ server_id → فضاء Appwrite القديم.
//    • الابن قبل الأب = تأجيل وإعادة محاولة بعد اكتمال الصفحات.
//    • ما بقي غير محلول = دورة فاشلة: المؤشر لا يتحرك ولا full sync
//      (سياسة «لا نجاح مع جداول ناقصة» على طرف العميل أيضاً).
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _syncFields(
  String uuid,
  int updatedAt, {
  int? serverId,
  String device = 'other-device',
}) => {
  'id': serverId,
  'local_uuid': uuid,
  'created_at': updatedAt,
  'updated_at': updatedAt,
  'last_modified': updatedAt,
  'created_at_epoch': 0,
  'last_modified_epoch': 0,
  'version': 1,
  'origin': 'local',
  'vector_clock': '{}',
  'device_id': device,
};

Map<String, dynamic> _roomRow(
  String uuid, {
  int? serverId,
  String? roomNumber,
  int updatedAt = 1700000100,
  Map<String, Object?> extra = const {},
}) => {
  ..._syncFields(uuid, updatedAt, serverId: serverId),
  'room_number': roomNumber ?? 'RN-$uuid',
  'type': 'double',
  'price': 100.0,
  'status': 'available',
  'cleaning_status': 'clean',
  'requires_maintenance': 0,
  ...extra,
};

Map<String, dynamic> _bookingRow(
  String uuid, {
  int? serverId,
  String? roomNumber,
  int updatedAt = 1700000200,
}) => {
  ..._syncFields(uuid, updatedAt, serverId: serverId),
  'room_number': roomNumber ?? 'RN-1',
  'guest_name': 'ضيف عقد FK',
  'guest_phone': '0771000000',
  'guest_nationality': 'يمني',
  'checkin_date': '2026-09-09',
  'status': 'active',
};

Map<String, dynamic> _nightRow(
  String uuid, {
  required int bookingLocalId,
  String? bookingUuidCache,
  int? serverBookingId,
  int updatedAt = 1700000300,
}) => {
  ..._syncFields(uuid, updatedAt),
  'booking_local_id': bookingLocalId,
  'hotel_day_key': '2026-09-09',
  'night_start': '2026-09-09 15:00',
  'night_end': '2026-09-10 12:00',
  'nightly_rate': 100.0,
  'sequence': 1,
  'is_processed_by_auto_fix': 0,
  'base_rate': 100.0,
  'adjustment': 0.0,
  'final_rate': 100.0,
  if (bookingUuidCache != null) 'booking_uuid_cache': bookingUuidCache,
  if (serverBookingId != null) 'server_booking_id': serverBookingId,
};

Map<String, dynamic> _noteRow(
  String uuid, {
  required int bookingId,
  int updatedAt = 1700000300,
}) => {
  ..._syncFields(uuid, updatedAt),
  'booking_id': bookingId,
  'note_text': 'ملاحظة عقد FK',
  'alert_type': 'info',
};

Map<String, dynamic> _paymentRow(
  String uuid, {
  int? bookingLocalId,
  String? bookingUuidCache,
  int? serverBookingId,
  int? cashTransactionLocalId,
  int updatedAt = 1700000400,
}) => {
  ..._syncFields(uuid, updatedAt),
  'booking_local_id': bookingLocalId,
  'booking_uuid_cache': bookingUuidCache,
  if (serverBookingId != null) 'server_booking_id': serverBookingId,
  'cash_transaction_local_id': cashTransactionLocalId,
  'amount': 250.0,
  'payment_date': '2026-09-09 20:00',
  'payment_method': 'cash',
  'revenue_type': 'room',
};

Map<String, dynamic> _employeeRow(
  String uuid, {
  int? serverId,
  int updatedAt = 1700000500,
}) => {
  ..._syncFields(uuid, updatedAt, serverId: serverId),
  'name': 'موظف عقد FK',
  'basic_salary': 1000.0,
  'position': 'موظف',
  'status': 'active',
};

Map<String, dynamic> _salaryCycleRow(
  String uuid, {
  required int employeeId,
  int? serverId,
  int updatedAt = 1700000600,
}) => {
  ..._syncFields(uuid, updatedAt, serverId: serverId),
  'employee_id': employeeId,
  'cycle_key': '2026-09',
  'expected_amount': 1000,
  'actual_paid': 0,
  'remaining_amount': 1000,
  'status': 'draft',
};

Map<String, dynamic> _salaryPaymentRow(
  String uuid, {
  required int cycleId,
  int updatedAt = 1700000700,
}) => {
  ..._syncFields(uuid, updatedAt),
  'cycle_id': cycleId,
  'amount': 500,
  'payment_date_iso': '2026-09-09',
};

class _PullQueueClient extends http.BaseClient {
  _PullQueueClient(this.pages);

  final List<Map<String, dynamic>> pages;
  int _served = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'GET') {
      throw StateError('unexpected ${request.method} ${request.url}');
    }
    if (_served >= pages.length) {
      throw StateError('exhausted after ${pages.length} pages');
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(pages[_served++]))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
    });
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<CloudflareSyncManager> makeManager(http.Client client) async {
    final manager = CloudflareSyncManager();
    manager.reset();
    manager.configureForTesting(
      database: db,
      httpClient: client,
      token: 'test-token',
      deviceId: 'fk-contract-device',
    );
    return manager;
  }

  Future<Object?> pref(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.get(key);
  }

  Future<int> count(String table) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM $table')
        .getSingle();
    return row.read<int>('c');
  }

  Future<Object?> cell(String table, String column, String uuid) async {
    final row = await db
        .customSelect(
          'SELECT $column AS v FROM $table WHERE local_uuid = ?',
          variables: [Variable<String>(uuid)],
        )
        .getSingleOrNull();
    return row?.data['v'];
  }

  group('الجذر (أ): الأعمدة الخادمية الغريبة تُفلتر ولا تُفشل الصف', () {
    test('sync_timestamp وbقايا مخطط D1 القديم تُسقط والصف يُطبق', () async {
      final manager = await makeManager(
        _PullQueueClient([
          {
            'changes': [
              _roomRow(
                'rm-1',
                serverId: 501,
                extra: const <String, Object?>{
                  'sync_timestamp': 1700000100000,
                  'legacy_appwrite_column': 'x',
                },
              ),
            ],
            'cursor': '1700000100',
            'has_more': false,
            'errors': <dynamic>[],
          },
        ]),
      );

      final result = await manager.sync();

      expect(result.status, SyncStatus.success);
      expect(result.recordsPulled, 1);
      expect(await count('rooms'), 1);
      // ظلّ هوية الخادم: server_id المحلي = id الصف على D1.
      expect(await cell('rooms', 'server_id', 'rm-1'), 501);
      // الأعمدة الغريبة لم تُكتب طبعاً — ولا أعطت أي أثر.
      expect(await pref('cf_last_pull_cursor'), 1700000100);
      expect(await pref('cf_full_sync_completed'), true);
    });
  });

  group('الجذر (ب): ترجمة مؤشرات FK من هوية D1 إلى الهوية المحلية', () {
    test(
      'الابن قبل الأب عبر الصفحات: يُؤجل ثم يُحل بالمفتاح العالمي',
      () async {
        // صفحة 1: ملاحظة تسبق حجزها (booking_id=501 هو id الأب على D1).
        // صفحة 2: الغرفة ثم الحجز (id=501, local_uuid='bk-1').
        // نستخدم booking_notes لا الليالي — الليالي صفوف مشتقة تُعاد
        // بناؤها محلياً بعد السحب (BookingDerivedFieldsService) فلا
        // تصلح لإثبات ترجمة صف مُسحوب.
        final manager = await makeManager(
          _PullQueueClient([
            {
              'changes': [_noteRow('note-1', bookingId: 501)],
              'cursor': '1700000100',
              'has_more': true,
              'errors': <dynamic>[],
            },
            {
              'changes': [
                _roomRow('rm-1', roomNumber: 'RN-1', updatedAt: 1700000050),
                _bookingRow('bk-1', serverId: 501, roomNumber: 'RN-1'),
              ],
              'cursor': '1700000200',
              'has_more': false,
              'errors': <dynamic>[],
            },
          ]),
        );

        final result = await manager.sync();

        expect(result.status, SyncStatus.success);
        expect(await count('rooms'), 1);
        expect(await count('bookings'), 1);
        expect(await count('booking_notes'), 1);
        // ظلّ هوية الخادم على الأب.
        expect(await cell('bookings', 'server_id', 'bk-1'), 501);
        // ⚠️ العقد الحرج: علاقة الملاحظة تشير إلى id الحجز المحلي (1)
        // وليس إلى id الخادم (501) — هذا ما كان يكسر العلاقات قبل الإصلاح.
        expect(await cell('booking_notes', 'booking_id', 'note-1'), 1);
        expect(await pref('cf_last_pull_cursor'), 1700000200);
        expect(await pref('cf_full_sync_completed'), true);
      },
    );

    test('uuid-cache يُقدَّم على الرقم الخادمي الغريب', () async {
      // الأب موجود مسبقاً؛ الليلة تحمل uuid صحيحاً ورقم خادمياً لا
      // يطابق ظلّ server_id — الأولوية للمفتاح العالمي (uuid).
      await db.customStatement(
        'INSERT INTO rooms (local_uuid, room_number, type, price, status,'
        ' created_at, updated_at, last_modified)'
        ' VALUES (\'rm-u\', \'RN-7\', \'double\', 100.0, \'available\', 1, 1, 1)',
      );
      await db.customStatement(
        'INSERT INTO bookings (local_uuid, room_number, guest_name,'
        ' guest_phone, guest_nationality, checkin_date, status,'
        ' server_id, created_at, updated_at, last_modified)'
        ' VALUES (\'bk-real\', \'RN-7\', \'ضيف\', \'077\', \'يمني\', \'2026-09-09\','
        ' \'active\', 777, 1, 1, 1)',
      );

      final manager = await makeManager(
        _PullQueueClient([
          {
            'changes': [
              _paymentRow(
                'pay-uuid',
                bookingLocalId: 999, // رقم خادمي بلا ظلّ مطابق
                bookingUuidCache: 'bk-real',
              ),
            ],
            'cursor': '1700000300',
            'has_more': false,
            'errors': <dynamic>[],
          },
        ]),
      );

      final result = await manager.sync();

      expect(result.status, SyncStatus.success);
      expect(await cell('payments', 'booking_local_id', 'pay-uuid'), 1);
    });

    test('فضاء Appwrite القديم (server_booking_id) يُستخدم احتياطاً', () async {
      // الأب مهاجر من Appwrite: server_booking_id=42 — الابن يحمل
      // نفس القيمة ولا uuid-cache ولا ظلّ مطابق.
      await db.customStatement(
        'INSERT INTO rooms (local_uuid, room_number, type, price, status,'
        ' created_at, updated_at, last_modified)'
        ' VALUES (\'rm-u2\', \'RN-8\', \'double\', 100.0, \'available\', 1, 1, 1)',
      );
      await db.customStatement(
        'INSERT INTO bookings (local_uuid, room_number, guest_name,'
        ' guest_phone, guest_nationality, checkin_date, status,'
        ' server_booking_id, created_at, updated_at, last_modified)'
        ' VALUES (\'bk-legacy\', \'RN-8\', \'ضيف\', \'077\', \'يمني\', \'2026-09-09\','
        ' \'active\', 42, 1, 1, 1)',
      );

      final manager = await makeManager(
        _PullQueueClient([
          {
            'changes': [
              _paymentRow(
                'pay-legacy',
                bookingLocalId: 8888,
                // payments تحمل serverBookingId محلياً — فضاء Appwrite.
                serverBookingId: 42,
              ),
            ],
            'cursor': '1700000301',
            'has_more': false,
            'errors': <dynamic>[],
          },
        ]),
      );

      final result = await manager.sync();

      expect(result.status, SyncStatus.success);
      expect(await cell('payments', 'booking_local_id', 'pay-legacy'), 1);
    });

    test(
      'سلسلة الرواتب المعكوسة (دفعة ← دورة ← موظف) تُحل بترتيب الآباء',
      () async {
        final manager = await makeManager(
          _PullQueueClient([
            {
              // ترتيب الوصول معكوس عمداً: الابن الأعمق أولاً.
              'changes': [
                _salaryPaymentRow('sp-1', cycleId: 77),
                _salaryCycleRow('sc-1', employeeId: 33, serverId: 77),
                _employeeRow('emp-1', serverId: 33),
              ],
              'cursor': '1700000700',
              'has_more': false,
              'errors': <dynamic>[],
            },
          ]),
        );

        final result = await manager.sync();

        expect(result.status, SyncStatus.success);
        expect(await count('employees'), 1);
        expect(await count('salary_cycles'), 1);
        expect(await count('salary_payments'), 1);
        // دورة ترجع لمعرف الموظف المحلي (1) لا 33.
        expect(await cell('salary_cycles', 'employee_id', 'sc-1'), 1);
        // دفعة ترجع لمعرف الدورة المحلي (1) لا 77.
        expect(await cell('salary_payments', 'cycle_id', 'sp-1'), 1);
      },
    );

    test('إعادة تطبيق نفس الصف تحافظ على العلاقة المحلية المُترجمة', () async {
      final manager = await makeManager(
        _PullQueueClient([
          {
            'changes': [
              _roomRow('rm-2', roomNumber: 'RN-2', updatedAt: 1700000050),
              _bookingRow('bk-2', serverId: 502, roomNumber: 'RN-2'),
              _paymentRow(
                'pay-2',
                bookingLocalId: 502,
                bookingUuidCache: 'bk-2',
              ),
            ],
            'cursor': '1700000300',
            'has_more': false,
            'errors': <dynamic>[],
          },
        ]),
      );
      expect((await manager.sync()).status, SyncStatus.success);
      expect(await cell('payments', 'booking_local_id', 'pay-2'), 1);

      // دورة ثانية: الخادم أعاد نفس الليلة (idempotent) — العلاقة
      // المحلية لا تُفسد بالرقم الخادمي من جديد.
      manager.configureForTesting(
        database: db,
        httpClient: _PullQueueClient([
          {
            'changes': [
              _paymentRow(
                'pay-2',
                bookingLocalId: 502,
                bookingUuidCache: 'bk-2',
              ),
            ],
            'cursor': '1700000400',
            'has_more': false,
            'errors': <dynamic>[],
          },
        ]),
        token: 'test-token',
      );
      final second = await manager.sync();

      expect(second.status, SyncStatus.success);
      expect(await count('payments'), 1);
      expect(await cell('payments', 'booking_local_id', 'pay-2'), 1);
    });

    test(
      'مؤشر الصندوق الثانوي غير القابل للحل يُصبح NULL ولا يُعطّل السحب',
      () async {
        final manager = await makeManager(
          _PullQueueClient([
            {
              'changes': [
                _roomRow('rm-9', roomNumber: 'RN-9', updatedAt: 1700000050),
                _bookingRow('bk-9', serverId: 9, roomNumber: 'RN-9'),
                _paymentRow(
                  'pay-1',
                  bookingLocalId: 9,
                  bookingUuidCache: 'bk-9',
                  cashTransactionLocalId: 888,
                ),
              ],
              'cursor': '1700000400',
              'has_more': false,
              'errors': <dynamic>[],
            },
          ]),
        );

        final result = await manager.sync();

        // الدفعة نفسها سليمة وعلاقتها بالحجز مُترجمة.
        expect(result.status, SyncStatus.success);
        expect(await count('payments'), 1);
        expect(await cell('payments', 'booking_local_id', 'pay-1'), 1);
        // مؤشر الصندوق بلا مفتاح عالمي على السلك — NULL بدل قيمة
        // خادمية مكذوبة، والدورة لا تُعطَّل لمجرد مؤشر ثانوي.
        expect(
          await cell('payments', 'cash_transaction_local_id', 'pay-1'),
          isNull,
        );
      },
    );
  });

  group('يتيم بلا أب = فشل صريح وتجميد المؤشر (لا نجاح مع ناقص)', () {
    test('ليلة بلا حجز: الدورة تفشل والمؤشر لا يتحرك والصف لا يُدرج', () async {
      final manager = await makeManager(
        _PullQueueClient([
          {
            'changes': [
              _nightRow('n-orphan', bookingLocalId: 424242),
            ],
            'cursor': '1700000300',
            'has_more': false,
            'errors': <dynamic>[],
          },
        ]),
      );

      final result = await manager.sync();

      expect(result.status, SyncStatus.failed);
      expect(result.errorMessage, contains('unresolvable'));
      expect(result.errorMessage, contains('booking_nights/n-orphan'));
      // ⚠️ العقد: لا checkpoint ولا علامة full sync إطلاقاً — المؤشر
      // مجمد عند نقطة البداية حتى يُشفى الخادم/يصل الأب.
      expect(await pref('cf_last_pull_cursor'), isNull);
      expect(await pref('cf_full_sync_completed'), isNull);
      expect(manager.failedCollectionsInLastSync, contains('pull'));
      // الصف اليتيم لا يُدرج بعلاقة مكذوبة.
      expect(await count('booking_nights'), 0);
    });
  });
}
