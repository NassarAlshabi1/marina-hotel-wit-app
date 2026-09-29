// ═══════════════════════════════════════════════════════════════
//  raw_d1_backup_upload_outbox_test.dart — تحقّق تجريبي قاطع لفرضية:
//  «الرفع الخام عبر شاشة النسخ الاحتياطي Cloudflare D1
//  (cloudflare_d1_tab.dart → CloudflareD1Service.uploadData) يخلق
//  حالة تُنتج سجلات outbox عند سحب الدلتا اللاحق»
//
//  لماذا هذا الملف: طلب المستخدم إثباتاً تجريبياً بدل التخمين لادّعاء
//  سابق. هذا الملف يبني السيناريو من الكود الفعلي لـ uploadData
//  (cloudflare_d1_service.dart:308-345: SELECT * ثم INSERT OR REPLACE
//  حرفي — كل الأعمدة كما هي، بلا دمج ساعة، بلا فحص version) ويحاكيه
//  بمحاكي Worker أمين مطابق للملفين السابقين، ثم يقيس النتيجة الفعلية
//  عبر CloudflareSyncManager الحقيقي — لا إعادة تنفيذ للمنطق، بل
//  استدعاء الكود الإنتاجي نفسه.
//
//  محاكاة الرفع الخام = كتابة مباشرة في worker.rows[entity][uuid] بنفس
//  أعمدة الصف المحلي كما هي — هذا مطابق تماماً لما تفعله uploadData()
//  فعلياً على مستوى SQL (INSERT OR REPLACE بلا تحويل ولا تحقق)، وليس
//  تبسيطاً تعسفياً.
//
//  النتائج (بعد التنفيذ الفعلي لا التخمين):
//   RU1 رفع خام لعملية معلّقة ثم مزامنة عادية (بلا جهاز آخر): outbox
//       ينتهي صفراً — الرفع الخام وحده، بمعزل عن أي تعارض حقيقي من
//       جهاز آخر، لا يُنتج سجل outbox زائداً بعد السحب.
//   RU2 (الحالة المطابقة لادّعائي السابق) رفع خام لتعديل معلّق، ثم
//       جهاز آخر يعدّل نفس الصف بعد أن استقر الرفع الخام، ثم تعديل
//       محلي ثانٍ غير مدفوع، ثم سحب: outbox ينتهي بسجل دمج واحد.
//   RU2-CONTROL نفس تسلسل RU2 تماماً لكن بلا خطوة الرفع الخام إطلاقاً
//       (الجهاز الآخر يعدّل الصف الأصلي مباشرة): نفس النتيجة بالضبط —
//       سجل دمج واحد. → الرفع الخام ليس هو السبب المائز؛ التزامن
//       الحقيقي بين جهازين هو السبب (T3 في outbox_delta_pull_diagnosis
//       أثبته أصلاً بمعزل عن أي رفع خام). ادّعائي السابق بأن الرفع
//       الخام هو «مصدر» outbox أثناء السحب غير دقيق: نفس الملف يثبت
//       الحقيقة الأدق.
//   RU3 (الخطر الفعلي المائز للرفع الخام) رفع خام لِنُسخة محلية
//       قديمة فوق صف خادمي أحدث (جهاز آخر سبق ورفع تعديلات حقيقية عبر
//       البروتوكول الطبيعي): الكتابة الخام تُدمّر تعديلات الخادم
//       الأحدث بصمت (لا فحص version) — فقدان بيانات حقيقي، لا علاقة
//       له بـ outbox، وهو الأثر الجانبي الحقيقي المُثبت لهذه الشاشة.
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
//  محاكي Worker أمين (نسخة مطابقة لـ outbox_delta_pull_diagnosis_test)
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

class _StatefulWorker extends http.BaseClient {

  _StatefulWorker(this.authDeviceId);
  final rows = <String, Map<String, Map<String, dynamic>>>{};
  final _seenIdempotency = <String>{};
  int serverClock = 1750000000;
  final String authDeviceId;

  int get _nextStamp => ++serverClock;

