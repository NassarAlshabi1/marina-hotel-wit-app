// ============================================================================
//  اختبارات عميقة — مصفوفة مداخل السحب (Pull Entry Matrix)
//  تقليل السحب — الخطوات 1+2+4 (2026-08-31)
// ============================================================================
//  المنهجية: نفس منهجية realtime_priority_sync_integration_test —
//  المدير الحقيقي + Drift في الذاكرة + طبقة شبكة وهمية "فشل صاخب".
//
//  ما تثبه:
//   E1  دورة عادية ثانية خلال فجوة الدقيقتين → يمنعها الحارس المركزي
//       (صفر استدعاءات شبكة) — الخطوة 1.
//   E2  sync(push: false, forcePull: true) خلال الفجوة نفسها → سحب فعلي
//       كامل (الزر اليدوي يسحب فوراً) — الخطوة 2.
//   E3  sync(forcePull: true) كاملة (push+pull) خلال الفجوة → السحب يعمل
//       والرفع يبقى سليماً.
//   E4  عقود الثوابت: minPullGap=2 دقائق، المؤقت الدوري 15 دقيقة (نافذة
//       10–15)، فاصل السحب عند الفتح ساعة.
//   E5  كيان بمؤشر خاص متقدم يمضي delta حتى لو كان وضع الدورة العام full
//       (fullSyncComplete=0 بفشل كيان آخر) — القرار على مستوى الكيان.
//   E6  كيان بلا مؤشر خاص في وضع عام full يبقى full له — شبكة الكمال
//       محفوظة (لا cutoff = مسح كامل للكيان).
//   S1..S4 عقود مصادر (tripwires ثابتة على الكود المصدري):
//       S1 فتح Dashboard يستدعي sync(deltaOnly:true) فقط — سحب ذكي مُقيَّد
//         (SyncGate + فحص ساعة) — لا Full Sync من الشاشة أبداً.
//       S2 زر التحديث (DashboardSyncButton) يمرر forcePull: true.
//       S3 EnhancedSyncButton يمرر forcePull: true في موضعيه.
//       S4 فحص الجلسة (AppSessionManager) يحتفظ بالتقييد الذكي (ساعة)
//          ويستدعي sync مرة واحدة فقط.
// ============================================================================

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:appwrite/models.dart' as models;
// ignore: depend_on_referenced_packages (واجهة المنصة لمحاكاة الاتصال فقط)
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_network_helper.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// بنية تحتية (نفس منهجية اختبارات التكامل السابقة)
// ─────────────────────────────────────────────────────────────────────────────

class _FakeConnectivityPlatform extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Future<void> ensureInitialized() async {}
}

/// تسجيل استدعاء metadata مع الفلاتر المُمرَّرة — للتمييز بين قراءة
/// delta (فلتر cutoff) وقراءة full (بلا فلتر زمني) في الادعاءات.
class _MetaCall {
  _MetaCall(this.collectionId, this.extraQueries);
  final String collectionId;
  final List<String> extraQueries;
}

/// خدمة Appwrite وهمية — فشل صاخب لكل استدعاء غير متوقع.
class _FakeAppwriteService implements AppwriteService {
  final Map<String, List<models.Document>> serverCollections = {};
  final List<String> callNames = [];
  final List<_MetaCall> metadataCalls = [];

  /// مراقب نجاح الرفع — حقل حقيقي كي يلتقطه مُنشئ المدير
  /// (بدون هذا يقع الـ setter في noSuchMethod → فشل صاخب عند البناء).
  @override
  void Function(String collectionId, models.Document document)?
  onDocumentUpserted;

  void reset() {
    serverCollections.clear();
    callNames.clear();
    metadataCalls.clear();
  }

