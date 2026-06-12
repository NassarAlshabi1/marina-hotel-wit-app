import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/id_resolver.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late IdResolver resolver;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    resolver = IdResolver(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('IdResolver.resolveBooking', () {
    test('returns id when booking exists locally by UUID', () async {
      await db.into(db.bookings).insert(BookingsCompanion(
        localUuid: const d.Value('booking-uuid-1'),
        roomNumber: const d.Value('101'),
        guestName: const d.Value('أحمد'),
        guestPhone: const d.Value('0500000000'),
        guestNationality: const d.Value('يمني'),
        checkinDate: const d.Value('2025-06-01'),
        status: const d.Value('checked_in'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      final id = await resolver.resolveBooking(uuid: 'booking-uuid-1');
      expect(id, isNotNull);
      expect(id, greaterThan(0));
    });

    test('returns id when booking exists by serverId', () async {
      await db.into(db.bookings).insert(BookingsCompanion(
        localUuid: const d.Value('booking-uuid-2'),
        serverBookingId: const d.Value(42),
        roomNumber: const d.Value('102'),
        guestName: const d.Value('محمد'),
        guestPhone: const d.Value('0500000001'),
        guestNationality: const d.Value('مصري'),
        checkinDate: const d.Value('2025-06-01'),
        status: const d.Value('checked_in'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      final id = await resolver.resolveBooking(serverId: 42);
      expect(id, isNotNull);
    });

    test('returns id when booking exists by localId', () async {
      final insertedId = await db.into(db.bookings).insert(BookingsCompanion(
        localUuid: const d.Value('booking-uuid-3'),
        roomNumber: const d.Value('103'),
        guestName: const d.Value('علي'),
        guestPhone: const d.Value('0500000002'),
        guestNationality: const d.Value('سعودي'),
        checkinDate: const d.Value('2025-06-01'),
        status: const d.Value('checked_in'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      final id = await resolver.resolveBooking(localId: insertedId);
      expect(id, equals(insertedId));
    });

    test('UUID takes priority over serverId and localId', () async {
      await db.into(db.bookings).insert(BookingsCompanion(
        localUuid: const d.Value('uuid-priority'),
        serverBookingId: const d.Value(100),
        roomNumber: const d.Value('104'),
        guestName: const d.Value('خالد'),
        guestPhone: const d.Value('0500000003'),
        guestNationality: const d.Value('عماني'),
        checkinDate: const d.Value('2025-06-01'),
        status: const d.Value('checked_in'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      // استخدام uuid فقط — يجب أن يجد الحجز
      final id = await resolver.resolveBooking(uuid: 'uuid-priority');
      expect(id, isNotNull);
    });

    test('returns null when booking does not exist', () async {
      final id = await resolver.resolveBooking(uuid: 'nonexistent-uuid');
      expect(id, isNull);

      final id2 = await resolver.resolveBooking(serverId: 99999);
      expect(id2, isNull);

      final id3 = await resolver.resolveBooking(localId: 99999);
      expect(id3, isNull);
    });
  });

  group('IdResolver.resolveEmployee', () {
    test('returns id when employee exists locally by UUID', () async {
      await db.into(db.employees).insert(EmployeesCompanion(
        localUuid: const d.Value('emp-uuid-1'),
        name: const d.Value('أحمد موظف'),
        phone: const d.Value('0500000010'),
        jobTitle: const d.Value('موظف استقبال'),
        salary: const d.Value(3000.0),
        status: const d.Value('active'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      final id = await resolver.resolveEmployee(uuid: 'emp-uuid-1');
      expect(id, isNotNull);
      expect(id, greaterThan(0));
    });

    test('returns id when employee exists by localId', () async {
      final insertedId = await db.into(db.employees).insert(EmployeesCompanion(
        localUuid: const d.Value('emp-uuid-2'),
        name: const d.Value('محمد موظف'),
        phone: const d.Value('0500000011'),
        jobTitle: const d.Value('مدير'),
        salary: const d.Value(5000.0),
        status: const d.Value('active'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      final id = await resolver.resolveEmployee(localId: insertedId);
      expect(id, equals(insertedId));
    });

    test('returns id when employee exists by serverId', () async {
      await db.into(db.employees).insert(EmployeesCompanion(
        localUuid: const d.Value('emp-uuid-3'),
        serverId: const d.Value(77),
        name: const d.Value('علي موظف'),
        phone: const d.Value('0500000012'),
        jobTitle: const d.Value('موظف صيانة'),
        salary: const d.Value(2500.0),
        status: const d.Value('active'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      final id = await resolver.resolveEmployee(serverId: 77);
      expect(id, isNotNull);
    });

    test('returns null when employee does not exist', () async {
      final id = await resolver.resolveEmployee(uuid: 'nonexistent-emp');
      expect(id, isNull);
    });
  });

  group('IdResolver.resolveSalaryCycle', () {
    test('returns id when cycle exists locally by UUID', () async {
      // نحتاج employee أولاً
      final empId = await db.into(db.employees).insert(EmployeesCompanion(
        localUuid: const d.Value('emp-for-cycle'),
        name: const d.Value('موظف دورة'),
        phone: const d.Value('0500000020'),
        jobTitle: const d.Value('موظف'),
        salary: const d.Value(3000.0),
        status: const d.Value('active'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      await db.into(db.salaryCycles).insert(SalaryCyclesCompanion(
        localUuid: const d.Value('cycle-uuid-1'),
        employeeId: d.Value(empId),
        cycleStartDate: const d.Value('2025-06-01'),
        cycleEndDate: const d.Value('2025-06-30'),
        totalSalary: const d.Value(3000.0),
        status: const d.Value('open'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      final id = await resolver.resolveSalaryCycle(uuid: 'cycle-uuid-1');
      expect(id, isNotNull);
      expect(id, greaterThan(0));
    });

    test('returns null when cycle does not exist', () async {
      final id = await resolver.resolveSalaryCycle(uuid: 'nonexistent-cycle');
      expect(id, isNull);
    });
  });
}
