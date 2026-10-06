// test/unit/provider_scope_g7_test.dart
//
// ✅ (G-7 / 2026-10-06): حارس نطاق المزوّد — إثبات أن تبديل الوجهة
// (endpoint/projectId/databaseId) يُصفّر كل مؤشر سحب مقيّد بالمزوّد
// **مرة واحدة بالضبط**، وأن أول تشغيل بعد الترقية لا يُصفّر شيئاً، وأن
// مخزن العلاقات المعلّقة (حالة ربط بـ UUID) **لا يُمسّ**.
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/provider_scope.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_checkpoint_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SyncCheckpointStore checkpoints;
  late SharedPreferences prefs;

  const endpointA = 'https://fra.cloud.appwrite.io/v1';
  const projectA = 'project-AAA';
  const databaseA = 'db-AAA';
  const endpointB = 'https://sfo.cloud.appwrite.io/v1';
  const projectB = 'project-BBB';
  const databaseB = 'db-BBB';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    checkpoints = SyncCheckpointStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedProviderState() async {
    // 1) نقاط فحص لكل مجموعة (بما فيها cursor السحب القابل للاستئناف).
    await checkpoints.setLastPullTs('rooms', 1111);
    await checkpoints.setLastPullTs('bookings', 2222);
    await checkpoints.setFullSyncCursor('bookings', 'doc-123');
    await checkpoints.bumpFullSyncMaxUpdated('bookings', 3333);

    // 2) المؤشر العام + علم الاكتمال في sync_state.
    await db
        .into(db.syncState)
        .insertOnConflictUpdate(
          const SyncStateCompanion(
            id: d.Value(1),
            lastPullTs: d.Value(4444),
            fullSyncComplete: d.Value(1),
          ),
        );

    // 3) مفاتيح SharedPreferences المقيّدة بالمزوّد.
    await prefs.setString(
      ProviderScopeGuard.entityPullTsMapKey,
      '{"rooms":1111,"bookings":2222}',
    );
    await prefs.setInt(ProviderScopeGuard.bookingNightsPullTsKey, 5555);
    await prefs.setInt(ProviderScopeGuard.lastSyncTimeKey, 6666);
    await prefs.setBool(ProviderScopeGuard.initialSeedDoneKey, true);

    // 4) خريطة metadata البعيدة (عقد: مسحها إلزامي قبل سحب كامل).
    await db.upsertRemoteMeta('bookings', {'doc-1': 1000, 'doc-2': 1001});

    // 5) مخزن العلاقات المعلّقة — حالة ربط بـ UUID، لا يجوز مسّها.
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS deferred_relations ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, collection_name TEXT NOT NULL, '
      'local_uuid TEXT NOT NULL, source TEXT NOT NULL DEFAULT \'appwrite\', '
      'payload_json TEXT NOT NULL, reason TEXT, missing_parent TEXT, '
      'parent_uuid TEXT, remote_parent_id INTEGER, source_device_id TEXT, '
      'attempts INTEGER NOT NULL DEFAULT 0, first_seen_at INTEGER NOT NULL '
      'DEFAULT 0, last_attempt_at INTEGER, state TEXT NOT NULL DEFAULT '
      '\'pending\', resolved_at INTEGER, '
      'UNIQUE(collection_name, local_uuid))',
    );
    await db.customStatement(
      'INSERT INTO deferred_relations (collection_name, local_uuid, '
      'payload_json, state) VALUES (?, ?, ?, ?)',
      [
        d.Variable.withString('salary_withdrawals'),
        d.Variable.withString('sw-keep'),
        d.Variable.withString('{"localUuid":"sw-keep"}'),
        d.Variable.withString('pending'),
      ],
    );
  }

  Future<int> deferredCount() async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM deferred_relations')
        .getSingle();
    return row.read<int>('c');
  }

  group('G-7 — حارس نطاق المزوّد', () {
    test('البصمة دالة نقية: التطبيع لا يُحدث تبديلاً، والتغيير يغيّر البصمة', () {
      final base = ProviderScopeGuard.fingerprint(
        endpoint: endpointA,
        projectId: projectA,
        databaseId: databaseA,
      );
      // اختلاف الشكل فقط (شرطة أخيرة/مسافات/حالة أحرف) ⇒ نفس البصمة.
      expect(
        ProviderScopeGuard.fingerprint(
          endpoint: '  HTTPS://FRA.CLOUD.APPWRITE.IO/V1/  ',
          projectId: ' $projectA ',
          databaseId: databaseA,
        ),
        base,
        reason: 'التطبيع لا يجوز أن يُكلّف سحباً كاملاً',
      );
      // تغيير أي عنصر من الثلاثة ⇒ بصمة مختلفة.
      for (final changed in [
        ProviderScopeGuard.fingerprint(
          endpoint: endpointB,
          projectId: projectA,
          databaseId: databaseA,
        ),
        ProviderScopeGuard.fingerprint(
          endpoint: endpointA,
          projectId: projectB,
          databaseId: databaseA,
        ),
        ProviderScopeGuard.fingerprint(
          endpoint: endpointA,
          projectId: projectA,
          databaseId: databaseB,
        ),
      ]) {
        expect(changed, isNot(base));
      }
    });

    test('أول تشغيل (لا بصمة): تُحفظ البصمة بلا أي إعادة ضبط', () async {
      await seedProviderState();

      final status = await ProviderScopeGuard.ensureCurrent(
        endpoint: endpointA,
        projectId: projectA,
        databaseId: databaseA,
        db: db,
        checkpoints: checkpoints,
        prefs: prefs,
      );

      expect(status.state, ProviderScopeState.firstRun);
      expect(status.changed, isFalse);
      // كل شيء كما هو.
      expect(await checkpoints.getLastPullTs('rooms'), 1111);
      expect(await checkpoints.isFullSyncComplete('bookings'), isTrue);
      expect(
        prefs.getString(ProviderScopeGuard.entityPullTsMapKey),
        isNotNull,
      );
      expect(await deferredCount(), 1);
    });

    test('نفس الوجهة: لا شيء يتغيّر (ولا إعادة ضبط متكررة)', () async {
      await seedProviderState();
      await ProviderScopeGuard.ensureCurrent(
        endpoint: endpointA,
        projectId: projectA,
        databaseId: databaseA,
        db: db,
        checkpoints: checkpoints,
        prefs: prefs,
      );

      final second = await ProviderScopeGuard.ensureCurrent(
        endpoint: endpointA,
        projectId: projectA,
        databaseId: databaseA,
        db: db,
        checkpoints: checkpoints,
        prefs: prefs,
      );
      expect(second.state, ProviderScopeState.unchanged);
      expect(await checkpoints.getLastPullTs('rooms'), 1111);
    });

    test('تبديل الوجهة: تُصفَّر كل مؤشرات المزوّد — ولا يُمسّ المعلّق', () async {
      await seedProviderState();
      await ProviderScopeGuard.ensureCurrent(
        endpoint: endpointA,
        projectId: projectA,
        databaseId: databaseA,
        db: db,
        checkpoints: checkpoints,
        prefs: prefs,
      );

      final status = await ProviderScopeGuard.ensureCurrent(
        endpoint: endpointB,
        projectId: projectB,
        databaseId: databaseB,
        db: db,
        checkpoints: checkpoints,
        prefs: prefs,
      );

      expect(status.state, ProviderScopeState.changed);
      expect(status.previousFingerprint, isNotNull);
      expect(status.changedAt, isNotNull);
      expect(status.invalidated, contains('sync_checkpoints'));
      expect(status.invalidated, contains('sync_state'));
      expect(status.invalidated, contains('sync_remote_meta'));
      expect(status.invalidated, contains('initial_seed'));

      // 1) نقاط الفحص صُفّرت (سحب كامل قادم) — وكل المجموعات.
      expect(await checkpoints.getLastPullTs('rooms'), 0);
      expect(await checkpoints.getLastPullTs('bookings'), 0);
      expect(await checkpoints.isFullSyncComplete('bookings'), isFalse);
      expect(await checkpoints.getFullSyncCursor('bookings'), isNull);
      expect(await checkpoints.getFullSyncMaxUpdated('bookings'), 0);

      // 2) المؤشر العام + علم الاكتمال.
      final state = await (db.select(
        db.syncState,
      )..where((t) => t.id.equals(1))).getSingle();
      expect(state.lastPullTs, 0);
      expect(state.fullSyncComplete, 0);

      // 3) مفاتيح SharedPreferences.
      expect(
        prefs.getString(ProviderScopeGuard.entityPullTsMapKey),
        isNull,
      );
      expect(prefs.getInt(ProviderScopeGuard.bookingNightsPullTsKey), isNull);
      expect(prefs.getInt(ProviderScopeGuard.lastSyncTimeKey), isNull);
      expect(
        prefs.getBool(ProviderScopeGuard.initialSeedDoneKey),
        isFalse,
        reason: 'الرفع الأولي هو المسار الوحيد لنقل ما خرج من outbox',
      );

      // 4) خريطة metadata البعيدة فُرّغت.
      expect(await db.getRemoteMetaMap('bookings'), isEmpty);

      // 5) مخزن العلاقات المعلّقة **سليم** (حالة ربط بـ UUID).
      expect(await deferredCount(), 1, reason: 'لا يجوز إسقاط حالات ربط');

      // 6) البصمة الجديدة محفوظة، وتكرار الفحص لا يُعيد الضبط.
      final again = await ProviderScopeGuard.ensureCurrent(
        endpoint: endpointB,
        projectId: projectB,
        databaseId: databaseB,
        db: db,
        checkpoints: checkpoints,
        prefs: prefs,
      );
      expect(again.state, ProviderScopeState.unchanged);
    });

    test('resetProviderScopedState — الأساس المشترك (إعادة ضبط يدوية)', () async {
      await seedProviderState();
      final reset = await ProviderScopeGuard.resetProviderScopedState(
        db: db,
        checkpoints: checkpoints,
        prefs: prefs,
      );
      expect(reset, contains('sync_checkpoints'));
      expect(reset, contains('sync_state'));
      expect(reset, contains('sync_remote_meta'));
      expect(reset, contains('initial_seed'));
      expect(await checkpoints.getLastPullTs('rooms'), 0);
      expect(await deferredCount(), 1);
    });
  });
}
