// ═══════════════════════════════════════════════════════════════
//  cloudflare_d1_push_mirror_test.dart — تحقّق سلكي (wiring) لإصلاح
//  RU3: شاشة النسخ الاحتياطي Cloudflare D1 يجب أن تمر عبر outbox +
//  /api/sync/push (CloudflareD1PushMirror) لا INSERT OR REPLACE الخام.
//
//  هذا الاختبار لا يعيد إثبات أن الخادم يرفض الكتابات القديمة —
//  ذاك مثبت بقراءة الكود المصدري الحقيقي مباشرة
//  (worker/src/database.ts:927-1031 resolveLwwDecision، الفرع
//  'local_newer' + timestampLoss → `return existing`، أي رفض صريح).
//  الغرض هنا اختبار أضيق ومختلف: هل CloudflareD1PushMirror يبني
//  عملية الدفع بالشكل الذي يسمح لذلك الحارس الخادمي بالعمل أصلاً؟
//  تحديداً:
//   W1 الصف يمر عبر outbox (لا REST مباشر) ثم يُدفع عبر
//      /api/sync/push الحقيقي (نفس عقد CloudflareSyncManager).
//   W2 الطابع الزمني المُرسل = updated_at الصف نفسه، لا "الآن" — لو
//      أُرسل "الآن" لكل صف لَبَطُل حارس resolveLwwDecision بالكامل
//      (كل صف قديم كان سيبدو معدَّلاً للتو فيربح دائماً).
//   W3 source:'restore' لا يُضخّم الساعة المتجهة للصف (لا OutboxDao.
//      _bumpVectorClockForLocalWrite) — هذه إعادة إرسال، لا تعديل.
//   W4 عمود id المحلي (autoincrement بلا معنى على D1) لا يُرسَل.
//   W5 outbox يُفرَّغ بعد كل دفعة (لا تراكم دائم لآلاف الصفوف).
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io' show gzip;

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marina_hotel_mobile/services/cloudflare_d1_push_mirror.dart';
import 'package:marina_hotel_mobile/services/cloudflare_d1_service.dart';
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/daos/rooms_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════
//  محاكي Worker أمين — التقاط عمليات /push فقط (نفس نمط الملفات
//  الأخرى). لا حاجة لمحاكاة resolveLwwDecision هنا — هذا اختبار سلكي.
// ═══════════════════════════════════════════════════════════════

class _CapturingWorker extends http.BaseClient {
  final rows = <String, Map<String, Map<String, dynamic>>>{};
  final capturedOperations = <Map<String, dynamic>>[];
  int serverClock = 1750000000;

