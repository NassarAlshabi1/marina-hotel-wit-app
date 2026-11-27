import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/hotel_day_key_fix_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/utils/hotel_time_engine.dart';

void main() {
  late AppDatabase db;
  late OutboxDao outbox;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outbox = OutboxDao(db);
  });
  tearDown(() async => db.close());

  Future<void> addPayment({required String uuid, required String? key}) async {
    await db
        .into(db.payments)
        .insert(
          PaymentsCompanion(
            localUuid: d.Value(uuid),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
            roomNumber: const d.Value('101'),
            amount: const d.Value(25),
            paymentDate: const d.Value('2026-06-10T14:00:00'),
            paymentMethod: const d.Value('cash'),
            revenueType: const d.Value('room'),
            hotelDayKey: d.Value(key),
          ),
        );
  }

  test(
    'repairs keys on records present after an initially empty local start',
    () async {
      final repair = HotelDayKeyFixService.instance;
      await repair.runIfNeeded(db); // startup before first pull: empty database
      await addPayment(uuid: 'null-key', key: null);
      await addPayment(uuid: 'empty-key', key: '');
      await addPayment(uuid: 'stale-key', key: '2026-06-08');

      await repair.runIfNeeded(
        db,
      ); // successful pull has populated legacy records
      final rows = await db.select(db.payments).get();
      final expected = HotelTimeEngine.getHotelDayKeyFromIso(
        '2026-06-10T14:00:00',
      );
      expect(rows.map((row) => row.hotelDayKey), everyElement(expected));
      expect(await outbox.countPendingPushable(), 3);

      await repair.runIfNeeded(
        db,
      ); // replay is a no-op, no duplicate Outbox entries
      expect(await outbox.countPendingPushable(), 3);
      expect(await (db.select(db.outbox)).get(), hasLength(3));
    },
  );

  test(
    'invalid/unknown date remains untouched rather than guessed as today',
    () async {
      await addPayment(uuid: 'unknown-date', key: null);
      await (db.update(
        db.payments,
      )).write(const PaymentsCompanion(paymentDate: d.Value('not-a-date')));
      await HotelDayKeyFixService.instance.runIfNeeded(db);
      expect((await db.select(db.payments).getSingle()).hotelDayKey, isNull);
      expect(await outbox.countPendingPushable(), 0);
    },
  );

  test(
    'explicit ISO offset is interpreted as an instant in the hotel zone',
    () {
      expect(
        HotelDayKeyFixService.computeCorrectHotelDayKey(
          '2024-03-02T15:00:00+03:00',
        ),
        '2024-03-02',
      );
    },
  );

  test(
    'an invalid date does not prevent valid rows from being repaired',
    () async {
      await addPayment(uuid: 'good-stale', key: '2026-06-08');
      await addPayment(uuid: 'bad-date', key: null);
      await (db.update(db.payments)
            ..where((row) => row.localUuid.equals('bad-date')))
          .write(const PaymentsCompanion(paymentDate: d.Value('not-a-date')));

      await HotelDayKeyFixService.instance.runIfNeeded(db);

      final rows = await db.select(db.payments).get();
      expect(
        rows.singleWhere((row) => row.localUuid == 'good-stale').hotelDayKey,
        '2026-06-09',
      );
      expect(
        rows.singleWhere((row) => row.localUuid == 'bad-date').hotelDayKey,
        isNull,
      );
      expect(await outbox.countPendingPushable(), 1);
    },
  );
}
