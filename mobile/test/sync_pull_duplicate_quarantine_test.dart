// ═══════════════════════════════════════════════════════════════
//  sync_pull_duplicate_quarantine_test.dart — 2026-09-09
//
//  إصلاحات تقرير أخطاء جهاز حقيقي (3 أعطال متزامنة):
//
//  1) «398 apply-failure on deferred retry: SqliteException(2067)
//     UNIQUE(booking_local_id, hotel_day_key)» — جذر مؤكد على D1:
//     381 مجموعة مكررة منطقياً (سطور restore نسخة احتياطية بمفاتيح
//     backup_* مقابل إعادة بناء محلية). العقد الجديد: مسبار المفتاح
//     الطبيعي قبل INSERT — النسخة المكررة تُدمج LWW في الصف المحلي
//     ولا تُدرج ثانية، والدورة تكمل.
//
//  2) «107 record(s) with unresolvable parent relations:
//     salary_withdrawals/...» — جذر مؤكد: استبعاد صفوف الجهاز نفسه
//     (exclude_device) يمنع الجهاز أبداً من تعلّم ظلّ server_id
//     لصفوفه هو، فتعجز سحبات روابعه المسحوبة عن حلّ الأب. العقد
//     الجديد: السحب الكامل لا يستبعد صفوف الجهاز؛ الدلتا تستبعد.
//
//  3) تجميد المؤشر إلى الأبد: تعارضات UNIQUE كانت ترمي الدورة بلا
//     سلّم حجر (الحجر يغطي المؤجَّل فقط). العقد الجديد: المتعارض
//     يمر بالسلّم نفسه — فرصة عادلة ثم عزل ويتقدم المؤشر.
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
  'origin': 'server',
  'vector_clock': '{}',
  'device_id': device,
};

Map<String, dynamic> _employeeRow(
  String uuid, {
  int? serverId,
  int updatedAt = 1700000500,
}) => {
  ..._syncFields(uuid, updatedAt, serverId: serverId),
  'name': 'موظف عقد التكرار',
  'basic_salary': 1000.0,
  'position': 'موظف',
  'status': 'active',
};

Map<String, dynamic> _salaryCycleRow(
  String uuid, {
  required int employeeId,
  int updatedAt = 1700000600,
}) => {
  ..._syncFields(uuid, updatedAt),
  'employee_id': employeeId,
  'cycle_key': '2026-09',
  'expected_amount': 1000,
  'actual_paid': 0,
  'remaining_amount': 1000,
  'status': 'draft',
};

Map<String, dynamic> _withdrawalRow(
  String uuid, {
  required int employeeId,
  int updatedAt = 1700000800,
}) => {
  ..._syncFields(uuid, updatedAt),
  'employee_id': employeeId,
  'amount': 250.0,
  'withdraw_date': '2026-09-09',
  'hotel_day_key': '2026-09-09',
  'withdrawal_type': 'cash',
  'description': 'سحب من عقد التكرار',
};

