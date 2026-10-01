// ═══════════════════════════════════════════════════════════════
//  bookings_outbox_pull_diagnosis_test.dart — تشخيص قاطع لسجلات
//  outbox الخاصة بكيان bookings أثناء/بعد سحب الدلتا (لا تخمين)
//
//  السؤال: «عند سحب تغييرات bookings تُنشأ سجلات outbox لماذا؟»
//
//  الخريطة الساكنة المكتملة لكُتّاب outbox ذات entity='bookings':
//   W1 BookingsDao (CRUD محلي للمستخدم) — بالتصميم.
//   W2 BookingDerivedFieldsService._refreshForBookingInTransaction:153
//      — فقط عند enqueueOutbox=true (افتراضي الشاشات المحلية).
//   W3 BookingDerivedFieldsService._promoteProvisionalBooking:233
//      — بلا شرط enqueueOutbox إطلاقاً (كتابة غير مشروطة!).
//   W4 EnhancedBookingCalculationService._replaceBookingNights:540
//      — فقط عند enqueueOutbox=true.
//   W5 recalculateAfterSync (تعريفان) — كود ميت: صفر مستدعٍ في lib/.
//   W6 المدير 3245 — دمج تعارض متزامن P0-F (يتطلب تعديلاً محلياً معلقاً).
//   W7 المدير 3716 — استبدال حذفي (يتطلب عملية محلية معلقة).
//   محيّد: bookings_adapter.dart — مجرد محوّل JSON بلا أي outbox.
//   محيّد: المدير 1443/1529 — قراءة outbox في طور الرفع لا كتابة.
//
//  مسار السحب: pull → touchedEntities ∩ {bookings,payments,...}
//  → _refreshDerivedAfterPull (المدير 2767/4035)
//  → refreshAllActiveBookings(enqueueOutbox:false) — لكن W3 يكتب
//  outbox رغم ذلك عند تحقق: حجز «مؤقت» نشط + الوقت بعد 14:01.
//
//  السيناريوهات المُثبتة:
//   T6 سحب دلتا يحمل حجزاً «مؤقتاً» قبل 14:01: صفر outbox والليالي
//      تُبنى — السحب نفسه نظيف.
//   T7 نفس استدعاء السحب (refreshAllActiveBookings، enqueueOutbox:false)
//      مع now بعد 14:01: يظهر سجل outbox واحد bookings/update —
//      التثبيت المحلي للحجز المؤقت (ترقية حالة حقيقية تُبث للأجهزة).
//   T8 نفس الاستدعاء قبل 14:01: صفر outbox والحالة تبقى مؤقتة.
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io' show gzip;

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marina_hotel_mobile/services/booking_derived_fields_service.dart';
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/utils/hotel_time_engine.dart';
import 'package:marina_hotel_mobile/utils/time.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════
//  محاكي Worker أمين (مرآة worker/src/sync.ts) — سحب فقط هنا
// ═══════════════════════════════════════════════════════════════

class _StatefulWorker extends http.BaseClient {
  _StatefulWorker(this.authDeviceId);

  final rows = <String, Map<String, Map<String, dynamic>>>{};
  int serverClock = 1750000000;
  final String authDeviceId;

  void seedServerBooking(String uuid, String status, int stamp) {
    rows.putIfAbsent('bookings', () => {})[uuid] = {
      'id': 501,
      'local_uuid': uuid,
      'room_number': '101',
      'guest_name': 'ضيف السحب',
      'guest_phone': '0500000000',
      'guest_nationality': 'يمني',
      'checkin_date': '2026-09-27T15:00:00.000',
      'checkout_date': '2026-09-30T14:00:00.000',
      'actual_checkout': null,
      'status': status,
      'discount': 0,
      'discount_type': 'nightly',
      'expected_nights': 1,
      'notes': null,
      'created_at': stamp,
      'updated_at': stamp,
      'last_modified': stamp,
      'version': 1,
      'origin': 'server',
      'vector_clock': '{"device-A":1}',
      'device_id': 'device-A', // جهاز آخر → لا يُستبعد بفلتر الصدى
      'deleted_at': null,
    };
  }

