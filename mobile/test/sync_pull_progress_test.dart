// ═══════════════════════════════════════════════════════════════
//  sync_pull_progress_test.dart — عقد مؤشر تقدم السحب الكامل
//  ✅ (2026-09-10) طلب المستخدم: «مؤشر السحب الكامل يجب أن أعرف مسار
//  حجم السحب والمتبقي ويجب أن لا يعيق الانتقال الى الشاشات الاخرى»
//
//  يثبت:
//   1. بثّ لقطة بداية (pulled=0) فور بدء الدورة
//   2. بثّ التقدم بعد كل صفحة (pulled تراكمي + remaining الخادمي)
//   3. لقطة نهاية isDone في النجاح (remaining=0) والفشل (الرسالة)
//   4. السحب الكامل فقط يطلب include_remaining=1 من الخادم
//   5. دلتا عادية: isFullSync=false وremaining=null (بلا طلب عدّ)
//   6. حساب fraction في SyncPullProgress (دقيق/غير-محدد)
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _roomRow(
  String uuid, {
  int updatedAt = 1700000100,
}) => {
  'local_uuid': uuid,
  'room_number': 'RN-$uuid',
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

/// عميل وهمي يخدم صفحات pull بالترتيب ويُسجّل روابط الطلبات.
class _QueueClient extends http.BaseClient {
  _QueueClient(this.pages);

  final List<Map<String, dynamic>> pages;
  final List<String> requestedUrls = <String>[];
  int _served = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestedUrls.add(request.url.toString());
    if (request.method != 'GET' || _served >= pages.length) {
      throw StateError('unexpected request: ${request.method} ${request.url}');
    }
    final bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(pages[_served++])),
    );
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

