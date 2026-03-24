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

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    adapters = AdapterRegistry(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('payments adapter round-trip (drive)', () async {
    final json = {
      'local_uuid': 'p-1',
      'booking_uuid_cache': 'b-1',
      'server_payment_id': 7,
      'amount': 120.5,
      'payment_date': '2025-01-02T00:00:00Z',
      'payment_method': 'cash',
      'revenue_type': 'room',
      'last_modified': 111,
      'created_at': 100,
    };

    final refs = await adapters.payments.adapter.resolveRefs(
      db,
      json,
      src: Source.drive,
    );
    final comp = adapters.payments.adapter.fromJson(
      json,
      src: Source.drive,
      refs: refs,
    );
    await db.into(db.payments).insert(comp);

    final row = await db.select(db.payments).getSingle();
    final out = adapters.payments.toJsonForSource(row, src: Source.drive);

    expect(out['local_uuid'], 'p-1');
    expect(out['booking_uuid_cache'], 'b-1');
    expect(out['payment_method'], 'cash');
    expect(out['amount'], 120.5);
  });

  test('bookings adapter round-trip (appwrite)', () async {
    await db.into(db.rooms).insert(
          RoomsCompanion(
            localUuid: const d.Value('r-101'),
            roomNumber: const d.Value('101'),
            type: const d.Value('single'),
            price: const d.Value(100.0),
            status: const d.Value('available'),
            cleaningStatus: const d.Value('clean'),
            createdAt: const d.Value(0),
            updatedAt: const d.Value(0),
            lastModified: const d.Value(0),
            createdAtEpoch: const d.Value(0),
            lastModifiedEpoch: const d.Value(0),
            version: const d.Value(1),
            origin: const d.Value('local'),
            vectorClock: const d.Value('{}'),
          ),
        );

    final json = {
      'localUuid': 'b-2',
      'roomNumber': '101',
      'guestName': 'Ahmed',
      'guestPhone': '+966',
      'status': 'checked_in',
      'expectedNights': 2,
      'calculatedNights': 2,
      'createdAt': 10,
      'lastModified': 20,
    };

    final refs = await adapters.bookings.adapter.resolveRefs(
      db,
      json,
      src: Source.appwrite,
    );
    final comp = adapters.bookings.adapter.fromJson(
      json,
      src: Source.appwrite,
      refs: refs,
    );
    await db.into(db.bookings).insert(comp);

    final row = await db.select(db.bookings).getSingle();
    final out = adapters.bookings.toJsonForSource(row, src: Source.appwrite);

    expect(out['localUuid'], 'b-2');
    expect(out['roomNumber'], '101');
    expect(out['guestName'], 'Ahmed');
    expect(out['status'], 'checked_in');
    expect(out['expectedNights'], 2);
  });
}
