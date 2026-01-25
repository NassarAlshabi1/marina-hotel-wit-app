import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/delta_sync_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/restore_fix_service.dart';
import 'package:marina_hotel_mobile/utils/id.dart';
import 'package:marina_hotel_mobile/utils/status_utils.dart';
import 'package:marina_hotel_mobile/utils/time.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('RestoreFixService', () {
    late AppDatabase database;
    late RestoreFixService service;

    setUp(() async {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      service = RestoreFixService(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('recalculates debts and settlement status', () async {
      final now = Time.nowEpoch();
      final roomUuid = IdGen.uuid();
      final bookingUuid = IdGen.uuid();
      await database
          .into(database.rooms)
          .insert(
            RoomsCompanion(
              localUuid: Value(roomUuid),
              roomNumber: const Value('101'),
              type: const Value('single'),
              price: const Value(200.0),
              status: const Value('محجوزة'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
      final bookingId = await database
          .into(database.bookings)
          .insert(
            BookingsCompanion(
              localUuid: Value(bookingUuid),
              roomNumber: const Value('101'),
              guestName: const Value('أحمد'),
              guestPhone: const Value('0500000000'),
              guestNationality: const Value('سعودي'),
              checkinDate: Value(DateTime(2024, 10, 1, 15).toIso8601String()),
              checkoutDate: Value(DateTime(2024, 10, 4, 13).toIso8601String()),
              status: const Value('محجوزة'),
              expectedNights: const Value(1),
              calculatedNights: const Value(1),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
      await database
          .into(database.payments)
          .insert(
            PaymentsCompanion(
              localUuid: Value(IdGen.uuid()),
              bookingLocalId: Value(bookingId),
              amount: const Value(600.0),
              paymentDate: Value(DateTime.now().toIso8601String()),
              paymentMethod: const Value('cash'),
              revenueType: const Value('room'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
      final debtUuid = IdGen.uuid();
      await database
          .into(database.debts)
          .insert(
            DebtsCompanion(
              localUuid: Value(debtUuid),
              bookingLocalId: Value(bookingId),
              guestName: const Value('أحمد'),
              checkinDate: Value(DateTime(2024, 10, 1).toIso8601String()),
              checkoutDate: Value(DateTime(2024, 10, 4).toIso8601String()),
              totalAmount: const Value(1200.0),
              paidAmount: const Value(0.0),
              remainingAmount: const Value(1200.0),
              paymentDate: Value(DateTime.now().toIso8601String()),
              isSettled: const Value(0),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      final report = await service.runAutoFixAfterRestore();

      expect(report.success, isTrue);
      final debt = await (database.select(
        database.debts,
      )..where((d) => d.localUuid.equals(debtUuid))).getSingle();
      expect(debt.totalAmount, closeTo(600.0, 0.01));
      expect(debt.paidAmount, closeTo(600.0, 0.01));
      expect(debt.remainingAmount, closeTo(0.0, 0.01));
      expect(debt.isSettled, equals(1));
    });

    test('handles large dataset efficiently', () async {
      final now = Time.nowEpoch();
      for (var i = 0; i < 100; i++) {
        await database
            .into(database.rooms)
            .insert(
              RoomsCompanion(
                localUuid: Value(IdGen.uuid()),
                roomNumber: Value('R${i + 1}'),
                type: const Value('standard'),
                price: const Value(150.0),
                status: const Value('شاغرة'),
                createdAt: Value(now),
                updatedAt: Value(now),
                lastModified: Value(now),
              ),
            );
      }
      for (var i = 0; i < 50; i++) {
        final bookingId = await database
            .into(database.bookings)
            .insert(
              BookingsCompanion(
                localUuid: Value(IdGen.uuid()),
                roomNumber: Value('R${(i % 100) + 1}'),
                guestName: Value('ضيف ${i + 1}'),
                guestPhone: const Value('0501111111'),
                guestNationality: const Value('سعودي'),
                checkinDate: Value(DateTime(2024, 9, 1, 14).toIso8601String()),
                checkoutDate: Value(DateTime(2024, 9, 4, 18).toIso8601String()),
                status: const Value('محجوزة'),
                expectedNights: const Value(1),
                calculatedNights: const Value(1),
                createdAt: Value(now),
                updatedAt: Value(now),
                lastModified: Value(now),
              ),
            );
        await database
            .into(database.payments)
            .insert(
              PaymentsCompanion(
                localUuid: Value(IdGen.uuid()),
                bookingLocalId: Value(bookingId),
                amount: const Value(150.0),
                paymentDate: Value(DateTime.now().toIso8601String()),
                paymentMethod: const Value('cash'),
                revenueType: const Value('room'),
                createdAt: Value(now),
                updatedAt: Value(now),
                lastModified: Value(now),
              ),
            );
      }

      final stopwatch = Stopwatch()..start();
      final report = await service.runAutoFixAfterRestore();
      stopwatch.stop();

      expect(report.success, isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(4000));
      expect(report.bookingsFixed, equals(50));
    });

    test('snapshot rollback restores data on failure', () async {
      final now = Time.nowEpoch();
      final originalStatus = 'شاغرة';
      await database
          .into(database.rooms)
          .insert(
            RoomsCompanion(
              localUuid: Value(IdGen.uuid()),
              roomNumber: const Value('201'),
              type: const Value('double'),
              price: const Value(250.0),
              status: Value(originalStatus),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
      final failingService = RestoreFixService(
        database,
        onBeforeCommit: () => Future.error(Exception('fail')),
      );
      final report = await failingService.runAutoFixAfterRestore();

      expect(report.success, isFalse);
      final room = await (database.select(
        database.rooms,
      )..where((r) => r.roomNumber.equals('201'))).getSingle();
      expect(room.status, equals(originalStatus));
    });

    test('end-to-end auto fix normalizes bookings and rooms', () async {
      final now = Time.nowEpoch();
      await database
          .into(database.rooms)
          .insert(
            RoomsCompanion(
              localUuid: Value(IdGen.uuid()),
              roomNumber: const Value('301'),
              type: const Value('suite'),
              price: const Value(500.0),
              status: const Value('شاغرة'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
      final bookingId = await database
          .into(database.bookings)
          .insert(
            BookingsCompanion(
              localUuid: Value(IdGen.uuid()),
              roomNumber: const Value('301'),
              guestName: const Value('سارة'),
              guestPhone: const Value('0502222222'),
              guestNationality: const Value('سعودية'),
              checkinDate: Value(DateTime(2024, 8, 10, 16).toIso8601String()),
              checkoutDate: Value(DateTime(2024, 8, 13, 15).toIso8601String()),
              status: const Value('محجوزة'),
              actualCheckout: Value(
                DateTime(2024, 8, 13, 15).toIso8601String(),
              ),
              expectedNights: const Value(1),
              calculatedNights: const Value(1),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
      await database
          .into(database.payments)
          .insert(
            PaymentsCompanion(
              localUuid: Value(IdGen.uuid()),
              bookingLocalId: Value(bookingId),
              amount: const Value(500.0),
              paymentDate: Value(DateTime.now().toIso8601String()),
              paymentMethod: const Value('cash'),
              revenueType: const Value('room'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      final report = await service.runAutoFixAfterRestore();

      expect(report.success, isTrue);
      final updatedBooking = await (database.select(
        database.bookings,
      )..where((b) => b.id.equals(bookingId))).getSingle();
      final expectedNights = Time.nightsWithCutoff(
        DateTime(2024, 8, 10, 16),
        checkout: DateTime(2024, 8, 13, 15),
      );
      expect(updatedBooking.calculatedNights, equals(expectedNights));
      final room = await (database.select(
        database.rooms,
      )..where((r) => r.roomNumber.equals('301'))).getSingle();
      expect(room.status, equals(StatusUtils.roomStatusForOccupancy(true)));
      final fixLogs = await database.select(database.restoreFixLog).get();
      final conflictLogs = await database
          .customSelect('SELECT * FROM restore_conflict_log')
          .get();
      expect(fixLogs, isNotEmpty);
      expect(conflictLogs, isNotEmpty);
    });
  });

  group('DeltaSyncService', () {
    late AppDatabase database;
    late DeltaSyncService deltaService;

    setUp(() async {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      deltaService = DeltaSyncService(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('detects inserts and normalizes timestamps', () async {
      final now = Time.nowEpoch();
      await database
          .into(database.rooms)
          .insert(
            RoomsCompanion(
              localUuid: Value(IdGen.uuid()),
              roomNumber: const Value('401'),
              type: const Value('standard'),
              price: const Value(100.0),
              status: const Value('محجوزة'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      final computation = await deltaService.compute();

      expect(
        computation.changes.any(
          (c) => c.entity == 'rooms' && c.operation == 'insert',
        ),
        isTrue,
      );
      final change = computation.changes.first;
      expect(change.clientTimestamp, greaterThan(1000000000000));
      expect((change.data['created_at'] as int), greaterThan(1000000000000));
    });

    test('detects updates after mirror persistence', () async {
      final now = Time.nowEpoch();
      final roomUuid = IdGen.uuid();
      await database
          .into(database.rooms)
          .insert(
            RoomsCompanion(
              localUuid: Value(roomUuid),
              roomNumber: const Value('501'),
              type: const Value('standard'),
              price: const Value(120.0),
              status: const Value('محجوزة'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
      final firstComputation = await deltaService.compute();
      await deltaService.persistMirror(firstComputation);
      await (database.into(database.syncState)).insertOnConflictUpdate(
        SyncStateCompanion(
          id: const Value(1),
          lastPushTs: Value(now),
          lastServerTs: const Value(0),
          lastPullTs: const Value(0),
          isSyncing: const Value(0),
        ),
      );
      final updateTs = now + 100;
      await (database.update(
        database.rooms,
      )..where((t) => t.roomNumber.equals('501'))).write(
        RoomsCompanion(
          price: const Value(150.0),
          updatedAt: Value(updateTs),
          lastModified: Value(updateTs),
        ),
      );

      final secondComputation = await deltaService.compute();

      expect(
        secondComputation.changes.any(
          (c) => c.entity == 'rooms' && c.operation == 'update',
        ),
        isTrue,
      );
    });

    test('detects deletes after soft removal', () async {
      final now = Time.nowEpoch();
      final roomUuid = IdGen.uuid();
      await database
          .into(database.rooms)
          .insert(
            RoomsCompanion(
              localUuid: Value(roomUuid),
              roomNumber: const Value('601'),
              type: const Value('standard'),
              price: const Value(140.0),
              status: const Value('محجوزة'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
      final initial = await deltaService.compute();
      await deltaService.persistMirror(initial);
      await (database.into(database.syncState)).insertOnConflictUpdate(
        SyncStateCompanion(
          id: const Value(1),
          lastPushTs: Value(now),
          lastServerTs: const Value(0),
          lastPullTs: const Value(0),
          isSyncing: const Value(0),
        ),
      );
      final deleteTs = now + 200;
      await (database.update(
        database.rooms,
      )..where((t) => t.roomNumber.equals('601'))).write(
        RoomsCompanion(
          deletedAt: Value(deleteTs),
          lastModified: Value(deleteTs),
        ),
      );

      final deleteComputation = await deltaService.compute();

      expect(
        deleteComputation.changes.any(
          (c) => c.entity == 'rooms' && c.operation == 'delete',
        ),
        isTrue,
      );
    });
  });
}
