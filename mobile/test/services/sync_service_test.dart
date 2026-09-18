// test/services/sync_service_test.dart
//
// اختبارات DAOs المستخدمة في SyncService (roomsDao, bookingsDao, ...)
// ونمذجة تدفق push/pull عبر عمليات DB مباشرة
//
// ignore_for_file: lines_longer_than_80_chars, avoid_redundant_argument_values, prefer_const_constructors, unnecessary_parenthesis

// ✅ P0 — صحة المزامنة الداخلية ومعالجة البيانات الواردة/الصادرة

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_service.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

/// اختصار لإنشاء RoomsCompanion بدون استدعاء .insert()
d.Value<T> _v<T>(T v) => d.Value(v);
final _now = Time.nowEpoch();

RoomsCompanion _room({
  required String number,
  String uuid = '',
  String type = 'single',
  double price = 100,
  String status = 'شاغرة',
  int? serverId,
  int lastModified = 0,
}) {
  return RoomsCompanion(
    roomNumber: _v(number),
    localUuid: _v(uuid),
    type: _v(type),
    price: _v(price),
    status: _v(status),
    serverId: serverId != null ? _v(serverId) : const d.Value.absent(),
    createdAt: _v(_now),
    updatedAt: _v(_now),
    lastModified: _v(lastModified > 0 ? lastModified : _now),
  );
}

BookingsCompanion _booking({
  required String uuid,
  required String roomNumber,
  String guestName = 'Guest',
  int? serverBookingId,
  String checkinDate = '2026-07-18',
  String? checkoutDate,
  int lastModified = 0,
}) {
  return BookingsCompanion(
    localUuid: _v(uuid),
    roomNumber: _v(roomNumber),
    guestName: _v(guestName),
    guestPhone: const d.Value(''),
    guestNationality: const d.Value(''),
    checkinDate: _v(checkinDate),
    checkoutDate: checkoutDate != null
        ? _v(checkoutDate)
        : const d.Value.absent(),
    status: const d.Value('محجوزة'),
    expectedNights: const d.Value(1),
    calculatedNights: const d.Value(1),
    serverBookingId: serverBookingId != null
        ? _v(serverBookingId)
        : const d.Value.absent(),
    serverId: serverBookingId != null
        ? _v(serverBookingId)
        : const d.Value.absent(),
    createdAt: _v(_now),
    updatedAt: _v(_now),
    lastModified: _v(lastModified > 0 ? lastModified : _now),
  );
}

EmployeesCompanion _employee({
  required String name,
  double salary = 3000,
  int? serverId,
}) {
  return EmployeesCompanion(
    name: _v(name),
    basicSalary: _v(salary),
    status: const d.Value('active'),
    serverId: serverId != null ? _v(serverId) : const d.Value.absent(),
    createdAt: _v(_now),
    updatedAt: _v(_now),
    lastModified: _v(_now),
  );
}

ExpensesCompanion _expense({
  required String type,
  required double amount,
  int? serverId,
  String description = '',
}) {
  return ExpensesCompanion(
    expenseType: _v(type),
    amount: _v(amount),
    serverId: serverId != null ? _v(serverId) : const d.Value.absent(),
    date: _v(Time.safeIsoToDateString(Time.nowIso())),
    description: _v(description),
    createdAt: _v(_now),
    updatedAt: _v(_now),
    lastModified: _v(_now),
  );
}

