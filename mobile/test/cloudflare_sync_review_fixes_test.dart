// ═══════════════════════════════════════════════════════════════
//  cloudflare_sync_review_fixes_test.dart — 2026-09-09
//
//  اختبارات عقدية لإصلاحات مراجعة 2026-09-09 (#1 #2 #3 #14 #15 #16):
//
//  #1  tombstone يصل في الدلتا → حذف ناعم محلي (كان يُتجاهل صمتاً —
//      الحذف لا يصل إلى الأجهزة الأخرى).
//  #1b tombstone لصف غير موجود محلياً → لا عملية (idempotent) بلا فشل.
//  #1c مسح تقارب الحذفيات لمرة واحدة (tombstones_only) يطبّق حذفيات
//      تاريخية ويُضبط علمه في prefs (لا يعاد السؤال).
//  #2b/#16 الحجر الصحي: اليتيم يفشل الدورتين الأوليين ثم يُعزل واكتمال
//      الدورة والمؤشر يتقدم — لا تجميد أبدي للـ bootstrap.
//  #3  ناتج Worker بمفتاح لا يعود لسجل في الدفعة لا يحذف شيئاً من
//      الـ outbox (كان orElse يحذف pending.first — فقدان بيانات).
//  #14 حلقة الرفع تتجاهل failed فوق سقف المحاولات (احترام backoff)،
//      والفشل المؤقت المزمن يبلغ dead-letter عند العتبة.
//  #15 العملية التي سقطت من results تُعامل فشلاً مؤقتاً وتُسجل.
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marina_hotel_mobile/screens/settings/error_tracker_screen.dart';
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _syncFields(
  String uuid,
  int updatedAt, {
  int? serverId,
  String device = 'other-device',
}) => {
  'id': serverId,
  'local_uuid': uuid,
  'created_at': updatedAt,
  'updated_at': updatedAt,
  'last_modified': updatedAt,
  'created_at_epoch': 0,
  'last_modified_epoch': 0,
  'version': 1,
  'origin': 'local',
  'vector_clock': '{}',
  'device_id': device,
};

Map<String, dynamic> _roomRow(
  String uuid, {
  int? serverId,
  int updatedAt = 1700000100,
  String device = 'other-device',
}) => {
  ..._syncFields(uuid, updatedAt, serverId: serverId, device: device),
  'room_number': 'RN-$uuid',
  'type': 'double',
  'price': 100.0,
  'status': 'available',
  'cleaning_status': 'clean',
  'requires_maintenance': 0,
};

/// غرفة بحالة tombstone — نفس الصف مع deleted_at خادمي.
Map<String, dynamic> _roomTombstone(
  String uuid, {
  int? serverId,
  int updatedAt = 1700000200,
}) => {
  ..._roomRow(uuid, serverId: serverId, updatedAt: updatedAt),
  'deleted_at': updatedAt,
};

Map<String, dynamic> _nightRow(String uuid, {int bookingLocalId = 999999}) => {
  ..._syncFields(uuid, 1700000300),
  'booking_local_id': bookingLocalId,
  'hotel_day_key': '2026-09-09',
  'night_start': '2026-09-09 15:00',
  'night_end': '2026-09-10 12:00',
  'nightly_rate': 100.0,
  'sequence': 1,
  'is_processed_by_auto_fix': 0,
  'base_rate': 100.0,
  'adjustment': 0.0,
  'final_rate': 100.0,
};

Map<String, dynamic> _emptyPullPage() => {
  'changes': <dynamic>[],
  'cursor': '0',
  'has_more': false,
  'errors': <dynamic>[],
};

/// عميل وهمي يفصل بين طلبات tombstones_only والسحب العادي ويعدّها.
class _ReviewFakeClient extends http.BaseClient {
  _ReviewFakeClient({this.pullHandler, this.pushHandler});

  final Map<String, dynamic> Function(http.BaseRequest request)? pullHandler;
  final Map<String, dynamic> Function(http.BaseRequest request)? pushHandler;

  int pushCalls = 0;
  int tombstonePullCalls = 0;
  int normalPullCalls = 0;

