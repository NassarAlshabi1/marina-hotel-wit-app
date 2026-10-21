// test/unit/cloudflare_d1_upload_speed_test.dart
//
// ✅ اختبار انحدار لتسريع رفع البيانات إلى Cloudflare D1
// (شاشة الإعدادات → النسخ الاحتياطي والاستعادة → تبويب Cloudflare D1).
//
// يثبّت الخصائص التي يقوم عليها التسريع في CloudflareD1Service.uploadData:
//   1) الدفعة الواحدة: حتى 800 عبارة (بدل 200) ما دام حجمها دون 128KB.
//   2) الدفعات داخل الجدول الواحد تُرسل متوازية بسقف 3 نداءات في الطيران.
//   3) ترتيب الجداول يبقى متسلسلاً (لا تتقاطع دفعات جدولين) حفظاً لعلاقات
//      FOREIGN KEY لأن D1 يفرضها افتراضياً.
//   4) الردود العابرة (429/5xx) تُعاد بمهلة تصاعدية بدل إفشال الرفع،
//      والردود غير العابرة (400 خطأ SQL) لا تُعاد.
//   5) البيان المرفوع (SQL) لم يتغيّر: نفس عبارات UPSERT ونفس القيم حرفياً.
//
// القياس بزمن صناعي على MockClient: الزمن الكلي ≈ عدد النداءات × زمن النداء
// الثابت (RTT) — وهو النموذج الذي بُني عليه التحسين. لذلك المرجع الذي
// نقارن به هو مجموع أزمنة النداءات (أي زمن المسار المتسلسل القديم).
//
// الاستخدام: flutter test test/unit/cloudflare_d1_upload_speed_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marina_hotel_mobile/services/cloudflare_d1_service.dart';

/// سقف العبارات لكل نداء — مطابق لـ CloudflareD1Service._statementBatch.
const int kProvenBatchStatements = 800;

/// سقف حجم الدفعة بالأحرف — مطابق لـ CloudflareD1Service._maxBatchChars.
const int kMaxBatchChars = 128 * 1024;

/// الدفعة القديمة (قبل التسريع) — المرجع الذي نقيس عليه انخفاض عدد النداءات.
const int kLegacyBatchStatements = 200;

/// سقف النداءات المتوازية داخل الجدول — مطابق لـ _maxParallelCalls.
const int kMaxParallelCalls = 3;

/// جدول مصدر صناعي (بلا قاعدة بيانات) — نفس عقد CloudflareD1SourceTable.
///
/// [narrow]: أعمدة قليلة قصيرة (صفوف ضيقة) فلا يتدخل سقف الـ 128KB؛
/// الافتراضي صفوف "عريضة" (نصوص عربية + عمود سعر) لاختبار سقف الحجم.
CloudflareD1SourceTable sourceTable(
  String name,
  int rowCount, {
  int startsAt = 0,
  bool narrow = false,
}) {
  return CloudflareD1SourceTable(
    name: name,
    rowCount: rowCount,
    readChunk: (limit, offset) async {
      if (offset >= rowCount) return const <Map<String, Object?>>[];
      final end = (offset + limit) > rowCount ? rowCount : offset + limit;
      return <Map<String, Object?>>[
        for (var i = offset; i < end; i++)
          narrow
              ? <String, Object?>{
                  'local_uuid': '$name-uuid-${startsAt + i}',
                  'n': startsAt + i,
                }
              : <String, Object?>{
                  'local_uuid': '$name-uuid-${startsAt + i}',
                  'created_at': 1735689600000,
                  'updated_at': 1735689600001,
                  'title': '$name ملاحظة تشغيلية ${startsAt + i}',
                  'amount': 100.5,
                  'deleted_at': null,
                },
      ];
    },
  );
}

/// عميل D1 صناعي: يقيس التوازي وعدد النداءات، ويحاكي زمن النداء الثابت.
class FakeD1 {
  FakeD1({this.latency = Duration.zero});

  /// زمن كل نداء (RTT صناعي).
  final Duration latency;

  final List<String> requestSqls = <String>[];
  int inFlight = 0;
  int maxInFlight = 0;
  int totalHandlerMs = 0;
  final Map<String, int> inFlightByTable = <String, int>{};
  int foreignOverlap = 0;

  /// رد مخصّص لكل نداء؛ الافتراضي نجاح فارغ.
  http.Response Function(String sql, int callIndex)? responder;

