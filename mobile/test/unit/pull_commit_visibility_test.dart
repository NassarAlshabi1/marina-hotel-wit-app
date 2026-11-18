// test/unit/pull_commit_visibility_test.dart
//
// ✅ درع انحدار لانهيار Crashlytics القاتل CouldNotRollBackException
// (COMMIT/ROLLBACK «no transaction is active») — نفس منهجية حارس N+1
// (booking_nights_pull_scale_test.dart): الكود الإنتاجي نفسه بلا محاكاة،
// عبر جسر @visibleForTesting.
//
// البنية القديمة (pre-21ab42cb) كانت تلف دورة السحب كاملة في
// `database.transaction` واحدة، وتسلسل الانهيار كان:
//   1. خطأ كشف صف واحد من عائلة (SQLITE_FULL / SQLITE_IOERR / ...)
//      يُنهي معاملة SQLite بأكملها تلقائياً (auto-rollback).
//   2. onTaskError لا يوقف الدورة → الكتابات اللاحقة تنفّذ في
//      auto-commit صامتاً.
//   3. COMMIT النهائي يفشل: «cannot commit - no transaction is active»
//      → drift يرسل ROLLBACK للتنظيف → يفشل أيضاً → CouldNotRollBackException.
//   4. إضافةً لذلك: write-lock واحدة محتجزة طوال السحب (دقائق على شبكة
//      ضعيفة) → تجميد كل الكتابات المحلية (حجز/دفعة/مصروف) — وهو السبب
//      الأصلي لإزالة الغلاف في 21ab42cb.
//
// هذا الملف يثبت عقدين سلوكيين للبنية الحالية على قاعدة ملف حقيقية
// (WAL — نفس beforeOpen الإنتاجي) مع اتصال sqlite3 خارجي مستقل عن drift:
//
//   A) «كل صفحة تُثبَّت بمعاملتها الخاصة»: بعد تطبيق الصفحة الأولى
//      يرى اتصال خارجي صفوفها فوراً (committed) بينما الدورة مستمرة.
//   B) «لا write-lock ممتدة»: كاتب خارجي يستطيع BEGIN IMMEDIATE بين
//      الصفحات — الواجهة ليست مجمدة أثناء السحب.
//
// ثم يعيد إنتاج البنية القديمة عمداً (database.transaction تلف عدة
// صفحات) ويُثبت أن المنهجية تكشفها — أي أن الحارس أعلاه قاطع لا صوري:
// لو أُعيد الغلاف القديم حول دورة السحب فشلت فحوصات العقد A/B بالضبط
// كما تنجح فحوصات التحكم السلبي.
//
// ⚠️ اختبار واحد متصل عمداً (ثلاث فصول): AppwriteSyncManager singleton
// بمُنشئ factory يتجاهل المعامل database بعد أول إنشاء — قاعدة ثانية
// في نفس الملف ستستلم مديناً باتصال مغلق («Can't re-open a database
// after closing it»). نفس نمط scale harness (سيناريوهات متتالية على
// نفس القاعدة والمدير).

// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:appwrite/models.dart' as models;
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;

import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

const int _kPageSize = 100; // مطابق UnifiedPullEngine.fullSyncPageSize.
const int _kTotalNights = 300; // 3 صفحات: فصلان للعقد + فصل التحكم.
const int _kRooms = 5; // غرف 211..251 — نفس صيغة scale harness.
const int _kBookings = 15; // i ~/ 20 → 15 حجزاً لـ 300 ليلة.
const int _kBaseEpochSec = 1760000000;

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
      'deviceId': 'canary-device',
    },
  );
}

