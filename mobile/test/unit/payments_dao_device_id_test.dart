// test/unit/payments_dao_device_id_test.dart
//
// ✅ يقابل إصلاح فرع guest-adjustment-edit-end (5b28254c):
// "fix(payments): ensure device ID and canonical UUID" — مكيَّفاً على
// مسار Cloudflare: هوية الجهاز تُوفَّر وتُخزَّن قبل أي كتابة محلية
// حتى لو حدثت قبل initialize، وUUID الدفعة يوحَّد بالشكل القياسي.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/daos/payments_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late PaymentsDao paymentsDao;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    CloudflareSyncManager.setStaticDeviceId(null);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AdapterRegistry.initialize(db);
    final outboxDao = OutboxDao(db, AdapterRegistry.testing(db));
    paymentsDao = PaymentsDao(db, outboxDao, AdapterRegistry.testing(db));
  });

  tearDown(() async {
    await db.close();
    CloudflareSyncManager.setStaticDeviceId(null);
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
      prefs.getString('cf_device_id'),
      saved.deviceId,
      reason: 'هوية الدفع نفسها يجب أن تُستخدم لاحقاً عند تسجيل الجهاز.',
    );
  });
}
