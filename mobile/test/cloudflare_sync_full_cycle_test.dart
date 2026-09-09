// ═══════════════════════════════════════════════════════════════
//  cloudflare_sync_full_cycle_test.dart — 2026-09-09
//
//  اختبار دورة المزامنة الكاملة عبر المدير الحقيقي (وليس الخدمات
//  المعزولة): CloudflareSyncManager.configureForTesting + قاعدة
//  Drift في الذاكرة + عميل HTTP وهمي.
//
//  الرحلة السعيدة:
//   رسوم الجلسة → رفع الـ outbox (استهلاك الرد بمفتاح idempotency)
//   → سحب صفحة (limit=400 لجهاز جديد) → تطبيق السجل وتقدّم المؤشر
//   وضبط علم اكتمال السحب الكامل → دورة دلتا ثانية (limit=100) +
//   نافذة tombstones_only لمرة واحدة → إحصائيات.
//
//  النمط مطابقٌ لـ cloudflare_sync_review_fixes_test.dart.
// ═══════════════════════════════════════════════════════════════

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

Map<String, dynamic> _emptyPullPage([String cursor = '1700000200']) => {
  'changes': <dynamic>[],
  'cursor': cursor,
  'has_more': false,
  'errors': <dynamic>[],
};

/// عميل وهمي يفصل بين طلبات tombstones_only والسحب العادي ويفشل
/// السحب عند الطلب (لاختبار استرداد الدورة).
class _FullCycleFakeClient extends http.BaseClient {
  _FullCycleFakeClient({
    this.pullHealthy = true,
    this.pullHandler,
    this.pushHandler,
  });

  final Map<String, dynamic> Function(http.BaseRequest request)? pullHandler;
  final Map<String, dynamic> Function(http.BaseRequest request)? pushHandler;
  bool pullHealthy;

  int pushCalls = 0;
  int tombstonePullCalls = 0;
  int normalPullCalls = 0;
  final List<int?> pullLimits = [];

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
      pullLimits.add(
        int.tryParse(request.url.queryParameters['limit'] ?? ''),
      );
      if (request.url.queryParameters['tombstones_only'] == '1') {
        tombstonePullCalls++;
      } else {
        normalPullCalls++;
      }
      if (!pullHealthy) throw http.ClientException('network down');
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

  Future<CloudflareSyncManager> makeManager(_FullCycleFakeClient client) async {
    final manager = CloudflareSyncManager();
    manager.reset();
    manager.configureForTesting(
      database: db,
      httpClient: client,
      token: 'test-token',
      deviceId: 'full-cycle-device',
    );
    return manager;
  }

  Future<Object?> pref(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.get(key);
  }

  Future<Map<String, Object?>> _roomRowOf(String uuid) async {
    final row = await db
        .customSelect(
          'SELECT server_id, local_uuid FROM rooms WHERE local_uuid = ?',
          variables: [Variable<String>(uuid)],
        )
        .getSingleOrNull();
    return row?.data ?? <String, Object?>{};
  }

  Future<bool> _outboxDrained(int id) async {
    final row = await db
        .customSelect(
          'SELECT 1 FROM outbox WHERE id = ?',
          variables: [Variable<int>(id)],
        )
        .getSingleOrNull();
    return row == null;
  }

  // ─── دورة سعيدة كاملة: رفع → سحب → تطبيق → مؤشر → علم → دلتا ──

