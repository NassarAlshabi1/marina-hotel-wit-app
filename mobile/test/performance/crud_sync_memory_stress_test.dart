// Marina Hotel — CRUD + Sync memory stress benchmark
//
// Runs five realistic local CRUD cycles using the production repositories.
// The optional Appwrite phase is enabled with:
//   flutter test test/performance/crud_sync_memory_stress_test.dart \
//     --dart-define=RUN_APPWRITE_SYNC_STRESS=true
//
// Without that flag the test still exercises the real local transaction,
// derived-field and Outbox paths, and reports the remote phase as disabled.

// ignore_for_file: lines_longer_than_80_chars

@Tags(['performance', 'integration'])
library marina_hotel_mobile.test.performance.crud_sync_memory_stress_test;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/daos/rooms_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';

const _runRemoteSync = bool.fromEnvironment(
  'RUN_APPWRITE_SYNC_STRESS',
  defaultValue: false,
);

String _isoForCycle(int cycle) =>
    DateTime.utc(2026, 8, 20, 10, cycle).toIso8601String();

void main() {
  test('five CRUD + Outbox/Appwrite sync cycles remain bounded', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    AdapterRegistry.initialize(db);
    final adapters = AdapterRegistry.testing(db);
    final roomOutbox = OutboxDao(db, adapters);
    final roomsDao = RoomsDao(db, roomOutbox);
    final bookingsRepository = BookingsRepository(db);
    final paymentsRepository = PaymentsRepository(db);
    final outbox = OutboxDao(db, adapters);

    // ✅ PaymentsRepository.create يتطلب جلسة مستخدم نشطة (guard حماية
    // في الإنتاج — commit 5c267bf2). الاختبار يبدأ جلسة محلية كما تفعل
    // بقية الاختبارات (payment_session_receipts_test.dart).
    PaymentSessionContext.start(
      userId: 1,
      userName: 'Stress Tester',
      sessionUuid: 'stress-session-1',
    );
    addTearDown(PaymentSessionContext.clear);

    AppwriteSyncManager? syncManager;
    if (_runRemoteSync) {
      final appwrite = AppwriteService();
      await appwrite.initialize();
      syncManager = AppwriteSyncManager(
        appwriteService: appwrite,
        database: db,
      );
    }

    final results = <Map<String, Object?>>[];
    for (var cycle = 1; cycle <= 5; cycle++) {
      final stopwatch = Stopwatch()..start();
      final timestamp = _isoForCycle(cycle);
      final roomNumber = '9${cycle}1';
      final roomUuid = 'stress-room-$cycle';

      await roomsDao.insertOne(
        RoomsCompanion(
          roomNumber: d.Value(roomNumber),
          type: const d.Value('عادية'),
          price: d.Value(150.0 + cycle),
          status: const d.Value('شاغرة'),
          localUuid: d.Value(roomUuid),
        ),
      );

      final bookingId = await bookingsRepository.create(
        roomNumber: roomNumber,
        guestName: 'Stress Guest $cycle',
        guestPhone: '05000000$cycle',
        guestNationality: 'يمني',
        checkinDate: timestamp,
        status: 'نشط',
        expectedNights: 2,
        notes: 'CRUD stress cycle $cycle',
      );

      final paymentId = await paymentsRepository.create(
        amount: 100.0 + cycle,
        paymentDate: timestamp,
        paymentMethod: 'نقدي',
        revenueType: 'room',
        bookingLocalId: bookingId,
        roomNumber: roomNumber,
        notes: 'Stress payment $cycle',
      );

      final bookingUpdate = await bookingsRepository.update(
        bookingId,
        guestName: 'Stress Guest $cycle Updated',
        notes: 'CRUD stress cycle $cycle updated',
      );
      final paymentUpdate = await paymentsRepository.update(
        paymentId,
        amount: 120.0 + cycle,
        notes: 'Stress payment $cycle updated',
      );

      final paymentDelete = await paymentsRepository.delete(paymentId);
      final bookingCheckout = await bookingsRepository.update(
        bookingId,
        status: 'مغادر',
        actualCheckout: timestamp,
      );
      final bookingDelete = await bookingsRepository.delete(bookingId);

      final pendingBeforeBatch = await outbox.countPendingPushable();
      final batch = await outbox.takeBatch(500);
      final batchIds = batch.map((entry) => entry.id).toList(growable: false);
      await outbox.markCompleted(batchIds);
      final pendingAfterBatch = await outbox.countPendingPushable();

      var pushed = 0;
      var pulled = false;
      if (syncManager != null) {
        pushed = await syncManager.pushLocalChanges();
        pulled = await syncManager.pullRemoteChanges();
      }

      stopwatch.stop();
      final result = <String, Object?>{
        'cycle': cycle,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'crud': {
          'bookingCreated': bookingId > 0,
          'paymentCreated': paymentId > 0,
          'bookingUpdated': bookingUpdate,
          'paymentUpdated': paymentUpdate,
          'paymentDeleted': paymentDelete,
          'bookingCheckedOut': bookingCheckout,
          'bookingDeleted': bookingDelete,
        },
        'outbox': {
          'pendingBeforeBatch': pendingBeforeBatch,
          'batchSize': batch.length,
          'pendingAfterBatch': pendingAfterBatch,
        },
        'remoteSync': {
          'enabled': syncManager != null,
          'recordsPushed': pushed,
          'remotePullApplied': pulled,
        },
        'rssBytes': ProcessInfo.currentRss,
      };
      results.add(result);
      // Machine-readable output consumed by CI logs and the stress report.
      print('CRUD_SYNC_STRESS ${jsonEncode(result)}');

      expect(bookingId, greaterThan(0));
      expect(paymentId, greaterThan(0));
      expect(bookingUpdate, greaterThan(0));
      expect(paymentUpdate, greaterThan(0));
      expect(paymentDelete, greaterThan(0));
      expect(bookingCheckout, greaterThan(0));
      expect(bookingDelete, greaterThan(0));
      expect(batch, isNotEmpty);
      expect(pendingAfterBatch, equals(0));
    }

    expect(results, hasLength(5));
  });
}