  String _memberName(Invocation invocation) {
    final raw = invocation.memberName.toString();
    final start = raw.indexOf('"');
    return start >= 0 ? raw.substring(start + 1, raw.length - 2) : raw;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = _memberName(invocation);
    callNames.add(name);

    switch (name) {
      case 'initialize':
        return Future<void>.value();

      case 'isInitialized':
        return true;

      case 'listDocumentsMetadata':
        final collectionId = invocation.positionalArguments[0].toString();
        final extra =
            (invocation.namedArguments[#extraQueries] as List<String>?) ??
            const <String>[];
        metadataCalls.add(_MetaCall(collectionId, List.of(extra)));
        return Future<List<models.Document>>.value(
          List.of(serverCollections[collectionId] ?? const []),
        );

      case 'listDocumentsByIds':
        final collectionId = invocation.positionalArguments[0].toString();
        final ids = (invocation.positionalArguments[1] as List).cast<String>();
        final all = serverCollections[collectionId] ?? const [];
        final idSet = ids.toSet();
        return Future<List<models.Document>>.value(
          all.where((d) => idSet.contains(d.$id)).toList(),
        );

      case 'listDocuments':
        final named = invocation.namedArguments;
        final collectionId = named[#collectionId].toString();
        return Future<List<models.Document>>.value(
          List.of(serverCollections[collectionId] ?? const []),
        );

      case 'listBookingNights':
        return Future<List<models.Document>>.value(
          List.of(serverCollections['booking_nights'] ?? const []),
        );

      case 'createSyncLog':
        // سجل المزامنة السحابي غير حرج — المسار يستمر بلا سجل.
        throw StateError('sync-log unavailable (fake)');

      case 'networkHelper':
        // مسار الرفع يقرأ حالة الـ circuit breaker — نسخة حقيقية بلا شبكة.
        return AppwriteNetworkHelper();

      case 'quickConnectionTest':
        return Future<bool>.value(true);
    }

    throw StateError(
      '_FakeAppwriteService: استدعاء غير متوقع → $name. '
      'إذا كان شرعياً في دورة السحب أضفه صراحةً إلى الـ fake.',
    );
  }
}

models.Document mkDoc(String id, int updatedAtSec) {
  final iso = DateTime.fromMillisecondsSinceEpoch(
    updatedAtSec * 1000,
    isUtc: true,
  ).toIso8601String();
  return models.Document(
    $id: id,
    $sequence: updatedAtSec,
    $collectionId: 'blacklist',
    $databaseId: 'main',
    $createdAt: iso,
    $updatedAt: iso,
    $permissions: const [],
    data: const {},
  );
}

/// قراءة ملف مصدري من جذر الحزمة (flutter test يُشغَّل من mobile/).
String readSource(String relativePath) =>
    File('lib/$relativePath').readAsStringSync();

// ─────────────────────────────────────────────────────────────────────────────
// الحزمة
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ConnectivityPlatform.instance = _FakeConnectivityPlatform();

  late AppDatabase db;
  late _FakeAppwriteService fake;
  late AppwriteSyncManager manager;

  db = AppDatabase.forTesting(NativeDatabase.memory());
  fake = _FakeAppwriteService();
  manager = AppwriteSyncManager(appwriteService: fake, database: db);

  Future<void> resetState() async {
    SharedPreferences.setMockInitialValues({});
    fake.reset();
    manager.resetPullThrottleForTesting();
    await (db.delete(db.syncState)).go();
    await (db.delete(db.syncRemoteMeta)).go();
    await (db.delete(db.shiftNotes)).go();
    await (db.delete(db.outbox)).go();
  }

  Future<int> localBlacklistCount() async {
    final rows = await db.select(db.shiftNotes).get();
    return rows.length;
  }

  group('E1→E3: مصفوفة المداخل خلال فجوة الدقيقتين (سلوك فعلي)', () {
    test('E1 الحارس يمنع العادي، E2 forcePull يسحب فوراً، E3 الدورة الكاملة '
        'بـ forcePull تعمل أيضاً', () async {
      await resetState();

      // ── خط الأساس: دورة سحب عادية ناجحة تضبط ساعة الحارس ──
      fake.serverCollections['blacklist'] = [mkDoc('A', 1700001000)];

      final first = await manager.sync(push: false, pull: true);
      expect(first.isSuccess, isTrue, reason: 'الدورة الأولى سليمة');
      expect(await localBlacklistCount(), 1, reason: 'السجل A طُبِّق محلياً');

      // تغيير خادم جديد — docB أحدث من مؤشر الدورة الأولى.
      // ⚠️ الترتيب: reset أولاً (يمسح الخادم والعداد معاً) ثم البذر —
      // reset() يستدعي serverCollections.clear().
      fake.reset();
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000),
        mkDoc('B', 1700001200),
      ];

      // ── E1: دورة عادية ثانية خلال الفجوة → الحارس يمنعها ──
      final blocked = await manager.sync(push: false, pull: true);
      expect(blocked.status, SyncStatus.idle);
      expect(blocked.errorMessage, contains('Pull skipped: minimum pull gap'));
      expect(
        fake.callNames.where((n) => n == 'listDocumentsMetadata'),
        isEmpty,
        reason: 'الحارس المركزي منع السحب — صفر قراءات شبكة',
      );
      expect(
        await localBlacklistCount(),
        1,
        reason: 'لم يُطبَّق أي شيء من الدورة الممنوعة',
      );

      // ── E2: forcePull خلال الفجوة نفسها → سحب فعلي ──
      final forced = await manager.sync(
        push: false,
        pull: true,
        forcePull: true,
      );
      expect(forced.isSuccess, isTrue, reason: 'الزر اليدوي يتجاوز الحارس');
      expect(
        fake.callNames.where((n) => n == 'listDocumentsMetadata'),
        isNotEmpty,
        reason: 'forcePull نفّذ قراءة شبكة فعلية',
      );
      expect(
        forced.recordsPulled,
        greaterThanOrEqualTo(1),
        reason: 'docB سُحب رغم أننا داخل الفجوة',
      );
      expect(await localBlacklistCount(), 2, reason: 'B طُبِّق محلياً');

      // ── E3: دورة كاملة push+pull بـ forcePull خلال الفجوة ──
      fake.reset();
      final fullForced = await manager.sync(
        push: true,
        pull: true,
        forcePull: true,
      );
      expect(
        fullForced.isSuccess,
        isTrue,
        reason: 'دورة كاملة بـ forcePull تعمل خلال الفجوة',
      );
      expect(
        fullForced.errorMessage,
        isNull,
        reason:
            'لا يوجد منع سحب — forcePull يتجاوز الحارس فقط، '
            'وبقية الحمايات (Outbox فارغ) غير مفعّلة هنا',
      );
      expect(
        await localBlacklistCount(),
        2,
        reason: 'إعادة السحب idempotent — لا تكرار',
      );
    });
  });