Map<String, dynamic> _nightRow(
  String uuid, {
  required int bookingLocalId,
  String? bookingUuidCache,
  int updatedAt = 1700000300,
  double finalRate = 100.0,
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
  'final_rate': finalRate,
  if (bookingUuidCache != null) 'booking_uuid_cache': bookingUuidCache,
};

/// يخدم الصفحات بالترتيب ويسجّل كل طلب URL للتحقق التعاقدي.
class _RecordingQueueClient extends http.BaseClient {
  _RecordingQueueClient(this.pages);

  final List<Map<String, dynamic>> pages;
  final urls = <Uri>[];
  int _served = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    urls.add(request.url);
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

/// يخدم الصفحات دورياً (يعيد من الأول بعد النهاية) — لمحاكاة دورات
/// سحب متتالية يعيد الخادم فيها نفس النافذة (مؤشر مجمّد).
class _CyclicQueueClient extends http.BaseClient {
  _CyclicQueueClient(this.pages);
  final List<Map<String, dynamic>> pages;
  int _served = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'GET' || pages.isEmpty) {
      throw StateError('unexpected ${request.method} ${request.url}');
    }
    final page = pages[_served % pages.length];
    _served++;
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(page))),
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

  Future<CloudflareSyncManager> makeManager(
    http.Client client, {
    String deviceId = 'dedup-contract-device',
    bool fullSyncCompleted = false,
    int lastPullCursor = 0,
  }) async {
    final manager = CloudflareSyncManager();
    manager.reset();
    manager.configureForTesting(
      database: db,
      httpClient: client,
      token: 'test-token',
      deviceId: deviceId,
      fullSyncCompleted: fullSyncCompleted,
      lastPullCursor: lastPullCursor,
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

  Future<Object?> cell(
    String table,
    String column, {
    String byUuid = '',
    int byId = -1,
  }) async {
    final row = await db
        .customSelect(
          byId > 0
              ? 'SELECT $column AS v FROM $table WHERE id = ?'
              : 'SELECT $column AS v FROM $table WHERE local_uuid = ?',
          variables: [Variable(byId > 0 ? byId : byUuid)],
        )
        .getSingleOrNull();
    return row?.data['v'];
  }

  Future<void> seedBookingWithLocalNight() async {
    // حالة غير نشطة ('completed') — إعادة بناء المشتقات بعد السحب
    // (refreshAllActiveBookings) تعالج الحجوزات النشطة فقط، فلا تعيد
    // كتابة الليلة المدمجة وتُبطل قيود الاختبار.
    await db.customStatement(
      "INSERT INTO rooms (local_uuid, room_number, type, price, status,"
      " created_at, updated_at, last_modified)"
      " VALUES ('rm-u', 'RN-7', 'double', 100.0, 'available', 1, 1, 1)",
    );
    await db.customStatement(
      "INSERT INTO bookings (local_uuid, room_number, guest_name,"
      " guest_phone, guest_nationality, checkin_date, status, server_id,"
      " created_at, updated_at, last_modified)"
      " VALUES ('bk-1', 'RN-7', 'ضيف', '077', 'يمني', '2026-09-09',"
      " 'completed', 501, 1, 1, 1)",
    );
    await db.customStatement(
      "INSERT INTO booking_nights (booking_local_id, hotel_day_key,"
      " night_start, night_end, nightly_rate, sequence, base_rate,"
      " adjustment, final_rate, local_uuid, created_at, updated_at,"
      " last_modified, origin)"
      " VALUES (1, '2026-09-09', '2026-09-09 15:00', '2026-09-10 12:00',"
      " 100.0, 1, 100.0, 0.0, 100.0, 'n-local', 100, 100, 100, 'local')",
    );
  }

  group('الإصلاح 1: النسخة المكررة منطقياً تُدمج LWW ولا تُفشل الدورة', () {
    test(
      'نسخة خادمية أحدث تُدمج في الصف المحلي — صف واحد وهوية محلية',
      () async {
        await seedBookingWithLocalNight();
        final manager = await makeManager(
          _RecordingQueueClient([
            {
              'changes': [
                // local_uuid مختلف + نفس المفتاح الطبيعي (حجز 1، ليلة
                // 2026-09-09) بعد الترجمة عبر uuid-cache — وأحدث من المحلي.
                _nightRow(
                  'n-server-copy',
                  bookingLocalId: 424242, // رقم خادمي غريب — uuid-cache يفوز
                  bookingUuidCache: 'bk-1',
                  updatedAt: 1700000300,
                  finalRate: 150.0,
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
        // ⚠️ العقد: صف واحد فقط — لم يُدرج ثانٍ ولا رمى UNIQUE.
        expect(await count('booking_nights'), 1);
        // الهوية المحلية بقيت (n-local) وبياناتها دُمجت (الأحدث فاز).
        expect(
          await cell('booking_nights', 'final_rate', byUuid: 'n-local'),
          150.0,
        );
        expect(
          await cell('booking_nights', 'updated_at', byUuid: 'n-local'),
          1700000300,
        );
        expect(
          await cell('booking_nights', 'id', byUuid: 'n-local'),
          isNotNull,
        );
        // النسخة الخادمية لم تُنشأ كهوية جديدة.
        expect(
          await cell('booking_nights', 'id', byUuid: 'n-server-copy'),
          isNull,
        );
        expect(await pref('cf_last_pull_cursor'), 1700000300);
      },
    );

    test('نسخة أقدم من المحلي تُتخطى وتبقى بيانات المحلي الأحدث', () async {
      await seedBookingWithLocalNight();
      final manager = await makeManager(
        _RecordingQueueClient([
          {
            'changes': [
              _nightRow(
                'n-old-copy',
                bookingLocalId: 424242,
                bookingUuidCache: 'bk-1',
                updatedAt: 50, // أقدم بكثير من المحلي (100)
                finalRate: 999.0,
              ),
            ],
            'cursor': '1700000310',
            'has_more': false,
            'errors': <dynamic>[],
          },
        ]),
      );

      final result = await manager.sync();

      expect(result.status, SyncStatus.success);
      expect(await count('booking_nights'), 1);
      expect(
        await cell('booking_nights', 'final_rate', byUuid: 'n-local'),
        100.0,
      );
      expect(
        await cell('booking_nights', 'updated_at', byUuid: 'n-local'),
        100,
      );
      expect(await pref('cf_last_pull_cursor'), 1700000310);
    });

    test('إعادة سحب نفس النسخة في دلتا لاحقة تبقى idempotent', () async {
      await seedBookingWithLocalNight();
      final duplicatePage = {
        'changes': [
          _nightRow(
            'n-server-copy',
            bookingLocalId: 424242,
            bookingUuidCache: 'bk-1',
            updatedAt: 1700000300,
            finalRate: 150.0,
          ),
        ],
        'cursor': '1700000300',
        'has_more': false,
        'errors': <dynamic>[],
      };
      final manager = await makeManager(_RecordingQueueClient([duplicatePage]));
      expect((await manager.sync()).status, SyncStatus.success);
      expect(await count('booking_nights'), 1);

      // دورة دلتا ثانية: نفس الصفحة (echo خادمي) — لا صف جديد ولا فشل.
      // الصفحة الأولى يستهلكها مسح الحذفيات لمرة واحدة (tombstones_only).
      final delta = await makeManager(
        _RecordingQueueClient([
          {
            'changes': <dynamic>[],
            'cursor': '0',
            'has_more': false,
            'errors': <dynamic>[],
          },
          duplicatePage,
        ]),
        fullSyncCompleted: true,
        lastPullCursor: 1700000300,
      );
      final second = await delta.sync();

      expect(second.status, SyncStatus.success);
      expect(await count('booking_nights'), 1);
      expect(
        await cell('booking_nights', 'final_rate', byUuid: 'n-local'),
        150.0,
      );
    });
  });

  group(
    'الإصلاح 2: السحب الكامل لا يستبعد صفوف الجهاز (تعلّم ظلّ server_id)',
    () {
      test('السحب الكامل يجلب صفوف الجهاز فيُبنى الظلّ ويُحلّ الابن', () async {
        // مشهد الجهاز الحقيقي: موظف رفعه هذا الجهاز (device_id يطابق)،
        // وسحوبة راتب من جهاز آخر تحمل employee_id بفضاء D1 — كانت
        // تُؤجل إلى الأبد لأن الموظف المستبعد لا يُعيد تعليم ظلّه.
        final client = _RecordingQueueClient([
          {
            'changes': [_withdrawalRow('sw-1', employeeId: 55)],
            'cursor': '1700000800',
            'has_more': true,
            'errors': <dynamic>[],
          },
          {
            'changes': [
              // صف الجهاز نفسه — كان exclude_device يمنع وصوله إطلاقاً.
              _employeeRow('emp-own', serverId: 55),
            ],
            'device_row_of_own_device': 'x',
            'cursor': '1700000810',
            'has_more': false,
            'errors': <dynamic>[],
          },
        ]);
        final manager = await makeManager(client);

        final result = await manager.sync();

        expect(result.status, SyncStatus.success);
        // ⚠️ العقد التعاقدي: طلبات السحب الكامل بلا exclude_device.
        final pullUrls = client.urls
            .where((u) => u.path.endsWith('/api/sync/pull'))
            .where((u) => !u.queryParameters.containsKey('tombstones_only'))
            .toList();
        expect(pullUrls, isNotEmpty);
        expect(
          pullUrls.every(
            (u) => !u.queryParameters.containsKey('exclude_device'),
          ),
          isTrue,
          reason: 'السحب الكامل يجب أن يشمل صفوف الجهاز نفسه',
        );
        // الظلّ تعلّم من صف الجهاز، والسحوبة حُلّت إلى الموظف المحلي.
        expect(await cell('employees', 'server_id', byUuid: 'emp-own'), 55);
        expect(await count('salary_withdrawals'), 1);
        expect(
          await cell('salary_withdrawals', 'employee_id', byUuid: 'sw-1'),
          1,
        );
        expect(await pref('cf_full_sync_completed'), true);
      });

      test(
        'الدلتا تستمر باستبعاد الصدى (exclude_device يبقى في النافذة الخفيفة)',
        () async {
          final fullClient = _RecordingQueueClient([
            {
              'changes': <dynamic>[],
              'cursor': '1700000900',
              'has_more': false,
              'errors': <dynamic>[],
            },
          ]);
          final manager = await makeManager(fullClient);
          expect((await manager.sync()).status, SyncStatus.success);

          // الصفحة الأولى يستهلكها مسح الحذفيات لمرة واحدة (tombstones_only
          // يطلق بعد اكتمال full sync) — ثم الصفحة الفعلية للدلتا.
          final deltaClient = _RecordingQueueClient([
            {
              'changes': <dynamic>[],
              'cursor': '0',
              'has_more': false,
              'errors': <dynamic>[],
            },
            {
              'changes': <dynamic>[],
              'cursor': '1700000910',
              'has_more': false,
              'errors': <dynamic>[],
            },
          ]);
          final deltaManager = await makeManager(
            deltaClient,
            fullSyncCompleted: true,
            lastPullCursor: 1700000900,
          );
          // نفس معرّف الجهاز — عقد configureForTesting يستعيده صراحة.
          final second = await deltaManager.sync();

          expect(second.status, SyncStatus.success);
          final pullUrls = deltaClient.urls
              .where((u) => u.path.endsWith('/api/sync/pull'))
              .where((u) => !u.queryParameters.containsKey('tombstones_only'))
              .toList();
          expect(pullUrls, isNotEmpty);
          expect(
            pullUrls.every(
              (u) =>
                  u.queryParameters['exclude_device'] ==
                  'dedup-contract-device',
            ),
            isTrue,
            reason: 'الدلتا تستبعد صفوف الجهاز (خطة 2.5) — خفة النافذة',
          );
        },
      );
    },
  );

  group('الإصلاح 3: تعارض UNIQUE يمر بسلّم الحجر ولا يجمّد المؤشر للأبد', () {
    test('دورتان فرصة عادلة ثم عزل واكتمال full sync — الصف المحلي سليم', () async {
      // محلياً: موظف بلا ظلّ + دورة لشهر 2026-09.
      await db.customStatement(
        "INSERT INTO employees (local_uuid, name, basic_salary, position,"
        " status, created_at, updated_at, last_modified, origin)"
        " VALUES ('emp-1', 'موظف', 1000.0, 'موظف', 'active', 1, 1, 1, 'local')",
      );
      await db.customStatement(
        "INSERT INTO salary_cycles (employee_id, cycle_key, expected_amount,"
        " actual_paid, remaining_amount, status, local_uuid, created_at,"
        " updated_at, last_modified, origin)"
        " VALUES (1, '2026-09', 1000, 0, 1000, 'draft', 'sc-local',"
        " 1, 1, 1, 'local')",
      );

      // الخادم: نسخة مكررة منطقياً (local_uuid جديد على نفس
      // employee_id+cycle_key بعد حلّ الموظف) — كانت ترمي SqliteException(2067)
      // في كل دورة بلا سلّم حجر = تجميد أبدِ.
      final cyclic = _CyclicQueueClient([
        {
          'changes': [_salaryCycleRow('sc-dup', employeeId: 55)],
          'cursor': '1700000600',
          'has_more': true,
          'errors': <dynamic>[],
        },
        {
          'changes': [_employeeRow('emp-1', serverId: 55)],
          'cursor': '1700000610',
          'has_more': false,
          'errors': <dynamic>[],
        },
      ]);
      final manager = await makeManager(cyclic);

      // الدورة 1: التأجيل ثم الاصطدام في إعادة المحاولة — فشل معلن.
      final first = await manager.sync();
      expect(first.status, SyncStatus.failed);
      expect(first.errorMessage, contains('unique-key conflicts'));
      expect(
        await pref('cf_last_pull_cursor'),
        isNull,
        reason: 'المؤشر لا يتحرك أثناء فترة الفرصة العادلة',
      );

      // الدورة 2: الظلّ جاهز — الاصطدام من التطبيق الأولي — فشل ثانٍ.
      final second = await manager.sync();
      expect(second.status, SyncStatus.failed);

      // الدورة 3: تجاوزت العتبة (3) — عُزل والمؤشر تقدّم واكتمل full sync.
      final third = await manager.sync();
      expect(third.status, SyncStatus.success);
      expect(
        await count('salary_cycles'),
        1,
        reason: 'الصف المحلي الوحيد باقٍ — النسخة المعزولة لم تُدرج',
      );
      expect(await cell('salary_cycles', 'local_uuid', byId: 1), 'sc-local');
      expect(await pref('cf_last_pull_cursor'), 1700000610);
      expect(await pref('cf_full_sync_completed'), true);
      // العدّاد وصل العتبة على هوية النسخة المكررة تحديداً.
      final countsRaw = await pref('cf_pull_orphan_block_counts');
      expect(countsRaw.toString(), contains('salary_cycles/sc-dup'));
    });
  });
}
