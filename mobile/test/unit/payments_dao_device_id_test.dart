import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    SharedPreferences.setMockInitialValues({});
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

  test('insertOne يحدد ويحفظ deviceId قبل حفظ الدفعة دون اتصال', () async {
    const paymentUuid = '621b28eb87dd429b9f12fe19c18f17df';
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
    expect(saved!.deviceId, isNotEmpty);
    expect(saved.localUuid, '621b28eb-87dd-429b-9f12-fe19c18f17df');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('appwrite_device_local_uuid'),
      saved.deviceId,
      reason: 'هوية الدفع نفسها يجب أن تُستخدم لاحقاً عند تسجيل الجهاز.',
    );
  });
}
