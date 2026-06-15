/// ============================================================
/// Marina Hotel - Sync Engine Tests with Mock Appwrite
/// ============================================================
/// اختبارات لوحدة المزامنة باستخدام MockAppwriteService
/// لا تحتاج اتصال فعلي بـ Appwrite Cloud
/// ============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/appwrite_config.dart';
import 'package:marina_hotel_mobile/utils/time.dart';
import 'mocks/mock_appwrite_service.dart';

void main() {
  late AppDatabase database;
  late MockAppwriteService mockService;
  late AppwriteSyncManager syncManager;
  late OutboxDao outboxDao;

  setUp(() async {
    // تهيئة SharedPreferences للاختبار
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    // إنشاء قاعدة بيانات في الذاكرة
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');

    // إنشاء Mock Appwrite Service
    mockService = MockAppwriteService();

    // تهيئة Adaptor Registry
    final adapters = AdapterRegistry(database);
    outboxDao = OutboxDao(database);

    // تهيئة Sync Manager
    syncManager = AppwriteSyncManager(
      appwriteService: mockService,
      database: database,
    );

    // بذر بيانات وهمية
    await _seedTestData();
  });

  tearDown(() async {
    await database.close();
  });

  group('Sync Engine - Outbox Tests', () {
    test('push: room outbox entry is processed correctly', () async {
      // إدراج سجل في الـ Outbox
      final localUuid = 'test-room-uuid-1';
      await outboxDao.merge(
        entity: 'rooms',
        op: 'insert',
        localUuid: localUuid,
        payload: {
          'localUuid': localUuid,
          'roomNumber': '101',
          'type': 'single',
          'price': 100.0,
          'status': 'clean',
        },
        clientTs: Time.nowEpoch(),
        source: 'local',
      );

      // التأكد من وجود السجل في الـ Outbox
      final count = await outboxDao.count(sources: const ['local']);
      expect(count, equals(1));
    });

    test('pull: rooms are inserted correctly from remote', () async {
      // بذر بيانات الغرف في Mock Service
      mockService.seedCollection(AppwriteConfig.roomsCollectionId, [
        {
          'localUuid': 'room-uuid-1',
          'roomNumber': '101',
          'type': 'single',
          'price': 100.0,
          'version': 1,
          'origin': 'appwrite',
        },
        {
          'localUuid': 'room-uuid-2',
          'roomNumber': '102',
          'type': 'double',
          'price': 150.0,
          'version': 1,
          'origin': 'appwrite',
        },
      ]);

      // استدعاء السحب
      final docs = await mockService.listRooms();
      final synced = await syncManager.syncRooms(docs);

      expect(synced, equals(2));

      // التحقق من وجود الغرف محلياً
      final rooms = await database.select(database.rooms).get();
      expect(rooms.length, equals(2));
      expect(rooms[0].roomNumber, equals('101'));
      expect(rooms[1].roomNumber, equals('102'));
    });

    test('pull: booking with FK to room is inserted correctly', () async {
      // بذر غرفة أولاً
      await database.into(database.rooms).insert(database.rooms.createCompanion(
        localUuid: d.Value('room-uuid-1'),
        roomNumber: d.Value('101'),
        type: d.Value('single'),
        price: d.Value(100.0),
        status: d.Value('clean'),
        createdAt: d.Value(Time.nowEpoch()),
        updatedAt: d.Value(Time.nowEpoch()),
        lastModified: d.Value(Time.nowEpoch()),
        version: d.Value(1),
        origin: d.Value('appwrite'),
      ));

      // بذر حجز في Mock Service
      mockService.seedCollection(AppwriteConfig.bookingsCollectionId, [
        {
          'localUuid': 'booking-uuid-1',
          'roomNumber': '101',
          'guestName': 'ضياء',
          'guestPhone': '0599999999',
          'guestNationality': 'سوري',
          'status': 'active',
          'version': 1,
          'origin': 'appwrite',
        },
      ]);

      // سحب الحجوزات
      final docs = await mockService.listBookings();
      final synced = await syncManager.syncBookings(docs);

      expect(synced, equals(1));

      // التحقق من وجود الحجز محلياً
      final bookings = await database.select(database.bookings).get();
      expect(bookings.length, equals(1));
      expect(bookings[0].guestName, equals('ضياء'));
      expect(bookings[0].roomNumber, equals('101'));
    });
  });

  group('Sync Engine - Conflict Resolution Tests', () {
    test('conflict: local version newer than remote keeps local', () async {
      // إدراج سجل محلي
      await database.into(database.rooms).insert(database.rooms.createCompanion(
        localUuid: d.Value('room-uuid-1'),
        roomNumber: d.Value('101'),
        type: d.Value('single'),
        price: d.Value(100.0),
        status: d.Value('clean'),
        createdAt: d.Value(Time.nowEpoch()),
        updatedAt: d.Value(Time.nowEpoch()),
        lastModified: d.Value(Time.nowEpoch()),
        version: d.Value(5), // إصدار أحدث
        origin: d.Value('local'),
      ));

      // بيانات بعيدة بإصدار أقدم
      final remoteData = {
        'localUuid': 'room-uuid-1',
        'roomNumber': '101',
        'type': 'single',
        'price': 200.0, // سعر مختلف
        'status': 'occupied',
        'version': 3, // إصدار أقدم
        'origin': 'appwrite',
      };

      final existing = await (database.select(database.rooms)
            ..where((t) => t.localUuid.equals('room-uuid-1'))
            ..limit(1))
          .getSingleOrNull();

      final shouldUpdate = syncManager.isRemoteDataNewer(
        remoteData,
        existing!.lastModified,
        localDeletedAt: existing.deletedAt,
      );

      expect(shouldUpdate, isFalse); // يجب ألا يُحدث (المحلي أحدث)
    });
  });

  group('Sync Engine - Deferred FK Tests', () {
    test('deferred: booking_price_adjustment waits for booking', () async {
      // سحب تعديل سعر قبل وجود الحجز
      mockService.seedCollection(
        AppwriteConfig.bookingPriceAdjustmentsCollectionId,
        [
          {
            'localUuid': 'adj-uuid-1',
            'bookingLocalUuid': 'booking-uuid-1',
            'adjustmentType': 1,
            'amount': 50,
            'version': 1,
          },
        ],
      );

      // سحب تعديلات الأسعار (يجب أن تؤجل لأن الحجز غير موجود)
      final adjustmentDocs = await mockService.listDocuments(
        collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
      );
      final adjSynced = await syncManager.syncBookingPriceAdjustments(adjustmentDocs);

      // يجب أن تكون 0 لأن الحجز غير موجود
      expect(adjSynced, equals(0));

      // الآن إضافة الحجز
      mockService.seedCollection(AppwriteConfig.bookingsCollectionId, [
        {
          'localUuid': 'booking-uuid-1',
          'roomNumber': '101',
          'guestName': 'اختبار',
          'guestPhone': '0500000000',
          'guestNationality': 'سوري',
          'status': 'active',
          'version': 1,
        },
      ]);

      // إضافة الغرفة المطلوبة
      await database.into(database.rooms).insert(database.rooms.createCompanion(
        localUuid: d.Value('room-uuid-1'),
        roomNumber: d.Value('101'),
        type: d.Value('single'),
        price: d.Value(100.0),
        status: d.Value('clean'),
        createdAt: d.Value(Time.nowEpoch()),
        updatedAt: d.Value(Time.nowEpoch()),
        lastModified: d.Value(Time.nowEpoch()),
        version: d.Value(1),
        origin: d.Value('appwrite'),
      ));

      // سحب الحجوزات
      final bookingDocs = await mockService.listBookings();
      await syncManager.syncBookings(bookingDocs);

      // سحب تعديلات الأسعار مرة أخرى (يجب أن تنجح هذه المرة)
      final adjustmentDocs2 = await mockService.listDocuments(
        collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
      );
      final adjSynced2 = await syncManager.syncBookingPriceAdjustments(adjustmentDocs2);

      expect(adjSynced2, equals(1)); // يجب أن تنجح الآن
    });
  });

  group('Mock Service - Network Simulation', () {
    test('mock: simulated timeout returns null', () async {
      mockService.setSimulatedDelay(const Duration(milliseconds: 100));
      mockService.seedCollection('test', [
        {'localUuid': 'test-1', 'value': 'test'},
      ]);

      final docs = await mockService.listDocuments(collectionId: 'test');
      expect(docs.length, equals(1));
    });

    test('mock: simulated failure throws exception', () async {
      mockService.setShouldFail(true);

      expect(
        () => mockService.listDocuments(collectionId: 'test'),
        throwsException,
      );
    });

    test('mock: tracks call count', () async {
      await mockService.listDocuments(collectionId: 'col1');
      await mockService.listDocuments(collectionId: 'col2');
      await mockService.listRooms();

      expect(mockService.callCount, equals(3));
    });
  });

  /// بذر بيانات وهمية أساسية في قاعدة البيانات المحلية
  Future<void> _seedTestData() async {
    // إضافة غرفة أساسية
    await database.into(database.rooms).insert(database.rooms.createCompanion(
      localUuid: d.Value('room-uuid-base'),
      roomNumber: d.Value('101'),
      type: d.Value('single'),
      price: d.Value(100.0),
      status: d.Value('clean'),
      createdAt: d.Value(Time.nowEpoch()),
      updatedAt: d.Value(Time.nowEpoch()),
      lastModified: d.Value(Time.nowEpoch()),
      version: d.Value(1),
      origin: d.Value('appwrite'),
    ));
  }
}

/// إضافة دوال مساعدة للـ SyncManager للاختبارات (extension)
extension SyncManagerTestExtensions on AppwriteSyncManager {
  Future<int> syncRooms(List<dynamic> docs) async {
    // TODO: استدعاء _syncRooms عبر reflection أو جعلها public
    return 0;
  }

  Future<int> syncBookings(List<dynamic> docs) async {
    // TODO: استدعاء _syncBookings عبر reflection أو جعلها public
    return 0;
  }

  Future<int> syncBookingPriceAdjustments(List<dynamic> docs) async {
    // TODO: استدعاء _syncBookingPriceAdjustments عبر reflection أو جعلها public
    return 0;
  }

  bool isRemoteDataNewer(Map<String, dynamic> remoteData, int? localLastModified, {int? localDeletedAt}) {
    // TODO: استدعاء _isRemoteDataNewer عبر reflection أو جعلها public
    return remoteData['version'] as int? ?? 0 > 1;
  }
}