  group('E5→E6: قرار delta على مستوى الكيان (وليس على مستوى الدورة)', () {
    test('E5: فشل كيان آخر (وضع عام full) لا يعيد سحب الكيان السليم كاملاً '
        '— مؤشره الخاص يقوده إلى delta', () async {
      await resetState();

      // ── خط أساس: دورة ناجحة تضبط checkpoint الكيان (مؤشر خاص > 0) ──
      fake.serverCollections['blacklist'] = [mkDoc('A', 1700001000)];
      final baseline = await manager.sync(push: false, pull: true);
      expect(baseline.isSuccess, isTrue, reason: 'الدورة الأساس سليمة');
      expect(await localBlacklistCount(), 1, reason: 'A طُبِّق محلياً');

      // ── إجبار وضع الدورة العام على full: fullSyncComplete=0 و
      // lastPullTs=0 (كأن كياناً آخر يفشل باستمرار ويجمّد المؤشر العام)
      // — دون لمس checkpoint الكيان في prefs ──
      await (db.update(db.syncState)..where((t) => t.id.equals(1))).write(
        const SyncStateCompanion(
          fullSyncComplete: Value(0),
          lastPullTs: Value(0),
        ),
      );
      fake.reset(); // ⚠️ يمسح الخادم والتسجيلات معاً — البذر بعده
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000), // غير متغير — مطابق محلياً (لا يُنزَّل)
        mkDoc('C', 1700001300), // جديد — يجب سحبه وحده
      ];

      // تصفير ساعة الحارس المركزي فقط (لا يمس prefs ولا DB) — الدورة
      // الثانية دورة عادية غير قسرية تقع زمنياً داخل فجوة الدقيقتين.
      manager.resetPullThrottleForTesting();

      final result = await manager.sync(push: false, pull: true);
      expect(result.isSuccess, isTrue, reason: 'الدورة الهجينة تعمل');

      // القرار: metadata الكيان مرّت بفلتر cutoff خاص به رغم أن وضع
      // الدورة العام full — هذا هو جوهر E5.
      final blacklistMeta = fake.metadataCalls
          .where((c) => c.collectionId == 'blacklist')
          .toList();
      expect(blacklistMeta, isNotEmpty, reason: 'مرّت بمرحلة metadata');
      expect(
        blacklistMeta.last.extraQueries
            .where((q) => AppwriteService.queryHasMethod(q, 'greaterThan'))
            .where((q) => q.contains(r'$updatedAt')),
        isNotEmpty,
        reason:
            'كيان بمؤشر خاص متقدم يمضي delta حتى مع وضع عام full '
            '— actual=${blacklistMeta.map((c) => c.extraQueries).toList()}',
      );

      // التنزيل عبر listDocumentsByIds (المتغيّر فقط) ثم التطبيق.
      expect(
        fake.callNames.where((n) => n == 'listDocumentsByIds'),
        isNotEmpty,
        reason: 'المتغيّر وحده يُنزَّل — لا مسح كامل للكيان السليم',
      );
      expect(await localBlacklistCount(), 2, reason: 'C طُبِّق محلياً');
    });

