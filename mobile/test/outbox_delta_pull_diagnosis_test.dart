// ═══════════════════════════════════════════════════════════════
//  outbox_delta_pull_diagnosis_test.dart — تشخيص قاطع (لا تخمين)
//
//  السؤال: «عند مزامنة سحب التغييرات delta sync تُنشأ سجلات في
//  outbox — لماذا؟»
//
//  المنهجية: محاكي Worker أمين (دمج ساعات المتجهة + أرقام نسخ +
//  allocateUpdatedAt + فلتر الصدى exclude_device + idempotency)
//  يعيد إنتاج دورة الدلتا الحقيقية فوق منتجين حقيقيين (RoomsDao +
//  OutboxDao) — ثم نقيس عدد صفوف outbox قبل/بعد كل سحب.
//
//  السيناريوهات المُثبتة:
//   T1 دورة جهاز واحد (إنشاء→دفع→دلتا): outbox يفرغ — لا صدى.
//   T2 جهاز آخر عدّل صفّنا بعد دفعنا: هل تُنشئ الدلتا سجلاً زائفاً؟
//   T3 تعديلان متزامنان حقيقيان: الدمج يحدّث الصف المعلق (لا تراكم).
//   T4 حذفية واردة بلا عمليات معلقة: صفر outbox.
//   T5 حذفية واردة فوق عملية معلقة: استبدال بـ delete (لا صف جديد).
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
//  محاكي Worker أمين — يعكس دلالات worker/src/sync.ts + database.ts
// ═══════════════════════════════════════════════════════════════

Map<String, int> _parseClock(String? s) {
  if (s == null || s.isEmpty) return {};
  try {
    return (jsonDecode(s) as Map).cast<String, int>();
  } catch (_) {
    return {};
  }
}

String _mergeClocks(String a, String b) {
  final ca = _parseClock(a);
  final cb = _parseClock(b);
  final out = <String, int>{...ca};
  cb.forEach((k, v) => out[k] = (out[k] ?? 0) > v ? out[k]! : v);
  return jsonEncode(out);
}

class _StatefulWorker extends http.BaseClient { // ctx.deviceId من الـ JWT

  _StatefulWorker(this.authDeviceId);
  /// صفوف الخادم: entity → local_uuid → row
  final rows = <String, Map<String, Map<String, dynamic>>>{};
  final _seenIdempotency = <String>{};
  int serverClock = 1750000000; // allocateUpdatedAt أحادي التصاعد
  final String authDeviceId;

  int get _nextStamp => ++serverClock;

  /// محاكاة دفعة من جهاز آخر (كأنها عبرت handlePush): update حقيقي
  /// بدمج ساعة الجهاز الآخر — نفس ما يفعله updateRecord في database.ts.
  void editAsDevice(
    String entity,
    String localUuid,
    String deviceId,
    Map<String, dynamic> edits,
  ) {
    final table = rows.putIfAbsent(entity, () => {});
    final row = table[localUuid];
    assert(row != null, 'صف الخادم غير موجود: $entity/$localUuid');
    final stamp = _nextStamp;
    final newClock = _mergeClocks(row!['vector_clock'] as String? ?? '{}',
        jsonEncode({deviceId: 1}));
    row
      ..addAll(edits)
      ..['updated_at'] = stamp
      ..['last_modified'] = stamp
      ..['version'] = ((row['version'] as int?) ?? 0) + 1
      ..['vector_clock'] = newClock
      ..['device_id'] = deviceId;
  }

  /// حذف ناعم من جهاز آخر (tombstone).
  void deleteAsDevice(String entity, String localUuid, String deviceId) {
    final row = rows[entity]![localUuid]!;
    final stamp = _nextStamp;
    row
      ..['deleted_at'] = stamp
      ..['updated_at'] = stamp
      ..['version'] = ((row['version'] as int?) ?? 0) + 1
      ..['vector_clock'] = _mergeClocks(row['vector_clock'] as String? ?? '{}',
          jsonEncode({deviceId: 1}))
      ..['device_id'] = deviceId;
  }

