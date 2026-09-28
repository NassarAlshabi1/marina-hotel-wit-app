// ═══════════════════════════════════════════════════════════════
//  outbox_500_push_drain_test.dart — إثبات تجريبي لسؤال المستخدم:
//  «زر رفع التغييرات في dashboard — هل يعمل جيداً حتى لو كان هناك
//   500 سجل في outbox؟»
//
//  المنهجية: نفس منهجية ملفات الإثبات السابقة (raw_d1_backup_upload
//  _outbox_test / outbox_delta_pull_diagnosis_test) — تشغيل الكود
//  الإنتاجي الحقيقي (OutboxDao.merge عبر RoomsDao.insertOne →
//  CloudflareSyncManager.pushLocalChanges — نفس استدعاء الزر حرفياً
//  في dashboard_sync_button.dart:612) أمام محاكي Worker أمين يطبق
//  عقد /api/sync/push نفسه (gzip، نتائج لكل عملية، idempotency
//  replay، رفض validation_error بـ status محدد — عقد fix M4).
//  لا إعادة تنفيذ للمنطق ولا تخمين — قياس السلوك الفعلي.
//
//  السيناريوهات:
//   A) 500 سجل حقيقي (RoomsDao.insertOne ×500) + ضغطة زر واحدة:
//      المتوقع — تفريغ كامل، 5 طلبات HTTP (سقف 100/دفعة)، كل دفعة
//      ≤ 100 عملية، العدّاد قبل الرفع يرى 500 (نفس استعلام الزر).
//   B) 497 سليمة + 3 سموم (رفض خادمي validation_error دائم):
//      المتوقع — 497 تُسلَّم في نفس الضغطة، السموم 3 تنتهي dead-letter
//      بلا تعطيل التفريغ ولا حلقة لا نهائية (عزل per-op).
//   C) الخادم يرجع 503 لكل الدفعات: المتوقع — pushLocalChanges يرمي
//      (زر أحمر + إعادة)، الـ 500 تبقى pending بلا فقد، محاولة واحدة
//      ثم توقف (لا عضّ على حد الطلبات).
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io' show gzip;

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/daos/rooms_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════
//  محاكي Worker أمين — نفس عقد worker/src/sync.ts handlePush
// ═══════════════════════════════════════════════════════════════

class _WorkerSim extends http.BaseClient {
  /// uuids تُرفض دائماً برفض دائم (validation_error) — عقد fix M4.
  final Set<String> poisonLocalUuids;

  /// إن حُدِّد: كل طلبات /api/sync/push تعيد هذا الكود (انقطاع خادمي).
  int? failHttpWith;

  /// قياس: عدد طلبات الدفع + حجم كل دفعة (عدد العمليات).
  final pushBatchSizes = <int>[];

  /// الصفوف المسلَّمة فعلاً (نجاح حقيقي غير مكرر).
  final delivered = <String, Set<String>>{};

  final _seenIdempotency = <String>{};

  int pushRequestCount = 0;

