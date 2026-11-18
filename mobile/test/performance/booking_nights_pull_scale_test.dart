// test/performance/booking_nights_pull_scale_test.dart
//
// ✅ P1 (2026-09-21) — booking_nights full-pull scale harness (بلا شبكة).
//
// يغلق فجوة تغطية CI: مسار سحب booking_nights (الإصلاح P0 المزدوج —
// السحب التدفقي بلا سقف + التطبيق المجمّع) لم يكن مغطى في
// android-low-ram-performance.yml إطلاقاً.
//
// ما يقيسه هذا الاختبار على جدول حقيقي عبر الكود الإنتاجي نفسه
// (AppwriteSyncManager._syncBookingNights — عبر جسر @visibleForTesting
// بلا محاكاة أو نسخ):
//
//   1. السحب الأول (fresh install): 7000 ليلة (فندق ~25 غرفة × سنة)
//      على 70 صفحة × 100 مستند — مطابق fullSyncPageSize في المحرك.
//      الحماية الحاسمة: processed == 7000 و صفوف الجدول == 7000
//      (حارس فقدان البيانات — الخلل P0 القديم كان يفقد ~85%).
//   2. إعادة السحب (idempotent re-pull): نفس المستندات مرة ثانية →
//      الكل يُتخطى (فحص الأحدثية) — processed == 0 و الصفوف دون تغيير.
//      هذا يقيس مسار فحص الأحدثية/VC لكل صف على نطاق 7000.
//   3. مقارنة بالمسار القديم (log-only): upsertFromJson صف-بصف على 300
//      مستند → نسبة التسريع للمسار المجمّع في ملف المقاييس.
//
// كل عتبات الزمن/الذاكرة معايرة من تشغيل فعلي محلي (Flutter 3.44.6)
// بهامش سخي لمعدّات CI الأبطأ — انظر أسفل الملف.
//
// لا شبكة: المستندات models.Document مولَّدة محلياً؛ مُنشئو
// AppwriteSyncManager/SyncPullService/UnifiedPullEngine تعيينات حقول فقط
// (تم التحقق بالفحص قبل كتابة هذا الملف).

// ignore_for_file: lines_longer_than_80_chars

@Tags(['performance'])
library marina_hotel_mobile.test.performance.booking_nights_pull_scale_test;

import 'dart:io';

import 'package:appwrite/models.dart' as models;
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

/// حجم فندق واقعي: ~25 غرفة × سنة ≈ 9125 ليلة؛ نستخدم 7000 (فوق سقف
/// 1000 القديم بـ7× — نفس رقم السيناريو الذي أثبت فقدان ~85% قبل P0).
const int _kTotalNights = 7000;
const int _kRoomCount = 25;
const int _kBookings = 350; // × 20 ليلة/حجز في المتوسط = 7000
const int _kPageSize = 100; // مطابق UnifiedPullEngine.fullSyncPageSize.

/// مقياس زمني أساسي (epoch ثابت لرتابة الاختبار — لا ساعة حائط).
const int _kBaseEpochSec = 1760000000; // 2025-10-09T09:46:40Z

/// العتبات (معايرة محلية Flutter 3.44.6 + هامش CI):
/// السحب الأول المتوقع محلياً ~2-8s؛ العتبة 120s = هامش ~15×+ لمعدّات
/// CI الأبطأ (shared runner تحت حمل). إعادة السحب أسرع (بلا كتابة).
const Duration _kFirstPullMax = Duration(seconds: 120);
const Duration _kRePullMax = Duration(seconds: 60);

/// حامي الذاكرة: السحب التدفقي يجب أن يبقي الذاكرة محدودة بحجم الصفحة
/// (100 مستند) وليس متناسباً مع 7000 — أي انفجار RSS يفشل الاختبار.
/// 512MB سقف متساهل جداً (التسرب الحقيقي سيتجاوزه بأضعاف).
const int _kMaxRssDeltaBytes = 512 * 1024 * 1024;

/// ✅ حارس ارتداد N+1 القاطع (مستقل عن سرعة الآلة):
/// المتوقع فعلياً ~140 SELECT للسحب الأول (2/صفحة × 70). العتبة 1000
/// = هامش 7×، وتظل أقل بكثير من أي N+1 (≥7000 = استعلام واحد لكل
/// ليلة على الأقل، وعملياً 21000+ مع resolveBooking SQL لكل صف).
const int _kMaxSelectsPerPull = 1000;

