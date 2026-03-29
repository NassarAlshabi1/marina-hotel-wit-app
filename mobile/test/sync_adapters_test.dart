import 'dart:convert';
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:uuid/uuid.dart';

/// Local-only Sync Adapter Tests
/// Tests the JSON <-> Model conversion for all tables without network calls

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AdapterRegistry adapters;

  setUpAll(() async {
    // Initialize local database
    db = AppDatabase.forTesting(NativeDatabase.memory());
    adapters = AdapterRegistry(db);
    print('Database initialized for testing');
  });

  tearDownAll(() async {
    await db.close();
    print('Database closed');
  });

  // ===========================================================================
  // Helper Functions
  // ===========================================================================

  String generateTestUuid() {
    return const Uuid().v4();
  }

  int currentEpoch() {
    return DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  Map<String, dynamic> createVectorClock(String deviceId, int counter) {
    return {deviceId: counter};
  }

  // ===========================================================================
  // Rooms Tests
  // ===========================================================================

  group('Rooms Adapter Tests', () {
    test('Create room and verify local storage', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final roomData = {
        'localUuid': uuid,
        'roomNumber': 'TEST-${now % 10000}',
        'type': 'single',
        'price': 150.0,
        'status': 'available',
        'cleaningStatus': 'clean',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
        'origin': 'test',
        'vectorClock': createVectorClock('test-device', 1),
      };

      // Insert into local database
      final refs = await adapters.rooms.adapter.resolveRefs(
        db,
        roomData,
        src: Source.appwrite,
      );
      final companion = adapters.rooms.adapter.fromJson(
        roomData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.rooms).insert(companion);

      // Verify local insertion
      final localRoom = await (db.select(
        db.rooms,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      expect(localRoom, isNotNull);
      expect(localRoom.roomNumber, equals(roomData['roomNumber']));
      expect(localRoom.price, equals(150.0));

      print('✓ Room created: ${localRoom.roomNumber}');
    });

    test('Room round-trip conversion preserves all fields', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final originalData = {
        'localUuid': uuid,
        'roomNumber': 'RT-${now % 10000}',
        'type': 'double',
        'price': 200.0,
        'status': 'available',
        'cleaningStatus': 'dirty',
        'requiresMaintenance': true,
        'lastCleanedHotelDay': '2025-01-15',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
        'origin': 'test',
        'vectorClock': {'device1': 1, 'device2': 2},
      };

      // Convert to local model
      final refs = await adapters.rooms.adapter.resolveRefs(
        db,
        originalData,
        src: Source.appwrite,
      );
      final companion = adapters.rooms.adapter.fromJson(
        originalData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.rooms).insert(companion);

      // Convert back to JSON
      final row = await (db.select(
        db.rooms,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      final exportedData = adapters.rooms.toJsonForSource(
        row,
        src: Source.appwrite,
      );

      // Verify critical fields
      expect(exportedData['localUuid'], equals(uuid));
      expect(exportedData['roomNumber'], equals(originalData['roomNumber']));
      expect(exportedData['type'], equals(originalData['type']));
      expect(exportedData['price'], equals(originalData['price']));
      expect(exportedData['cleaningStatus'], equals('dirty'));
      expect(exportedData['requiresMaintenance'], isTrue);
      expect(exportedData['vectorClock'], isNotNull);

      print('✓ Room round-trip successful');
    });
  });

  // ===========================================================================
  // Bookings Tests
  // ===========================================================================

  group('Bookings Adapter Tests', () {
    test('Create booking with all fields', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      // Create room first
      final roomData = {
        'localUuid': 'room-$uuid',
        'roomNumber': 'BOOK-TEST',
        'type': 'single',
        'price': 100.0,
        'status': 'available',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
      };

      final roomRefs = await adapters.rooms.adapter.resolveRefs(
        db,
        roomData,
        src: Source.appwrite,
      );
      await db
          .into(db.rooms)
          .insert(
            adapters.rooms.adapter.fromJson(
              roomData,
              src: Source.appwrite,
              refs: roomRefs,
            ),
          );

      final bookingData = {
        'localUuid': uuid,
        'roomNumber': 'BOOK-TEST',
        'guestName': 'Test Guest محمد',
        'guestPhone': '+966500000000',
        'guestIdType': 'بطاقة شخصية',
        'guestIdNumber': '1234567890',
        'guestNationality': 'Saudi',
        'checkinDate': DateTime.now().toIso8601String(),
        'status': 'checked_in',
        'expectedNights': 3,
        'calculatedNights': 3,
        'discount': 10.0,
        'discountType': 'per_night',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
        'origin': 'test',
      };

      final refs = await adapters.bookings.adapter.resolveRefs(
        db,
        bookingData,
        src: Source.appwrite,
      );
      final companion = adapters.bookings.adapter.fromJson(
        bookingData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.bookings).insert(companion);

      final localBooking = await (db.select(
        db.bookings,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      expect(localBooking, isNotNull);
      expect(localBooking.guestName, equals('Test Guest محمد'));
      expect(localBooking.guestIdType, equals('بطاقة شخصية'));
      expect(localBooking.expectedNights, equals(3));

      print('✓ Booking created: ${localBooking.guestName}');
    });

    test('Booking round-trip preserves Arabic text', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      // Create room first
      final roomData = {
        'localUuid': 'room-ar-$uuid',
        'roomNumber': 'AR-TEST',
        'type': 'single',
        'price': 100.0,
        'status': 'available',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
      };

      final roomRefs = await adapters.rooms.adapter.resolveRefs(
        db,
        roomData,
        src: Source.appwrite,
      );
      await db
          .into(db.rooms)
          .insert(
            adapters.rooms.adapter.fromJson(
              roomData,
              src: Source.appwrite,
              refs: roomRefs,
            ),
          );

      final originalData = {
        'localUuid': uuid,
        'roomNumber': 'AR-TEST',
        'guestName': 'أحمد محمد العلي',
        'guestPhone': '+966511111111',
        'guestIdType': 'إقامة',
        'guestIdNumber': '9876543210',
        'guestNationality': 'مصري',
        'checkinDate': DateTime.now().toIso8601String(),
        'status': 'checked_in',
        'expectedNights': 5,
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
      };

      final refs = await adapters.bookings.adapter.resolveRefs(
        db,
        originalData,
        src: Source.appwrite,
      );
      final companion = adapters.bookings.adapter.fromJson(
        originalData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.bookings).insert(companion);

      final row = await (db.select(
        db.bookings,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      final exportedData = adapters.bookings.toJsonForSource(
        row,
        src: Source.appwrite,
      );

      expect(exportedData['guestName'], equals('أحمد محمد العلي'));
      expect(exportedData['guestIdType'], equals('إقامة'));
      expect(exportedData['guestNationality'], equals('مصري'));

      print('✓ Arabic text preserved in round-trip');
    });
  });

  // ===========================================================================
  // Payments Tests
  // ===========================================================================

  group('Payments Adapter Tests', () {
    test('Create payment and verify amount', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final paymentData = {
        'localUuid': uuid,
        'amount': 1500.50,
        'paymentDate': DateTime.now().toIso8601String(),
        'paymentMethod': 'cash',
        'revenueType': 'room',
        'notes': 'دفع نقدية',
        'hotelDayKey': '2025-01-15',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
        'origin': 'test',
      };

      final refs = await adapters.payments.adapter.resolveRefs(
        db,
        paymentData,
        src: Source.appwrite,
      );
      final companion = adapters.payments.adapter.fromJson(
        paymentData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.payments).insert(companion);

      final localPayment = await (db.select(
        db.payments,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      expect(localPayment, isNotNull);
      expect(localPayment.amount, equals(1500.50));
      expect(localPayment.paymentMethod, equals('cash'));

      print('✓ Payment created: ${localPayment.amount}');
    });

    test('Payment round-trip with all fields', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final originalData = {
        'localUuid': uuid,
        'amount': 750.75,
        'paymentDate': '2025-01-15T14:30:00Z',
        'paymentMethod': 'card',
        'revenueType': 'room',
        'notes': 'Test payment',
        'hotelDayKey': '2025-01-15',
        'isPendingBalance': true,
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
      };

      final refs = await adapters.payments.adapter.resolveRefs(
        db,
        originalData,
        src: Source.appwrite,
      );
      final companion = adapters.payments.adapter.fromJson(
        originalData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.payments).insert(companion);

      final row = await (db.select(
        db.payments,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      final exportedData = adapters.payments.toJsonForSource(
        row,
        src: Source.appwrite,
      );

      expect(exportedData['amount'], equals(750.75));
      expect(exportedData['paymentMethod'], equals('card'));
      expect(exportedData['hotelDayKey'], equals('2025-01-15'));

      print('✓ Payment round-trip successful');
    });
  });

  // ===========================================================================
  // Expenses Tests
  // ===========================================================================

  group('Expenses Adapter Tests', () {
    test('Create expense with idempotencyKey and deviceId', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final expenseData = {
        'localUuid': uuid,
        'expenseType': 'maintenance',
        'description': 'إصلاح مكيف',
        'amount': 500.0,
        'date': DateTime.now().toIso8601String(),
        'hotelDayKey': '2025-01-15',
        'isAutoGenerated': false,
        'idempotencyKey': 'exp-$uuid',
        'deviceId': 'device-001',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
        'origin': 'test',
      };

      final refs = await adapters.expenses.adapter.resolveRefs(
        db,
        expenseData,
        src: Source.appwrite,
      );
      final companion = adapters.expenses.adapter.fromJson(
        expenseData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.expenses).insert(companion);

      final localExpense = await (db.select(
        db.expenses,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      expect(localExpense, isNotNull);
      expect(localExpense.amount, equals(500.0));
      expect(localExpense.idempotencyKey, equals('exp-$uuid'));
      expect(localExpense.deviceId, equals('device-001'));

      print(
        '✓ Expense created with idempotencyKey: ${localExpense.idempotencyKey}',
      );
    });
  });

  // ===========================================================================
  // Employees Tests
  // ===========================================================================

  group('Employees Adapter Tests', () {
    test('Create employee and verify salary', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final employeeData = {
        'localUuid': uuid,
        'name': 'أحمد محمد',
        'basicSalary': 5000.0,
        'position': 'receptionist',
        'phone': '+966512345678',
        'hireDate': DateTime.now().toIso8601String(),
        'status': 'active',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
        'origin': 'test',
      };

      final refs = await adapters.employees.adapter.resolveRefs(
        db,
        employeeData,
        src: Source.appwrite,
      );
      final companion = adapters.employees.adapter.fromJson(
        employeeData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.employees).insert(companion);

      final localEmployee = await (db.select(
        db.employees,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      expect(localEmployee, isNotNull);
      expect(localEmployee.name, equals('أحمد محمد'));
      expect(localEmployee.basicSalary, equals(5000.0));

      print('✓ Employee created: ${localEmployee.name}');
    });
  });

  // ===========================================================================
  // Debts Tests
  // ===========================================================================

  group('Debts Adapter Tests', () {
    test('Create debt and verify amounts', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final debtData = {
        'localUuid': uuid,
        'guestName': 'خالد سعيد',
        'checkinDate': DateTime.now().toIso8601String(),
        'checkoutDate': DateTime.now().add(Duration(days: 3)).toIso8601String(),
        'dateRecorded': DateTime.now().toIso8601String(),
        'debtReason': 'رسوم غير مدفوعة',
        'totalAmount': 1500.0,
        'paidAmount': 500.0,
        'remainingAmount': 1000.0,
        'paymentDate': DateTime.now().toIso8601String(),
        'isSettled': 0,
        'pledge': 'بطاقة هوية',
        'pledgeType': 'national_id',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
        'origin': 'test',
      };

      final refs = await adapters.debts.adapter.resolveRefs(
        db,
        debtData,
        src: Source.appwrite,
      );
      final companion = adapters.debts.adapter.fromJson(
        debtData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.debts).insert(companion);

      final localDebt = await (db.select(
        db.debts,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      expect(localDebt, isNotNull);
      expect(localDebt.totalAmount, equals(1500.0));
      expect(localDebt.remainingAmount, equals(1000.0));

      print('✓ Debt created: ${localDebt.guestName}');
    });
  });

  // ===========================================================================
  // Shift Notes Tests
  // ===========================================================================

  group('Shift Notes Adapter Tests', () {
    test('Create shift note with vectorClock', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final shiftNoteData = {
        'localUuid': uuid,
        'title': 'ملاحظة مهمة',
        'content': 'يرجى الانتباه للحجوزات الجديدة',
        'priority': 'high',
        'shiftType': 'morning',
        'isRead': 0,
        'expiresAt': DateTime.now().add(Duration(days: 7)).toIso8601String(),
        'createdBy': 'admin',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'createdAtEpoch': now,
        'lastModifiedEpoch': now,
        'version': 1,
        'origin': 'test',
        'vectorClock': {'device1': 1, 'device2': 2},
      };

      final refs = await adapters.shiftNotes.adapter.resolveRefs(
        db,
        shiftNoteData,
        src: Source.appwrite,
      );
      final companion = adapters.shiftNotes.adapter.fromJson(
        shiftNoteData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.shiftNotes).insert(companion);

      final localNote = await (db.select(
        db.shiftNotes,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      expect(localNote, isNotNull);
      expect(localNote.title, equals('ملاحظة مهمة'));
      expect(localNote.priority, equals('high'));
      expect(localNote.vectorClock, isNotNull);

      print('✓ Shift note created: ${localNote.title}');
    });
  });

  // ===========================================================================
  // Cash Transactions Tests
  // ===========================================================================

  group('Cash Transactions Adapter Tests', () {
    test('Create cash transaction with vectorClock', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final cashData = {
        'localUuid': uuid,
        'transactionType': 'income',
        'amount': 2000.0,
        'referenceType': 'payment',
        'description': 'دفعة نقدية',
        'transactionTime': DateTime.now().toIso8601String(),
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'createdAtEpoch': now,
        'lastModifiedEpoch': now,
        'version': 1,
        'origin': 'test',
        'vectorClock': {'device1': 1},
      };

      final refs = await adapters.cashTransactions.adapter.resolveRefs(
        db,
        cashData,
        src: Source.appwrite,
      );
      final companion = adapters.cashTransactions.adapter.fromJson(
        cashData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.cashTransactions).insert(companion);

      final localCash = await (db.select(
        db.cashTransactions,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      expect(localCash, isNotNull);
      expect(localCash.transactionType, equals('income'));
      expect(localCash.amount, equals(2000.0));
      expect(localCash.vectorClock, isNotNull);

      print('✓ Cash transaction created: ${localCash.amount}');
    });
  });

  // ===========================================================================
  // Booking Nights Tests
  // ===========================================================================

  group('Booking Nights Adapter Tests', () {
    test('Create booking night with appliedAdjustmentsJson', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      // Create room and booking first
      final roomData = {
        'localUuid': 'room-night-$uuid',
        'roomNumber': 'NIGHT-TEST',
        'type': 'single',
        'price': 100.0,
        'status': 'available',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
      };

      final roomRefs = await adapters.rooms.adapter.resolveRefs(
        db,
        roomData,
        src: Source.appwrite,
      );
      await db
          .into(db.rooms)
          .insert(
            adapters.rooms.adapter.fromJson(
              roomData,
              src: Source.appwrite,
              refs: roomRefs,
            ),
          );

      final bookingData = {
        'localUuid': 'booking-night-$uuid',
        'roomNumber': 'NIGHT-TEST',
        'guestName': 'Night Test',
        'guestPhone': '+966500000000',
        'guestNationality': 'Saudi',
        'checkinDate': DateTime.now().toIso8601String(),
        'status': 'checked_in',
        'expectedNights': 3,
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
      };

      final bookingRefs = await adapters.bookings.adapter.resolveRefs(
        db,
        bookingData,
        src: Source.appwrite,
      );
      final bookingCompanion = adapters.bookings.adapter.fromJson(
        bookingData,
        src: Source.appwrite,
        refs: bookingRefs,
      );
      await db.into(db.bookings).insert(bookingCompanion);

      // Get the booking local ID
      final booking = await (db.select(
        db.bookings,
      )..where((t) => t.localUuid.equals('booking-night-$uuid'))).getSingle();

      // Create booking night with bookingLocalId
      final nightData = {
        'localUuid': uuid,
        'bookingLocalId': booking.id,
        'hotelDayKey': '2025-01-15',
        'nightStart': '2025-01-15T14:00:00Z',
        'nightEnd': '2025-01-16T12:00:00Z',
        'nightlyRate': 100.0,
        'sequence': 1,
        'baseRate': 100.0,
        'adjustment': -10.0,
        'finalRate': 90.0,
        'appliedAdjustmentsJson': jsonEncode({
          'discount': 10,
          'type': 'early_booking',
        }),
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
        'origin': 'test',
      };

      final refs = await adapters.nights.adapter.resolveRefs(
        db,
        nightData,
        src: Source.appwrite,
      );
      final companion = adapters.nights.adapter.fromJson(
        nightData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.bookingNights).insert(companion);

      final localNight = await (db.select(
        db.bookingNights,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      expect(localNight, isNotNull);
      expect(localNight.hotelDayKey, equals('2025-01-15'));
      expect(localNight.nightlyRate, equals(100.0));
      expect(localNight.appliedAdjustmentsJson, isNotNull);

      // Verify JSON can be decoded
      final adjustments = jsonDecode(localNight.appliedAdjustmentsJson!);
      expect(adjustments['discount'], equals(10));

      print(
        '✓ Booking night created with adjustments: ${localNight.appliedAdjustmentsJson}',
      );
    });
  });

  // ===========================================================================
  // Vector Clock Tests
  // ===========================================================================

  group('Vector Clock Tests', () {
    test('Vector clock is preserved in round-trip', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final vectorClock = {'device-A': 3, 'device-B': 5, 'device-C': 1};

      final data = {
        'localUuid': uuid,
        'roomNumber': 'VC-TEST',
        'type': 'single',
        'price': 100.0,
        'status': 'available',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
        'vectorClock': vectorClock,
      };

      final refs = await adapters.rooms.adapter.resolveRefs(
        db,
        data,
        src: Source.appwrite,
      );
      final companion = adapters.rooms.adapter.fromJson(
        data,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.rooms).insert(companion);

      final row = await (db.select(
        db.rooms,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      final exported = adapters.rooms.toJsonForSource(
        row,
        src: Source.appwrite,
      );

      expect(exported['vectorClock'], isNotNull);
      expect(exported['vectorClock']['device-A'], equals(3));
      expect(exported['vectorClock']['device-B'], equals(5));
      expect(exported['vectorClock']['device-C'], equals(1));

      print('✓ Vector clock preserved: ${exported['vectorClock']}');
    });

    test('Empty vector clock is handled correctly', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final data = {
        'localUuid': uuid,
        'roomNumber': 'EMPTY-VC',
        'type': 'single',
        'price': 100.0,
        'status': 'available',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
        'vectorClock': {},
      };

      final refs = await adapters.rooms.adapter.resolveRefs(
        db,
        data,
        src: Source.appwrite,
      );
      final companion = adapters.rooms.adapter.fromJson(
        data,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.rooms).insert(companion);

      final row = await (db.select(
        db.rooms,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      final exported = adapters.rooms.toJsonForSource(
        row,
        src: Source.appwrite,
      );

      expect(exported['vectorClock'], isNotNull);
      expect(exported['vectorClock'], isEmpty);

      print('✓ Empty vector clock handled correctly');
    });
  });

  // ===========================================================================
  // Comprehensive Tests
  // ===========================================================================

  group('Comprehensive Round-Trip Tests', () {
    test('All adapters can convert from JSON to model and back', () async {
      final now = currentEpoch();

      // Test data for each adapter
      final testCases = <String, Map<String, dynamic>>{
        'rooms': {
          'localUuid': generateTestUuid(),
          'roomNumber': 'COMP-TEST',
          'type': 'suite',
          'price': 300.0,
          'status': 'available',
          'createdAt': now,
          'updatedAt': now,
          'lastModified': now,
          'version': 1,
        },
        'payments': {
          'localUuid': generateTestUuid(),
          'amount': 150.0,
          'paymentDate': DateTime.now().toIso8601String(),
          'paymentMethod': 'cash',
          'revenueType': 'room',
          'createdAt': now,
          'updatedAt': now,
          'lastModified': now,
          'version': 1,
        },
        'expenses': {
          'localUuid': generateTestUuid(),
          'expenseType': 'utilities',
          'description': 'Test expense',
          'amount': 75.0,
          'date': DateTime.now().toIso8601String(),
          'idempotencyKey': 'comp-test-${generateTestUuid()}',
          'deviceId': 'test-device',
          'createdAt': now,
          'updatedAt': now,
          'lastModified': now,
          'version': 1,
        },
        'employees': {
          'localUuid': generateTestUuid(),
          'name': 'Test Employee',
          'basicSalary': 4000.0,
          'position': 'manager',
          'status': 'active',
          'createdAt': now,
          'updatedAt': now,
          'lastModified': now,
          'version': 1,
        },
        'debts': {
          'localUuid': generateTestUuid(),
          'guestName': 'Test Debtor',
          'checkinDate': DateTime.now().toIso8601String(),
          'checkoutDate': DateTime.now().toIso8601String(),
          'totalAmount': 500.0,
          'paidAmount': 0.0,
          'remainingAmount': 500.0,
          'paymentDate': DateTime.now().toIso8601String(),
          'isSettled': 0,
          'createdAt': now,
          'updatedAt': now,
          'lastModified': now,
          'version': 1,
        },
        'shiftNotes': {
          'localUuid': generateTestUuid(),
          'title': 'Test Note',
          'content': 'Testing all adapters',
          'priority': 'low',
          'shiftType': 'all',
          'isRead': 0,
          'createdAt': now,
          'updatedAt': now,
          'lastModified': now,
          'createdAtEpoch': now,
          'lastModifiedEpoch': now,
          'version': 1,
          'vectorClock': {},
        },
        'cashTransactions': {
          'localUuid': generateTestUuid(),
          'transactionType': 'expense',
          'amount': 100.0,
          'transactionTime': DateTime.now().toIso8601String(),
          'createdAt': now,
          'updatedAt': now,
          'lastModified': now,
          'createdAtEpoch': now,
          'lastModifiedEpoch': now,
          'version': 1,
          'vectorClock': {},
        },
      };

      int successCount = 0;
      for (final entry in testCases.entries) {
        final tableName = entry.key;
        final data = entry.value;

        // Get the appropriate repository
        dynamic repository;
        switch (tableName) {
          case 'rooms':
            repository = adapters.rooms;
            break;
          case 'payments':
            repository = adapters.payments;
            break;
          case 'expenses':
            repository = adapters.expenses;
            break;
          case 'employees':
            repository = adapters.employees;
            break;
          case 'debts':
            repository = adapters.debts;
            break;
          case 'shiftNotes':
            repository = adapters.shiftNotes;
            break;
          case 'cashTransactions':
            repository = adapters.cashTransactions;
            break;
        }

        // Test round-trip
        final refs = await repository.adapter.resolveRefs(
          db,
          data,
          src: Source.appwrite,
        );
        final companion = repository.adapter.fromJson(
          data,
          src: Source.appwrite,
          refs: refs,
        );

        // Insert
        await db.into(repository.table).insert(companion);

        // Fetch
        final table = repository.table;
        final row =
            await (db.select(table)..where(
                  (t) => (t as dynamic).localUuid.equals(data['localUuid']),
                ))
                .getSingle();

        // Convert back
        final exported = repository.toJsonForSource(row, src: Source.appwrite);

        // Verify
        expect(exported['localUuid'], equals(data['localUuid']));
        successCount++;
        print('  ✓ $tableName round-trip successful');
      }

      expect(successCount, equals(testCases.length));
      print('\n✓ All $successCount adapters passed round-trip test');
    });
  });

  // ===========================================================================
  // Summary Test
  // ===========================================================================

  test('Test summary', () async {
    // Count records in each table
    final roomsCount = await (db.select(db.rooms).get()).then((l) => l.length);
    final bookingsCount = await (db.select(db.bookings).get()).then(
      (l) => l.length,
    );
    final paymentsCount = await (db.select(db.payments).get()).then(
      (l) => l.length,
    );
    final expensesCount = await (db.select(db.expenses).get()).then(
      (l) => l.length,
    );
    final employeesCount = await (db.select(db.employees).get()).then(
      (l) => l.length,
    );
    final debtsCount = await (db.select(db.debts).get()).then((l) => l.length);
    final shiftNotesCount = await (db.select(db.shiftNotes).get()).then(
      (l) => l.length,
    );
    final cashCount = await (db.select(db.cashTransactions).get()).then(
      (l) => l.length,
    );
    final nightsCount = await (db.select(db.bookingNights).get()).then(
      (l) => l.length,
    );

    print('\n=== Test Summary ===');
    print('Rooms: $roomsCount');
    print('Bookings: $bookingsCount');
    print('Payments: $paymentsCount');
    print('Expenses: $expensesCount');
    print('Employees: $employeesCount');
    print('Debts: $debtsCount');
    print('Shift Notes: $shiftNotesCount');
    print('Cash Transactions: $cashCount');
    print('Booking Nights: $nightsCount');
    print('====================');

    expect(roomsCount, greaterThan(0));
    expect(bookingsCount, greaterThan(0));
    expect(paymentsCount, greaterThan(0));
    expect(expensesCount, greaterThan(0));
    expect(employeesCount, greaterThan(0));
    expect(debtsCount, greaterThan(0));
    expect(shiftNotesCount, greaterThan(0));
    expect(cashCount, greaterThan(0));
    expect(nightsCount, greaterThan(0));
  });
}