    test('E6: كيان بلا مؤشر خاص في وضع عام full يبقى full له — شبكة الكمال '
        'محفوظة (metadata بلا cutoff)', () async {
      await resetState();
      fake.serverCollections['blacklist'] = [mkDoc('A', 1700001000)];
      final r = await manager.sync(push: false, pull: true);
      expect(r.isSuccess, isTrue);

      final blacklistMeta = fake.metadataCalls
          .where((c) => c.collectionId == 'blacklist')
          .toList();
      expect(blacklistMeta, isNotEmpty);
      expect(
        blacklistMeta.first.extraQueries,
        isEmpty,
        reason:
            'كيان لا مؤشر له (bootstrap) يبقى full له وحده — '
            'metadata بلا فلتر cutoff',
      );
      expect(await localBlacklistCount(), 1);
    });
  });

  group('E4: عقود الثوابت (نافذة التقليل)', () {
    test('minPullGap دقيقتان، المؤقت الدوري 15 دقيقة، الفتح ساعة', () {
      // الخطوة 1: الحارس المركزي.
      expect(SyncConstants.minPullGap, const Duration(minutes: 2));
      // الخطوة 2: المؤقت الدوري داخل نافذة 10–15 دقيقة.
      expect(
        SyncConstants.defaultAutoSyncInterval.inMinutes,
        inInclusiveRange(10, 15),
      );
      expect(
        SyncConstants.defaultAutoSyncInterval,
        const Duration(minutes: 15),
      );
      // ساعة فحص الفتح الذكية (مدخل الجلسة أقل تكراراً من الحارس).
      expect(SyncConstants.appOpenSyncInterval, const Duration(hours: 1));
    });
  });

  group('S1..S4: عقود مصادر السحب (tripwires على الكود المصدري)', () {
    test(
      'S1: فتح Dashboard يستدعي sync(deltaOnly:true) فقط — لا Full من الشاشة',
      () {
        final source = readSource('screens/dashboard_screen.dart');
        // ✅ (2026-09-01) العقد المحدَّث (طلب صريح: بنفس طريقة الفرع
        // refactor/performance-fixes-v2): فتح الشاشة يشغّل سحباً ذكياً
        // (SyncGate + فحص ساعة lastAppOpenPullKey) لكن **دلتا فقط** —
        // أي sync() بلا deltaOnly:true أو أي Full من الشاشة يكسر العقد.
        expect(
          source.contains('.sync('),
          isTrue,
          reason: 'فتح الشاشة يشغّل السحب الذكي (deltaOnly) لتحديث الاستلامات',
        );
        expect(
          source.contains('deltaOnly: true'),
          isTrue,
          reason: 'سحب الشاشة مقيَّد deltaOnly — لا Full Sync من الخلفية',
        );
        // لا استدعاء sync دون deltaOnly داخل الشاشة (كل الاستدعاءات مقيّدة).
        final syncCalls = RegExp(r'\.sync\([^)]*\)').allMatches(source);
        expect(syncCalls, isNotEmpty);
        for (final call in syncCalls) {
          expect(
            call.group(0)!.contains('deltaOnly'),
            isTrue,
            reason: 'كل استدعاءات sync في الشاشة يجب أن تمرر deltaOnly',
          );
        }
      },
    );

    test('S2: زر التحديث اليدوي يمرر forcePull: true', () {
      final source = readSource('widgets/dashboard_sync_button.dart');
      expect(
        source.contains('forcePull: true'),
        isTrue,
        reason: 'الزر اليدوي يسحب فوراً (يتجاوز حارس الدقيقتين فقط)',
      );
    });

    test('S3: EnhancedSyncButton يمرر forcePull: true في موضعيه', () {
      final source = readSource('widgets/enhanced_sync_button.dart');
      final count = 'forcePull: true'.allMatches(source).length;
      expect(count, 2, reason: 'sync() الكاملة وsync(push: false) كلاهما يدوي');
    });

    test('S4: فحص الجلسة يحتفظ بالتقييد الذكي ويستدعي sync مرة واحدة', () {
      final source = readSource('services/app_session_manager.dart');
      // التقييد الذكي (ساعة) ما زال موجوداً قبل الاستدعاء.
      expect(
        source.contains('last_appwrite_pull_on_open_timestamp'),
        isTrue,
        reason: 'مدخل الجلسة يبقى مقيَّداً بساعته الذكية + الحارس المركزي',
      );
      expect(
        RegExp(r'\.sync\(').allMatches(source).length,
        1,
        reason: 'استدعاء sync واحد فقط من مدخل الجلسة',
      );
    });
  });
}
