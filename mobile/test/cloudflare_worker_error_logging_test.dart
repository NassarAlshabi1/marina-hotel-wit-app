// ═══════════════════════════════════════════════════════════════
//  cloudflare_worker_error_logging_test.dart — 2026-09-09
//
//  اختبارات عقدية لتسجيل أخطاء Cloudflare وWorker في مركز أخطاء
//  المزامنة (ErrorTrackerStore). العقد:
//
//  1. أخطاء errors[] الخادمية أثناء السحب تُسجل بتصنيف worker ومصدر
//     worker:pull — مع فشل الدورة وتجميد المؤشر (لا نجاح مع ناقص).
//  2. رفض Worker لسجلات الدفع الفردية (validation_error) يُسجل
//     بتصنيف worker ومصدر worker:push مع مفتاح idempotency.
//  3. تطبيع الطوابع الزمنية غير المكتمل (remaining > 0) يُسجل
//     تحذيراً بتصنيف worker — دون إفشال الدورة.
//  4. العلاقات الأب غير المحلولة تُسجل بتصنيف sync ومصدر
//     sync:pull-apply (سبب «البيانات غير مكتملة» الأشهر).
//  5. المؤشر المسموم (ميلي-ثانية) عند الإقلاع يُسجل بتصنيف sync
//     ومصدر sync:init.
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';

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
}) => {
  ..._syncFields(uuid, updatedAt, serverId: serverId),
  'room_number': 'RN-$uuid',
  'type': 'double',
  'price': 100.0,
  'status': 'available',
  'cleaning_status': 'clean',
  'requires_maintenance': 0,
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

Map<String, dynamic> _emptyPullPage({Map<String, dynamic>? extra}) => {
  'changes': <dynamic>[],
  'cursor': '0',
  'has_more': false,
  'errors': <dynamic>[],
  ...?extra,
};

/// عميل وهمي يجيب: login 200، push 200 بنتيجة قابلة للضبط، وpull
/// بصفحات مرتبة.
class _FakeWorkerClient extends http.BaseClient {
  _FakeWorkerClient({
    this.pullPages = const <Map<String, dynamic>>[],
    this.pushBody,
  });

  final List<Map<String, dynamic>> pullPages;
  final Map<String, dynamic>? pushBody;
  int _served = 0;

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
        'user': {
          'id': 'u1',
          'username': 'sync_service',
          'role': 'admin',
        },
      });
    }
    if (request.method == 'POST' && path.endsWith('/api/sync/push')) {
      return _json(pushBody ?? {'results': <dynamic>[]});
    }
    if (request.method == 'GET' && path.endsWith('/api/sync/pull')) {
      if (_served >= pullPages.length) {
        throw StateError('pull exhausted after ${pullPages.length} pages');
      }
      return _json(pullPages[_served++]);
    }
    throw StateError('unexpected ${request.method} $path');
  }
}

