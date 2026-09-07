// ═══════════════════════════════════════════════════════════════
//  sync_pull_contract_test.dart — 2026-09-08 إعادة هيكلة مسار السحب
//
//  اختبارات عقدية للمحاور الثلاثة لإصلاح «لم يتم سحب كل البيانات»:
//
//  1) فصل دورة الدفع عن السحب — فشل الرفع (شبكة) لا يمنع السحب،
//     والتقرير يجمع فشلَي الدورتين بدل قطع الثانية بأولى.
//  2) منع السحب من إعلان النجاح مع جداول ناقصة — أخطاء الجداول
//     الخادمية (errors[]) تمنع تقدّم checkpoint وضبط علامة
//     full sync، مع التراجع إلى ما قبل أول صفحة معطوبة (الصفوف
//     التابعة للجدول المتخطى بين الحدين لم تُرسل أصلاً — علامة
//     مائية صارمة `>` ستفقدها للأبد).
//  3) ع freshness العقد: فشل دورة سابقة لا يلوّث دورة نظيفة لاحقة.
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _roomRow(
  String uuid, {
  int updatedAt = 1700000100,
  String? roomNumber,
}) => {
  'local_uuid': uuid,
  'room_number': roomNumber ?? 'RN-$uuid',
  'type': 'double',
  'price': 100.0,
  'status': 'available',
  'cleaning_status': 'clean',
  'requires_maintenance': 0,
  'created_at': updatedAt,
  'updated_at': updatedAt,
  'last_modified': updatedAt,
  'created_at_epoch': 0,
  'last_modified_epoch': 0,
  'version': 1,
  'origin': 'local',
  'vector_clock': '{}',
  'device_id': 'other-device',
};

/// عميل وهمي يخدم صفحات pull من طابور بالترتيب، ويرمي على أي طلب آخر
/// (لكي يُظهر الاختبار أي نداء غير متوقع حدث).
class _PullQueueClient extends http.BaseClient {
  final List<Map<String, dynamic>> pages;
  int _served = 0;
  _PullQueueClient(this.pages);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'GET') {
      throw StateError(
        '_PullQueueClient got unexpected ${request.method} ${request.url}',
      );
    }
    if (_served >= pages.length) {
      throw StateError(
        '_PullQueueClient exhausted after ${pages.length} pages '
        '(cursor=${request.url.queryParameters['cursor']})',
      );
    }
    final body = jsonEncode(pages[_served++]);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