  Map<String, dynamic>? serverRow(String entity, String localUuid) =>
      rows[entity]?[localUuid];

  // ─── معالجة الدفع (مرآة handlePush) ───────────────────────────
  final pushErrors = <String>[];
  Future<http.Response> _handlePush(http.Request request) async {
    try {
      // العميل يرسل جسم الدفع مضغوطاً gzip (سقف مزدوج في worker) — فُكّه
      final raw = request.bodyBytes;
      final isGzip = raw.length >= 2 && raw[0] == 0x1f && raw[1] == 0x8b;
      final bodyText = isGzip ? utf8.decode(gzip.decode(raw)) : utf8.decode(raw);
      final body =
          jsonDecode(bodyText) as Map<String, dynamic>;
      final operations =
          (body['operations'] as List).cast<Map<String, dynamic>>();
    final results = <Map<String, dynamic>>[];
    for (final op in operations) {
      final idem = op['idempotencyKey'] as String;
      if (_seenIdempotency.contains(idem)) {
        results.add({
          'idempotencyKey': idem,
          'success': true,
          'skipped': true,
        });
        continue;
      }
      _seenIdempotency.add(idem);
      final entity = op['entity'] as String;
      final operation = op['operation'] as String;
      final data = (op['data'] as Map).cast<String, dynamic>();
      final localUuid = data['local_uuid'] as String;
      final incomingClock = (op['vectorClock'] as String?) ?? '{}';
      final table = rows.putIfAbsent(entity, () => {});
      final existing = table[localUuid];
      final stamp = _nextStamp;

      if (operation == 'delete') {
        if (existing != null) {
          existing
            ..['deleted_at'] = stamp
            ..['updated_at'] = stamp
            ..['version'] = ((existing['version'] as int?) ?? 0) + 1
            ..['vector_clock'] =
                _mergeClocks(existing['vector_clock'] as String? ?? '{}', incomingClock)
            ..['device_id'] = authDeviceId;
        }
        results.add({'idempotencyKey': idem, 'success': true});
        continue;
      }

      if (existing == null) {
        // مرآة createRecord: ختم الخادم + ملء ساعة فارغة
        final row = <String, dynamic>{...data};
        row.remove('id');
        row['updated_at'] = stamp;
        row['deleted_at'] = null;
        row['version'] = 1;
        row['origin'] = 'cloud';
        row['device_id'] = authDeviceId;
        final vc = data['vector_clock'] as String?;
        row['vector_clock'] =
            (vc != null && vc.isNotEmpty && vc != '{}') ? vc : jsonEncode({authDeviceId: 1});
        table[localUuid] = row;
        results.add({'idempotencyKey': idem, 'success': true});
        continue;
      }

      // مرآة updateRecord: tombstone يفوز حتماً (F1)
      if (existing['deleted_at'] != null) {
        results.add({
          'idempotencyKey': idem,
          'success': true,
          'status': 'deleted',
        });
        continue;
      }
      // مرآة resolveLwwDecision + buildUpdateStatement
      existing
        ..addAll(data)
        ..remove('id')
        ..remove('local_uuid')
        ..remove('created_at')
        ..remove('server_id')
        ..['updated_at'] = stamp
        ..['version'] = ((existing['version'] as int?) ?? 0) + 1
        ..['vector_clock'] =
            _mergeClocks(existing['vector_clock'] as String? ?? '{}', incomingClock)
        ..['device_id'] = authDeviceId;
      results.add({'idempotencyKey': idem, 'success': true});
    }
    return _json({'results': results});
    } catch (e) {
      pushErrors.add('$e');
      return http.Response(jsonEncode({'error': 'mock-internal: $e'}), 500,
          headers: {'content-type': 'application/json'});
    }
  }