bool _hasEntry({
  required ErrorCategory category,
  required String source,
  String? titleContains,
}) {
  return ErrorTrackerStore.instance.errors.any(
    (e) =>
        e.category == category &&
        e.source == source &&
        (titleContains == null || e.title.contains(titleContains)),
  );
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

  Future<CloudflareSyncManager> makeManager(
    http.Client client, {
    String deviceId = 'error-log-device',
  }) async {
    final manager = CloudflareSyncManager();
    manager.reset();
    manager.configureForTesting(
      database: db,
      httpClient: client,
      token: 'test-token',
      deviceId: deviceId,
    );
    return manager;
  }

  Future<Object?> pref(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.get(key);
  }

  test(
    'أخطاء errors[] الخادمية أثناء السحب تُسجل بتصنيف worker (worker:pull)',
    () async {
      final manager = await makeManager(
        _FakeWorkerClient(
          pullPages: [
            {
              'changes': [_roomRow('rm-err-1')],
              'cursor': '1700000100',
              'has_more': false,
              'errors': [
                {
                  'entity': 'booking_nights',
                  'error': 'simulated worker table failure',
                },
              ],
            },
          ],
        ),
      );

      final result = await manager.sync();

      // الدورة نفسها تُعتبر فاشلة (سياسة لا نجاح مع جداول ناقصة) —
      // والمؤشر لا يتحرك (لا يُكتب في prefs إلا عند النجاح الكامل).
      expect(result.status, SyncStatus.failed);
      expect(manager.failedCollectionsInLastSync, contains('booking_nights'));
      expect(
        await pref('cf_last_pull_cursor'),
        isNull,
        reason: 'المؤشر المتجمد لا يُكتب إطلاقاً في prefs',
      );

      // ✅ العقد الجديد: الخطأ الخادمي ظاهر في مركز أخطاء المزامنة.
      expect(
        _hasEntry(
          category: ErrorCategory.worker,
          source: 'worker:pull',
          titleContains: 'Worker',
        ),
        isTrue,
        reason: 'worker errors[] يجب أن تُسجل في ErrorTrackerStore',
      );
      final entry = ErrorTrackerStore.instance.errors.firstWhere(
        (e) => e.source == 'worker:pull',
      );
      expect(entry.message, contains('booking_nights'));
      expect(entry.message, contains('simulated worker table failure'));
    },
  );

  test(
    'رفض Worker لسجل دفع (validation_error) يُسجل بتصنيف worker (worker:push)',
    () async {
      const clientTs = 1700000900;
      await OutboxDao(db).merge(
        entity: 'rooms',
        op: 'update',
        localUuid: 'rm-push-reject',
        payload: const <String, dynamic>{
          'room_number': 'RN-REJECT',
          'status': 'available',
        },
        clientTs: clientTs,
      );

      final manager = await makeManager(
        _FakeWorkerClient(
          pullPages: [_emptyPullPage()],
          pushBody: {
            'results': [
              {
                'idempotencyKey': 'rooms:update:rm-push-reject:$clientTs',
                'success': false,
                'status': 'validation_error',
                'error': 'no such column: ghost_col',
              },
            ],
          },
        ),
      );

      await manager.sync();

      // ✅ العقد الجديد: رفض الخادم ظاهر في المركز مع المفتاح والسبب.
      expect(
        _hasEntry(
          category: ErrorCategory.worker,
          source: 'worker:push',
          titleContains: 'Worker رفض',
        ),
        isTrue,
        reason: 'رفض الدفع الخادمي يجب أن يُسجل في ErrorTrackerStore',
      );
      final entry = ErrorTrackerStore.instance.errors.firstWhere(
        (e) => e.source == 'worker:push',
      );
      expect(entry.message, contains('validation_error'));
      expect(entry.message, contains('rooms:update:rm-push-reject:$clientTs'));
      expect(entry.message, contains('no such column: ghost_col'));
    },
  );

  test(
    'تطبيع الطوابع غير المكتمل (remaining>0) يُسجل تحذيراً دون إفشال الدورة',
    () async {
      final manager = await makeManager(
        _FakeWorkerClient(
          pullPages: [
            _emptyPullPage(
              extra: {
                'normalization': {
                  'normalized': 3,
                  'remaining': 7,
                  'perTable': {'guest_infos': 3},
                },
              },
            ),
          ],
        ),
      );

      final result = await manager.sync();

      // التطبيع تحذير تشخيصي فقط — لا يفشل الدورة.
      expect(result.status, SyncStatus.success);
      expect(
        _hasEntry(
          category: ErrorCategory.worker,
          source: 'worker:pull',
          titleContains: 'تطبيع',
        ),
        isTrue,
        reason: 'remaining>0 يجب أن يظهر تحذيراً في المركز',
      );
    },
  );

  test(
    'العلاقات الأب غير المحلولة تُسجل بتصنيف sync (sync:pull-apply)',
    () async {
      final manager = await makeManager(
        _FakeWorkerClient(
          pullPages: [
            {
              'changes': [_nightRow('nt-orphan-log')],
              'cursor': '1700000300',
              'has_more': false,
              'errors': <dynamic>[],
            },
          ],
        ),
      );

      final result = await manager.sync();

      expect(result.status, SyncStatus.failed);
      expect(
        _hasEntry(
          category: ErrorCategory.sync,
          source: 'sync:pull-apply',
        ),
        isTrue,
        reason: 'السجلات اليتيمة يجب أن تُسجل في مركز الأخطاء',
      );
      final entry = ErrorTrackerStore.instance.errors.firstWhere(
        (e) => e.source == 'sync:pull-apply',
      );
      expect(entry.message, contains('booking_nights/nt-orphan-log'));
    },
  );

  test(
    'المؤشر المسموم (ميلي-ثانية) عند الإقلاع يُسجل بتصنيف sync (sync:init)',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'cloudflare_sync_local_override': true,
        'cf_last_pull_cursor': 200000000000,
        'cf_full_sync_completed': true,
      });

      final manager = CloudflareSyncManager();
      manager.reset();
      await manager.initialize(database: db);

      // العقد: التصفير حدث + الحدث مسجل في المركز.
      expect(await pref('cf_last_pull_cursor'), 0);
      expect(
        _hasEntry(
          category: ErrorCategory.sync,
          source: 'sync:init',
          titleContains: 'مسموم',
        ),
        isTrue,
        reason: 'تصفير المؤشر المسموم يجب أن يظهر في مركز الأخطاء',
      );
    },
  );

  test('عدّاد سجل القراءة: دفتر النظافة لا يسرّب سجلات بين الاختبارات', () {
    // setUp يصفّر المخزن — يضمن أن clear() يعمل وأن الاختبارات معزولة.
    expect(ErrorTrackerStore.instance.errors, isEmpty);
    expect(
      _hasEntry(category: ErrorCategory.worker, source: 'worker:pull'),
      isFalse,
    );
  });
}