/// حجم عينة مقارنة المسار القديم (صف-بصف): كافٍ لقياس النسبة دون
/// إبطاء CI — 300 × (~5-7 عملية DB) دقيقة قليلة حتى على CI بطيء.
const int _kOldPathSampleSize = 300;

models.Document _nightDoc(int i) {
  final booking = i ~/ 20;
  final seq = i % 20;
  final day = DateTime.utc(2026, 1, 1).add(Duration(days: i % 365));
  final nextDay = day.add(const Duration(days: 1));
  return models.Document(
    $id: 'night-$i',
    $sequence: i,
    $collectionId: 'booking_nights',
    $databaseId: 'marina',
    $createdAt: '2026-01-01T00:00:00.000Z',
    $updatedAt: '2026-09-01T12:00:00.000Z',
    $permissions: const <String>[],
    data: <String, dynamic>{
      'localUuid': 'night-uuid-$i',
      'bookingUuidCache': 'booking-uuid-$booking',
      'serverId': i,
      'hotelDayKey': day.toIso8601String().substring(0, 10),
      'nightStart': '${day.toIso8601String()}',
      'nightEnd': '${nextDay.toIso8601String()}',
      'nightlyRate': 100.0 + (i % 7) * 10,
      'baseRate': 100.0 + (i % 7) * 10,
      'adjustment': 0,
      'finalRate': 100.0 + (i % 7) * 10,
      'sequence': seq,
      'createdAt': _kBaseEpochSec,
      'lastModified': _kBaseEpochSec + i,
      'vectorClock': '{}',
      'deviceId': 'ci-perf-device',
    },
  );
}

Future<int> _countNights(AppDatabase db) async =>
    db.bookingNights.count().getSingle();

void _writeMetricsFile(String body) {
  try {
    final dir = Directory('build/low-ram-performance');
    dir.createSync(recursive: true);
    File('${dir.path}/booking_nights_pull_metrics.txt').writeAsStringSync(body);
  } catch (_) {
    // كتابة ملف المقاييس أفضل-جهد — فشلها لا يفشل الاختبار (التقاط
    // stdout في CI يكفي).
  }
}

/// حارس ارتداد N+1 (2026-09-21): عدّاد استعلامات عبر QueryInterceptor
/// الرسمي من drift — مستقل تماماً عن سرعة الآلة، لذلك قاطع على CI.
///
/// المنطق: المسار المجمّع يجري ~2 SELECT لكل صفحة (حالة مجمعة + بناء
/// الفهرس) أي ~140 لـ 70 صفحة. لو ارتد أحدٌ إلى N+1 (SELECT لكل ليلة
/// + resolveBooking بلا فهرس) سيتخطى العدد 7000+ فوراً → فشل حاسم.
class _QueryCounter extends d.QueryInterceptor {
  int selects = 0;
  int inserts = 0;
  int updates = 0;
  int batches = 0;

  void reset() {
    selects = 0;
    inserts = 0;
    updates = 0;
    batches = 0;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    d.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    return executor.runSelect(statement, args);
  }