/// بذر الآباء (غرف + حجوزات) — نفس أشكال scale harness (FK سليمة).
Future<void> _seedParents(AppDatabase db) async {
  final rooms = <RoomsCompanion>[];
  for (var r = 0; r < _kRooms; r++) {
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
}

/// اتصال sqlite3 خارجي مستقل تماماً عن اتصال drift — يرى الصور
/// المُثبَّتة فقط (committed)، تماماً كعملية أخرى في التطبيق.
raw_sqlite.Database _openObserver(String path) {
  final observer = raw_sqlite.sqlite3.open(path);
  // مهلة قصيرة لمسبار القفل — القفل المحتجز يجب أن يُكشف خلالها لا أن
  // يعلّق الاختبار (الوضع الطبيعي: القفل حر فتنجح فوراً).
  observer.execute('PRAGMA busy_timeout = 250');
  return observer;
}

int _observerNightCount(raw_sqlite.Database observer) =>
    observer.select('SELECT COUNT(*) FROM booking_nights').first.values.first
        as int;

/// هل يمكن لكاتب خارجي انتزاع write-lock الآن؟ (عقد «الواجهة غير مجمدة»)
bool _externalWriterCanAcquireWriteLock(raw_sqlite.Database observer) {
  try {
    observer.execute('BEGIN IMMEDIATE');
    observer.execute('ROLLBACK');
    return true;
  } catch (_) {
    // SQLITE_BUSY: كاتب آخر (اتصال drift) يحتجز write-lock.
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'درع CouldNotRollBack: صفحات السحب تُثبَّت بمعاملتها الخاصة (والبنية القديمة تُكشف)',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tmpDir = await Directory.systemTemp.createTemp('pull_commit_vis');
      addTearDown(() async {
        try {
          await tmpDir.delete(recursive: true);
        } catch (_) {
          // أفضل-جهد — أنظمة CI المختلفة قد تبقي مقابض مؤقتة.
        }
      });

      // قاعدة ملف حقيقية (WAL من beforeOpen الإنتاجي) — شرط أساسي لرؤية
      // اتصال خارجي لما ثُبِّت وما لم يُثبَّت بعد.
      final dbPath = '${tmpDir.path}/app.db';
      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);
      AdapterRegistry.initialize(db);
      await _seedParents(db);

      // المدير الحقيقي (مُنشئ factory بلا شبكة — تعيينات حقول فقط،
      // كما تم التحقق في scale harness).
      final manager = AppwriteSyncManager(
        appwriteService: AppwriteService(),
        database: db,
      );

      final observer = _openObserver(dbPath);
      addTearDown(observer.dispose);

      final docs = List<models.Document>.generate(_kTotalNights, _nightDoc);

      // ═══════════════════════════════════════════════════════════════
      // الفصل 1 — العقد A+B للبنية الحالية (بين الصفحتين 1 و 2)
      // ═══════════════════════════════════════════════════════════════

      // الصفحة 1 — كما يقدّمها المحرك التدفقي (apply لكل صفحة).
      final applied1 = await manager.applyBookingNightsForTesting(
        docs.take(_kPageSize).toList(growable: false),
      );
      expect(applied1, _kPageSize);

      // ⬇️ نقطة الفحص: «بين الصفحتين» — الدورة لم تنتهِ بعد.
      expect(
        _observerNightCount(observer),
        _kPageSize,
        reason:
            'العقد A: صفحة 1 مُثبَّتة (committed) بمعاملتها الخاصة '
            'ومرئية لاتصال خارجي فوراً. لو أُعيد غلاف database.transaction '
            'القديم حول دورة السحب لرأى القارئ 0 هنا (يثبته الفصل 3) — '
            'وهي مقدمة انهيار «COMMIT: no transaction is active»',
      );
      expect(
        _externalWriterCanAcquireWriteLock(observer),
        isTrue,
        reason:
            'العقد B: write-lock غير محتجزة بين الصفحات — الكتابات '
            'المحلية (حجز/دفعة/مصروف من الواجهة) لا تتجمد أثناء سحب قد '
            'يستغرق دقائق على شبكة ضعيفة',
      );

      // الصفحة 2 — تُثبَّت بدورها بمعاملتها الخاصة.
      final applied2 = await manager.applyBookingNightsForTesting(
        docs.skip(_kPageSize).take(_kPageSize).toList(growable: false),
      );
      expect(applied2, _kPageSize);
      expect(_observerNightCount(observer), _kPageSize * 2);

      // ═══════════════════════════════════════════════════════════════
      // الفصل 2 — العقد A+B بعد الصفحة الثانية (نفس الاستدلال)
      // ═══════════════════════════════════════════════════════════════
      expect(
        _externalWriterCanAcquireWriteLock(observer),
        isTrue,
        reason:
            'العقد B بعد عدة صفحات: لا write-lock متراكمة — كل دفعة '
            'db.batch (250) تُغلق معاملتها عند نهايتها',
      );

      // ═══════════════════════════════════════════════════════════════
      // الفصل 3 — التحكم السلبي: البنية القديمة (transaction واحدة تلف
      // عدة صفحات) تُكشف بنفس المنهجية — إثبات أن الحارس أعلاه قاطع.
      // ═══════════════════════════════════════════════════════════════

      // الصفحة 3 (docs 200..299) داخل معاملة ممتدة — إعادة إنتاج عمدية
      // لنمط pre-21ab42cb.
      await db.transaction(() async {
        final applied3 = await manager.applyBookingNightsForTesting(
          docs.skip(_kPageSize * 2).toList(growable: false),
        );
        expect(applied3, _kPageSize);

        expect(
          _observerNightCount(observer),
          _kPageSize * 2,
          reason:
              'داخل معاملة ممتدة: كتابات الصفحة 3 غير مرئية للخارج '
              '(uncommitted) — لو ارتد غلاف السحب إلى هذه البنية لفشل '
              'فحص العقد A في الفصل 1 عند هذه النقطة بالضبط',
        );
        expect(
          _externalWriterCanAcquireWriteLock(observer),
          isFalse,
          reason:
              'write-lock محتجزة داخل معاملة ممتدة — هذا هو تجميد '
              'الواجهة الذي أزاله 21ab42cb',
        );
      });

      // بعد COMMIT: الكل يصبح مرئياً — هذا ما كانت البنية القديمة تصل
      // إليه «ناجحاً»؛ انهيار الإنتاج حدث حين تنتهي المعاملة صامتاً
      // (خطأ كشف صف) فيفشل COMMIT بـ «no transaction is active».
      expect(_observerNightCount(observer), _kTotalNights);
    },
  );
}
