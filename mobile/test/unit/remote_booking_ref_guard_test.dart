// السجلات التابعة القادمة من Appwrite/Drive لا تُربط بحجز عبر رقمه المحلي
// (رقم جهاز آخر) — تُحل بـ UUID فقط، وإلا تُؤجَّل/تُتخطّى.
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AdapterRegistry adapters;
  late int localBookingId;
  const bookingUuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0001';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    adapters = AdapterRegistry(db);
    await db
        .into(db.rooms)
        .insert(
          RoomsCompanion.insert(
            localUuid: 'room-1',
            roomNumber: '101',
            type: 'standard',
            price: 100.0,
            status: 'available',
            createdAt: 0,
            updatedAt: 0,
            lastModified: 0,
          ),
        );
    localBookingId = await db
        .into(db.bookings)
        .insert(
          BookingsCompanion.insert(
            localUuid: bookingUuid,
            guestPhone: '',
            guestNationality: '',
            roomNumber: '101',
            guestName: 'Test',
            checkinDate: '2026-08-01',
            checkoutDate: const d.Value('2026-08-05'),
            status: 'checked_in',
            createdAt: 0,
            updatedAt: 0,
            lastModified: 0,
          ),
        );
  });

  tearDown(() async => db.close());

  group('booking_nights', () {
    test('appwrite بلا UUID ورقم محلي مطابق → تخطٍّ لا ربط', () async {
      final refs = await adapters.nights.adapter.resolveRefs(db, {
        'bookingLocalId': localBookingId,
        'hotelDayKey': '2026-08-01',
      }, src: Source.appwrite);
      expect(refs.shouldSkip, isTrue);
      expect(refs.bookingLocalId, isNull);
    });

    test('appwrite مع UUID → يُحل', () async {
      final refs = await adapters.nights.adapter.resolveRefs(db, {
        'bookingLocalId': 999,
        'bookingUuidCache': bookingUuid,
      }, src: Source.appwrite);
      expect(refs.shouldSkip, isFalse);
      expect(refs.bookingLocalId, localBookingId);
    });
  });

  test('debts: appwrite برقم محلي فقط → لا ربط', () async {
    final refs = await adapters.debts.adapter.resolveRefs(db, {
      'bookingLocalId': localBookingId,
    }, src: Source.appwrite);
    expect(refs.bookingLocalId, isNull);
  });

  test('booking_price_adjustments: appwrite برقم محلي فقط → تخطٍّ', () async {
    final refs = await adapters.bookingPriceAdjustments.adapter.resolveRefs(
      db,
      {'bookingLocalId': localBookingId},
      src: Source.appwrite,
    );
    expect(refs.shouldSkip, isTrue);
    expect(refs.bookingLocalId, isNull);
  });

  group('booking_notes', () {
    test('appwrite برقم محلي فقط → تخطٍّ ولا يُدرج', () async {
      final json = {
        'localUuid': 'note-1',
        'bookingId': localBookingId,
        'noteText': 'x',
        'createdAt': 1,
        'lastModified': 1,
      };
      final refs = await adapters.bookingNotes.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );
      expect(refs.shouldSkip, isTrue);
      expect(
        await adapters.bookingNotes.upsertFromJson(json, src: Source.appwrite),
        -1,
      );
      expect(await db.select(db.bookingNotes).get(), isEmpty);
    });

    test('appwrite مع UUID → يُحل', () async {
      final refs = await adapters.bookingNotes.adapter.resolveRefs(db, {
        'bookingId': 999,
        'bookingUuidCache': bookingUuid,
      }, src: Source.appwrite);
      expect(refs.shouldSkip, isFalse);
      expect(refs.bookingLocalId, localBookingId);
    });
  });
}