  Future<http.Response> _handlePull(http.Request request) async {
    final cursor = int.parse(request.url.queryParameters['cursor'] ?? '0');
    final found = <Map<String, dynamic>>[];
    rows.forEach((entity, table) {
      table.forEach((uuid, row) {
        final updated = (row['updated_at'] as int?) ?? 0;
        if (updated <= cursor) return;
        if (row['device_id'] == authDeviceId) return; // فلتر الصدى
        found.add({...row, '_entity': entity});
      });
    });
    return _json({
      'changes': found,
      'cursor': found.isEmpty
          ? '$cursor'
          : '${found.map((r) => r['updated_at'] as int).reduce((a, b) => a > b ? a : b)}',
      'has_more': false,
      'remaining': 0,
      'errors': <dynamic>[],
      'server_time': serverClock,
    });
  }

  final pushLog = <Map<String, dynamic>>[];

  Future<http.Response> _handlePush(http.Request request) async {
    final raw = request.bodyBytes;
    final isGzip = raw.length >= 2 && raw[0] == 0x1f && raw[1] == 0x8b;
    final body =
        jsonDecode(isGzip ? utf8.decode(gzip.decode(raw)) : utf8.decode(raw))
            as Map<String, dynamic>;
    pushLog.add(body);
    return _json({
      'results': [
        for (final op in (body['operations'] as List)
            .cast<Map<String, dynamic>>())
          {'idempotencyKey': op['idempotencyKey'], 'success': true},
      ],
    });
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' &&
        request.url.path.endsWith('/api/sync/push')) {
      return _awaited(await _handlePush(request as http.Request));
    }
    if (request.method == 'GET' &&
        request.url.path.endsWith('/api/sync/pull')) {
      return _awaited(await _handlePull(request as http.Request));
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"error":"unexpected-path"}')),
      404,
      headers: {'content-type': 'application/json'},
    );
  }

  static http.StreamedResponse _awaited(http.Response r) =>
      http.StreamedResponse(
        Stream.value(r.bodyBytes),
        r.statusCode,
        headers: r.headers,
      );
}

http.Response _json(Map<String, dynamic> body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

// ═══════════════════════════════════════════════════════════════
//  أدوات القياس
// ═══════════════════════════════════════════════════════════════

Future<int> outboxCount(AppDatabase db) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM outbox')
      .getSingle();
  return row.read<int>('c');
}