  /// محاكاة دفعة حقيقية من جهاز آخر عبر /push (مرآة updateRecord).
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
    final newClock = _mergeClocks(
      row!['vector_clock'] as String? ?? '{}',
      jsonEncode({deviceId: 1}),
    );
    row
      ..addAll(edits)
      ..['updated_at'] = stamp
      ..['last_modified'] = stamp
      ..['version'] = ((row['version'] as int?) ?? 0) + 1
      ..['vector_clock'] = newClock
      ..['device_id'] = deviceId;
  }

  /// ✅ محاكاة «الرفع الخام» عبر شاشة Cloudflare D1 backup:
  /// مطابقة حرفية لـ CloudflareD1Service.uploadData
  /// (cloudflare_d1_service.dart:336-345: INSERT OR REPLACE بكل
  /// الأعمدة كما هي من SELECT * محلي) — استبدال كامل للصف بلا أي
  /// دمج ساعة وبلا أي فحص version، تماماً كما يفعل INSERT OR REPLACE
  /// في SQLite/D1 الحقيقي.
  void rawBackupUpload(String entity, String localUuid, Map<String, dynamic> localRow) {
    final table = rows.putIfAbsent(entity, () => {});
    final copy = Map<String, dynamic>.from(localRow);
    copy.remove('id'); // id محلي فقط — لا مقابل له على D1
    table[localUuid] = copy;
  }

  Map<String, dynamic>? serverRow(String entity, String localUuid) =>
      rows[entity]?[localUuid];

  final pushErrors = <String>[];
  Future<http.Response> _handlePush(http.Request request) async {
    try {
      final raw = request.bodyBytes;
      final isGzip = raw.length >= 2 && raw[0] == 0x1f && raw[1] == 0x8b;
      final bodyText = isGzip ? utf8.decode(gzip.decode(raw)) : utf8.decode(raw);
      final body = jsonDecode(bodyText) as Map<String, dynamic>;
      final operations = (body['operations'] as List).cast<Map<String, dynamic>>();
      final results = <Map<String, dynamic>>[];
      for (final op in operations) {
        final idem = op['idempotencyKey'] as String;
        if (_seenIdempotency.contains(idem)) {
          results.add({'idempotencyKey': idem, 'success': true, 'skipped': true});
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

        if (existing['deleted_at'] != null) {
          results.add({'idempotencyKey': idem, 'success': true, 'status': 'deleted'});
          continue;
        }
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
        if (tombstonesOnly && !isTombstone) return;
        if (excludeDevice != null &&
            excludeDevice.isNotEmpty &&
            row['device_id'] == excludeDevice) {
          return;
        }
        found.add((entity: entity, row: {...row, '_entity': entity}));
      });
    });
    found.sort((a, b) =>
        ((a.row['updated_at'] as int?) ?? 0).compareTo((b.row['updated_at'] as int?) ?? 0));
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

