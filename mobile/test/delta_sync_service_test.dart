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

  Booking _booking({required String uuid, required int created, required int id}) {
    return Booking(
      localUuid: uuid,
      serverId: null,
      createdAt: created,
      updatedAt: created,
      deletedAt: null,
      lastModified: created,
      createdAtIso: null,
      updatedAtIso: null,
      deletedAtIso: null,
      createdAtEpoch: created,
      lastModifiedEpoch: created,
      version: 1,
      origin: 'app',
      id: id,
      serverBookingId: null,
      roomNumber: '101',
      guestName: 'guest',
      guestPhone: '123',
      guestIdType: 'id',
      guestIdNumber: '123',
      guestIdIssueDate: null,
      guestIdIssuePlace: null,
      guestNationality: 'nat',
      guestEmail: null,
      guestAddress: null,
      checkinDate: '2024-01-01',
      checkoutDate: '2024-01-02',
      actualCheckout: null,
      status: 'active',
      notes: null,
      expectedNights: 1,
      calculatedNights: 1,
      totalNightsCached: 1,
      stayDurationIso: null,
      lastNightEpoch: null,
      isOverdue: false,
      needsCheckoutReview: false,
      totalDueCached: 0,
      totalPaidCached: 0,
      remainingBalanceCached: 0,
      isFullyPaid: true,
      hotelDayCheckin: null,
      hotelDayCheckout: null,
    );
  }

  test('compute produces insert/update/delete with mirror persistence and fallback', () async {
    final booking = _booking(uuid: 'b1', created: 1, id: 1);
    await db.into(db.bookings).insert(booking);

    final comp1 = await service.compute();
    expect(comp1.fallbackTables.contains('bookings'), isTrue);
    expect(comp1.changes.where((c) => c.operation == 'insert').length, 1);
    await service.persistMirror(comp1);

    final updated = _booking(uuid: 'b1', created: 2000, id: 1);
    await db.into(db.bookings).insertOnConflictUpdate(updated);
    final comp2 = await service.compute(since: 1);
    expect(comp2.changes.where((c) => c.operation == 'update').length, 1);

    await db.delete(db.bookings).go();
    final comp3 = await service.compute(since: 1);
    expect(comp3.changes.where((c) => c.operation == 'delete').length, 1);
  });

  test('validateMirror reports mismatch and repairMirror rebuilds', () async {
    final booking = _booking(uuid: 'b2', created: 10, id: 2);
    await db.into(db.bookings).insert(booking);
    final comp = await service.compute();
    await service.persistMirror(comp);

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
}
