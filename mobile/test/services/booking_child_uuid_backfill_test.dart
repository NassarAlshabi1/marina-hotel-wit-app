import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/booking_child_uuid_backfill_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/utils/time.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int bookingId;
  final service = BookingChildUuidBackfillService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final now = Time.nowEpoch();
    await db
        .into(db.rooms)
        .insert(
          RoomsCompanion(
            localUuid: const d.Value('room-legacy-101'),
            roomNumber: const d.Value('101'),
            type: const d.Value('standard'),
            price: const d.Value(100),
            status: const d.Value('available'),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
          ),
        );
    bookingId = await db
        .into(db.bookings)
        .insert(
          BookingsCompanion(
            localUuid: const d.Value('booking-legacy-001'),
            roomNumber: const d.Value('101'),
            guestName: const d.Value('ضيف'),
            guestPhone: const d.Value('0500000000'),
            guestNationality: const d.Value('يمني'),
            checkinDate: const d.Value('2026-01-01T15:00:00'),
            checkoutDate: const d.Value('2026-01-03T12:00:00'),
            status: const d.Value('مكتمل'),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
          ),
        );
    for (final day in ['2026-01-01', '2026-01-02']) {
      await db
          .into(db.bookingNights)
          .insert(
            BookingNightsCompanion(
              localUuid: d.Value('night-$day'),
              createdAt: d.Value(now),
              updatedAt: d.Value(now),
              lastModified: d.Value(now),
              bookingLocalId: d.Value(bookingId),
              hotelDayKey: d.Value(day),
              nightStart: d.Value('${day}T14:01:00'),
              nightEnd: d.Value('${day}T23:59:00'),
            ),
          );
    }
    await db
        .into(db.bookingNotes)
        .insert(
          BookingNotesCompanion(
            localUuid: const d.Value('note-legacy-001'),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            bookingId: d.Value(bookingId),
            noteText: const d.Value('ملاحظة'),
            alertType: const d.Value('info'),
          ),
        );
  });

  tearDown(() => db.close());

  Future<List<OutboxData>> outboxFor(String entity) =>
      (db.select(db.outbox)..where((o) => o.entity.equals(entity))).get();

  test('يملأ UUID الحجز للّيالي القديمة ويضعها في طابور الرفع', () async {
    final lastModifiedBefore = (await db.select(db.bookingNights).get())
        .map((n) => n.lastModified)
        .toList();

    expect(await service.backfillNights(db), 2);

    final nights = await db.select(db.bookingNights).get();
    expect(
      nights.map((n) => n.bookingUuidCache),
      everyElement('booking-legacy-001'),
    );
    expect(nights.map((n) => n.lastModified).toList(), lastModifiedBefore);
    final queued = await outboxFor('booking_nights');
    expect(queued.map((o) => o.localUuid).toSet(), {
      'night-2026-01-01',
      'night-2026-01-02',
    });

    expect(await service.backfillNights(db), 0);
    expect(await outboxFor('booking_nights'), hasLength(2));
  });

  test('يعيد رفع الملاحظات مرة واحدة فقط', () async {
    expect(await service.repushNotesOnce(db), 1);
    final queued = await outboxFor('booking_notes');
    expect(queued.single.localUuid, 'note-legacy-001');
    expect(queued.single.op, 'update');

    expect(await service.repushNotesOnce(db), 0);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(BookingChildUuidBackfillService.notesRepushPrefKey),
      isTrue,
    );
  });
}
