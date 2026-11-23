import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/daos/payments_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late PaymentsDao paymentsDao;

  setUp(() async {
    AppwriteSyncManager.updateStaticDeviceId(null);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AdapterRegistry.initialize(db);
    final outboxDao = OutboxDao(db, AdapterRegistry.testing(db));
    paymentsDao = PaymentsDao(db, outboxDao, AdapterRegistry.testing(db));
  });

  tearDown(() async {
    await db.close();
    AppwriteSyncManager.updateStaticDeviceId(null);
  });

  test(
    'insertOne يحفظ deviceId المسجل و UUID الدفع بالصيغة القياسية',
    () async {
      const paymentUuid = '621b28eb87dd429b9f12fe19c18f17df';
      const registeredDeviceId = 'registered-device-document-id';
      AppwriteSyncManager.updateStaticDeviceId(registeredDeviceId);

      await paymentsDao.insertOne(
        const PaymentsCompanion(
          localUuid: Value(paymentUuid),
          paymentDate: Value('2026-11-21T18:20:00.000Z'),
          paymentMethod: Value('cash'),
          amount: Value(25500),
          revenueType: Value('room'),
        ),
      );

      final saved = await paymentsDao.watchById(1).first;
      expect(saved, isNotNull);
      expect(saved!.deviceId, registeredDeviceId);
      expect(saved.localUuid, '621b28eb-87dd-429b-9f12-fe19c18f17df');
    },
  );

  test('immutable payment rejects ordinary update and soft delete', () async {
    await paymentsDao.insertOne(
      const PaymentsCompanion(
        localUuid: Value('immutable-payment'),
        paymentDate: Value('2026-11-21T18:20:00.000Z'),
        paymentMethod: Value('cash'),
        amount: Value(25500),
        revenueType: Value('room'),
        isImmutable: Value(true),
      ),
    );

    expect(
      await paymentsDao.updateById(
        1,
        const PaymentsCompanion(amount: Value(1)),
      ),
      0,
    );
    expect(await paymentsDao.softDelete(1), 0);

    final saved = await paymentsDao.watchById(1).first;
    expect(saved, isNotNull);
    expect(saved!.amount, 25500);
    expect(saved.isImmutable, isTrue);
    expect(saved.deletedAt, isNull);
  });

  test(
    'list وwatchList يدعمان المطابقة عبر bookingUuidCache وimportFromJson يحفظ أعلام الإلغاء والمناعة',
    () async {
      const bookingUuid = '12345678-1234-1234-1234-1234567890ab';
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              localUuid: 'room-dao-1',
              roomNumber: '101',
              type: 'single',
              price: 10000,
              status: 'شغور',
              createdAt: 1000,
              updatedAt: 1000,
              lastModified: 1000,
            ),
          );
      final bookingId = await db
          .into(db.bookings)
          .insert(
            BookingsCompanion.insert(
              localUuid: bookingUuid,
              roomNumber: '101',
              guestName: 'نزيل الاختبار',
              guestPhone: '777',
              guestNationality: 'يمني',
              checkinDate: '2026-11-20',
              status: 'نشط',
              createdAt: 1000,
              updatedAt: 1000,
              lastModified: 1000,
            ),
          );

      // إدراج دفعة مربوطة بـ bookingUuidCache بالصيغة المضغوطة فقط (bookingLocalId = null)
      await paymentsDao.insertOne(
        const PaymentsCompanion(
          localUuid: Value('pay-uuid-only'),
          bookingUuidCache: Value('123456781234123412341234567890ab'),
          paymentDate: Value('2026-11-21T18:20:00.000Z'),
          paymentMethod: Value('cash'),
          amount: Value(12000),
          revenueType: Value('room'),
          isVoided: Value(true),
          isImmutable: Value(true),
        ),
        originIsServer: true,
      );

      final listed = await paymentsDao.list(bookingLocalId: bookingId);
      expect(listed.length, 1);
      expect(listed.first.localUuid, 'pay-uuid-only');

      final watched = await paymentsDao
          .watchList(bookingLocalId: bookingId)
          .first;
      expect(watched.length, 1);

      final exported = await paymentsDao.exportToJson();
      await paymentsDao.importFromJson(exported, clearExisting: true);

      final reimported = await paymentsDao.list(bookingLocalId: bookingId);
      expect(reimported.length, 1);
      expect(reimported.first.isVoided, isTrue);
      expect(reimported.first.isImmutable, isTrue);
      expect(
        reimported.first.bookingUuidCache,
        '123456781234123412341234567890ab',
      );
    },
  );
}
