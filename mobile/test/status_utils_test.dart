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
        StatusUtils.roomStatusForOccupancy(true, fallbackOccupied: 'X'), 'X');
  });

  test('isBookingActive reads from booking model', () {
    final booking = Booking(
      localUuid: 'u',
      serverId: null,
      createdAt: 1,
      updatedAt: 1,
      deletedAt: null,
      lastModified: 1,
      createdAtIso: null,
      updatedAtIso: null,
      deletedAtIso: null,
      createdAtEpoch: 1,
      lastModifiedEpoch: 1,
      version: 1,
      origin: 'app',
      id: 1,
      roomId: 1,
      customerName: 'c',
      customerPhone: 'p',
      checkin: '2024-01-01',
      checkout: '2024-01-02',
      nights: 1,
      totalAmount: 0,
      paidAmount: 0,
      remainingAmount: 0,
      status: 'active',
      createdBy: 'u',
      updatedBy: 'u',
      source: 'app',
      roomType: 'std',
      roomName: '101',
      adultCount: 1,
      childCount: 0,
      city: null,
      notes: null,
      currency: 'usd',
      pricePerNight: 0,
      hotelDay: '2024-01-01',
      bookingTime: '2024-01-01T00:00:00Z',
      roomFloor: null,
      discount: 0,
      email: null,
      nationalId: null,
      country: null,
      checkoutReason: null,
      channel: null,
      stayPurpose: null,
      hasCar: 0,
      carPlate: null,
      carType: null,
      carColor: null,
      preference: null,
      deviceId: null,
      cancellationReason: null,
    );

    expect(StatusUtils.isBookingActive(booking), isTrue);
  });
}