/// عميل وهمي: POST (دفع) يرمي خطأ شبكة، GET (سحب) يخدم الطابور.
class _PushBrokenClient extends http.BaseClient {
  final List<Map<String, dynamic>> pullPages;
  int _served = 0;
  _PushBrokenClient(this.pullPages);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST') {
      throw http.ClientException('push endpoint unreachable (simulated)');
    }
    if (_served >= pullPages.length) {
      throw StateError('_PushBrokenClient exhausted');
    }
    final body = jsonEncode(pullPages[_served++]);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
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

  Future<CloudflareSyncManager> makeManager(
    http.Client client, {
    Map<String, Object> prefsInit = const <String, Object>{},
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true, // تجاوز مفتاح الإيقاف البعيد
      ...prefsInit,
    });
    final manager = CloudflareSyncManager();
    manager.reset();
    manager.configureForTesting(
      database: db,
      httpClient: client,
      token: 'test-token',
      deviceId: 'contract-device',
    );
    return manager;
  }

  Future<int> roomsCount() async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM rooms')
        .getSingle();
    return row.read<int>('c');
  }

  Future<Object?> pref(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.get(key);
  }

  group('عقد السحب: أخطاء الجداول الخادمية (محور 2)', () {
    test(
      'دورة نظيفة: المؤشر يتقدم لعلامة الخادم + full sync يُضبط + نجاح',
      () async {
        final manager = await makeManager(
          _PullQueueClient([
            {
              'changes': [
                _roomRow('uuid-a', updatedAt: 1700000100),
                _roomRow('uuid-b', updatedAt: 1700000101, roomNumber: 'RN-2'),
              ],
              'cursor': '1700000101',
              'has_more': false,
              'errors': <dynamic>[],
            },
          ]),
        );

        final result = await manager.sync();

        expect(result.status, SyncStatus.success);
        expect(result.recordsPulled, 2);
        expect(await pref('cf_last_pull_cursor'), 1700000101);
        expect(await pref('cf_full_sync_completed'), true);
        expect(manager.failedCollectionsInLastSync, isEmpty);
        expect(await roomsCount(), 2);
      },
    );

    test(
      'خطأ خادمي في أول صفحة: المؤشر لا يتقدم للأبد + بلا علامة full sync + فشل صريح',
      () async {
        // الصفحة الوحيدة حملت صفاً سليماً وcursor متقدماً، لكن الخادم
        // أخطأ جدول devices كلياً — الصفوف التابعة له في هذه النافذة
        // لم تُرسل أبداً، فلا يجوز اعتماد المؤشر المتقدم.
        final manager = await makeManager(
          _PullQueueClient([
            {
              'changes': [_roomRow('uuid-a')],
              'cursor': '1700000100',
              'has_more': false,
              'errors': [
                {'entity': 'devices', 'error': 'no such table: devices'},
              ],
            },
          ]),
        );

        final result = await manager.sync();

        expect(result.status, SyncStatus.failed);
        expect(result.errorMessage, contains('devices'));
        // ⚠️ العقد الحرج: المؤشر تراجع إلى ما قبل الصفحة المعطوبة (0)
        // رغم أن الخادم أرسل cursor=1700000100.
        expect(await pref('cf_last_pull_cursor'), 0);
        expect(await pref('cf_full_sync_completed'), isNull);
        expect(manager.failedCollectionsInLastSync, contains('devices'));
        // الصف السليم طُبق فعلاً (idempotent عند إعادة السحب لاحقاً).
        expect(await roomsCount(), 1);
      },
    );

    test(
      'خطأ خادمي في صفحة وسطى: يُحفظ تقدم الصفحات النظيفة فقط',
      () async {
        // صفحة 1 نظيفة (cursor 100) ← صفحة 2 معطوبة (cursor 200).
        // الحد الآمن = 100: صفوف devices بين 100 و200 لم تُرسل.
        final manager = await makeManager(
          _PullQueueClient([
            {
              'changes': [
                _roomRow('uuid-a', updatedAt: 1700000050),
              ],
              'cursor': '1700000100',
              'has_more': true,
              'errors': <dynamic>[],
            },
            {
              'changes': [
                _roomRow('uuid-b', updatedAt: 1700000150, roomNumber: 'RN-2'),
              ],
              'cursor': '1700000200',
              'has_more': false,
              'errors': [
                {'entity': 'devices', 'error': 'no such table: devices'},
              ],
            },
          ]),
        );

        final result = await manager.sync();

        expect(result.status, SyncStatus.failed);
        expect(await pref('cf_last_pull_cursor'), 1700000100);
        expect(await pref('cf_full_sync_completed'), isNull);
        expect(manager.failedCollectionsInLastSync, contains('devices'));
        // الصفان السليمان طُبقا (الصفحة النظيفة + صفوف الصفحة المعطوبة
        // السليمة) — إعادة السحب من 100 لاحقاً idempotent.
        expect(await roomsCount(), 2);
      },
    );
  });

  group('عقد فصل الدفع عن السحب (محور 1)', () {
    test(
      'فشل شبكة الدفع لا يمنع السحب: الصفوف تُسحب والفشل يُذكر صراحة',
      () async {
        final manager = await makeManager(
          _PushBrokenClient([
            {
              'changes': [
                _roomRow('uuid-pull', updatedAt: 1700000100),
              ],
              'cursor': '1700000100',
              'has_more': false,
              'errors': <dynamic>[],
            },
          ]),
        );

        // ازرع صف outbox معلّق ليضمن محاولة POST فعلية أثناء الدورة.
        await OutboxDao(db).merge(
          entity: 'rooms',
          op: 'update',
          localUuid: 'uuid-outbox',
          payload: _roomRow('uuid-outbox'),
          clientTs: 1700000099,
        );

        final result = await manager.sync();

        // الدفع فشل → الدورة failed والسبب مذكور بمصدره…
        expect(result.status, SyncStatus.failed);
        expect(result.errorMessage, contains('push:'));
        expect(result.errorMessage, contains('Push network error'));
        // …لكن السحب اكتمل وعُبّيت بياناته (قبل الإصلاح كان السحب
        // يُقفز كلياً عند أول استثناء دفع).
        expect(result.recordsPulled, 1);
        expect(await roomsCount(), 1);
        expect(await pref('cf_last_pull_cursor'), 1700000100);
        expect(await pref('cf_full_sync_completed'), true);
      },
    );
  });

  group('عقد نقاء الحالة بين الدورات (محور 3)', () {
    test(
      'دورة متدهورة تليها دورة نظيفة: النجاح يعود والمجموعة تُنظّف',
      () async {
        // دورة 1: خطأ خادمي → فشل + مؤشر ثابت عند 0.
        final manager = await makeManager(
          _PullQueueClient([
            {
              'changes': <dynamic>[],
              'cursor': '1700000100',
              'has_more': false,
              'errors': [
                {'entity': 'devices', 'error': 'no such table: devices'},
              ],
            },
          ]),
        );
        expect((await manager.sync()).status, SyncStatus.failed);
        expect(manager.failedCollectionsInLastSync, contains('devices'));

        // دورة 2 (نفس المدير): خادم شُفي — صفحات نظيفة.
        manager.configureForTesting(
          database: db,
          httpClient: _PullQueueClient([
            {
              'changes': [
                _roomRow('uuid-healed', updatedAt: 1700000100),
              ],
              'cursor': '1700000100',
              'has_more': false,
              'errors': <dynamic>[],
            },
          ]),
          token: 'test-token',
        );

        final second = await manager.sync();

        // قبل الإصلاح كانت المجموعة تراكمياً — كل الدورات اللاحقة
        // «فاشلة جزئياً» للأبد. العقد: الدورة النظيفة = نجاح كامل.
        expect(second.status, SyncStatus.success);
        expect(manager.failedCollectionsInLastSync, isEmpty);
        expect(await pref('cf_last_pull_cursor'), 1700000100);
        expect(await pref('cf_full_sync_completed'), true);
      },
    );
  });
}