  http.StreamedResponse _json(Map<String, dynamic> body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        200,
        headers: {'content-type': 'application/json'},
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/api/auth/login')) {
      return _json({
        'token': 'fake-token',
        'user': {'id': 'u1', 'username': 'sync_service', 'role': 'admin'},
      });
    }
    if (request.method == 'POST' && path.endsWith('/api/sync/push')) {
      pushCalls++;
      return _json(pushHandler?.call(request) ?? {'results': <dynamic>[]});
    }
    if (request.method == 'GET' && path.endsWith('/api/sync/pull')) {
      if (request.url.queryParameters['tombstones_only'] == '1') {
        tombstonePullCalls++;
        return _json(pullHandler?.call(request) ?? _emptyPullPage());
      }
      normalPullCalls++;
      return _json(pullHandler?.call(request) ?? _emptyPullPage());
    }
    throw StateError('unexpected ${request.method} $path');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
    });
    ErrorTrackerStore.instance.clear();
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<CloudflareSyncManager> makeManager(_ReviewFakeClient client) async {
    final manager = CloudflareSyncManager();
    manager.reset();
    manager.configureForTesting(
      database: db,
      httpClient: client,
      token: 'test-token',
      deviceId: 'review-fixes-device',
    );
    return manager;
  }

  Future<Object?> pref(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.get(key);
  }

  Future<bool> _roomSoftDeleted(String uuid) async {
    final row = await db
        .customSelect(
          'SELECT deleted_at, updated_at FROM rooms WHERE local_uuid = ?',
          variables: [Variable<String>(uuid)],
        )
        .getSingleOrNull();
    if (row == null) return false;
    return row.data['deleted_at'] != null;
  }

  // ─── #1: tombstone يُطبَّق كحذف ناعم محلي ────────────────────

  test(
    '#1 tombstone في الدلتا يحذف الصف المحلي حذفاً ناعماً (الحذف يصل للأجهزة الأخرى)',
    () async {
      final manager = await makeManager(_ReviewFakeClient());

      // 1) الصف الحي يصل ويُطبَّق.
      final live = await manager.applyPulledRecords([
        (entity: 'rooms', record: _roomRow('rm-tomb-1', serverId: 11)),
      ]);
      expect(live.appliedCount, 1);
      expect(await _roomSoftDeleted('rm-tomb-1'), isFalse);

      // 2) tombstone نفس الصف يصل من جهاز آخر → حذف ناعم محلي.
      final dead = await manager.applyPulledRecords([
        (entity: 'rooms', record: _roomTombstone('rm-tomb-1', serverId: 11)),
      ]);
      expect(dead.appliedCount, 1);
      expect(await _roomSoftDeleted('rm-tomb-1'), isTrue);
    },
  );

  test('#1b tombstone لصف غير موجود محلياً = لا عملية بلا فشل', () async {
    final manager = await makeManager(_ReviewFakeClient());

    final report = await manager.applyPulledRecords([
      (entity: 'rooms', record: _roomTombstone('rm-ghost', serverId: 99)),
    ]);

    expect(report.appliedCount, 1, reason: 'التخطي بعذر يُحسب تطبيقاً');
    expect(report.errors, isEmpty);
    final row = await db
        .customSelect(
          'SELECT 1 FROM rooms WHERE local_uuid = ?',
          variables: [const Variable<String>('rm-ghost')],
        )
        .getSingleOrNull();
    expect(row, isNull, reason: 'لا يُنشأ صف من tombstone لصف غير موجود');
  });

  test(
    '#1c مسح تقارب الحذفيات يعمل مرة واحدة ويُضبط علمه في prefs',
    () async {
      // صف حي محلي — الحذفية التاريخية له ستصل عبر المسح.
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              roomNumber: 'RN-SWEEP',
              type: 'double',
              price: 100.0,
              status: 'available',
              localUuid: 'rm-sweep-1',
              serverId: const Value(42),
              createdAt: 1700000100,
              updatedAt: 1700000100,
              lastModified: 1700000100,
            ),
          );

      final client = _ReviewFakeClient(
        pullHandler: (request) => {
          'changes': [_roomTombstone('rm-sweep-1', serverId: 42)],
          'cursor': '1700000200',
          'has_more': false,
          'errors': <dynamic>[],
        },
      );
      final manager = await makeManager(client);
      // جهاز قائم (أتم full sync سابقاً) — بوابة المسح تسمح له فقط؛
      // التثبيت الجديد يجلب الحذفيات ضمن سحبه الكامل بلا طلب إضافي.
      manager.configureForTesting(
        database: db,
        httpClient: client,
        token: 'test-token',
        deviceId: 'review-fixes-device',
        fullSyncCompleted: true,
      );

      await manager.sync();

      expect(await _roomSoftDeleted('rm-sweep-1'), isTrue);
      expect(client.tombstonePullCalls, 1);
      expect(await pref('cf_tombstone_sweep_v1_done'), isTrue);

      // دورة ثانية: لا مسح مجدداً (العلم مضبوط) — الحذفية نفسها قد
      // تعود عبر السحب العادي فتُطبَّق idempotent بلا ضرر.
      await manager.sync();
      expect(client.tombstonePullCalls, 1);
    },
  );

  // ─── #2+#16: الحجر الصحي للصفوف اليتيمة ─────────────────────

  test(
    '#2b/#16 اليتيم يفشل دورتين ثم يُعزل وتكتمل الدورة ويتقدم المؤشر',
    () async {
      final client = _ReviewFakeClient(
        pullHandler: (request) => {
          'changes': [_nightRow('night-orphan-1')],
          'cursor': '1700000300',
          'has_more': false,
          'errors': <dynamic>[],
        },
      );
      final manager = await makeManager(client);

      // الدورة 1 و 2: فشل (فرصة عادلة للأب المتأخر).
      final r1 = await manager.sync();
      expect(r1.status, SyncStatus.failed);
      final r2 = await manager.sync();
      expect(r2.status, SyncStatus.failed);
      expect(await pref('cf_last_pull_cursor'), isNull);

      // الدورة 3: العتبة (3) اكتملت — العزل واكتمال الدورة.
      final r3 = await manager.sync();
      expect(r3.status, SyncStatus.success);
      expect(await pref('cf_last_pull_cursor'), 1700000300);
      expect(await pref('cf_full_sync_completed'), isTrue);

      // السجل في ledger الحجر ولم يُطبَّق محلياً.
      final ledgerRaw = await pref('cf_pull_quarantined_records') as String?;
      expect(ledgerRaw, isNotNull);
      expect(ledgerRaw, contains('booking_nights/night-orphan-1'));
      final nightCount = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM booking_nights WHERE local_uuid = ?',
            variables: [const Variable<String>('night-orphan-1')],
          )
          .getSingle();
      expect(nightCount.data['n'], 0);

      // حدث العزل ظاهر في مركز الأخطاء.
      expect(
        ErrorTrackerStore.instance.errors.any(
          (e) => e.source == 'sync:pull-apply' && e.title.contains('عُزلت'),
        ),
        isTrue,
      );

      // الدورة 4: المعزول يُتخطى بصمت موثق والدورة سليمة.
      final r4 = await manager.sync();
      expect(r4.status, SyncStatus.success);
    },
  );

  // ─── #3: مفتاح مجهول في نتائج الرفع لا يحذف شيئاً ───────────

  test('#3 ناتج ناجح لمفتاح لا يعود لأي سجل لا يحذف من الـ outbox', () async {
    const clientTs = 1700000900;
    final outboxId = await OutboxDao(db).merge(
      entity: 'rooms',
      op: 'update',
      localUuid: 'rm-key-safe',
      payload: const <String, dynamic>{'room_number': 'RN-SAFE'},
      clientTs: clientTs,
    );

    final client = _ReviewFakeClient(
      pushHandler: (request) => {
        'results': [
          {
            'idempotencyKey': 'rooms:update:GHOST-NOT-IN-BATCH:123',
            'success': true,
            'status': 'ok',
          },
        ],
      },
    );
    final manager = await makeManager(client);
    await manager.sync(pull: false);

    // العقد المزدوج:
    // - #3: سجلنا لم يُحذف (كان orElse يحذف pending.first فتُفقد البيانات).
    // - #15: عمليتنا لم يعد لها ناتج → فشل مؤقت موثق (ليس نجاحاً زائفاً).
    final row = await db
        .customSelect(
          'SELECT id, processing_status, attempts, last_error FROM outbox '
          'WHERE id = ?',
          variables: [Variable<int>(outboxId)],
        )
        .getSingle();
    expect(row.data['id'], outboxId, reason: 'السجل موجود — لم يُحذف أبداً');
    expect(row.data['processing_status'], 'failed');
    expect(row.data['attempts'], 1);
    expect(row.data['last_error'], contains('results'));
    // المفتاح المجهول ظهر في مركز الأخطاء (ناتج بلا صاحب).
    expect(
      ErrorTrackerStore.instance.errors.any(
        (e) =>
            e.source == 'worker:push' &&
            e.message.contains('GHOST-NOT-IN-BATCH'),
      ),
      isTrue,
    );
  });

  // ─── #14: سقف المحاولات + dead-letter ───────────────────────

  test(
    '#14a حلقة الرفع تتجاهل failed فوق سقف المحاولات (احترام backoff)',
    () async {
      final outboxId = await OutboxDao(db).merge(
        entity: 'rooms',
        op: 'update',
        localUuid: 'rm-backoff',
        payload: const <String, dynamic>{'room_number': 'RN-B'},
        clientTs: 1700000901,
      );
      // attempts=6 فوق سقف reclaimForPush — تُترك للمؤقت الدوري.
      await OutboxDao(db).setError(outboxId, 'previous failure', 6);

      final client = _ReviewFakeClient();
      final manager = await makeManager(client);
      await manager.sync(pull: false);

      expect(
        client.pushCalls,
        0,
        reason: 'لا يُدفع السجل فوق السقف في كل دورة — backoff محترم',
      );
      final row = await db
          .customSelect(
            'SELECT processing_status, attempts FROM outbox WHERE id = ?',
            variables: [Variable<int>(outboxId)],
          )
          .getSingle();
      expect(row.data['processing_status'], 'failed');
      expect(row.data['attempts'], 6);
    },
  );

  test('#14b فشل مؤقت مزمن يبلغ dead-letter عند العتبة (10)', () async {
    final outboxId = await OutboxDao(db).merge(
      entity: 'rooms',
      op: 'update',
      localUuid: 'rm-toxic',
      payload: const <String, dynamic>{'room_number': 'RN-T'},
      clientTs: 1700000902,
    );
    // محاكاة سجل عاد من backoff الدوري: pending بـ 9 محاولات.
    await (db.update(db.outbox)..where((t) => t.id.equals(outboxId))).write(
      const OutboxCompanion(attempts: Value(9)),
    );

    final client = _ReviewFakeClient(
      pushHandler: (request) => {
        'results': [
          {
            'idempotencyKey': 'rooms:update:rm-toxic:1700000902',
            'success': false,
            'status': 'server_error',
            'error': 'upstream timeout',
          },
        ],
      },
    );
    final manager = await makeManager(client);
    await manager.sync(pull: false);

    final row = await db
        .customSelect(
          'SELECT processing_status, attempts, last_error FROM outbox '
          'WHERE id = ?',
          variables: [Variable<int>(outboxId)],
        )
        .getSingle();
    expect(row.data['processing_status'], 'dead');
    expect(row.data['attempts'], 10);
    expect(row.data['last_error'], contains('تجاوز الحد الأقصى'));
  });

  // ─── #15: مطابقة results مع المُرسَل ────────────────────────

  test(
    '#15 عملية سقطت من results تُعامل فشلاً مؤقتاً وتُسجل في مركز الأخطاء',
    () async {
      const tsA = 1700000910;
      const tsB = 1700000911;
      final idA = await OutboxDao(db).merge(
        entity: 'rooms',
        op: 'update',
        localUuid: 'rm-missing-a',
        payload: const <String, dynamic>{'room_number': 'RN-A'},
        clientTs: tsA,
      );
      final idB = await OutboxDao(db).merge(
        entity: 'rooms',
        op: 'update',
        localUuid: 'rm-missing-b',
        payload: const <String, dynamic>{'room_number': 'RN-B'},
        clientTs: tsB,
      );

      final client = _ReviewFakeClient(
        pushHandler: (request) => {
          'results': [
            {
              'idempotencyKey': 'rooms:update:rm-missing-a:$tsA',
              'success': true,
              'status': 'ok',
            },
          ],
        },
      );
      final manager = await makeManager(client);
      await manager.sync(pull: false);

      // A ناجح → حُذف من الـ outbox.
      final rowA = await db
          .customSelect(
            'SELECT id FROM outbox WHERE id = ?',
            variables: [Variable<int>(idA)],
          )
          .getSingleOrNull();
      expect(rowA, isNull);

      // B سقط من results → فشل مؤقت + محاولة + سبب موثق.
      final rowB = await db
          .customSelect(
            'SELECT processing_status, attempts, last_error FROM outbox '
            'WHERE id = ?',
            variables: [Variable<int>(idB)],
          )
          .getSingle();
      expect(rowB.data['processing_status'], 'failed');
      expect(rowB.data['attempts'], 1);
      expect(rowB.data['last_error'], contains('results'));

      // الحدث ظاهر في مركز أخطاء المزامنة (worker:push).
      expect(
        ErrorTrackerStore.instance.errors.any(
          (e) =>
              e.source == 'worker:push' &&
              e.message.contains('missing_result') &&
              e.message.contains('rm-missing-b'),
        ),
        isTrue,
      );
    },
  );
}