  Future<http.Response> _handlePush(http.Request request) async {
    final raw = request.bodyBytes;
    final isGzip = raw.length >= 2 && raw[0] == 0x1f && raw[1] == 0x8b;
    final bodyText = isGzip ? utf8.decode(gzip.decode(raw)) : utf8.decode(raw);
    final body = jsonDecode(bodyText) as Map<String, dynamic>;
    final operations = (body['operations'] as List).cast<Map<String, dynamic>>();
    capturedOperations.addAll(operations);
    final results = <Map<String, dynamic>>[];
    for (final op in operations) {
      final entity = op['entity'] as String;
      final data = (op['data'] as Map).cast<String, dynamic>();
      final localUuid = data['local_uuid'] as String;
      final table = rows.putIfAbsent(entity, () => {});
      table[localUuid] = {...data, 'version': 1, 'device_id': 'contract-device'};
      results.add({'idempotencyKey': op['idempotencyKey'], 'success': true});
    }
    return http.Response(
      jsonEncode({'results': results}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  Future<http.Response> _handlePull(http.Request request) async {
    return http.Response(
      jsonEncode({
        'changes': <dynamic>[],
        'cursor': '0',
        'has_more': false,
        'remaining': 0,
        'errors': <dynamic>[],
        'server_time': serverClock,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' && request.url.path.endsWith('/api/sync/push')) {
      return _awaited(await _handlePush(request as http.Request));
    }
    if (request.method == 'GET' && request.url.path.endsWith('/api/sync/pull')) {
      return _awaited(await _handlePull(request as http.Request));
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"error":"unexpected-path"}')),
      404,
      headers: {'content-type': 'application/json'},
    );
  }

  static http.StreamedResponse _awaited(http.Response r) => http.StreamedResponse(
        Stream.value(r.bodyBytes),
        r.statusCode,
        headers: r.headers,
      );
}

Future<int> outboxCount(AppDatabase db) async {
  final row = await db.customSelect('SELECT COUNT(*) AS c FROM outbox').getSingle();
  return row.read<int>('c');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _CapturingWorker worker;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
      'cf_device_id': 'contract-device',
    });
    db = AppDatabase.forTesting(NativeDatabase.memory());
    worker = _CapturingWorker();
    final manager = CloudflareSyncManager();
    manager.reset();
    manager.configureForTesting(
      database: db,
      httpClient: worker,
      token: 'test-token',
      deviceId: 'contract-device',
      fullSyncCompleted: true,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> produceRoom({double price = 150.0}) async {
    final outboxDao = OutboxDao(db);
    final roomsDao = RoomsDao(db, outboxDao);
    await roomsDao.insertOne(
      RoomsCompanion(
        roomNumber: const d.Value('701'),
        type: const d.Value('standard'),
        price: d.Value(price),
        status: const d.Value('شاغرة'),
      ),
    );
    final row = await db
        .customSelect('SELECT local_uuid FROM rooms ORDER BY id DESC LIMIT 1')
        .getSingle();
    return row.data['local_uuid'] as String;
  }

  group('CloudflareD1PushMirror — تحقّق سلكي (RU3 fix)', () {
    test(
      'W1+W5: الصف يمر عبر outbox ثم يُدفع عبر /api/sync/push الحقيقي، '
      'ويُفرَّغ outbox بعد الدفع (لا تراكم)',
      () async {
        final uuid = await produceRoom();
        // ننهي دورة outbox الطبيعية أولاً حتى لا يتداخل الإنشاء المحلي
        // (source:'local') مع ما سنقيسه هنا.
        await CloudflareSyncManager().sync(pull: false, forcePull: true);
        expect(await outboxCount(db), 0);

        final row = await db
            .customSelect('SELECT * FROM rooms WHERE local_uuid = ?',
                variables: [d.Variable<String>(uuid)])
            .getSingle();

        final mirror = CloudflareD1PushMirror(db);
        final result = await mirror.upload(
          tables: [
            CloudflareD1SourceTable(
              name: 'rooms',
              rowCount: 1,
              readChunk: (limit, offset) async =>
                  offset == 0 ? [row.data] : const [],
            ),
          ],
        );

        expect(result.ok, isTrue);
        expect(result.rowsUploaded, 1);
        expect(await outboxCount(db), 0,
            reason: 'W5: الصف يُدفع فعلياً ولا يبقى عالقاً في outbox');
        expect(worker.rows['rooms']?[uuid], isNotNull,
            reason: 'W1: وصل للخادم عبر /push الحقيقي (لا REST إداري)');
      },
    );

    test('W2: الطابع الزمني المُرسَل = updated_at الصف، لا لحظة الرفع',
        () async {
      final uuid = await produceRoom();
      await CloudflareSyncManager().sync(pull: false, forcePull: true);
      worker.capturedOperations.clear(); // نعزل التقاط عملية المرآة فقط

      final row = await db
          .customSelect('SELECT * FROM rooms WHERE local_uuid = ?',
              variables: [d.Variable<String>(uuid)])
          .getSingle();
      final realUpdatedAt = row.data['updated_at'] as int;

      final mirror = CloudflareD1PushMirror(db);
      await mirror.upload(
        tables: [
          CloudflareD1SourceTable(
            name: 'rooms',
            rowCount: 1,
            readChunk: (limit, offset) async =>
                offset == 0 ? [row.data] : const [],
          ),
        ],
      );

      expect(worker.capturedOperations, hasLength(1));
      expect(
        worker.capturedOperations.single['updatedAt'],
        realUpdatedAt,
        reason: 'W2: لو أُرسلت "الآن" هنا لبطل حارس resolveLwwDecision '
            'الخادمي (database.ts:993-1023) تماماً — كل صف قديم كان '
            'سيبدو معدَّلاً للتو فيربح دوماً، وتعود ثغرة RU3 من الباب '
            'الخلفي رغم المرور عبر /push.',
      );
    });

    test('W3: source:restore لا يُضخّم الساعة المتجهة للصف', () async {
      final uuid = await produceRoom();
      await CloudflareSyncManager().sync(pull: false, forcePull: true);

      final before = await db
          .customSelect('SELECT * FROM rooms WHERE local_uuid = ?',
              variables: [d.Variable<String>(uuid)])
          .getSingle();
      final clockBefore = before.data['vector_clock'];

      final mirror = CloudflareD1PushMirror(db);
      await mirror.upload(
        tables: [
          CloudflareD1SourceTable(
            name: 'rooms',
            rowCount: 1,
            readChunk: (limit, offset) async =>
                offset == 0 ? [before.data] : const [],
          ),
        ],
      );

      final after = await db
          .customSelect('SELECT * FROM rooms WHERE local_uuid = ?',
              variables: [d.Variable<String>(uuid)])
          .getSingle();
      expect(
        after.data['vector_clock'],
        clockBefore,
        reason: 'W3: إعادة إرسال حالة قائمة يجب ألا تُصطنع تعديلاً محلياً '
            'جديداً على الساعة المتجهة (source:local كان سيفعل ذلك عبر '
            'OutboxDao._bumpVectorClockForLocalWrite).',
      );
    });

    test('W4: عمود id المحلي لا يُرسَل ضمن حمولة الدفع', () async {
      final uuid = await produceRoom();
      await CloudflareSyncManager().sync(pull: false, forcePull: true);
      worker.capturedOperations.clear(); // نعزل التقاط عملية المرآة فقط

      final row = await db
          .customSelect('SELECT * FROM rooms WHERE local_uuid = ?',
              variables: [d.Variable<String>(uuid)])
          .getSingle();
      expect(row.data['id'], isNotNull); // تأكيد أن id موجود في المصدر فعلاً

      final mirror = CloudflareD1PushMirror(db);
      await mirror.upload(
        tables: [
          CloudflareD1SourceTable(
            name: 'rooms',
            rowCount: 1,
            readChunk: (limit, offset) async =>
                offset == 0 ? [row.data] : const [],
          ),
        ],
      );

      final sentData =
          worker.capturedOperations.single['data'] as Map<String, dynamic>;
      expect(
        sentData.containsKey('id'),
        isFalse,
        reason: 'W4: id محلي autoincrement — إرساله قد يصطدم بعمود id '
            'المستقل على D1 (نفس تصرف uploadData القديم وbuildPushOperation '
            'العادي: كلاهما يُسقطان id الوارد).',
      );
    });
  });
}
