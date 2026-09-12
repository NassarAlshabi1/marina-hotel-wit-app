// ✅ (2026-09-13) اختبارات إصلاح تسليم الآباء المحذوفين ناعماً.
//
// الخلفية (تحذيرات «الموظف 12 (uuid=null) غير موجود محلياً (سجل يتيم)»):
// 1) entityNeedsTombstoneParents('employees') كانت معرّفة منذ 2026-09-02
//    لكن بلا أي استدعاء في كود الإنتاج — UnifiedPullEngine.plan() كان
//    يستدعي buildFullSyncQueries() دائماً بلا tombstones → الموظفون
//    المحذوفون ناعماً لا يُنزّلون → السحوبات القديمة بلا employeeUuid
//    تُتخطى كأيتام في كل دورة.
// 2) الأجهزة الموجودة لا تتعافى ذاتياً: checkpoint لكل مجموعة + دلتا فقط،
//    فtombstones قديمة ($updatedAt قبل مؤشر الجهاز) لا تصل أبداً →
//    TombstoneParentsRepull يعيد ضبط checkpoint الموظفين مرة واحدة.
//
// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_checkpoint_store.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_pull_service.dart';
import 'package:marina_hotel_mobile/services/sync_core/tombstone_parents_repull.dart';
import 'package:marina_hotel_mobile/services/sync_core/unified_pull_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مستودع checkpoints محاكى لفشل إعادة الضبط (اختبار مسار الاستثناء).
class _ThrowingCheckpoints extends SyncCheckpointStore {
  _ThrowingCheckpoints(super.db);

  @override
  Future<void> reset(String collectionName) async {
    throw StateError('simulated reset failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SyncCheckpointStore checkpoints;
  late UnifiedPullEngine engine;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    checkpoints = SyncCheckpointStore(db);
    engine = UnifiedPullEngine(
      checkpoints: checkpoints,
      pullService: SyncPullService(
        appwriteService: AppwriteService(),
        database: db,
        outboxDao: OutboxDao(db),
      ),
    );
  });

  tearDown(() async => db.close());

  group('الإصلاح A — توصيل entityNeedsTombstoneParents في UnifiedPullEngine', () {
    test(
      'employees: خطة Full pull بلا فلتر tombstones (استثناء الآباء موصول)',
      () async {
        final plan = await engine.plan('employees');
        expect(plan.isFullSync, isTrue, reason: 'checkpoint غير موجود → Full');
        expect(
          plan.queries,
          isEmpty,
          reason:
              'يجب ألا يوجد فلتر deletedAt — tombstones الموظفين (الآباء '
              'المرجعيين لسحوبات الرواتب القديمة) تُسحب حتى في Full pull',
        );
      },
    );

    test(
      'salary_withdrawals: خطة Full pull مع فلتر استبعاد tombstones (كما كان)',
      () async {
        final plan = await engine.plan('salary_withdrawals');
        expect(plan.isFullSync, isTrue);
        expect(plan.queries, hasLength(1));
        expect(plan.queries.single, contains('deletedAt'));
      },
    );

    test(
      'bookings: تبقى مستبعدة tombstones (ليست أباً مرجعياً)',
      () async {
        final plan = await engine.plan('bookings');
        expect(plan.isFullSync, isTrue);
        expect(plan.queries.single, contains('deletedAt'));
      },
    );

    test(
      'بعد اكتمال checkpoint: employees تتحول إلى Delta كأي مجموعة',
      () async {
        await checkpoints.setLastPullTs('employees', 1785000000);
        final plan = await engine.plan('employees');
        expect(plan.isFullSync, isFalse);
        expect(plan.sinceTs, 1785000000);
        expect(plan.queries.single, contains(r'$updatedAt'));
      },
    );
  });

  group('الإصلاح B — TombstoneParentsRepull (إعادة سحب لمرة واحدة)', () {
    test(
      'أول استدعاء: يعيد ضبط checkpoint الموظفين ويعيد true',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        // جهاز موجود: checkpoint موظفين مكتمل بمؤشر أحدث من تواريخ الحذف
        await checkpoints.setLastPullTs('employees', 1786000000);
        expect(await checkpoints.isFullSyncComplete('employees'), isTrue);
        expect(await checkpoints.getLastPullTs('employees'), 1786000000);

        final ran = await TombstoneParentsRepull.runIfNeeded(
          checkpoints: checkpoints,
          prefs: prefs,
        );

        expect(ran, isTrue);
        expect(
          await checkpoints.getLastPullTs('employees'),
          0,
          reason: 'المؤشر صفّر → الدورة القادمة Full pull شامل tombstones',
        );
        expect(
          await checkpoints.isFullSyncComplete('employees'),
          isFalse,
          reason: 'علامة الاكتمال صفّرت أيضاً',
        );
        expect(
          prefs.getBool(TombstoneParentsRepull.doneKey),
          isTrue,
          reason: 'العلم يُكتب بعد نجاح إعادة الضبط',
        );
      },
    );

    test(
      'استدعاء ثانٍ: لا يعيد التنفيذ (idempotent عبر العلم)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        await checkpoints.setLastPullTs('employees', 1786000000);
        expect(
          await TombstoneParentsRepull.runIfNeeded(
            checkpoints: checkpoints,
            prefs: prefs,
          ),
          isTrue,
        );

        // الجهاز أعاد السحب واكتمل بمؤشر جديد
        await checkpoints.setLastPullTs('employees', 1786100000);

        final ranAgain = await TombstoneParentsRepull.runIfNeeded(
          checkpoints: checkpoints,
          prefs: prefs,
        );

        expect(ranAgain, isFalse);
        expect(
          await checkpoints.getLastPullTs('employees'),
          1786100000,
          reason: 'المؤشر الجديد لا يُمس بعد اكتمال الإصلاح لمرة واحدة',
        );
      },
    );

    test(
      'فشل إعادة الضبط: العلم لا يُكتب (يُعاد المحاولة في التشغيل التالي)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        final throwing = _ThrowingCheckpoints(db);
        await expectLater(
          TombstoneParentsRepull.runIfNeeded(
            checkpoints: throwing,
            prefs: prefs,
          ),
          throwsA(anything),
        );

        expect(
          prefs.getBool(TombstoneParentsRepull.doneKey) ?? false,
          isFalse,
          reason:
              'العلم يجب ألا يُكتب عند فشل إعادة الضبط — وإلا يُفقد الإصلاح '
              'لهذا الجهاز إلى الأبد',
        );
      },
    );

    test(
      'reset على جهاز لم يسحب الموظفين بعد (لا صف checkpoint) — لا يضر',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        // لا يوجد صف checkpoint لإ employees إطلاقاً (تثبيت جديد)
        final ran = await TombstoneParentsRepull.runIfNeeded(
          checkpoints: checkpoints,
          prefs: prefs,
        );

        expect(ran, isTrue);
        // الخطة تبقى Full pull (isFullSyncComplete=false لأن الصف غير موجود)
        expect(await checkpoints.isFullSyncComplete('employees'), isFalse);
      },
    );
  });
}