  // ─── معالجة السحب (مرآة handlePull + فلتر الصدى خطة 2.5) ─────
  Future<http.Response> _handlePull(http.Request request) async {
    final q = request.url.queryParameters;
    final cursor = int.parse(q['cursor'] ?? '0');
    final limit = int.tryParse(q['limit'] ?? '200') ?? 200;
    final excludeDevice = q['exclude_device'];
    final tombstonesOnly = q['tombstones_only'] == '1';

    final found = <({String entity, Map<String, dynamic> row})>[];
    rows.forEach((entity, table) {
      table.forEach((uuid, row) {
        final updated = (row['updated_at'] as int?) ?? 0;
        if (updated <= cursor) return;
        final isTombstone = row['deleted_at'] != null;
        // ✅ الخادم الحقيقي (database.ts pullChanges): delClause فارغ في
        // الدلتا العادية — الحذفيات تُبثّ بجانب الصفوف الحية (مراجعة
        // 2026-09-09 #1). tombstones_only يجلب الحذفيات حصراً فقط.
        if (tombstonesOnly && !isTombstone) return;
        if (excludeDevice != null &&
            excludeDevice.isNotEmpty &&
            row['device_id'] == excludeDevice) {
          return; // فلتر الصدى
        }
        found.add((entity: entity, row: {...row, '_entity': entity}));
      });
    });
    found.sort((a, b) => ((a.row['updated_at'] as int?) ?? 0)
        .compareTo((b.row['updated_at'] as int?) ?? 0));
    final page = found.take(limit).toList();
    final newCursor = page.isEmpty
        ? cursor
        : page.map((e) => (e.row['updated_at'] as int?) ?? 0).reduce((a, b) => a > b ? a : b);
    return _json({
      'changes': [for (final f in page) f.row],
      'cursor': newCursor.toString(),
      'has_more': false,
      'remaining': 0,
      'errors': <dynamic>[],
      'server_time': serverClock,
    });
  }

  final requestLog = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestLog.add('${request.method} ${request.url.path}?${request.url.query}');
    if (request.method == 'POST' && request.url.path.endsWith('/api/sync/push')) {
      return _awaited(await _handlePush(request as http.Request));
    }
    if (request.method == 'GET' && request.url.path.endsWith('/api/sync/pull')) {
      return _awaited(await _handlePull(request as http.Request));
    }
    // أي مسار آخر: 404 مسجَّل بدل رمي — لنداءات التهيئة (login/register)
    // حتى يكمل المدير ويظهر السجل كاملاً في التشخيص
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
//  العدّادات والتشخيص
// ═══════════════════════════════════════════════════════════════

Future<int> outboxCount(AppDatabase db) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM outbox')
      .getSingle();
  return row.read<int>('c');
}

Future<List<String>> outboxDump(AppDatabase db) async {
  final rows = await db.customSelect(
    'SELECT entity, op, local_uuid, payload, processing_status FROM outbox',
  ).get();
  return [
    for (final r in rows)
      _outboxRowLabel(
        r.data,
        _parsePayloadClock(r.data['payload'] as String?),
      ),
  ];
}

String _outboxRowLabel(Map<String, dynamic> data, String clock) {
  return '${data['entity']}/${data['op']}/${data['processing_status']} '
      'clockInPayload=$clock';
}

String _parsePayloadClock(String? payload) {
  if (payload == null) return '?';
  try {
    final p = jsonDecode(payload) as Map;
    return (p['vector_clock'] as String?) ?? '(بدون حقل)';
  } catch (_) {
    return 'حملة تالفة';
  }
}