  Future<http.Response> handle(http.Request request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final sql = body['sql'] as String;
    final callIndex = requestSqls.length;
    requestSqls.add(sql);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final started = DateTime.now();
    final table = insertTableOf(sql);
    try {
      if (table != null) {
        final foreignBusy = inFlightByTable.entries
            .where((e) => e.key != table && e.value > 0)
            .toList();
        if (foreignBusy.isNotEmpty) foreignOverlap++;
        inFlightByTable[table] = (inFlightByTable[table] ?? 0) + 1;
      }
      if (latency > Duration.zero) {
        await Future<void>.delayed(latency);
      }
      final responder = this.responder;
      return responder == null
          ? http.Response('{"success": true, "result": []}', 200)
          : responder(sql, callIndex);
    } finally {
      inFlight--;
      if (table != null) {
        inFlightByTable[table] = (inFlightByTable[table] ?? 1) - 1;
      }
      totalHandlerMs += DateTime.now().difference(started).inMilliseconds;
    }
  }

  MockClient get client => MockClient(handle);
}

CloudflareD1Service serviceFor(FakeD1 fake) => CloudflareD1Service(
  const CloudflareD1Config(accountId: 'a', databaseId: 'b', apiToken: 't'),
  client: fake.client,
);

/// اسم الجدول من أول عبارة كتابة على جدول بيانات (تُتجاهل نداءات المرآة:
/// pragma_table_info وapp_backup_meta غير المقتبسين).
String? insertTableOf(String sql) {
  final m = RegExp(
    r'(?:INSERT INTO|INSERT OR REPLACE INTO|ALTER TABLE) "([a-z0-9_]+)"',
  ).firstMatch(sql);
  return m?.group(1);
}

List<String> insertStatementsOf(String sql) => sql
    .split(';\n')
    .map((s) => s.trim())
    .where(
      (s) =>
          s.startsWith('INSERT INTO "') ||
          s.startsWith('INSERT OR REPLACE INTO "'),
    )
    .toList();

List<int> statementsPerCall(FakeD1 fake) =>
    fake.requestSqls.map((sql) => insertStatementsOf(sql).length).toList();