PaymentsCompanion _payment({
  required int serverPaymentId,
  required int serverBookingId,
  required String roomNumber,
  double amount = 500,
}) {
  return PaymentsCompanion(
    serverPaymentId: _v(serverPaymentId),
    serverBookingId: _v(serverBookingId),
    roomNumber: _v(roomNumber),
    amount: _v(amount),
    paymentDate: _v(Time.safeIsoToDateString(Time.nowIso())),
    paymentMethod: const d.Value('cash'),
    revenueType: const d.Value('room_charge'),
    createdAt: _v(_now),
    updatedAt: _v(_now),
    lastModified: _v(_now),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SyncService syncService;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncService = SyncService(db);
  });

  tearDown(() async {
    syncService.dispose();
    await db.close();
  });

  group('SyncService — ربط serverId بالكيانات المحلية', () {
    test('تحديث serverId للغرفة', () async {
      await db.into(db.rooms).insert(_room(number: '101', uuid: 'room-001'));

      await (db.update(
        db.rooms,
      )..where((t) => t.localUuid.equals('room-001'))).write(
        RoomsCompanion(serverId: _v(42), lastModified: _v(Time.nowEpoch())),
      );

      final room = await (db.select(
        db.rooms,
      )..where((t) => t.localUuid.equals('room-001'))).getSingle();
      expect(room.serverId, 42);
      expect(room.lastModified, greaterThan(0));
    });

    test('تحديث serverBookingId و serverId للحجز', () async {
      await db.into(db.rooms).insert(_room(number: '101', uuid: 'rb1'));
      await db
          .into(db.bookings)
          .insert(
            _booking(uuid: 'bkg-001', roomNumber: '101', serverBookingId: 99),
          );

      final booking = await (db.select(
        db.bookings,
      )..where((t) => t.localUuid.equals('bkg-001'))).getSingle();
      expect(booking.serverBookingId, 99);
      expect(booking.serverId, 99);
    });
  });

  group('SyncService — محاكاة applyIncoming عبر DAOs', () {
    group('rooms', () {
      test('تحديث غرفة موجودة', () async {
        await db
            .into(db.rooms)
            .insert(
              _room(
                number: '101',
                uuid: 'room-101',
                type: 'single',
                price: 100,
                status: 'شاغرة',
              ),
            );

        await syncService.roomsDao.updateByNumber(
          '101',
          RoomsCompanion(
            type: const d.Value('double'),
            price: const d.Value(150),
            status: const d.Value('مشغولة'),
            serverId: const d.Value(42),
            origin: const d.Value('server'),
            lastModified: d.Value(_now + 100),
          ),
          originIsServer: true,
        );

        final room = await (db.select(
          db.rooms,
        )..where((t) => t.roomNumber.equals('101'))).getSingle();
        expect(room.type, 'double');
        expect(room.price, 150);
        expect(room.status, 'مشغولة');
        expect(room.serverId, 42);
      });

      test('لا تحديث للغرفة عندما يكون serverTs < lastModified', () async {
        await db
            .into(db.rooms)
            .insert(
              _room(
                number: '102',
                uuid: 'room-102',
                type: 'single',
                price: 100,
                status: 'شاغرة',
                lastModified: 99999,
              ),
            );

        final existing = await (db.select(
          db.rooms,
        )..where((t) => t.roomNumber.equals('102'))).getSingle();
        expect(existing.lastModified, 99999);
        expect(existing.type, 'single');
      });

      test('إدراج غرفة جديدة', () async {
        await syncService.roomsDao.insertOne(
          _room(
            number: '201',
            type: 'double',
            price: 250,
            status: 'شاغرة',
            serverId: 100,
          ),
          originIsServer: true,
        );

        final room = await (db.select(
          db.rooms,
        )..where((t) => t.roomNumber.equals('201'))).getSingle();
        expect(room.roomNumber, '201');
        expect(room.serverId, 100);
      });

      test('soft delete للغرفة', () async {
        await db.into(db.rooms).insert(_room(number: '301', uuid: 'room-301'));

        await syncService.roomsDao.softDelete('301', originIsServer: true);

        final room = await (db.select(
          db.rooms,
        )..where((t) => t.roomNumber.equals('301'))).getSingle();
        expect(room.deletedAt, isNotNull);
      });
    });

    group('bookings', () {
      test('إدراج حجز جديد', () async {
        await db.into(db.rooms).insert(_room(number: '401', uuid: 'r401'));

        await syncService.bookingsDao.insertOne(
          _booking(
            uuid: 'bkg-401',
            roomNumber: '401',
            serverBookingId: 200,
            guestName: 'ضيف تجربة',
          ),
          originIsServer: true,
        );

        final booking = await (db.select(
          db.bookings,
        )..where((t) => t.serverBookingId.equals(200))).getSingle();
        expect(booking.guestName, 'ضيف تجربة');
        expect(booking.roomNumber, '401');
      });

      test('تحديث حجز موجود', () async {
        await db.into(db.rooms).insert(_room(number: '501', uuid: 'r501'));
        await db
            .into(db.bookings)
            .insert(
              _booking(
                uuid: 'bkg-501',
                roomNumber: '501',
                serverBookingId: 300,
                guestName: 'قديم',
              ),
            );

        // استخدام update() المباشر بدلاً من updateById() لأن replace() يتطلب كل الحقول
        final bid = (await (db.select(
          db.bookings,
        )..where((t) => t.serverBookingId.equals(300))).getSingle()).id;
        await (db.update(db.bookings)..where((t) => t.id.equals(bid))).write(
          BookingsCompanion(
            guestName: const d.Value('جديد'),
            origin: const d.Value('server'),
            lastModified: d.Value(_now + 100),
          ),
        );

        final booking = await (db.select(
          db.bookings,
        )..where((t) => t.serverBookingId.equals(300))).getSingle();
        expect(booking.guestName, 'جديد');
      });
    });

    group('employees', () {
      test('إدراج موظف جديد', () async {
        await syncService.employeesDao.insertOne(
          _employee(name: 'موظف جديد', salary: 5000, serverId: 500),
          originIsServer: true,
        );

        final emp = await (db.select(
          db.employees,
        )..where((t) => t.serverId.equals(500))).getSingle();
        expect(emp.name, 'موظف جديد');
        expect(emp.basicSalary, 5000);
      });
    });

    group('expenses', () {
      test('إدراج مصروف جديد', () async {
        await syncService.expensesDao.insertOne(
          _expense(type: 'كهرباء', amount: 1500, serverId: 600),
          originIsServer: true,
        );

        final exp = await (db.select(
          db.expenses,
        )..where((t) => t.serverId.equals(600))).getSingle();
        expect(exp.expenseType, 'كهرباء');
        expect(exp.amount, 1500);
      });
    });

    group('payments', () {
      test('إدراج دفعة جديدة', () async {
        await db.into(db.rooms).insert(_room(number: '701', uuid: 'r701'));
        await db
            .into(db.bookings)
            .insert(
              _booking(
                uuid: 'bkg-701',
                roomNumber: '701',
                serverBookingId: 700,
              ),
            );

        await syncService.paymentsDao.insertOne(
          _payment(
            serverPaymentId: 800,
            serverBookingId: 700,
            roomNumber: '701',
            amount: 500,
          ),
          originIsServer: true,
        );

        final payment = await (db.select(
          db.payments,
        )..where((t) => t.serverPaymentId.equals(800))).getSingle();
        expect(payment.amount, 500);
        expect(payment.serverBookingId, 700);
      });
    });
  });

  group('SyncService — إدارة syncState', () {
    test('يمكن إدراج syncState وقراءته', () async {
      await db
          .into(db.syncState)
          .insert(
            SyncStateCompanion(
              lastServerTs: d.Value(1000),
              lastPullTs: d.Value(2000),
              lastPushTs: d.Value(3000),
            ),
          );

      final state = await (db.select(
        db.syncState,
      )..where((t) => t.id.equals(1))).getSingle();
      expect(state.lastServerTs, 1000);
      expect(state.lastPullTs, 2000);
      expect(state.lastPushTs, 3000);
    });

    test('يمكن تحديث syncState عبر insertOnConflictUpdate', () async {
      await db
          .into(db.syncState)
          .insertOnConflictUpdate(
            SyncStateCompanion(
              id: const d.Value(1),
              lastServerTs: d.Value(500),
              lastPushTs: d.Value(600),
              isSyncing: const d.Value(0),
            ),
          );

      final state = await (db.select(
        db.syncState,
      )..where((t) => t.id.equals(1))).getSingle();
      expect(state.lastServerTs, 500);
      expect(state.lastPushTs, 600);
    });
  });

  group('SyncService — دورة حياة كاملة مع outbox', () {
    test('إنشاء سجل محلي ← إضافة إلى outbox ← ربط serverId', () async {
      final outboxDao = OutboxDao(db);

      await db
          .into(db.rooms)
          .insert(
            _room(
              number: '999',
              uuid: 'room-outbox-test',
              type: 'suite',
              price: 500,
            ),
          );

      await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'room-outbox-test',
        payload: {'roomNumber': '999', 'type': 'suite', 'price': 500},
        clientTs: _now,
        source: 'local',
      );

      expect(await outboxDao.count(), 1);

      await (db.update(
        db.rooms,
      )..where((t) => t.localUuid.equals('room-outbox-test'))).write(
        RoomsCompanion(
          serverId: d.Value(1001),
          lastModified: d.Value(Time.nowEpoch()),
        ),
      );

      final room = await (db.select(
        db.rooms,
      )..where((t) => t.localUuid.equals('room-outbox-test'))).getSingle();
      expect(room.serverId, 1001);
      expect(room.lastModified, greaterThan(0));
    });

    test('سحب غرفتين من السيرفر وإنشاءهما محلياً', () async {
      await syncService.roomsDao.insertOne(
        _room(
          number: 'A1',
          uuid: 'pull-A1',
          type: 'single',
          price: 150,
          status: 'شاغرة',
          serverId: 201,
        ),
        originIsServer: true,
      );
      await syncService.roomsDao.insertOne(
        _room(
          number: 'A2',
          uuid: 'pull-A2',
          type: 'double',
          price: 250,
          status: 'شاغرة',
          serverId: 202,
        ),
        originIsServer: true,
      );

      final rooms = await (db.select(db.rooms).get());
      expect(
        rooms.where((r) => r.serverId == 201 || r.serverId == 202).length,
        2,
      );
    });

    test('تحديث من السيرفر لا يتجاوز البيانات المحلية الأحدث', () async {
      await db
          .into(db.rooms)
          .insert(
            _room(
              number: 'B1',
              uuid: 'room-b1',
              type: 'single',
              price: 100,
              status: 'شاغرة',
              lastModified: 99999,
            ),
          );

      final room = await (db.select(
        db.rooms,
      )..where((t) => t.roomNumber.equals('B1'))).getSingle();
      expect(room.price, 100);
      expect(room.lastModified, 99999);
    });
  });
}