Future<String> rowClock(AppDatabase db, String uuid) async {
  final row = await db.customSelect(
    'SELECT vector_clock, version, updated_at FROM rooms WHERE local_uuid = ?',
    variables: [d.Variable<String>(uuid)],
  ).getSingleOrNull();
  if (row == null) return '(صف محلي مفقود)';
  return 'vc=${row.data['vector_clock']} v=${row.data['version']} '
      'ua=${row.data['updated_at']}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _StatefulWorker worker;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
      'cf_device_id': 'contract-device',
    });
    db = AppDatabase.forTesting(NativeDatabase.memory());
    worker = _StatefulWorker('contract-device');
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
      deviceId: 'contract-device',
      fullSyncCompleted: true,
    );
    return manager;
  }

  /// منتج حقيقي: غرفة عبر RoomsDao (نفس مسار الإنتاج) — يعيد الـ uuid
  /// (يُقرأ من القاعدة مباشرة لأن قيمة إرجاع insertOne ليست local_uuid)
  Future<String> produceRoom({double price = 150.0}) async {
    final outboxDao = OutboxDao(db);
    final roomsDao = RoomsDao(db, outboxDao);
    await roomsDao.insertOne(
      RoomsCompanion(
        roomNumber: d.Value('7${(price % 10).toInt()}'),
        type: const d.Value('standard'),
        price: d.Value(price),
        status: const d.Value('شاغرة'),
      ),
    );
    final row = await db.customSelect(
      'SELECT local_uuid FROM rooms ORDER BY id DESC LIMIT 1',
    ).getSingle();
    return row.data['local_uuid'] as String;
  }

  group('تشخيص outbox أثناء سحب الدلتا — القياس المباشر', () {
    test('T1: دورة جهاز واحد (إنشاء→دفع→دلتا) تفرغ الـ outbox بلا صدى',
        () async {
      final manager = await makeManager();
      final uuid = await produceRoom();
      expect(await outboxCount(db), 1, reason: 'الإنشاء المحلي يسجل outbox');

      await manager.sync(); // دفع + سحب دلتا (فلتر الصدى مفعّل)
      // ignore: avoid_print
      print('── T1 طلبات المدير: ${worker.requestLog}');
      if (worker.pushErrors.isNotEmpty) {
        print('── T1 أخطاء محاكي الدفع: ${worker.pushErrors}');
      }
      print('── T1 صفوف الخادم: ${worker.rows.map((k, v) => MapEntry(k, v.keys.toList()))}');

      final after = await outboxCount(db);
      expect(after, 0,
          reason: 'بعد دورة كاملة: العنصر سُلّم وحُذف، والدلتا لم تعيد '
              'إلينا صفنا (exclude_device) — لا يجوز أن يظهر سجل جديد');
      expect(worker.serverRow('rooms', uuid), isNotNull);
    });

    test('T2: جهاز آخر عدّل صفّنا بعد دفعنا — هل تُنشئ الدلتا سجلاً زائفاً؟',
        () async {
      final manager = await makeManager();
      final uuid = await produceRoom();
      await manager.sync(); // صفنا على الخادم والـ outbox فارغ
      expect(await outboxCount(db), 0);

      // جهاز آخر يدفع تعديلاً حقيقياً للصف (مرآة updateRecord)
      worker.editAsDevice('rooms', uuid, 'device-A', {'price': 180.0});

      final before = await outboxCount(db);
      await manager.sync(push: false); // سحب دلتا فقط — نعزل أثر السحب
      final after = await outboxCount(db);

      // ignore: avoid_print
      print('── T2 تشخيص ──');
      print('طلبات المدير: ${worker.requestLog.take(12)}');
      // ignore: avoid_print
      print('outbox قبل السحب: $before / بعد السحب: $after');
      // ignore: avoid_print
      print('الصف المحلي: ${await rowClock(db, uuid)}');
      // ignore: avoid_print
      print('صف الخادم: ${worker.serverRow('rooms', uuid)?['vector_clock']}');
      for (final line in await outboxDump(db)) {
        // ignore: avoid_print
        print('outbox: $line');
      }

      expect(after, 0,
          reason: 'لا يوجد أي تعديل محلي معلق — ساعة الخادم يجب أن تحتوي '
              'مكوّن جهازنا (دُفع مع الساعة) فتطغى نسخة device-A وتُطبق '
              'تسلسلياً بلا دمج. إن فشل هذا فالسحب يولّد سجلات outbox '
              'زائفة (الصدى الساعي) وهذا هو الخلل المطلوب إصلاحه');
      // والسعر الجديد وصل محلياً
      final price = await db.customSelect(
        'SELECT price FROM rooms WHERE local_uuid = ?',
        variables: [d.Variable<String>(uuid)],
      ).getSingle();
      expect((price.data['price'] as num).toDouble(), 180.0);
    });

    test('T3: تعديلان متزامنان حقيقيان — الدمج يحدّث المعلق ولا يراكم',
        () async {
      final manager = await makeManager();
      final uuid = await produceRoom();
      await manager.sync();
      expect(await outboxCount(db), 0);

      // تعديل محلي حقيقي (منتج إنتاجي) → outbox 1
      final outboxDao = OutboxDao(db);
      final roomsDao = RoomsDao(db, outboxDao);
      final localRow = await db.customSelect(
        'SELECT * FROM rooms WHERE local_uuid = ?',
        variables: [d.Variable<String>(uuid)],
      ).getSingle();
      await roomsDao.updateById(
        localRow.data['id'] as int,
        const RoomsCompanion(price: d.Value(200.0)),
      );
      expect(await outboxCount(db), 1, reason: 'التعديل المحلي يسجل outbox');

      // جهاز آخر عدّل نفس الصف بالتوازي (ساعة مستقلة + updated_at أحدث)
      worker.editAsDevice('rooms', uuid, 'device-A', {'price': 190.0});

      await manager.sync(push: false); // السحب يجلب التعارض المتزامن

      final count = await outboxCount(db);
      for (final line in await outboxDump(db)) {
        // ignore: avoid_print
        print('── T3 outbox: $line');
      }
      expect(count, 1,
          reason: 'الدمج المتزامن يجب أن يحدّث العنصر المعلق نفسه '
              '(merge dedup لكل entity+local_uuid) لا أن ينشئ صفاً ثانياً');
    });

    test('T4: حذفية واردة بلا عمليات معلقة → صفر outbox', () async {
      final manager = await makeManager();
      final uuid = await produceRoom();
      await manager.sync();
      expect(await outboxCount(db), 0);

      worker.deleteAsDevice('rooms', uuid, 'device-A');
      await manager.sync(push: false);

      expect(await outboxCount(db), 0,
          reason: 'tombstone بلا عمليات محلية معلقة يُطبق حذفاً محلياً '
              'نظيفاً — لا شيء يُرفع');
      final gone = await db.customSelect(
        'SELECT deleted_at FROM rooms WHERE local_uuid = ?',
        variables: [d.Variable<String>(uuid)],
      ).getSingle();
      expect(gone.data['deleted_at'], isNotNull);
    });

    test('T5: حذفية واردة فوق عملية معلقة → استبدال بـ delete لا تراكم',
        () async {
      final manager = await makeManager();
      final uuid = await produceRoom();
      await manager.sync();

      // تعديل محلي معلق
      final outboxDao = OutboxDao(db);
      final roomsDao = RoomsDao(db, outboxDao);
      final localRow = await db.customSelect(
        'SELECT * FROM rooms WHERE local_uuid = ?',
        variables: [d.Variable<String>(uuid)],
      ).getSingle();
      await roomsDao.updateById(
        localRow.data['id'] as int,
        const RoomsCompanion(price: d.Value(210.0)),
      );
      expect(await outboxCount(db), 1);

      worker.deleteAsDevice('rooms', uuid, 'device-A');
      await manager.sync(push: false);

      final dump = await outboxDump(db);
      for (final line in dump) {
        // ignore: avoid_print
        print('── T5 outbox: $line');
      }
      final count = await outboxCount(db);
      expect(count, lessThanOrEqualTo(1),
          reason: 'الحذفية فوق عملية معلقة تستبدلها (merge) — لا ينشأ '
              'صف ثانٍ مهما تكرر السحب');
      final opRow = await db.customSelect(
        'SELECT op FROM outbox LIMIT 1',
      ).getSingleOrNull();
      if (opRow != null) {
        expect(opRow.data['op'], 'delete',
            reason: 'العملية المعلقة تحولت لحذفية تأكيدية (عقد '
                '_supersedePendingOpsWithTombstone)');
      }
    });
  });
}