http.Response _json(Map<String, dynamic> body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

Future<int> outboxCount(AppDatabase db) async {
  final row = await db.customSelect('SELECT COUNT(*) AS c FROM outbox').getSingle();
  return row.read<int>('c');
}

Future<List<String>> outboxDump(AppDatabase db) async {
  final rows = await db.customSelect(
    'SELECT entity, op, local_uuid, payload, processing_status FROM outbox',
  ).get();
  return [
    for (final r in rows)
      _outboxRowPrice(
        r.data,
        _parsePayloadField(r.data['payload'] as String?, 'price'),
      ),
  ];
}

String _outboxRowPrice(Map<String, dynamic> data, String price) {
  return '${data['entity']}/${data['op']}/${data['processing_status']} '
      'price=$price';
}

String _parsePayloadField(String? payload, String field) {
  if (payload == null) return '?';
  try {
    final p = jsonDecode(payload) as Map;
    return '${p[field]}';
  } catch (_) {
    return 'حملة تالفة';
  }
}

Future<Map<String, dynamic>> localRow(AppDatabase db, String uuid) async {
  final row = await db.customSelect(
    'SELECT * FROM rooms WHERE local_uuid = ?',
    variables: [d.Variable<String>(uuid)],
  ).getSingle();
  return row.data;
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

  group('تحقّق تجريبي: هل الرفع الخام عبر شاشة Cloudflare D1 يُنتج outbox عند السحب؟', () {
    test(
      'RU1: رفع خام لتعديل معلّق بمعزل عن أي جهاز آخر ثم مزامنة كاملة — '
      'outbox ينتهي صفراً (لا أثر مباشر للرفع الخام وحده)',
      () async {
        final manager = await makeManager();
        final uuid = await produceRoom();
        await manager.sync(); // إنشاء نظيف على الخادم، outbox صفر
        expect(await outboxCount(db), 0);

        // تعديل محلي معلّق (لم يُدفع بعد)
        final outboxDao = OutboxDao(db);
        final roomsDao = RoomsDao(db, outboxDao);
        var row = await localRow(db, uuid);
        await roomsDao.updateById(row['id'] as int, const RoomsCompanion(price: d.Value(200.0)));
        expect(await outboxCount(db), 1);

        // ✅ محاكاة الرفع الخام: بدل أن يُدفع هذا التعديل عبر /push
        // الطبيعي، يستخدم المستخدم شاشة النسخ الاحتياطي فينسخ الصف
        // المحلي الحالي حرفياً إلى D1.
        row = await localRow(db, uuid);
        worker.rawBackupUpload('rooms', uuid, row);

        // الآن مزامنة طبيعية كاملة (push فعلي للعملية المعلّقة القديمة + سحب)
        await manager.sync();

        final after = await outboxCount(db);
        print('── RU1 outbox بعد المزامنة الكاملة: $after');
        print('── RU1 صف الخادم بعد الدفع اللاحق: ${worker.serverRow('rooms', uuid)}');
        expect(
          after,
          0,
          reason:
              'الرفع الخام وحده — بمعزل عن أي تعديل متزامن من جهاز آخر — '
              'لا يُبقي ولا يُنشئ سجل outbox عند المزامنة اللاحقة. الخادم '
              'يقبل الدفعة المتأخرة رغم أنه كان يحمل نسخة مطابقة مسبقاً '
              '(idempotent بالمحتوى) ويُطهَّر outbox بشكل طبيعي.',
        );
      },
    );

    test(
      'RU2: رفع خام ثم تعديل محلي ثانٍ + تعديل حقيقي من جهاز آخر ثم سحب — '
      'outbox ينتهي بسجل دمج واحد',
      () async {
        final manager = await makeManager();
        final uuid = await produceRoom();
        await manager.sync();
        expect(await outboxCount(db), 0);

        final outboxDao = OutboxDao(db);
        final roomsDao = RoomsDao(db, outboxDao);

        // تعديل محلي أول (معلّق، غير مدفوع)
        var row = await localRow(db, uuid);
        await roomsDao.updateById(row['id'] as int, const RoomsCompanion(price: d.Value(200.0)));

        // ✅ رفع خام لهذه الحالة (بدل الدفع الطبيعي)
        row = await localRow(db, uuid);
        worker.rawBackupUpload('rooms', uuid, row);
        print('── RU2 بعد الرفع الخام: ${worker.serverRow('rooms', uuid)!['vector_clock']}');

        // تعديل محلي ثانٍ (لا يزال غير مدفوع — المستخدم يعتمد على الرفع الخام لا على sync)
        row = await localRow(db, uuid);
        await roomsDao.updateById(row['id'] as int, const RoomsCompanion(price: d.Value(205.0)));

        // جهاز آخر يعدّل نفس الصف عبر البروتوكول الطبيعي، بعد استقرار الرفع
        // الخام — مرتين، حتى يتقدّم version على الخادم فعلياً فوق version
        // المحلي (وإلا فحارس LWW الأولي يتخطى السحب قبل أي مقارنة ساعات).
        worker.editAsDevice('rooms', uuid, 'device-A', {'price': 190.0});
        worker.editAsDevice('rooms', uuid, 'device-A', {'price': 191.0});
        final remoteRow = worker.serverRow('rooms', uuid)!;
        final localRowNow = await localRow(db, uuid);
        print('── RU2 صف الخادم قبل السحب: version=${remoteRow['version']} '
            'vc=${remoteRow['vector_clock']}');
        print('── RU2 الصف المحلي قبل السحب: version=${localRowNow['version']} '
            'vc=${localRowNow['vector_clock']}');

        await manager.sync(push: false); // نعزل أثر السحب تحديداً

        final count = await outboxCount(db);
        for (final line in await outboxDump(db)) {
          print('── RU2 outbox: $line');
        }
        expect(
          count,
          1,
          reason:
              'تعارض ساعات متجهة حقيقي (concurrent) بين تعديل device-A '
              'والتعديل المحلي الثاني غير المدفوع — الدمج (W6، '
              'cloudflare_sync_manager.dart:3204-3254) يكتب النتيجة '
              'المدمجة في outbox، تماماً كما وُصف.',
        );
      },
    );

    test(
      'RU2-CONTROL: نفس تسلسل RU2 تماماً لكن بلا أي خطوة رفع خام — '
      'يجب أن تكون النتيجة مطابقة (سجل دمج واحد) لإثبات أن الرفع الخام '
      'ليس هو المتغيّر المسبّب',
      () async {
        final manager = await makeManager();
        final uuid = await produceRoom();
        await manager.sync();
        expect(await outboxCount(db), 0);

        final outboxDao = OutboxDao(db);
        final roomsDao = RoomsDao(db, outboxDao);

        var row = await localRow(db, uuid);
        await roomsDao.updateById(row['id'] as int, const RoomsCompanion(price: d.Value(200.0)));
        // ⛔ لا رفع خام هنا — نفس المتغيرات الأخرى فقط

        row = await localRow(db, uuid);
        await roomsDao.updateById(row['id'] as int, const RoomsCompanion(price: d.Value(205.0)));

        worker.editAsDevice('rooms', uuid, 'device-A', {'price': 190.0});
        worker.editAsDevice('rooms', uuid, 'device-A', {'price': 191.0});
        final remoteRow = worker.serverRow('rooms', uuid)!;
        final localRowNow = await localRow(db, uuid);
        print('── RU2-CONTROL صف الخادم قبل السحب: version=${remoteRow['version']} '
            'vc=${remoteRow['vector_clock']}');
        print('── RU2-CONTROL الصف المحلي قبل السحب: version=${localRowNow['version']} '
            'vc=${localRowNow['vector_clock']}');

        await manager.sync(push: false);

        final count = await outboxCount(db);
        for (final line in await outboxDump(db)) {
          print('── RU2-CONTROL outbox: $line');
        }
        expect(
          count,
          1,
          reason:
              'نفس النتيجة بالضبط بلا أي رفع خام — التعارض الحقيقي بين '
              'جهازين (T3 في outbox_delta_pull_diagnosis_test.dart) هو '
              'المتغيّر الفعلي المسبّب لسجل outbox، لا الرفع الخام. '
              'الرفع الخام لا يُضيف سبباً جديداً لظهور outbox عند السحب '
              '— كان الادّعاء السابق بأنه "المصدر" غير دقيق.',
        );
      },
    );

    test(
      'RU3: الخطر الفعلي المائز للرفع الخام — استبدال صامت لصف خادمي '
      'أحدث بنسخة محلية أقدم (لا علاقة بـ outbox، بل فقدان بيانات)',
      () async {
        final manager = await makeManager();
        final uuid = await produceRoom();
        await manager.sync();

        // خُذ لقطة من الصف المحلي *الآن* (قديمة) لمحاكاة جهاز لم يُزامن منذ فترة
        final staleSnapshot = await localRow(db, uuid);
        expect(staleSnapshot['price'], 150.0);

        // بينما جهاز آخر يدفع تعديلات حقيقية متعددة عبر البروتوكول الطبيعي
        worker.editAsDevice('rooms', uuid, 'device-A', {'price': 999.0});
        worker.editAsDevice('rooms', uuid, 'device-A', {'price': 1200.0});
        final beforeOverwrite = worker.serverRow('rooms', uuid)!;
        print('── RU3 صف الخادم قبل الرفع الخام: '
            'price=${beforeOverwrite['price']} version=${beforeOverwrite['version']}');

        // ✅ المستخدم يفتح شاشة النسخ الاحتياطي على الجهاز القديم غير
        // المُزامَن ويضغط «رفع البيانات الآن» — INSERT OR REPLACE بلا أي
        // فحص version (cloudflare_d1_service.dart:336-345)
        worker.rawBackupUpload('rooms', uuid, staleSnapshot);

        final afterOverwrite = worker.serverRow('rooms', uuid)!;
        print('── RU3 صف الخادم بعد الرفع الخام: '
            'price=${afterOverwrite['price']} version=${afterOverwrite['version']}');

        expect(
          afterOverwrite['price'],
          150.0,
          reason:
              'الرفع الخام استبدل صف الخادم (كان 1200 بعد تعديلين حقيقيين '
              'من device-A) بالقيمة القديمة 150 بلا أي تحذير أو فحص — '
              'فقدان بيانات صامت. هذا هو الخطر الحقيقي المميّز لهذه '
              'الشاشة، لا توليد outbox.',
        );
        expect(
          (afterOverwrite['version'] as int) <= (beforeOverwrite['version'] as int),
          isTrue,
          reason: 'رقم النسخة لم يتقدّم أو حتى تراجع — عقد "version يتزايد دوماً" '
              'الذي يعتمد عليه حارس انزياح الساعة في السحب '
              '(cloudflare_sync_manager.dart:3178-3186) انتُهك.',
        );
      },
    );
  });
}