/// عميل صفحته الأولى تُفسد بفشل تطبيق — لعقد لقطة نهاية الفشل.
class _FailFirstClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST') {
      throw http.ClientException('push unreachable (simulated)');
    }
    // صفحة سليمة لكن تطبيقها سيفشل: حقل entity غير معروف لا يُفسّر —
    // لا، ذلك يُسقط صمتاً. نستخدم صندوق أسهل: HTTP 500.
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"error":"server exploded"}')),
      500,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
      'cf_device_id': 'progress-device',
      // مسح الحذفيات التاريخي لمرة واحدة — نعلمه منجزاً كي لا يُطلق
      // طلب tombstones_only إضافياً يخلط على طابور الصفحات الوهمي.
      'cf_tombstone_sweep_v1_done': true,
    });
  });

  tearDown(() async {
    await db.close();
  });

  CloudflareSyncManager makeManager(
    http.Client client, {
    bool fullSyncCompleted = false,
  }) {
    final manager = CloudflareSyncManager();
    manager.reset();
    manager.configureForTesting(
      database: db,
      httpClient: client,
      token: 'test-token',
      deviceId: 'progress-device',
      fullSyncCompleted: fullSyncCompleted,
    );
    return manager;
  }

  group('SyncPullProgress (الوحدة)', () {
    test('fraction دقيق عند توفر remaining', () {
      final p = SyncPullProgress(pulledRows: 300, remainingRows: 100);
      expect(p.fraction, closeTo(0.75, 1e-9));
    });

    test('fraction null بلا remaining (غير-محدد)', () {
      final p = SyncPullProgress(pulledRows: 300);
      expect(p.fraction, isNull);
    });

    test('fraction 1.0 عند الاكتمال الصفري', () {
      final p = SyncPullProgress(
        pulledRows: 0,
        remainingRows: 0,
        isDone: true,
      );
      expect(p.fraction, 1.0);
    });

    test('copyWith بـ remainingRows callable يُحدّث القيمة (لا يُبقيها)', () {
      final p = SyncPullProgress(pulledRows: 10, remainingRows: 90);
      final p2 = p.copyWith(remainingRows: () => 40);
      expect(p2.remainingRows, 40);
      final p3 = p.copyWith(remainingRows: () => null);
      expect(p3.remainingRows, isNull);
    });
  });

  group('عقد تدفق التقدم أثناء دورة السحب', () {
    test(
      'full sync متعدد الصفحات: بداية + لكل صفحة + نهاية — والطلب يطلب '
      'include_remaining',
      () async {
        final client = _QueueClient([
          {
            'changes': [
              _roomRow('p1-a'),
              _roomRow('p1-b', updatedAt: 1700000101),
            ],
            'cursor': '1700000101',
            'has_more': true,
            'remaining': 1,
            'errors': <dynamic>[],
          },
          {
            'changes': [_roomRow('p2-a', updatedAt: 1700000102)],
            'cursor': '1700000102',
            'has_more': false,
            'remaining': 0,
            'errors': <dynamic>[],
          },
        ]);
        final manager = makeManager(client);

        final events = <SyncPullProgress>[];
        final sub = manager.syncPullProgressStream.listen(events.add);

        final result = await manager.sync(push: false);
        expect(result.isSuccess, isTrue);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        // البداية + صفحتان + النهاية
        expect(events, hasLength(4));
        expect(events[0].pulledRows, 0);
        expect(events[0].isFullSync, isTrue);
        expect(events[0].isDone, isFalse);

        expect(events[1].pulledRows, 2);
        expect(events[1].remainingRows, 1);
        expect(events[1].pages, 1);

        expect(events[2].pulledRows, 3);
        expect(events[2].remainingRows, 0);
        expect(events[2].pages, 2);

        expect(events[3].isDone, isTrue);
        expect(events[3].remainingRows, 0);
        expect(events[3].errorMessage, isNull);
        // snapshot getter متزامن للشاشات المتأخرة
        expect(manager.lastPullProgress.isDone, isTrue);
        expect(manager.lastPullProgress.pulledRows, 3);

        // السحب الكامل فقط يطلب remaining الخادمي
        expect(client.requestedUrls, isNotEmpty);
        expect(
          client.requestedUrls.every(
            (u) => u.contains('include_remaining=1'),
          ),
          isTrue,
        );
      },
    );

    test(
      'دلتا عادية: isFullSync=false وremaining=null — ولا include_remaining',
      () async {
        final client = _QueueClient([
          {
            'changes': [_roomRow('d1', updatedAt: 1700000200)],
            'cursor': '1700000200',
            'has_more': false,
            'errors': <dynamic>[],
          },
        ]);
        final manager = makeManager(client, fullSyncCompleted: true);

        final events = <SyncPullProgress>[];
        final sub = manager.syncPullProgressStream.listen(events.add);

        final result = await manager.sync(push: false);
        expect(result.isSuccess, isTrue);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(events, hasLength(3)); // بداية + صفحة + نهاية
        expect(events.every((e) => !e.isFullSync), isTrue);
        // الدلتا لا تحصل على remaining خادمي في الصفحات — لكن لقطة
        // النهاية الناجحة تُغلق العدّاد على صفر (عقد التدفق).
        expect(
          events.where((e) => !e.isDone).every((e) => e.remainingRows == null),
          isTrue,
        );
        expect(events.last.isDone, isTrue);
        expect(events.last.remainingRows, 0);
        expect(
          client.requestedUrls.every(
            (u) => !u.contains('include_remaining'),
          ),
          isTrue,
        );
      },
    );

    test(
      'فشل HTTP: لقطة النهاية تحمل isDone + رسالة الخطأ (بلا انتظار)',
      () async {
        final manager = makeManager(_FailFirstClient());

        final events = <SyncPullProgress>[];
        final sub = manager.syncPullProgressStream.listen(events.add);

        final result = await manager.sync(push: false);
        expect(result.isSuccess, isFalse);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(events, hasLength(2)); // بداية + نهاية (لا صفحات ناجحة)
        expect(events.last.isDone, isTrue);
        expect(events.last.errorMessage, isNotNull);
        expect(events.last.remainingRows, isNull);
      },
    );
  });
}
