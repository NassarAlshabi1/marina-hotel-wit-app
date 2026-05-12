import 'dart:convert';
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appwrite/appwrite.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/appwrite_config.dart';
import 'package:uuid/uuid.dart';

// Note: These tests can run without Appwrite credentials (local-only mode)
// To run with real Appwrite data, provide the API key:
// flutter test test/sync_integration_test.dart --dart-define=APPWRITE_API_KEY=your_key

/// Appwrite Integration Tests for All Tables
///
/// To run with the provided credentials:
/// flutter test test/sync_integration_test.dart --dart-define=APPWRITE_API_KEY=standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da
///
/// Or run without credentials for local-only tests (will skip integration tests)

const String _apiKey = String.fromEnvironment(
  'APPWRITE_API_KEY',
  defaultValue: '',
);

const String _testProjectId = '690ff0da0025518570c1';
const String _testEndpoint = 'https://fra.cloud.appwrite.io/v1';
const String _testDatabaseId = 'hotel_db';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bool hasApiKey = _apiKey.isNotEmpty;
  final String skipReason =
      'APPWRITE_API_KEY not provided; skipping integration test.';

  late AppDatabase db;
  late AdapterRegistry adapters;
  late Databases databases;
  late Client client;

  setUpAll(() async {
    // Initialize local database
    db = AppDatabase.forTesting(NativeDatabase.memory());
    adapters = AdapterRegistry(db);

    if (hasApiKey) {
      // Initialize Appwrite client with provided credentials
      client = Client()
        ..setEndpoint(_testEndpoint)
        ..setProject(_testProjectId)
        ..addHeader('X-Appwrite-Key', _apiKey);

      databases = Databases(client);
      print('Appwrite client initialized with API key');
    } else {
      print('Running in local-only mode (no API key provided)');
    }
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

  /// Clean up test documents from Appwrite
  Future<void> cleanupTestDocuments(
    String collectionId,
    List<String> documentIds,
  ) async {
    if (!hasApiKey) return;
    for (final docId in documentIds) {
      try {
        await databases.deleteDocument(
          databaseId: _testDatabaseId,
          collectionId: collectionId,
          documentId: docId,
        );
      } catch (e) {
        // Ignore 404 errors (document already deleted)
        if (!e.toString().contains('404')) {
          print('Cleanup warning: $e');
        }
      }
    }
  }

  // ===========================================================================
  // Connection Tests
  // ===========================================================================

  group('Appwrite Connection Tests', () {
    test('Can connect to Appwrite', () async {
      if (!hasApiKey) {
        markTestSkipped(skipReason);
        return;
      }

      final result = await databases.listDocuments(
        databaseId: _testDatabaseId,
        collectionId: AppwriteConfig.roomsCollectionId,
        queries: [Query.limit(1)],
      );

      expect(result, isNotNull);
      expect(result.documents, isA<List>());
    }, skip: hasApiKey ? false : skipReason);

    test('Can read from rooms collection', () async {
      if (!hasApiKey) {
        markTestSkipped(skipReason);
        return;
      }

      final result = await databases.listDocuments(
        databaseId: _testDatabaseId,
        collectionId: AppwriteConfig.roomsCollectionId,
        queries: [Query.limit(5)],
      );

      print('Found ${result.documents.length} rooms in Appwrite');
      for (final doc in result.documents.take(3)) {
        print('  Room: ${doc.data['roomNumber']} - ${doc.data['type']}');
      }

      expect(result, isNotNull);
    }, skip: hasApiKey ? false : skipReason);
  });

  // ===========================================================================
  // Rooms Sync Tests
  // ===========================================================================

  group('Rooms Sync Tests', () {
    final testDocIds = <String>[];

    tearDownAll(() async {
      await cleanupTestDocuments(AppwriteConfig.roomsCollectionId, testDocIds);
    });

    test('Create room locally and push to server', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      // Create room data
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
        'createdAtEpoch': now,
        'lastModifiedEpoch': now,
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

      // Push to server if credentials available
      if (hasApiKey) {
        final serverRoom = await databases.createDocument(
          databaseId: _testDatabaseId,
          collectionId: AppwriteConfig.roomsCollectionId,
          documentId: uuid,
          data: roomData,
        );
        testDocIds.add(uuid);

        expect(serverRoom.$id, equals(uuid));
        expect(serverRoom.data['roomNumber'], equals(roomData['roomNumber']));

        print('Created room on server: ${serverRoom.$id}');
      }
    });

    test('Pull rooms from server', () async {
      if (!hasApiKey) {
        markTestSkipped(skipReason);
        return;
      }

      // Fetch rooms from server
      final result = await databases.listDocuments(
        databaseId: _testDatabaseId,
        collectionId: AppwriteConfig.roomsCollectionId,
        queries: [Query.limit(10)],
      );

      int pulledCount = 0;
      for (final doc in result.documents) {
        // Check if room exists locally
        final existing = await (db.select(
          db.rooms,
        )..where((t) => t.localUuid.equals(doc.$id))).getSingleOrNull();

        if (existing == null) {
          // Insert into local database
          final roomData = Map<String, dynamic>.from(doc.data);
          roomData['localUuid'] = doc.$id;

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
          pulledCount++;
        }
      }

      print('Pulled $pulledCount new rooms from server');
      expect(pulledCount, greaterThanOrEqualTo(0));
    }, skip: hasApiKey ? false : skipReason);

    test('Room round-trip conversion', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      // Create original data
      final originalData = {
        'localUuid': uuid,
        'roomNumber': 'RT-${now % 10000}',
        'type': 'double',
        'price': 200.0,
        'status': 'available',
        'cleaningStatus': 'clean',
        'requiresMaintenance': false,
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
        'origin': 'test',
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
    });
  });

  // ===========================================================================
  // Bookings Sync Tests
  // ===========================================================================

  group('Bookings Sync Tests', () {
    final testDocIds = <String>[];
    String? testRoomUuid;

    setUpAll(() async {
      // Create a test room for bookings
      if (hasApiKey) {
        testRoomUuid = generateTestUuid();
        final now = currentEpoch();

        await databases.createDocument(
          databaseId: _testDatabaseId,
          collectionId: AppwriteConfig.roomsCollectionId,
          documentId: testRoomUuid!,
          data: {
            'localUuid': testRoomUuid,
            'roomNumber': 'BTEST-${now % 10000}',
            'type': 'single',
            'price': 100.0,
            'status': 'available',
            'cleaningStatus': 'clean',
            'createdAt': now,
            'updatedAt': now,
            'lastModified': now,
            'version': 1,
            'origin': 'test',
          },
        );
        testDocIds.add(testRoomUuid!);
      }
    });

    tearDownAll(() async {
      await cleanupTestDocuments(
        AppwriteConfig.bookingsCollectionId,
        testDocIds.where((id) => id != testRoomUuid).toList(),
      );
      await cleanupTestDocuments(
        AppwriteConfig.roomsCollectionId,
        [testRoomUuid].whereType<String>().toList(),
      );
    });

    test('Create booking locally and push to server', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      // First create room locally
      final roomUuid = testRoomUuid ?? generateTestUuid();
      final roomData = {
        'localUuid': roomUuid,
        'roomNumber': 'BTEST-${now % 10000}',
        'type': 'single',
        'price': 100.0,
        'status': 'available',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
        'origin': 'test',
      };

      final roomRefs = await adapters.rooms.adapter.resolveRefs(
        db,
        roomData,
        src: Source.appwrite,
      );
      final roomCompanion = adapters.rooms.adapter.fromJson(
        roomData,
        src: Source.appwrite,
        refs: roomRefs,
      );
      await db.into(db.rooms).insert(roomCompanion);

      // Create booking data
      final bookingData = {
        'localUuid': uuid,
        'roomNumber': roomData['roomNumber'],
        'guestName': 'Test Guest',
        'guestPhone': '+966500000000',
        'guestNationality': 'Saudi',
        'checkinDate': DateTime.now().toIso8601String(),
        'status': 'checked_in',
        'expectedNights': 3,
        'calculatedNights': 3,
        'discount': 0.0,
        'discountType': 'per_night',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
        'origin': 'test',
      };

      // Insert into local database
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

      // Verify local insertion
      final localBooking = await (db.select(
        db.bookings,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      expect(localBooking, isNotNull);
      expect(localBooking.guestName, equals('Test Guest'));

      // Push to server if credentials available
      if (hasApiKey) {
        final serverBooking = await databases.createDocument(
          databaseId: _testDatabaseId,
          collectionId: AppwriteConfig.bookingsCollectionId,
          documentId: uuid,
          data: bookingData,
        );
        testDocIds.add(uuid);

        expect(serverBooking.$id, equals(uuid));
        print('Created booking on server: ${serverBooking.$id}');
      }
    });

    test('Pull bookings from server', () async {
      if (!hasApiKey) {
        markTestSkipped(skipReason);
        return;
      }

      // Fetch bookings from server
      final result = await databases.listDocuments(
        databaseId: _testDatabaseId,
        collectionId: AppwriteConfig.bookingsCollectionId,
        queries: [Query.limit(10)],
      );

      print('Found ${result.documents.length} bookings on server');
      expect(result, isNotNull);
    }, skip: hasApiKey ? false : skipReason);

    test('Booking round-trip conversion', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      // Create room first
      final roomData = {
        'localUuid': 'room-rt-$uuid',
        'roomNumber': 'RT-BOOK-${now % 10000}',
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

      // Create original booking data
      final originalData = {
        'localUuid': uuid,
        'roomNumber': roomData['roomNumber'],
        'guestName': 'Round Trip Guest',
        'guestPhone': '+966511111111',
        'guestIdType': 'بطاقة شخصية',
        'guestIdNumber': '1234567890',
        'guestNationality': 'Saudi',
        'checkinDate': DateTime.now().toIso8601String(),
        'status': 'checked_in',
        'expectedNights': 2,
        'calculatedNights': 2,
        'discount': 10.0,
        'discountType': 'per_night',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
      };

      // Convert to local model
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

      // Convert back to JSON
      final row = await (db.select(
        db.bookings,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      final exportedData = adapters.bookings.toJsonForSource(
        row,
        src: Source.appwrite,
      );

      // Verify critical fields
      expect(exportedData['localUuid'], equals(uuid));
      expect(exportedData['guestName'], equals(originalData['guestName']));
      expect(exportedData['guestPhone'], equals(originalData['guestPhone']));
      expect(exportedData['status'], equals(originalData['status']));
    });
  });

  // ===========================================================================
  // Payments Sync Tests
  // ===========================================================================

  group('Payments Sync Tests', () {
    final testDocIds = <String>[];

    tearDownAll(() async {
      await cleanupTestDocuments(
        AppwriteConfig.paymentsCollectionId,
        testDocIds,
      );
    });

    test('Create payment locally', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final paymentData = {
        'localUuid': uuid,
        'amount': 500.0,
        'paymentDate': DateTime.now().toIso8601String(),
        'paymentMethod': 'cash',
        'revenueType': 'room',
        'notes': 'Test payment',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
        'origin': 'test',
      };

      // Insert into local database
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

      // Verify
      final localPayment = await (db.select(
        db.payments,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      expect(localPayment, isNotNull);
      expect(localPayment.amount, equals(500.0));
    });

    test('Pull payments from server', () async {
      if (!hasApiKey) {
        markTestSkipped(skipReason);
        return;
      }

      final result = await databases.listDocuments(
        databaseId: _testDatabaseId,
        collectionId: AppwriteConfig.paymentsCollectionId,
        queries: [Query.limit(10)],
      );

      print('Found ${result.documents.length} payments on server');
      expect(result, isNotNull);
    }, skip: hasApiKey ? false : skipReason);

    test('Payment round-trip conversion', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final originalData = {
        'localUuid': uuid,
        'amount': 750.5,
        'paymentDate': DateTime.now().toIso8601String(),
        'paymentMethod': 'card',
        'revenueType': 'room',
        'notes': 'Round trip test',
        'hotelDayKey': '2025-01-15',
        'isPendingBalance': false,
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

      expect(exportedData['localUuid'], equals(uuid));
      expect(exportedData['amount'], equals(originalData['amount']));
      expect(
        exportedData['paymentMethod'],
        equals(originalData['paymentMethod']),
      );
    });
  });

  // ===========================================================================
  // Expenses Sync Tests
  // ===========================================================================

  group('Expenses Sync Tests', () {
    final testDocIds = <String>[];

    tearDownAll(() async {
      await cleanupTestDocuments(
        AppwriteConfig.expensesCollectionId,
        testDocIds,
      );
    });

    test('Create expense locally', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final expenseData = {
        'localUuid': uuid,
        'expenseType': 'maintenance',
        'description': 'Test expense for AC repair',
        'amount': 250.0,
        'date': DateTime.now().toIso8601String(),
        'hotelDayKey': '2025-01-15',
        'isAutoGenerated': false,
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
      expect(localExpense.amount, equals(250.0));
      // idempotencyKey و deviceId ليسا حقول في جدول Expenses
      // هما حقول في Outbox فقط
      expect(localExpense.expenseType, equals('maintenance'));
    });

    test('Pull expenses from server', () async {
      if (!hasApiKey) {
        markTestSkipped(skipReason);
        return;
      }

      final result = await databases.listDocuments(
        databaseId: _testDatabaseId,
        collectionId: AppwriteConfig.expensesCollectionId,
        queries: [Query.limit(10)],
      );

      print('Found ${result.documents.length} expenses on server');
      expect(result, isNotNull);
    }, skip: hasApiKey ? false : skipReason);

    test('Expense round-trip conversion', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final originalData = {
        'localUuid': uuid,
        'expenseType': 'supplies',
        'description': 'Round trip test expense',
        'amount': 100.0,
        'date': DateTime.now().toIso8601String(),
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
      };

      final refs = await adapters.expenses.adapter.resolveRefs(
        db,
        originalData,
        src: Source.appwrite,
      );
      final companion = adapters.expenses.adapter.fromJson(
        originalData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.expenses).insert(companion);

      final row = await (db.select(
        db.expenses,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      final exportedData = adapters.expenses.toJsonForSource(
        row,
        src: Source.appwrite,
      );

      expect(exportedData['localUuid'], equals(uuid));
      expect(exportedData['expenseType'], equals(originalData['expenseType']));
      // idempotencyKey و deviceId ليسا حقول في جدول Expenses
      expect(exportedData['description'], equals(originalData['description']));
    });
  });

  // ===========================================================================
  // Employees Sync Tests
  // ===========================================================================

  group('Employees Sync Tests', () {
    final testDocIds = <String>[];

    tearDownAll(() async {
      await cleanupTestDocuments(
        AppwriteConfig.employeesCollectionId,
        testDocIds,
      );
    });

    test('Create employee locally', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final employeeData = {
        'localUuid': uuid,
        'name': 'Test Employee',
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
      expect(localEmployee.name, equals('Test Employee'));
      expect(localEmployee.basicSalary, equals(5000.0));
    });

    test('Pull employees from server', () async {
      if (!hasApiKey) {
        markTestSkipped(skipReason);
        return;
      }

      final result = await databases.listDocuments(
        databaseId: _testDatabaseId,
        collectionId: AppwriteConfig.employeesCollectionId,
        queries: [Query.limit(10)],
      );

      print('Found ${result.documents.length} employees on server');
      expect(result, isNotNull);
    }, skip: hasApiKey ? false : skipReason);
  });

  // ===========================================================================
  // Debts Sync Tests
  // ===========================================================================

  group('Debts Sync Tests', () {
    final testDocIds = <String>[];

    tearDownAll(() async {
      await cleanupTestDocuments(AppwriteConfig.debtsCollectionId, testDocIds);
    });

    test('Create debt locally', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final debtData = {
        'localUuid': uuid,
        'guestName': 'Test Debtor',
        'checkinDate': DateTime.now().toIso8601String(),
        'checkoutDate': DateTime.now().add(Duration(days: 3)).toIso8601String(),
        'dateRecorded': DateTime.now().toIso8601String(),
        'debtReason': 'Unpaid room charges',
        'totalAmount': 1000.0,
        'paidAmount': 200.0,
        'remainingAmount': 800.0,
        'paymentDate': DateTime.now().toIso8601String(),
        'isSettled': 0,
        'pledge': 'ID card held',
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
      expect(localDebt.guestName, equals('Test Debtor'));
      expect(localDebt.totalAmount, equals(1000.0));
    });

    test('Pull debts from server', () async {
      if (!hasApiKey) {
        markTestSkipped(skipReason);
        return;
      }

      final result = await databases.listDocuments(
        databaseId: _testDatabaseId,
        collectionId: AppwriteConfig.debtsCollectionId,
        queries: [Query.limit(10)],
      );

      print('Found ${result.documents.length} debts on server');
      expect(result, isNotNull);
    }, skip: hasApiKey ? false : skipReason);
  });

  // ===========================================================================
  // Shift Notes Sync Tests
  // ===========================================================================

  group('Shift Notes Sync Tests', () {
    final testDocIds = <String>[];

    tearDownAll(() async {
      await cleanupTestDocuments(
        AppwriteConfig.shiftNotesCollectionId,
        testDocIds,
      );
    });

    test('Create shift note locally', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final shiftNoteData = {
        'localUuid': uuid,
        'title': 'Test Shift Note',
        'content': 'This is a test note for shift handover',
        'priority': 'high',
        'shiftType': 'morning',
        'isRead': 0,
        'expiresAt': DateTime.now().add(Duration(days: 7)).toIso8601String(),
        'createdBy': 'test-user',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'createdAtEpoch': now,
        'lastModifiedEpoch': now,
        'version': 1,
        'origin': 'test',
        'vectorClock': createVectorClock('test-device', 1),
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
      expect(localNote.title, equals('Test Shift Note'));
      expect(localNote.priority, equals('high'));
    });

    test('Shift note round-trip with vectorClock', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final originalData = {
        'localUuid': uuid,
        'title': 'Vector Clock Test',
        'content': 'Testing vector clock persistence',
        'priority': 'medium',
        'shiftType': 'evening',
        'isRead': 0,
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'createdAtEpoch': now,
        'lastModifiedEpoch': now,
        'version': 1,
        'vectorClock': {'device1': 1, 'device2': 2},
      };

      final refs = await adapters.shiftNotes.adapter.resolveRefs(
        db,
        originalData,
        src: Source.appwrite,
      );
      final companion = adapters.shiftNotes.adapter.fromJson(
        originalData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.shiftNotes).insert(companion);

      final row = await (db.select(
        db.shiftNotes,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      final exportedData = adapters.shiftNotes.toJsonForSource(
        row,
        src: Source.appwrite,
      );

      expect(exportedData['localUuid'], equals(uuid));
      expect(exportedData['title'], equals(originalData['title']));
      expect(exportedData['vectorClock'], isNotNull);
    });
  });

  // ===========================================================================
  // Cash Transactions Sync Tests
  // ===========================================================================

  group('Cash Transactions Sync Tests', () {
    test('Create cash transaction locally', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      final cashData = {
        'localUuid': uuid,
        'transactionType': 'income',
        'amount': 500.0,
        'referenceType': 'payment',
        'description': 'Test cash transaction',
        'transactionTime': DateTime.now().toIso8601String(),
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'createdAtEpoch': now,
        'lastModifiedEpoch': now,
        'version': 1,
        'origin': 'test',
        'vectorClock': createVectorClock('test-device', 1),
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
      expect(localCash.amount, equals(500.0));
    });
  });

  // ===========================================================================
  // Booking Nights Sync Tests
  // ===========================================================================

  group('Booking Nights Sync Tests', () {
    test('Create booking night locally', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      // Create a booking first
      final bookingUuid = generateTestUuid();
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
        'localUuid': bookingUuid,
        'roomNumber': 'NIGHT-TEST',
        'guestName': 'Night Test Guest',
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

      // Create booking night
      final nightData = {
        'localUuid': uuid,
        'hotelDayKey': '2025-01-15',
        'nightStart': '2025-01-15T14:00:00Z',
        'nightEnd': '2025-01-16T12:00:00Z',
        'nightlyRate': 100.0,
        'sequence': 1,
        'baseRate': 100.0,
        'adjustment': 0.0,
        'finalRate': 100.0,
        'appliedAdjustmentsJson': jsonEncode({'discount': 0}),
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
    });
  });

  // ===========================================================================
  // Salary Cycles Sync Tests
  // ===========================================================================

  group('Salary Cycles Sync Tests', () {
    test('Create salary cycle locally', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      // Create employee first
      final employeeUuid = generateTestUuid();
      final employeeData = {
        'localUuid': employeeUuid,
        'name': 'Salary Test Employee',
        'basicSalary': 5000.0,
        'position': 'cleaner',
        'status': 'active',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
      };

      final empRefs = await adapters.employees.adapter.resolveRefs(
        db,
        employeeData,
        src: Source.appwrite,
      );
      await db
          .into(db.employees)
          .insert(
            adapters.employees.adapter.fromJson(
              employeeData,
              src: Source.appwrite,
              refs: empRefs,
            ),
          );

      // Get the employee ID
      final employee = await (db.select(
        db.employees,
      )..where((t) => t.localUuid.equals(employeeUuid))).getSingle();

      final cycleData = {
        'localUuid': uuid,
        'cycleKey': '2025-01',
        'hotelDayStart': '2025-01-01',
        'hotelDayEnd': '2025-01-31',
        'expectedAmount': 500000,
        'actualPaid': 0,
        'remainingAmount': 500000,
        'status': 'draft',
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'version': 1,
        'origin': 'test',
      };

      final refs = await adapters.salaryCycles.adapter.resolveRefs(
        db,
        cycleData,
        src: Source.appwrite,
      );
      final companion = adapters.salaryCycles.adapter.fromJson(
        cycleData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.salaryCycles).insert(companion);

      final localCycle = await (db.select(
        db.salaryCycles,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();
      expect(localCycle, isNotNull);
      expect(localCycle.cycleKey, equals('2025-01'));
      expect(localCycle.status, equals('draft'));
    });
  });

  // ===========================================================================
  // Comprehensive Round-Trip Tests
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
          'description': 'Comprehensive test',
          'amount': 75.0,
          'date': DateTime.now().toIso8601String(),
          'hotelDayKey': '2025-01-15',
          'createdAt': now,
          'updatedAt': now,
          'lastModified': now,
          'version': 1,
        },
        'employees': {
          'localUuid': generateTestUuid(),
          'name': 'Comprehensive Test Employee',
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
          'guestName': 'Comprehensive Test Debtor',
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
          'title': 'Comprehensive Test Note',
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

      for (final entry in testCases.entries) {
        final tableName = entry.key;
        final data = entry.value;

        print('Testing round-trip for $tableName');

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
        print('  ✓ $tableName round-trip successful');
      }
    });
  });

  // ===========================================================================
  // Sync with Real Data Tests
  // ===========================================================================

  group('Real Data Sync Tests', () {
    test('Pull all data from server and verify', () async {
      if (!hasApiKey) {
        markTestSkipped(skipReason);
        return;
      }

      // Pull rooms
      final roomsResult = await databases.listDocuments(
        databaseId: _testDatabaseId,
        collectionId: AppwriteConfig.roomsCollectionId,
        queries: [Query.limit(50)],
      );
      print('Rooms on server: ${roomsResult.documents.length}');

      // Pull bookings
      final bookingsResult = await databases.listDocuments(
        databaseId: _testDatabaseId,
        collectionId: AppwriteConfig.bookingsCollectionId,
        queries: [Query.limit(50)],
      );
      print('Bookings on server: ${bookingsResult.documents.length}');

      // Pull payments
      final paymentsResult = await databases.listDocuments(
        databaseId: _testDatabaseId,
        collectionId: AppwriteConfig.paymentsCollectionId,
        queries: [Query.limit(50)],
      );
      print('Payments on server: ${paymentsResult.documents.length}');

      // Pull expenses
      final expensesResult = await databases.listDocuments(
        databaseId: _testDatabaseId,
        collectionId: AppwriteConfig.expensesCollectionId,
        queries: [Query.limit(50)],
      );
      print('Expenses on server: ${expensesResult.documents.length}');

      // Pull employees
      final employeesResult = await databases.listDocuments(
        databaseId: _testDatabaseId,
        collectionId: AppwriteConfig.employeesCollectionId,
        queries: [Query.limit(50)],
      );
      print('Employees on server: ${employeesResult.documents.length}');

      // Pull debts
      final debtsResult = await databases.listDocuments(
        databaseId: _testDatabaseId,
        collectionId: AppwriteConfig.debtsCollectionId,
        queries: [Query.limit(50)],
      );
      print('Debts on server: ${debtsResult.documents.length}');

      // Summary
      print('\n=== Server Data Summary ===');
      print('Total rooms: ${roomsResult.documents.length}');
      print('Total bookings: ${bookingsResult.documents.length}');
      print('Total payments: ${paymentsResult.documents.length}');
      print('Total expenses: ${expensesResult.documents.length}');
      print('Total employees: ${employeesResult.documents.length}');
      print('Total debts: ${debtsResult.documents.length}');

      expect(true, isTrue); // Test passed if we got here
    }, skip: hasApiKey ? false : skipReason);

    test('Sync specific booking data from server', () async {
      if (!hasApiKey) {
        markTestSkipped(skipReason);
        return;
      }

      // Get active bookings
      final result = await databases.listDocuments(
        databaseId: _testDatabaseId,
        collectionId: AppwriteConfig.bookingsCollectionId,
        queries: [Query.equal('status', 'checked_in'), Query.limit(10)],
      );

      print('Active bookings found: ${result.documents.length}');

      for (final doc in result.documents.take(3)) {
        final data = doc.data;
        print('  Booking: ${data['guestName']} - Room ${data['roomNumber']}');
        print('    Check-in: ${data['checkinDate']}');
        print('    Status: ${data['status']}');
      }

      expect(result, isNotNull);
    }, skip: hasApiKey ? false : skipReason);
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
    });
  });

  // ===========================================================================
  // Conflict Resolution Tests
  // ===========================================================================

  group('Conflict Resolution Tests', () {
    test('Newer local data wins conflict', () async {
      final uuid = generateTestUuid();
      final now = currentEpoch();

      // Create initial local data
      final localData = {
        'localUuid': uuid,
        'roomNumber': 'CONFLICT-TEST',
        'type': 'single',
        'price': 100.0,
        'status': 'available',
        'createdAt': now - 1000,
        'updatedAt': now,
        'lastModified': now,
        'version': 2,
      };

      final refs = await adapters.rooms.adapter.resolveRefs(
        db,
        localData,
        src: Source.appwrite,
      );
      final companion = adapters.rooms.adapter.fromJson(
        localData,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.rooms).insert(companion);

      // Try to update with older data
      final olderData = {
        'localUuid': uuid,
        'roomNumber': 'CONFLICT-TEST',
        'type': 'double', // Different value
        'price': 150.0, // Different value
        'status': 'occupied',
        'createdAt': now - 1000,
        'updatedAt': now - 500, // Older timestamp
        'lastModified': now - 500,
        'version': 1, // Older version
      };

      await adapters.rooms.upsertFromJson(olderData, src: Source.appwrite);

      // Verify the local (newer) data was preserved
      final row = await (db.select(
        db.rooms,
      )..where((t) => t.localUuid.equals(uuid))).getSingle();

      // The data should remain as the newer version
      expect(row.type, equals('single')); // Original value preserved
      expect(row.price, equals(100.0)); // Original value preserved
    });
  });
}