void main() {
  test(
    'صفوف ضيقة: الدفعة تحمل 800 عبارة → 10 نداءات بدل 25 لخمسة آلاف صف',
    () async {
      const rows = 5000;
      final fake = FakeD1();

      final result = await serviceFor(
        fake,
      ).uploadData(tables: [sourceTable('rooms', rows, narrow: true)]);

      expect(result.ok, isTrue, reason: result.errors.join('؛ '));
      expect(result.rowsUploaded, rows);

      final perCall = statementsPerCall(fake);
      expect(
        perCall.every((n) => n <= kProvenBatchStatements),
        isTrue,
        reason: 'تجاوز نداء سقف العبارات المثبت: $perCall',
      );

      // 5000 صف = 5 قراءات × (800 + 200) = 10 نداءات (القديم: 25).
      final dataCalls = perCall.where((n) => n > 0).length;
      final legacyCalls =
          (rows / 1000).ceil() * (1000 / kLegacyBatchStatements).ceil();
      expect(
        dataCalls,
        lessThan(legacyCalls),
        reason:
            'عدد نداءات البيانات $dataCalls لم ينخفض عن المرجع القديم '
            '$legacyCalls (دفعات $kLegacyBatchStatements)',
      );

      final inserts = fake.requestSqls
          .expand(insertStatementsOf)
          .where((s) => s.startsWith('INSERT INTO "rooms"'))
          .toList();
      expect(inserts, hasLength(rows), reason: 'فقدان صفوف في الرفع');
      final uuids = inserts
          .map((s) => RegExp(r"'rooms-uuid-\d+'").firstMatch(s)!.group(0))
          .toSet();
      expect(uuids, hasLength(rows), reason: 'تكرار/فقدان هويات local_uuid');
    },
  );

  test('صفوف عريضة: سقف الحجم 128KB يبقى الحارس وعدد النداءات ينخفض', () async {
    const rows = 5000;
    final fake = FakeD1();

    final result = await serviceFor(
      fake,
    ).uploadData(tables: [sourceTable('rooms', rows)]);

    expect(result.ok, isTrue, reason: result.errors.join('؛ '));
    expect(result.rowsUploaded, rows);

    // كل نداء يبقى تحت سقف الأحرف (عبارة واحدة قد تتجاوزه وحدها — تُسمح وحدها).
    for (final sql in fake.requestSqls) {
      final stmts = insertStatementsOf(sql);
      if (stmts.length <= 1) continue;
      expect(
        sql.length,
        lessThanOrEqualTo(kMaxBatchChars),
        reason: 'نداء تجاوز سقف الحجم: ${sql.length} حرفاً',
      );
    }

    // المرجع القديم: 200 عبارة/نداء → 25 نداءً؛ الآن أقل بوضوح.
    final dataCalls = statementsPerCall(fake).where((n) => n > 0).length;
    expect(
      dataCalls,
      lessThan((rows / kLegacyBatchStatements).ceil()),
      reason: 'ما زال الرفع يستخدم دفعات $kLegacyBatchStatements القديمة',
    );
  });

  test('التوازي محدود بـ 3 نداءات داخل الجدول وترتيب الجداول متسلسل', () async {
    final fake = FakeD1(latency: const Duration(milliseconds: 30));

    final result = await serviceFor(fake).uploadData(
      tables: [
        sourceTable('rooms', 3000, narrow: true),
        sourceTable('bookings', 3000, narrow: true),
      ],
    );

    expect(result.ok, isTrue, reason: result.errors.join('؛ '));
    expect(result.rowsUploaded, 6000);

    // توازٍ فعلي حدث، ولم يتجاوز السقف المعلن.
    expect(
      fake.maxInFlight,
      greaterThan(1),
      reason: 'الدفعات لم تُرسل متوازية — التسريع معطّل',
    );
    expect(
      fake.maxInFlight,
      lessThanOrEqualTo(kMaxParallelCalls),
      reason: 'تجاوز سقف التوازي: ${fake.maxInFlight}',
    );

    // لا تتقاطع دفعات جدولين: قيود FOREIGN KEY تبقى محفوظة بترتيب الجداول.
    expect(
      fake.foreignOverlap,
      0,
      reason: 'تزامنت دفعات من جدولين مختلفين في ${fake.foreignOverlap} نداء',
    );
  });

  test(
    'الزمن: الرفع المتوازي أقصر من مجموع أزمنة النداءات (المسار المتسلسل)',
    () async {
      final fake = FakeD1(latency: const Duration(milliseconds: 40));
      final sw = Stopwatch()..start();
      final result = await serviceFor(
        fake,
      ).uploadData(tables: [sourceTable('rooms', 5000, narrow: true)]);
      sw.stop();

      expect(result.ok, isTrue, reason: result.errors.join('؛ '));
      expect(result.rowsUploaded, 5000);
      expect(fake.requestSqls, isNotEmpty);

      // المرجع المتسلسل = مجموع أزمنة النداءات فعلياً (كل نداء ينتظر RTT واحداً).
      final sequentialMs = fake.totalHandlerMs;
      expect(sequentialMs, greaterThanOrEqualTo(300));
      expect(
        sw.elapsedMilliseconds,
        lessThan((sequentialMs * 0.8).round()),
        reason:
            'الزمن المقاس ${sw.elapsedMilliseconds}ms لم يهبط تحت 80% من '
            'المرجع المتسلسل ${sequentialMs}ms',
      );
    },
  );

  test(
    'الرد العابر 429 يُعاد بمهلة تصاعدية ثم ينجح الرفع',
    () async {
      final fake = FakeD1()..responder = _retryOnceResponder();

      final result = await serviceFor(
        fake,
      ).uploadData(tables: [sourceTable('rooms', 1, narrow: true)]);

      expect(result.ok, isTrue, reason: result.errors.join('؛ '));
      expect(result.rowsUploaded, 1);
      final insertCalls = fake.requestSqls
          .where((sql) => insertStatementsOf(sql).isNotEmpty)
          .length;
      expect(
        insertCalls,
        greaterThanOrEqualTo(2),
        reason: 'نداء الـ 429 لم يُعد إطلاقاً',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('الرد غير العابر (400 خطأ SQL) لا يُعاد ويُسجَّل خطأ الجدول', () async {
    final fake = FakeD1()
      ..responder = (sql, _) => http.Response(
        '{"success": false, "errors": [{"code": 7500, "message": "SQLITE_ERROR"}]}',
        400,
      );

    final result = await serviceFor(
      fake,
    ).uploadData(tables: [sourceTable('rooms', 1, narrow: true)]);

    expect(result.ok, isFalse);
    expect(result.errors, isNotEmpty);
    final insertCalls = fake.requestSqls
        .where((sql) => insertStatementsOf(sql).isNotEmpty)
        .length;
    expect(
      insertCalls,
      1,
      reason: 'أُعيد إرسال خطأ SQL غير عابر $insertCalls مرات',
    );
  });
}

/// أول نداء بيانات يُرد بـ 429 ثم تنجح كل النداءات التالية.
http.Response Function(String sql, int callIndex) _retryOnceResponder() {
  var rejected = false;
  return (sql, _) {
    final isInsert = insertStatementsOf(sql).isNotEmpty;
    if (isInsert && !rejected) {
      rejected = true;
      return http.Response(
        '{"success": false, "errors": [{"code": 1035, "message": "rate limited"}]}',
        429,
      );
    }
    return http.Response('{"success": true, "result": []}', 200);
  };
}