  _WorkerSim({this.poisonLocalUuids = const {}, this.failHttpWith});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' && request.url.path.endsWith('/api/sync/push')) {
      final r = await _handlePush(request as http.Request);
      return http.StreamedResponse(
        Stream.value(r.bodyBytes),
        r.statusCode,
        headers: r.headers,
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"error":"unexpected-path"}')),
      404,
      headers: {'content-type': 'application/json'},
    );
  }

  Future<http.Response> _handlePush(http.Request request) async {
    pushRequestCount++;
    if (failHttpWith != null) {
      return http.Response(jsonEncode({'error': 'simulated outage'}), failHttpWith!,
          headers: {'content-type': 'application/json'});
    }
    // نفس عقد الحجم الخادمي: readBodyTextWithLimit + MAX_BATCH_SIZE=100
    final raw = request.bodyBytes;
    final isGzip = raw.length >= 2 && raw[0] == 0x1f && raw[1] == 0x8b;
    expect(isGzip, isTrue, reason: 'العميل يجب أن يرسل gzip (Content-Encoding)');
    final body = jsonDecode(utf8.decode(gzip.decode(raw))) as Map<String, dynamic>;
    final operations = (body['operations'] as List).cast<Map<String, dynamic>>();
    expect(operations.length, lessThanOrEqualTo(100),
        reason: 'سقف الخادم MAX_BATCH_SIZE=100 — أي دفعة أكبر تُرفض 400');
    pushBatchSizes.add(operations.length);

    final results = <Map<String, dynamic>>[];
    for (final op in operations) {
      final idem = op['idempotencyKey'] as String;
      if (_seenIdempotency.contains(idem)) {
        // إعادة إرسال بعد انقطاع — exactly-once (نفس عقد الخادم)
        results.add({'idempotencyKey': idem, 'success': true, 'skipped': true});
        continue;
      }
      _seenIdempotency.add(idem);
      final data = (op['data'] as Map).cast<String, dynamic>();
      final localUuid = data['local_uuid'] as String;
      final entity = op['entity'] as String;

      if (poisonLocalUuids.contains(localUuid)) {
        results.add({
          'idempotencyKey': idem,
          'success': false,
          'status': 'validation_error',
          'error': 'validation: poisoned record (simulated)',
        });
        continue;
      }

      delivered.putIfAbsent(entity, () => {}).add(localUuid);
      results.add({'idempotencyKey': idem, 'success': true});
    }
    return http.Response(jsonEncode({'results': results}), 200,
        headers: {'content-type': 'application/json'});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
      'cf_device_id': 'drain-device',
    });
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<CloudflareSyncManager> makeManager(_WorkerSim worker) async {
    final manager = CloudflareSyncManager();
    manager.reset();
    manager.configureForTesting(
      database: db,
      httpClient: worker,
      token: 'test-token',
      deviceId: 'drain-device',
      fullSyncCompleted: true,
    );
    return manager;
  }

  /// المنتج الحقيقي: 500 غرفة عبر RoomsDao.insertOne — نفس الطريق
  /// الذي يكتب به الإنتاج في outbox (merge داخلياً).
  Future<void> seedRooms(
    int count, {
    Set<int> poisonIndexes = const {},
  }) async {
    final outboxDao = OutboxDao(db);
    final roomsDao = RoomsDao(db, outboxDao);
    for (var i = 0; i < count; i++) {
      final isPoison = poisonIndexes.contains(i);
      await roomsDao.insertOne(
        RoomsCompanion(
          roomNumber: d.Value(isPoison ? '9${i.toString().padLeft(3, '0')}' : '7${i.toString().padLeft(3, '0')}'),
          type: const d.Value('standard'),
          price: d.Value(100.0 + i),
          status: const d.Value('شاغرة'),
          localUuid: isPoison
              ? d.Value('poison-room-$i')
              : const d.Value.absent(),
        ),
      );
    }
  }

  Future<int> undeliveredCount() async {
    return OutboxDao(db).countUndeliveredToPrimary(sources: const ['local']);
  }

  Future<Map<String, int>> outboxStatusCounts() async {
    final rows = await db
        .customSelect(
          'SELECT processing_status AS s, COUNT(*) AS c FROM outbox GROUP BY processing_status',
        )
        .get();
    return {for (final r in rows) r.read<String>('s'): r.read<int>('c')};
  }

  group('زر «رفع التغييرات» مع outbox كبير (500 سجل)', () {
    test('A: 500 سجلاً سليماً — ضغطة واحدة تفرغها في 5 دفعات ≤100', () async {
      await seedRooms(500);
      final worker = _WorkerSim();
      final manager = await makeManager(worker);

      // عدّاد الزر نفسه (dashboard_sync_button._loadPendingChangesCount)
      expect(await undeliveredCount(), 500,
          reason: 'الزر يجب أن يرى السجلات الخمسمئة قبل الرفع');

      // ✅ نفس الاستدعاء الحرفي للزر: dashboard_sync_button.dart:612
      final pushed = await manager.pushLocalChanges();

      expect(pushed, 500, reason: 'يجب أن يُرفع كل السجلات بضغطة واحدة');
      expect(worker.pushBatchSizes.length, 5,
          reason: '500 ÷ سقف 100 = 5 طلبات HTTP بالضبط');
      for (final size in worker.pushBatchSizes) {
        expect(size, lessThanOrEqualTo(100));
      }
      expect(worker.pushBatchSizes.reduce((a, b) => a + b), 500);
      expect(await undeliveredCount(), 0, reason: 'الـ outbox يجب أن يفرغ تماماً');
      expect(worker.delivered['rooms']!.length, 500,
          reason: 'الخادم استلم 500 صف فريداً — لا فقد ولا تكرار');
      final statusCounts = await outboxStatusCounts();
      expect(statusCounts['pending'] ?? 0, 0);
      expect(statusCounts['failed'] ?? 0, 0);
      expect(statusCounts['dead'] ?? 0, 0);
    });

    test('B: 497 سليمة + 3 سموم خادمية — التسليم 497 والسموم dead بلا تعطيل',
        () async {
      await seedRooms(500, poisonIndexes: {10, 250, 490});
      final worker = _WorkerSim(
        poisonLocalUuids: {'poison-room-10', 'poison-room-250', 'poison-room-490'},
      );
      final manager = await makeManager(worker);

      final pushed = await manager.pushLocalChanges();

      expect(pushed, 497,
          reason: 'الرفض الدائم لثلاث عمليات لا يمنع تسليم البقية');
      expect(worker.pushBatchSizes.length, 5,
          reason: 'الحلقة تُكمل تفريغ السليم رغم الرفض الدائم (عزل per-op)');
      expect(worker.delivered['rooms']!.length, 497);
      final statusCounts = await outboxStatusCounts();
      expect(statusCounts['dead'], 3,
          reason: 'السموم تبلغ dead-letter فوراً (عقد M4) — بلا إعادة دفع أبدية');
      expect(statusCounts['pending'] ?? 0, 0);
      expect(statusCounts['failed'] ?? 0, 0);
    });

    test('C: انقطاع خادمي (503) — الزر يرمي، السجلات تبقى pending بلا فقد',
        () async {
      await seedRooms(500);
      final worker = _WorkerSim(failHttpWith: 503);
      final manager = await makeManager(worker);

      await expectLater(
        manager.pushLocalChanges(),
        throwsA(isA<StateError>()),
        reason: 'العقد الصادق: فشل خادمي → استثناء (زر أحمر + زر إعادة)، '
            'ليس snackbar أخضر زائفاً',
      );

      expect(await undeliveredCount(), 500,
          reason: 'لا فقد: السجلات تبقى pending قابلة لإعادة الرفع');
      expect(worker.pushRequestCount, 1,
          reason: 'أول فشل يوقف الدورة فوراً — لا صرف بقية الطلبات على خادم ميت');
      expect(worker.delivered, isEmpty);
      final statusCounts = await outboxStatusCounts();
      expect(statusCounts['pending'], 500);
    });
  });
}
