import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/delta_sync_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  late AppDatabase db;
  late DeltaSyncService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = DeltaSyncService(db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
      'compute produces insert/update/delete with mirror persistence and fallback',
      () async {
    // Seed bookings and mirror empty
    final booking = Booking(
      localUuid: 'b1',
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
    await db.into(db.bookings).insert(booking);

    final comp1 = await service.compute();
    // Mirror initially absent => fallback for bookings
    expect(comp1.fallbackTables.contains('bookings'), isTrue);
    expect(comp1.changes.where((c) => c.operation == 'insert').length, 1);
    await service.persistMirror(comp1);

    // Update booking -> should yield update
    final updated = booking.copyWith(updatedAt: 2000, lastModified: 2000);
    await db.into(db.bookings).insertOnConflictUpdate(updated);
    final comp2 = await service.compute(since: 1);
    expect(comp2.changes.where((c) => c.operation == 'update').length, 1);

    // Delete booking -> should yield delete when missing in snapshot
    await db.delete(db.bookings).go();
    final comp3 = await service.compute(since: 1);
    expect(comp3.changes.where((c) => c.operation == 'delete').length, 1);
  });

  test('validateMirror reports mismatch and repairMirror rebuilds', () async {
    // Build mirror with one booking
    final booking = Booking(
      localUuid: 'b2',
      serverId: null,
      createdAt: 10,
      updatedAt: 10,
      deletedAt: null,
      lastModified: 10,
      createdAtIso: null,
      updatedAtIso: null,
      deletedAtIso: null,
      createdAtEpoch: 10,
      lastModifiedEpoch: 10,
      version: 1,
      origin: 'app',
      id: 2,
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
    await db.into(db.bookings).insert(booking);
    final comp = await service.compute();
    await service.persistMirror(comp);

    // Corrupt mirror hash directly
    await db.customStatement(
      "UPDATE sync_mirror SET row_hash = 'bad' WHERE table_name = 'bookings'",
    );

    final validation = await service.validateMirror();
    expect(validation.isValid, isFalse);
    expect(validation.issues.any((i) => i.contains('hash mismatch')), isTrue);

    await service.repairMirrorIfNeeded();
    final post = await service.validateMirror();
    expect(post.isValid, isTrue);
  });

  test(
      '_preparePayload and hashing normalize keys/timestamps deterministically',
      () async {
    final payload = {
      'localUuid': 'x',
      'createdAt': 123,
      'child': {'createdAt': 5},
      'list': [
        {'createdAt': 7},
        9,
      ],
    };

    final prepared = _preparePayload(payload);
    expect(prepared.keys,
        containsAll(['local_uuid', 'created_at', 'child', 'list']));
    expect(prepared['created_at'], 123000);
    final hash1 = _hashPayload(prepared);
    final hash2 = _hashPayload(prepared);
    expect(hash1, hash2);
  });
}