Future<List<Map<String, dynamic>>> outboxRows(AppDatabase db) async {
  final rows = await db.customSelect(
    'SELECT entity, op, local_uuid, payload FROM outbox',
  ).get();
  return [
    for (final r in rows)
      {
        'entity': r.data['entity'],
        'op': r.data['op'],
        'payload': r.data['payload'] == null
            ? null
            : jsonDecode(r.data['payload'] as String),
      },
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _StatefulWorker worker;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
      'cf_device_id': 'bookings-diag-device',
    });
    // ✅ (2026-09-30) عزل حتمي: vector-clock bump في OutboxDao يُتخطى
    // بصمت عندما يكون معرّف الجهاز الساكن فارغاً — T7 كان يفشل عندما
    // يُنفَّذ قبل أي اختبار يضبطه (T6 عبر makeManager) لأن ترتيب seed
    // عشوائي. الضبط هنا يجعل كل اختبار مكتفياً بذاته.
    CloudflareSyncManager.setStaticDeviceId('bookings-diag-device');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    worker = _StatefulWorker('bookings-diag-device');
  });

  tearDown(() async {
    await db.close();
  });

  Future<CloudflareSyncManager> makeManager() async {
    final manager = CloudflareSyncManager();
    manager.reset();
    manager.configureForTesting(
      database: db,
      httpClient: worker,
      token: 'test-token',
      deviceId: 'bookings-diag-device',
      fullSyncCompleted: true,
    );
    return manager;
  }

  /// الأب أولاً — نفس ترتيب السحب الإنتاجي (الآباء قبل الأبناء،
  /// المدير 3463): قيد FK على bookings.room_number يتطلب الغرفة
  Future<void> seedLocalRoom(String number) async {
    final now = Time.nowEpoch();
    await db.into(db.rooms).insert(
          RoomsCompanion(
            localUuid: d.Value('room-$number'),
            roomNumber: d.Value(number),
            type: const d.Value('standard'),
            price: const d.Value(15000),
            status: const d.Value('شاغرة'),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            version: const d.Value(1),
            origin: const d.Value('server'),
          ),
        );
  }

  group('تشخيص outbox الخاص بـ bookings حول سحب الدلتا', () {
    test(
      'T6: سحب حجز «مؤقت» قبل حدّ 14:01 → صفر outbox والليالي تُبنى',
      () async {
        worker.seedServerBooking('bk-pull-001', 'مؤقت', 1750000100);
        await seedLocalRoom('101'); // الأب قبل الابن — ترتيب السحب الإنتاجي
        final manager = await makeManager();

        // لقطة الساعة قبل السحب: المدير يستدعي المشتق بعد السحب بساعة
        // الحائط الحقيقية (refreshAllActiveBookings بلا now) — فسلوك
        // الترقية W3 يتحدد بساعة التشغيل نفسها، ولذلك يفرع توقع الحالة
        // والعدّاد معاً على هذه اللقطة (كان السطران متناقضين سابقاً:
        // العدّاد يتفرع والحالة لا — فانفجر الاختبار بعد 14:01).
        final afterCutoff = HotelTimeEngine.isAfterCutoff(DateTime.now());

        await manager.sync(push: false); // سحب دلتا فقط — عزل أثر السحب

        // الحجز وصل محلياً (يحرس ضد نجاح زيف بسبب فشل تطبيق صامت)
        final local = await db.customSelect(
          "SELECT id, status FROM bookings WHERE local_uuid = 'bk-pull-001'",
        ).getSingleOrNull();
        expect(local, isNotNull, reason: 'الحجز المسحوب يجب أن يُطبَّق محلياً');
        expect(
          local!.data['status'],
          afterCutoff ? 'محجوزة' : 'مؤقت',
          reason: afterCutoff
              ? 'بعد 14:01: المشتق بعد السحب (ساعة حقيقية) يرقّى المؤقت '
                  '→ محجوزة — نفس مصدر فرع العدّاد أدناه (W3)'
              : 'قبل 14:01: لا ترقية → الحالة تبقى مؤقت',
        );

        // إثبات أن إعادة البناء المشتق بعد السحب اشتغلت فعلاً (الأسلاك
        // بين السحب و _refreshDerivedAfterPull تعمل): الليالي بُنيت
        final nights = await db.customSelect(
          'SELECT COUNT(*) AS c FROM booking_nights WHERE booking_local_id = ?',
          variables: [d.Variable<int>(local.data['id'] as int)],
        ).getSingle();
        expect(nights.data['c'] as int, greaterThan(0),
            reason: 'إعادة البناء المشتق بعد السحب يجب أن تكون قد شغلت');

        final count = await outboxCount(db);
        // ignore: avoid_print
        print('── T6 وقت التشغيل المحلي: ${DateTime.now()} '
            '(بعد الحدّ: $afterCutoff) ──');
        for (final r in await outboxRows(db)) {
          // ignore: avoid_print
          print('── T6 outbox: ${r['entity']}/${r['op']}');
        }

        if (!afterCutoff) {
          expect(count, 0,
              reason: 'قبل 14:01: لا ترقية مؤقت → السحب + المشتق صفر outbox');
        } else {
          expect(count, 1,
              reason: 'بعد 14:01: الترقية المحلية للحجز المؤقت تكتب سجل '
                  'outbox واحد (bookings/update) — سلوك الترقية لا السحب');
        }
      },
    );

    test(
      'T7: استدعاء السحب نفسه (enqueueOutbox:false) بعد 14:01 → سجل '
      'bookings واحد من الترقية المحلية رغم enqueueOutbox:false',
      () async {
        // حجز محلي «مؤقت» نشط (نفس ما ينتجه السحب)
        final now = Time.nowEpoch();
        await seedLocalRoom('102');
        await db.into(db.bookings).insert(
              BookingsCompanion(
                localUuid: const d.Value('bk-local-001'),
                roomNumber: const d.Value('102'),
                guestName: const d.Value('ضيف محلي'),
                guestPhone: const d.Value('0555555555'),
                guestNationality: const d.Value('يمني'),
                checkinDate: const d.Value('2026-09-27T15:00:00.000'),
                checkoutDate: const d.Value('2026-09-30T14:00:00.000'),
                status: const d.Value('مؤقت'),
                discount: const d.Value(0),
                discountType: const d.Value('nightly'),
                expectedNights: const d.Value(1),
                createdAt: d.Value(now),
                updatedAt: d.Value(now),
                lastModified: d.Value(now),
                version: const d.Value(1),
                origin: const d.Value('server'),
              ),
            );

        // نفس التوقيع الذي يستدعيه المدير بعد السحب (المدير 4040) —
        // الفرق الوحيد: now قابل للحقن هنا لجعل الاختبار حتمياً
        await BookingDerivedFieldsService(db).refreshAllActiveBookings(
          now: DateTime(2026, 9, 28, 15, 30), // بعد 14:01
          enqueueOutbox: false,
        );

        final rows = await outboxRows(db);
        for (final r in rows) {
          // ignore: avoid_print
          print('── T7 outbox: ${r['entity']}/${r['op']} '
              'status=${(r['payload'] as Map?)?['status']}');
        }

        expect(rows.length, 1,
            reason: 'الترقية المحلية (مؤقت→محجوزة) تكتب outbox رغم '
                'enqueueOutbox:false — هذه هي الكتابة غير المشروطة W3 '
                '(_promoteProvisionalBooking:233) الوحيدة في مسار ما بعد السحب');
        expect(rows.single['entity'], 'bookings');
        expect(rows.single['op'], 'update');
        expect((rows.single['payload'] as Map)['status'], 'محجوزة',
            reason: 'الحمولة تحمل الحالة الجديدة — تغيير دلالي حقيقي '
                'يستحق البث للأجهزة الأخرى');

        // الحالة المحلية ترقّت وساعة الصف bumped → الدفع مكتمل الأهلية
        final row = await db.customSelect(
          "SELECT status, vector_clock FROM bookings WHERE local_uuid = 'bk-local-001'",
        ).getSingle();
        expect(row.data['status'], 'محجوزة');
        expect(row.data['vector_clock'], isNot('{}'),
            reason: 'merge رفع ساعة متجه الصف → الدفع لن يُرفض كقديم');
      },
    );

    test(
      'T8: نفس الاستدعاء قبل 14:01 → صفر outbox والحالة تبقى مؤقتة',
      () async {
        final now = Time.nowEpoch();
        await seedLocalRoom('103');
        await db.into(db.bookings).insert(
              BookingsCompanion(
                localUuid: const d.Value('bk-local-002'),
                roomNumber: const d.Value('103'),
                guestName: const d.Value('ضيف محلي ٢'),
                guestPhone: const d.Value('0544444444'),
                guestNationality: const d.Value('يمني'),
                checkinDate: const d.Value('2026-09-27T15:00:00.000'),
                checkoutDate: const d.Value('2026-09-30T14:00:00.000'),
                status: const d.Value('مؤقت'),
                discount: const d.Value(0),
                discountType: const d.Value('nightly'),
                expectedNights: const d.Value(1),
                createdAt: d.Value(now),
                updatedAt: d.Value(now),
                lastModified: d.Value(now),
                version: const d.Value(1),
                origin: const d.Value('server'),
              ),
            );

        await BookingDerivedFieldsService(db).refreshAllActiveBookings(
          now: DateTime(2026, 9, 28, 10), // قبل 14:01
          enqueueOutbox: false,
        );

        expect(await outboxCount(db), 0,
            reason: 'بلا ترقية: المشتق كله بلا outbox (enqueueOutbox:false '
                'محترم في كل الكتابات ما عدا الترقية)');
        final row = await db.customSelect(
          "SELECT status FROM bookings WHERE local_uuid = 'bk-local-002'",
        ).getSingle();
        expect(row.data['status'], 'مؤقت');
      },
    );
  });
}