  test(
    'دورة سعيدة كاملة: رفع outbox وتطبيق صفحة السحب وتقدّم المؤشر '
    'وضبط اكتمال السحب الكامل ثم دورة دلتا بنافذة حذفيات واحدة',
    () async {
      // 1) رفعة محلية تنتظر في الـ outbox.
      const clientTs = 1700000900;
      final outboxId = await OutboxDao(db).merge(
        entity: 'rooms',
        op: 'update',
        localUuid: 'rm-my-1',
        payload: const <String, dynamic>{'room_number': 'RN-MINE'},
        clientTs: clientTs,
      );

      // 2) الدورة الأولى: رفع + سحب صفحة يعيد غرفة بعيدة واحدة.
      var pullIteration = 0;
      final client = _FullCycleFakeClient(
        pushHandler: (request) => {
          'results': [
            {
              'idempotencyKey': 'rooms:update:rm-my-1:$clientTs',
              'success': true,
              'status': 'ok',
            },
          ],
        },
        pullHandler: (request) {
          pullIteration++;
          if (pullIteration == 1) {
            return {
              'changes': [
                _roomRow('rm-remote-1', serverId: 101, updatedAt: 1700000101),
              ],
              'cursor': '1700000101',
              'has_more': false,
              'errors': <dynamic>[],
            };
          }
          // الدورات اللاحقة (دلتا + مسح الحذفيات): صفحة فارغة بمؤشر متقدم.
          return _emptyPullPage('1700000200');
        },
      );
      final manager = await makeManager(client);

      final r1 = await manager.sync();
      expect(r1.status, SyncStatus.success);

      // رفع ناجح → الـ outbox استُنزف.
      expect(client.pushCalls, 1, reason: 'الرفعة أُرسلت');
      expect(await _outboxDrained(outboxId), isTrue,
          reason: 'الرفعة الناجحة حُذفت من الـ outbox');

      // السحب: جهاز جديد → سحب كامل limit=400، بلا نافذة حذفيات.
      expect(client.normalPullCalls, 1);
      expect(client.pullLimits.first, 400,
          reason: 'السحب الكامل لجهاز جديد يطلب 400');
      expect(client.tombstonePullCalls, 0,
          reason: 'جهاز جديد لا يطلب نافذة حذفيات (جلبها ضمن السحب)');

      // التطبيق: الغرفة البعيدة وُضعت محلياً بهوية الخادم.
      final applied = await _roomRowOf('rm-remote-1');
      expect(applied.containsKey('local_uuid'), isTrue);
      expect(applied['server_id'], 101);
      expect(await _roomRowOf('rm-my-1'), isEmpty,
          reason: 'الرفعة المحلية لم تُعاد كصف محلي ضِدّها');

      // المؤشر تفقّد وعلم اكتمال السحب الكامل ضُبط.
      expect(await pref('cf_last_pull_cursor'), 1700000101);
      expect(await pref('cf_full_sync_completed'), isTrue);

      // 3) الدورة الثانية (دلتا): limit=100 + نافذة حذفيات لمرة واحدة.
      final r2 = await manager.sync();
      expect(r2.status, SyncStatus.success);
      expect(client.normalPullCalls, 2);
      expect(client.pullLimits.last, 100, reason: 'الدلتا تطلب 100');
      expect(client.tombstonePullCalls, 1,
          reason: 'العلم مضبوط → نافذة الحذفيات الرخيصة تُطلب مرة واحدة');
      expect(await pref('cf_tombstone_sweep_v1_done'), isTrue);

      // 4) الدورة الثالثة: لا نافذة حذفيات مجدداً (العلم مضبوط).
      final r3 = await manager.sync();
      expect(r3.status, SyncStatus.success);
      expect(client.tombstonePullCalls, 1);

      // 5) إحصائيات المزامنة تعكس الرحلة الفعلية.
      final stats = await manager.getSyncStatistics();
      expect((stats['totalRecordsPushed'] as num?) ?? 0,
          greaterThanOrEqualTo(1));
      expect((stats['totalRecordsPulled'] as num?) ?? 0,
          greaterThanOrEqualTo(1));
      expect(stats['fullSyncCompleted'], true);
    },
  );

  // ─── استرداد: دورة فاشلة لا تقدّم المؤشر والدورة التالية تتعافى ─

  test(
    'دورة فاشلة (السحب ساقط) لا تقدّم المؤشر والدورة التالية تتعافى',
    () async {
      final client = _FullCycleFakeClient(pullHealthy: false);
      final manager = await makeManager(client);

      final r1 = await manager.sync();
      expect(r1.status, SyncStatus.failed);
      expect(await pref('cf_last_pull_cursor'), isNull,
          reason: 'لا يُثبَّت مؤشر من دورة لم تصل صفحة سليمة');
      expect(client.normalPullCalls, greaterThanOrEqualTo(1));

      // تجهيز الشبكة ثم إعادة الدورة.
      client.pullHealthy = true;
      final r2 = await manager.sync();
      expect(r2.status, SyncStatus.success);
      expect(await pref('cf_last_pull_cursor'), 1700000200);
      expect(await pref('cf_full_sync_completed'), isTrue);
    },
  );
}