// test/unit/sync_pull_service_pushed_to_remote_test.dart
//
// ✅ Sync Safety Wave 3 (2026-08-10): اختبار Conflict Resolution End-to-End
//
// يتحقق هذا الملف من أن SyncPullService.checkAndResolveConflict() يضع
// pushedToRemote=true عند إنتاج بيانات مدمجة (3-way merge) لتعارض متزامن.
// AppwriteSyncManager._isRemoteDataNewer يستهلك هذه القيمة ويُنشئ outbox
// entry لإعادة رفع النتيجة للسحابة.
//
// السيناريوهات المغطاة:
//  1. تعارض متزامن (concurrent) مع 3-way merge ناجح → pushedToRemote=true
//  2. تعارض متزامن بدون ancestor → fallback LWW → pushedToRemote=false
//  3. لا تعارض (remote newer) → pushedToRemote=false
//  4. لا تعارض (local newer) → shouldApplyRemote=false
//  5. سجل محذوف محلياً → soft delete protection → shouldApplyRemote=false
//  6. سجل جديد محلياً → shouldApplyRemote=true

// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/daos/ancestor_cache_dao.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_pull_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late OutboxDao outboxDao;
  late AncestorCacheDao ancestorCacheDao;
  late SyncPullService pullService;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outboxDao = OutboxDao(db);
    ancestorCacheDao = AncestorCacheDao(db);
    // ✅ نستخدم AppwriteService() singleton — checkAndResolveConflict لا
    // يستدعي أي methods عليه (فقط isRemoteEpochMillis يفعل، وليست في scope
    // اختباراتنا). هذا يُجنّبنا الحاجة لـ mock معقد.
    pullService = SyncPullService(
      appwriteService: AppwriteService(),
      database: db,
      outboxDao: outboxDao,
    );
    pullService.setAncestorCacheDao(ancestorCacheDao, deviceId: 'device-A');
  });

  tearDown(() async {
    await db.close();
  });

  group('SyncPullService — pushedToRemote behavior', () {
    test(
      '25. تعارض متزامن مع 3-way merge ناجح → pushedToRemote=true',
      () async {
        // ✅ إعداد: سجل محلي بنسخة متجهية + ancestor مشترك
        final localUuid = 'booking-001';
        final entity = 'bookings';

        // ancestor مشترك (النسخة الأصلية قبل التشعّب)
        final ancestor = {
          'localUuid': localUuid,
          'status': 'confirmed',
          'roomNumber': '101',
          'lastModified': 1000,
          'vectorClock': '{"device-A": 1, "device-B": 1}',
        };
        await ancestorCacheDao.saveAncestor(
          entity: entity,
          localUuid: localUuid,
          data: ancestor,
        );

        // محلي: غيّر status من device-A
        final localData = {
          'localUuid': localUuid,
          'status': 'checked_in', // ← تغيير محلي
          'roomNumber': '101',
          'lastModified': 2000,
          'vectorClock': '{"device-A": 2, "device-B": 1}',
        };

        // بعيد: غيّر roomNumber من device-B (في نفس الوقت)
        final remoteData = {
          'localUuid': localUuid,
          'status': 'confirmed',
          'roomNumber': '102', // ← تغيير بعيد
          'lastModified': 2000,
          'vectorClock': '{"device-A": 1, "device-B": 2}',
        };

        // تنفيذ
        final result = await pullService.checkAndResolveConflict(
          remoteData,
          2000, // localLastModified
          remoteUpdatedAtSec: 2000,
          localVectorClock: '{"device-A": 2, "device-B": 1}',
          entityName: entity,
          localUuid: localUuid,
          localData: localData,
        );

        // تحقق
        expect(
          result.shouldApplyRemote,
          isTrue,
          reason: 'البيانات المدمجة يجب أن تُطبَّق محلياً',
        );
        expect(
          result.pushedToRemote,
          isTrue,
          reason: 'يجب رفع النتيجة للسحابة لمنع silent divergence',
        );
        expect(
          result.mergedData,
          isNotNull,
          reason: 'يجب أن تحتوي على بيانات مدمجة',
        );
        // دمج ثلاثي الأطراف: status من المحلي، roomNumber من البعيد
        expect(result.mergedData!['status'], 'checked_in');
        expect(result.mergedData!['roomNumber'], '102');
      },
    );

    test(
      '26. تعارض متزامن بدون localData → fallback LWW → pushedToRemote=false',
      () async {
        final localUuid = 'booking-002';

        // بعيد مختلف (concurrent) — لكن لا نمرّر localData
        // → SmartConflictResolver لا يُستدعى (يتطلب localData)
        // → LWW fallback مع deviceId tie-break
        final remoteData = {
          'localUuid': localUuid,
          'status': 'confirmed',
          'lastModified': 2000,
          'vectorClock': '{"device-A": 1, "device-B": 2}',
        };

        // بدون localData → LWW fallback path
        final result = await pullService.checkAndResolveConflict(
          remoteData,
          2000,
          remoteUpdatedAtSec: 2000,
          localVectorClock: '{"device-A": 2, "device-B": 1}',
          entityName: 'bookings',
          localUuid: localUuid,
          localData: null, // ← لا localData → لا 3-way merge
        );

        // LWW: timestamps متطابقة (2000==2000) → deviceId tie-break
        // device-A > device-B بترتيب lexicographic → local يفوز
        expect(
          result.pushedToRemote,
          isFalse,
          reason:
              'LWW fallback لا يضع pushedToRemote=true '
              '(البيانات المحلية أحدث)',
        );
      },
    );

    test('27. remote newer (no conflict) → pushedToRemote=false', () async {
      final localUuid = 'booking-003';
      final remoteData = {
        'localUuid': localUuid,
        'status': 'checked_in',
        'lastModified': 3000,
        'vectorClock': '{"device-A": 1, "device-B": 3}',
      };

      final result = await pullService.checkAndResolveConflict(
        remoteData,
        1000, // local older
        remoteUpdatedAtSec: 3000,
        localVectorClock: '{"device-A": 1, "device-B": 1}',
        entityName: 'bookings',
        localUuid: localUuid,
        localData: {
          'localUuid': localUuid,
          'status': 'confirmed',
          'lastModified': 1000,
          'vectorClock': '{"device-A": 1, "device-B": 1}',
        },
      );

      expect(result.shouldApplyRemote, isTrue, reason: 'البعيد أحدث');
      expect(
        result.pushedToRemote,
        isFalse,
        reason: 'لا تعارض → لا حاجة للرفع للسحابة',
      );
      expect(result.mergedData, isNull);
    });

    test(
      '28. local newer (no conflict) → shouldApplyRemote=false',
      () async {
        final localUuid = 'booking-004';
        final remoteData = {
          'localUuid': localUuid,
          'status': 'confirmed',
          'lastModified': 1000,
          'vectorClock': '{"device-A": 1, "device-B": 1}',
        };

        final result = await pullService.checkAndResolveConflict(
          remoteData,
          3000, // local newer
          remoteUpdatedAtSec: 1000,
          localVectorClock: '{"device-A": 3, "device-B": 1}',
          entityName: 'bookings',
          localUuid: localUuid,
          localData: {
            'localUuid': localUuid,
            'status': 'checked_in',
            'lastModified': 3000,
            'vectorClock': '{"device-A": 3, "device-B": 1}',
          },
        );

        expect(
          result.shouldApplyRemote,
          isFalse,
          reason: 'المحلي أحدث — لا نطبّق البعيد',
        );
        expect(result.pushedToRemote, isFalse);
        expect(result.mergedData, isNull);
      },
    );

    test(
      '29. soft delete محلي محمي — shouldApplyRemote=false',
      () async {
        final localUuid = 'booking-005';
        final remoteData = {
          'localUuid': localUuid,
          'status': 'confirmed',
          'lastModified': 2000,
          // لا deletedAt في البعيد → السجل ما زال حياً في السحابة
        };

        final result = await pullService.checkAndResolveConflict(
          remoteData,
          1000,
          localDeletedAt: 2000, // محذوف محلياً
          remoteUpdatedAtSec: 2000,
          localVectorClock: '{"device-A": 2}',
          entityName: 'bookings',
          localUuid: localUuid,
          localData: null,
        );

        expect(
          result.shouldApplyRemote,
          isFalse,
          reason: 'soft delete المحلي محمي — لا نُحيي السجل من السحابة',
        );
        expect(result.pushedToRemote, isFalse);
      },
    );

    test(
      '30. سجل جديد محلياً (آخر تعديل null) → shouldApplyRemote=true',
      () async {
        final localUuid = 'booking-006';
        final remoteData = {
          'localUuid': localUuid,
          'status': 'confirmed',
          'lastModified': 2000,
        };

        final result = await pullService.checkAndResolveConflict(
          remoteData,
          null, // لا يوجد محلياً → جديد
          remoteUpdatedAtSec: 2000,
          entityName: 'bookings',
          localUuid: localUuid,
          localData: null,
        );

        expect(
          result.shouldApplyRemote,
          isTrue,
          reason: 'السجل غير موجود محلياً → يجب إضافته',
        );
        expect(
          result.pushedToRemote,
          isFalse,
          reason: 'لا تعارض → لا حاجة للرفع',
        );
      },
    );
  });

  group('VectorClockComparator — حالات التعارض', () {
    test(
      '31. VCs متساوية مع محتوى مختلف → shouldApplyRemote=true (apply remote)',
      () async {
        final localUuid = 'booking-007';

        final result = await pullService.checkAndResolveConflict(
          {
            'localUuid': localUuid,
            'status': 'checked_in', // ← مختلف
            'lastModified': 2000,
            'vectorClock': '{"device-A": 1, "device-B": 1}',
          },
          2000,
          remoteUpdatedAtSec: 2000,
          localVectorClock: '{"device-A": 1, "device-B": 1}',
          entityName: 'bookings',
          localUuid: localUuid,
          localData: {
            'localUuid': localUuid,
            'status': 'confirmed', // ← مختلف
            'lastModified': 2000,
            'vectorClock': '{"device-A": 1, "device-B": 1}',
          },
        );

        expect(
          result.shouldApplyRemote,
          isTrue,
          reason:
              'VC متطابق لكن المحتوى مختلف → البعيد أحدث (appwrite لم '
              'يزد الـ VC تلقائياً)',
        );
      },
    );

    test('32. VCs متساوية مع محتوى متطابق → shouldApplyRemote=false', () async {
      final localUuid = 'booking-008';

      final result = await pullService.checkAndResolveConflict(
        {
          'localUuid': localUuid,
          'status': 'confirmed',
          'lastModified': 2000,
          'vectorClock': '{"device-A": 1, "device-B": 1}',
        },
        2000,
        remoteUpdatedAtSec: 2000,
        localVectorClock: '{"device-A": 1, "device-B": 1}',
        entityName: 'bookings',
        localUuid: localUuid,
        localData: {
          'localUuid': localUuid,
          'status': 'confirmed', // ← متطابق
          'lastModified': 2000,
          'vectorClock': '{"device-A": 1, "device-B": 1}',
        },
      );

      expect(
        result.shouldApplyRemote,
        isFalse,
        reason: 'VC + محتوى متطابق → لا تحديث',
      );
    });
  });
}
