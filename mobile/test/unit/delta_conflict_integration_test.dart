// test/unit/delta_conflict_integration_test.dart
//
// ✅ اختبار تكامل نقطة التقاء Delta Pull بمعالجة التعارضات:
// SyncPullService.checkAndResolveConflict هو ما يُستدعى لكل مستند مُسحوب
// عبر delta query (انظر appwrite_sync_manager.dart:2296 وما بعدها).
// يثبت القرارات الحتمية عند غياب ancestor cache (الحالة الشائعة في السحب).

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_pull_service.dart';
import 'package:marina_hotel_mobile/test/helpers/test_database.dart';

void main() {
  group('SyncPullService.checkAndResolveConflict (delta + conflict)', () {
    late SyncPullService pull;
    late AppDatabase db;

    setUp(() {
      db = TestDatabase.create();
      pull = SyncPullService(
        appwriteService: AppwriteService(),
        database: db,
        outboxDao: OutboxDao(db),
      );
    });

    tearDown(() => db.close());

    test('حذف محلي له الأولوية على تحديث بعيد (لا فقدان صامت)', () async {
      final result = await pull.checkAndResolveConflict(
        {'status': 'updated', 'lastModified': 6000, 'deviceId': 'devB'},
        5000,
        localDeletedAt: 5500, // محذوف محلياً
        remoteUpdatedAtSec: 6000,
        localVectorClock: '{"devA":1}',
        entityName: 'bookings',
        localUuid: 'u1',
      );
      expect(result.shouldApplyRemote, isFalse);
    });

    test('سجل غير موجود محلياً → يُطبَّق البعيد دائماً', () async {
      final result = await pull.checkAndResolveConflict(
        {'status': 'new', 'lastModified': 6000, 'deviceId': 'devB'},
        null, // غير موجود محلياً
        remoteUpdatedAtSec: 6000,
        entityName: 'bookings',
        localUuid: 'u1',
      );
      expect(result.shouldApplyRemote, isTrue);
    });

    test('بعيد أحدث صراحةً → يُطبَّق (delta يجلب التحديث)', () async {
      final result = await pull.checkAndResolveConflict(
        {'status': 'remote', 'lastModified': 7000, 'deviceId': 'devB'},
        5000,
        remoteUpdatedAtSec: 7000,
        localVectorClock: '{"devA":1}',
        entityName: 'bookings',
        localUuid: 'u1',
      );
      expect(result.shouldApplyRemote, isTrue);
    });

    test('محلي أحدث → لا يُطبَّع البعيد (يحمي التعديل المحلي)', () async {
      final result = await pull.checkAndResolveConflict(
        {'status': 'remote', 'lastModified': 4000, 'deviceId': 'devB'},
        5000,
        remoteUpdatedAtSec: 4000,
        localVectorClock: '{"devA":2}',
        entityName: 'bookings',
        localUuid: 'u1',
      );
      expect(result.shouldApplyRemote, isFalse);
    });
  });
}