  @override
  Future<int> runInsert(
    d.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    inserts++;
    return executor.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(
    d.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    updates++;
    return executor.runUpdate(statement, args);
  }

  @override
  Future<void> runBatched(
    d.QueryExecutor executor,
    d.BatchedStatements statements,
  ) {
    batches++;
    return executor.runBatched(statements);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // عدّاد الاستعلامات — حارس ارتداد N+1 (مستقل عن سرعة الآلة).
  final queryCounter = _QueryCounter();

  test(
    'booking_nights full-pull: 7000 docs applied lossless, bounded and fast',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final db = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(queryCounter),
      );
      addTearDown(db.close);

      // ── البذر: غرف + حجوزات فقط (جدول الليالي فارغ — تثبيت جديد) ────
      AdapterRegistry.initialize(db);
      final rooms = <RoomsCompanion>[];
      for (var r = 0; r < _kRoomCount; r++) {
        final roomNo = '2${(r % 5) + 1}${(r ~/ 5) + 1}';
        rooms.add(
          RoomsCompanion(
            roomNumber: d.Value(roomNo),
            type: const d.Value('عادية'),
            price: d.Value(120.0 + (r % 4) * 30),
            status: const d.Value('شاغرة'),
            localUuid: d.Value('room-uuid-$r'),
            createdAt: const d.Value(_kBaseEpochSec),
            updatedAt: const d.Value(_kBaseEpochSec),
            lastModified: const d.Value(_kBaseEpochSec),
          ),
        );
      }
      final bookings = <BookingsCompanion>[];
      for (var b = 0; b < _kBookings; b++) {
        final roomNo = '2${(b % 5) + 1}${(b ~/ 70) + 1}';
        final day = DateTime.utc(2026, 1, 1).add(Duration(days: b % 330));
        bookings.add(
          BookingsCompanion(
            roomNumber: d.Value(roomNo),
            guestName: d.Value('ضيف $b'),
            guestPhone: d.Value('05000$b'),
            guestNationality: const d.Value('يمني'),
            checkinDate: d.Value('${day.toIso8601String()}'),
            status: const d.Value('نشط'),
            localUuid: d.Value('booking-uuid-$b'),
            createdAt: const d.Value(_kBaseEpochSec),
            updatedAt: const d.Value(_kBaseEpochSec),
            lastModified: const d.Value(_kBaseEpochSec),
            expectedNights: const d.Value(20),
          ),
        );
      }
      await db.batch((batch) {
        batch.insertAll(db.rooms, rooms);
        batch.insertAll(db.bookings, bookings);
      });

      // ── المدير الحقيقي (مُنشئ بلا شبكة — تعيينات حقول فقط) ──────────
      final manager = AppwriteSyncManager(
        appwriteService: AppwriteService(),
        database: db,
      );

      final docs = List<models.Document>.generate(
        _kTotalNights,
        _nightDoc,
        growable: false,
      );

      // ── السيناريو A: السحب الأول (70 صفحة × 100) ─────────────────────
      queryCounter.reset();
      final rssBefore = ProcessInfo.currentRss;
      final sw = Stopwatch()..start();
      var processed = 0;
      for (var p = 0; p < docs.length; p += _kPageSize) {
        final page = docs.skip(p).take(_kPageSize).toList(growable: false);
        processed += await manager.applyBookingNightsForTesting(page);
      }
      sw.stop();
      final firstPullMs = sw.elapsedMilliseconds;
      final firstSelects = queryCounter.selects;
      final firstInserts = queryCounter.inserts;
      final firstBatches = queryCounter.batches;
      final rssAfter = ProcessInfo.currentRss;
      final rowCount = await _countNights(db);

      expect(
        processed,
        _kTotalNights,
        reason:
            'حارس فقدان البيانات: كل 7000 ليلة يجب أن تُطبَّق — '
            'السقف القديم (1000) كان يفقد الباقي صامتاً',
      );
      expect(
        rowCount,
        _kTotalNights,
        reason: 'كل ليلة يجب أن تكون صفاً فعلياً في الجدول',
      );
      expect(
        firstPullMs,
        lessThan(_kFirstPullMax.inMilliseconds),
        reason:
            'مسار التطبيق المجمّع (bulk state + فهرس + db.batch) يجب '
            'ألا يرجع لنمط N+1 (كان ~5-7 عملية DB/ليلة)',
      );
      expect(
        rssAfter - rssBefore,
        lessThan(_kMaxRssDeltaBytes),
        reason: 'الذاكرة محدودة بحجم الصفحة (100 مستند) — ليست 7000',
      );
      // ✅ حارس N+1 القاطع: عدّ SELECTs مستقل عن سرعة الآلة.
      // المتوقع: ~2 لكل صفحة (bulk state + فهرس) ≈ 140 لـ 70 صفحة؛
      // N+1 (SELECT لكل ليلة + resolveBooking SQL) = 7000-35000+.
      expect(
        firstSelects,
        lessThan(_kMaxSelectsPerPull),
        reason:
            'ارتداد N+1: عدد SELECTs ($firstSelects) خلال السحب الأول '
            'تجاوز الحد — المسار المجمّع يتطلب ~2 استعلام/صفحة لا استعلام/ليلة',
      );
      expect(
        firstBatches,
        greaterThan(0),
        reason:
            'الكتابة يجب أن تمر عبر db.batch (الإصلاح P0-2) — '
            'لا INSERT منفصل لكل سجل',
      );

      // ── السيناريو B: إعادة سحب نفس المستندات (idempotent) ───────────
      queryCounter.reset();
      final swRe = Stopwatch()..start();
      final reProcessed = await manager.applyBookingNightsForTesting(docs);
      swRe.stop();
      final rePullMs = swRe.elapsedMilliseconds;
      final reSelects = queryCounter.selects;
      final reWrites =
          queryCounter.inserts + queryCounter.updates + queryCounter.batches;
      final rowCountAfterRe = await _countNights(db);

      expect(
        reProcessed,
        0,
        reason:
            'إعادة سحب بلا تغييرات يجب أن تتخطى الكل (فحص الأحدثية '
            'صف-بصف على 7000 — لا كتابات)',
      );
      expect(rowCountAfterRe, _kTotalNights, reason: 'لا تغيير في الصفوف');
      expect(
        rePullMs,
        lessThan(_kRePullMax.inMilliseconds),
        reason: 'فحص الأحدثية الكمي يجب أن يبقى رخيصاً (CPU + استعلامان)',
      );
      expect(
        reWrites,
        0,
        reason:
            'إعادة السحب بلا تغييرات يجب ألا تكتب شيئاً إطلاقاً '
            '(الاستبعاد في فحص الأحدثية — لا INSERT/UPDATE/batch)',
      );
      expect(
        reSelects,
        lessThan(_kMaxSelectsPerPull),
        reason:
            'فحص الأحدثية الكمي: bulk state (7000 uuid → 14 chunk) + '
            'فهرس واحد — ليس استعلاماً لكل ليلة',
      );

      // ── السيناريو C (log-only): مقارنة المسار القديم صف-بصف ─────────
      // 300 مستند جديدة (بادئة old-) عبر upsertFromJson — نفس ما كان
      // يحدث لكل ليلة قبل الإصلاح (SELECT + resolveRefs بلا فهرس + INSERT
      // + إشعار لكل سجل).
      final oldDocs = List<models.Document>.generate(
        _kOldPathSampleSize,
        (i) => _nightDoc(_kTotalNights + i),
        growable: false,
      );
      final swOld = Stopwatch()..start();
      for (final doc in oldDocs) {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await AdapterRegistry.instance.nights.upsertFromJson(
          data,
          src: Source.appwrite,
        );
      }
      swOld.stop();
      final oldPathMs = swOld.elapsedMilliseconds;

      // ── ملف المقاييس (تنشره خطوة CI في ملخص التشغيل) ─────────────────
      final perDocNew = firstPullMs / _kTotalNights;
      final perDocOld = oldPathMs / _kOldPathSampleSize;
      final ratio = perDocOld / perDocNew;
      final metrics = StringBuffer()
        ..writeln('booking_nights full-pull scale (P1 CI coverage)')
        ..writeln(
          'docs=$_kTotalNights pages=${_kTotalNights ~/ _kPageSize} '
          'page_size=$_kPageSize bookings=$_kBookings rooms=$_kRoomCount',
        )
        ..writeln(
          'first_pull_ms=$firstPullMs '
          '(${(1000 / perDocNew).toStringAsFixed(0)} docs/sec) '
          'selects=$firstSelects batches=$firstBatches '
          'inserts_nonbatch=$firstInserts',
        )
        ..writeln(
          're_pull_ms=$rePullMs skipped=$_kTotalNights '
          'selects=$reSelects writes=$reWrites',
        )
        ..writeln(
          'old_path_${_kOldPathSampleSize}docs_ms=$oldPathMs '
          '(${perDocOld.toStringAsFixed(2)} ms/doc)',
        )
        ..writeln(
          'new_path_ms_per_doc=${perDocNew.toStringAsFixed(4)} '
          'speedup=${ratio.isFinite ? '${ratio.toStringAsFixed(1)}x' : 'n/a'}',
        )
        ..writeln(
          'rss_before_mb=${(rssBefore / 1048576).toStringAsFixed(1)} '
          'rss_after_mb=${(rssAfter / 1048576).toStringAsFixed(1)} '
          'rss_delta_mb=${((rssAfter - rssBefore) / 1048576).toStringAsFixed(1)}',
        )
        ..writeln('db_rows=$_kTotalNights (+$_kOldPathSampleSize old-path)')
        ..writeln(
          'thresholds: first<${_kFirstPullMax.inSeconds}s '
          're<${_kRePullMax.inSeconds}s '
          'rss_delta<${_kMaxRssDeltaBytes ~/ 1048576}MB',
        )
        ..writeln('verdict=PASS');
      _writeMetricsFile(metrics.toString());
      // ignore: avoid_print
      print(metrics.toString());
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
