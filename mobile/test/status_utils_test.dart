import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/utils/status_utils.dart';

void main() {
  test('room availability detection is case/whitespace insensitive', () {
    expect(StatusUtils.isRoomAvailable('  Available '), isTrue);
    expect(StatusUtils.isRoomAvailable('مشغولة'), isFalse);
    expect(StatusUtils.isRoomOccupied('occupied'), isTrue);
    expect(StatusUtils.isRoomOccupied(' شاغرة '), isFalse);
  });

  test('active booking detection covers arabic/english variants', () {
    expect(StatusUtils.isActiveBooking('active'), isTrue);
    expect(StatusUtils.isActiveBooking('نشط'), isTrue);
    expect(StatusUtils.isActiveBooking('cancelled'), isFalse);
  });

  test('roomStatusForOccupancy returns proper fallback', () {
    expect(StatusUtils.roomStatusForOccupancy(true), 'محجوزة');
    expect(StatusUtils.roomStatusForOccupancy(false), 'شاغرة');
    expect(
      StatusUtils.roomStatusForOccupancy(true, fallbackOccupied: 'X'),
      'X',
    );
  });

  test('isBookingActive reads from booking model', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await database
        .into(database.rooms)
        .insert(
          RoomsCompanion.insert(
            localUuid: 'room-uuid',
            createdAt: 1,
            updatedAt: 1,
            lastModified: 1,
            roomNumber: '101',
            type: 'std',
            price: 100,
            status: 'available',
          ),
        );

    final bookingId = await database
        .into(database.bookings)
        .insert(
          BookingsCompanion.insert(
            localUuid: 'booking-uuid',
            createdAt: 1,
            updatedAt: 1,
            lastModified: 1,
            roomNumber: '101',
            guestName: 'guest',
            guestPhone: '123',
            guestNationality: 'nat',
            checkinDate: '2024-01-01',
            status: 'active',
          ),
        );

    final booking = await (database.select(
      database.bookings,
    )..where((tbl) => tbl.id.equals(bookingId))).getSingle();

    expect(StatusUtils.isBookingActive(booking), isTrue);
  });
}
