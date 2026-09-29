// ═══════════════════════════════════════════════════════════════
//  sync_epoch_test.dart — ✅ (2026-09-29) جيل بيانات الخادم (epoch)
//  عقود العميل (CloudflareSyncManager._handleServerEpoch):
//   1. أول مشاهدة → تبنٍّ صامت (لا سحب كامل مكلف لمجرد الترقية).
//   2. جيل مختلف → الصفحة المبنية على مؤشر الجيل السابق تُهمل،
//      المؤشر وعلامة full sync يُصفّران، ويُعاد السحب من الصفر في
//      الدورة نفسها.
//   3. worker قديم بلا epoch → لا شيء يتغير.
//   4. تغيّر ثانٍ أثناء إعادة التشغيل من الصفر → تبنٍّ بلا حلقة.
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _roomRow(String uuid, int updatedAt) => {
  'id': null,
  'local_uuid': uuid,
  'created_at': updatedAt,
  'updated_at': updatedAt,
  'last_modified': updatedAt,
  'created_at_epoch': 0,
  'last_modified_epoch': 0,
  'version': 1,
  'origin': 'local',
  'vector_clock': '{}',
  'device_id': 'other-device',
  'room_number': 'RN-$uuid',
  'type': 'double',
  'price': 100.0,
  'status': 'available',
  'cleaning_status': 'clean',
  'requires_maintenance': 0,
};

Map<String, dynamic> _page({
  required List<Map<String, dynamic>> changes,
  required String cursor,
  String? epoch,
}) => {
  'changes': changes,
  'cursor': cursor,
  'has_more': false,
  'errors': <dynamic>[],
  'epoch': ?epoch,
};

/// يخدم صفحات السحب بالترتيب ويسجّل مؤشر كل طلب سحب.
class _ScriptedWorker extends http.BaseClient {
  _ScriptedWorker(this.pages);

  final List<Map<String, dynamic>> pages;
  final List<String> pullCursors = <String>[];
  int _served = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/api/sync/push')) {
      return _json({'results': <dynamic>[]});
    }
    if (request.method == 'GET' && path.endsWith('/api/sync/pull')) {
      if (request.url.queryParameters['tombstones_only'] == '1') {
        return _json(_page(changes: const [], cursor: '0'));
      }
      pullCursors.add(request.url.queryParameters['cursor'] ?? '?');
      if (_served >= pages.length) {
        throw StateError('pull exhausted after ${pages.length} pages');
      }
      return _json(pages[_served++]);
    }
    throw StateError('unexpected ${request.method} $path');
  }

  http.StreamedResponse _json(Map<String, dynamic> body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        200,
        headers: {'content-type': 'application/json'},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<CloudflareSyncManager> managerWith(
    _ScriptedWorker client, {
    required int cursor,
  }) async {
    final manager = CloudflareSyncManager()..reset();
    manager.configureForTesting(
      database: db,
      httpClient: client,
      token: 'test-token',
      fullSyncCompleted: true,
      lastPullCursor: cursor,
    );
    return manager;
  }

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  test('أول مشاهدة للجيل → تبنٍّ صامت والمؤشر يتقدم طبيعياً', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
      'cf_last_pull_cursor': 1700000000,
      'cf_full_sync_completed': true,
      // علم مسح الحذفيات مضبوط حتى لا يدخل طلبه في السيناريو.
      'cf_tombstone_sweep_v1_done': true,
    });
    final worker = _ScriptedWorker([
      _page(
        changes: [_roomRow('rm-a', 1700000100)],
        cursor: '1700000100',
        epoch: 'e1',
      ),
    ]);
    final manager = await managerWith(worker, cursor: 1700000000);

    await manager.sync(push: false);

    expect(worker.pullCursors, <String>['1700000000']);
    final p = await prefs();
    expect(p.getString(CloudflareSyncManager.kSyncEpochKey), 'e1');
    expect(p.getInt('cf_last_pull_cursor'), 1700000100);
  });

  test('تغيّر الجيل → الصفحة القديمة تُهمل ويُعاد السحب من الصفر '
      'في الدورة نفسها', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
      'cf_last_pull_cursor': 1700000000,
      'cf_full_sync_completed': true,
      'cf_tombstone_sweep_v1_done': true,
      CloudflareSyncManager.kSyncEpochKey: 'e1',
    });
    final worker = _ScriptedWorker([
      // صفحة من الجيل الجديد لكن بمؤشر الجيل القديم — يجب ألا تُطبَّق.
      _page(
        changes: [_roomRow('rm-stale-page', 1700000200)],
        cursor: '1700000200',
        epoch: 'e2',
      ),
      // إعادة السحب من الصفر.
      _page(
        changes: [_roomRow('rm-restored', 1600000000)],
        cursor: '1700000300',
        epoch: 'e2',
      ),
    ]);
    final manager = await managerWith(worker, cursor: 1700000000);

    await manager.sync(push: false);

    expect(worker.pullCursors, <String>['1700000000', '0']);
    final p = await prefs();
    expect(p.getString(CloudflareSyncManager.kSyncEpochKey), 'e2');
    expect(p.getInt('cf_last_pull_cursor'), 1700000300);

    final rooms = await db.select(db.rooms).get();
    final uuids = rooms.map((r) => r.localUuid).toSet();
    expect(
      uuids,
      contains('rm-restored'),
      reason: 'صف أقدم من المؤشر القديم (1600000000) وصل بفضل السحب من الصفر',
    );
    expect(
      uuids,
      isNot(contains('rm-stale-page')),
      reason: 'صفحة الجيل الجديد المبنية على المؤشر القديم أُهملت',
    );
  });

  test('worker قديم بلا epoch → لا تخزين ولا إعادة سحب', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
      'cf_last_pull_cursor': 1700000000,
      'cf_full_sync_completed': true,
      'cf_tombstone_sweep_v1_done': true,
      CloudflareSyncManager.kSyncEpochKey: 'e1',
    });
    final worker = _ScriptedWorker([
      _page(changes: const [], cursor: '1700000000'),
    ]);
    final manager = await managerWith(worker, cursor: 1700000000);

    await manager.sync(push: false);

    expect(worker.pullCursors, <String>['1700000000']);
    expect(
      (await prefs()).getString(CloudflareSyncManager.kSyncEpochKey),
      'e1',
    );
  });

  test('تغيّر ثانٍ أثناء إعادة التشغيل من الصفر → تبنٍّ بلا حلقة', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
      'cf_last_pull_cursor': 1700000000,
      'cf_full_sync_completed': true,
      'cf_tombstone_sweep_v1_done': true,
      CloudflareSyncManager.kSyncEpochKey: 'e1',
    });
    final worker = _ScriptedWorker([
      _page(changes: const [], cursor: '1700000000', epoch: 'e2'),
      _page(changes: const [], cursor: '1700000400', epoch: 'e3'),
    ]);
    final manager = await managerWith(worker, cursor: 1700000000);

    await manager.sync(push: false);

    expect(worker.pullCursors, <String>['1700000000', '0']);
    final p = await prefs();
    expect(p.getString(CloudflareSyncManager.kSyncEpochKey), 'e3');
    expect(p.getInt('cf_last_pull_cursor'), 1700000400);
  });
}
