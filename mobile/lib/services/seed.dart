import 'dart:math';
import 'package:drift/drift.dart' as d;
import '../utils/time.dart';
import 'local_db.dart';

class Seeder {
  Seeder(this.db);
  final AppDatabase db;

  Future<void> seedIfEmpty() async {
    final roomsCount = (await db.customSelect('SELECT COUNT(*) c FROM rooms').getSingle()).data['c'] as int;
    if (roomsCount > 0) return;
    final now = DateTime.now();

    final roomsCompanions = [
      RoomsCompanion(roomNumber: d.Value('101'), type: d.Value('سرير عائلي'), price: d.Value(15000), status: d.Value('شاغرة'), localUuid: d.Value('r-101')),
      RoomsCompanion(roomNumber: d.Value('102'), type: d.Value('سرير عائلي'), price: d.Value(15000), status: d.Value('محجوزة'), localUuid: d.Value('r-102')),
      RoomsCompanion(roomNumber: d.Value('103'), type: d.Value('سرير فردي'), price: d.Value(12000), status: d.Value('شاغرة'), localUuid: d.Value('r-103')),
      RoomsCompanion(roomNumber: d.Value('104'), type: d.Value('سرير فردي'), price: d.Value(10000), status: d.Value('شاغرة'), localUuid: d.Value('r-104')),
      RoomsCompanion(roomNumber: d.Value('201'), type: d.Value('سرير فردي'), price: d.Value(15000), status: d.Value('شاغرة'), localUuid: d.Value('r-201')),
      RoomsCompanion(roomNumber: d.Value('202'), type: d.Value('سرير عائلي'), price: d.Value(17000), status: d.Value('محجوزة'), localUuid: d.Value('r-202')),
      RoomsCompanion(roomNumber: d.Value('203'), type: d.Value('سرير عائلي'), price: d.Value(17000), status: d.Value('شاغرة'), localUuid: d.Value('r-203')),
      RoomsCompanion(roomNumber: d.Value('204'), type: d.Value('سرير فردي'), price: d.Value(15000), status: d.Value('شاغرة'), localUuid: d.Value('r-204')),
      RoomsCompanion(roomNumber: d.Value('301'), type: d.Value('سرير عائلي'), price: d.Value(7000), status: d.Value('شاغرة'), localUuid: d.Value('r-301')),
      RoomsCompanion(roomNumber: d.Value('302'), type: d.Value('سرير فردي'), price: d.Value(15000), status: d.Value('محجوزة'), localUuid: d.Value('r-302')),
    ];

    for (final r in roomsCompanions) {
      final t = Time.nowEpoch();
      await db.into(db.rooms).insert(r.copyWith(createdAt: d.Value(t), updatedAt: d.Value(t), lastModified: d.Value(t), version: const d.Value(1), origin: const d.Value('local')));
    }

    final b1 = await db.into(db.bookings).insert(BookingsCompanion(
      roomNumber: d.Value('102'),
      guestName: d.Value('محمد علي'),
      guestPhone: d.Value('773000111'),
      guestNationality: d.Value('يمني'),
      guestEmail: const d.Value(null),
      guestAddress: const d.Value(null),
      checkinDate: d.Value(now.subtract(const Duration(days: 1)).toIso8601String()),
      checkoutDate: const d.Value(null),
      status: d.Value('محجوزة'),
      notes: const d.Value(null),
      localUuid: d.Value('b-1'),
      createdAt: d.Value(Time.nowEpoch()),
      updatedAt: d.Value(Time.nowEpoch()),
      lastModified: d.Value(Time.nowEpoch()),
      version: const d.Value(1),
      origin: const d.Value('local'),
    ));

    final b2 = await db.into(db.bookings).insert(BookingsCompanion(
      roomNumber: d.Value('202'),
      guestName: d.Value('فايز صالح'),
      guestPhone: d.Value('774399835'),
      guestNationality: d.Value('يمني'),
      guestEmail: const d.Value(null),
      guestAddress: const d.Value(null),
      checkinDate: d.Value(now.toIso8601String()),
      checkoutDate: const d.Value(null),
      status: d.Value('محجوزة'),
      notes: const d.Value(''),
      localUuid: d.Value('b-2'),
      createdAt: d.Value(Time.nowEpoch()),
      updatedAt: d.Value(Time.nowEpoch()),
      lastModified: d.Value(Time.nowEpoch()),
      version: const d.Value(1),
      origin: const d.Value('local'),
    ));

    await db.into(db.employees).insert(EmployeesCompanion(
      name: d.Value('محمد احمد'), basicSalary: d.Value(0), status: d.Value('active'), localUuid: d.Value('e-1'), createdAt: d.Value(Time.nowEpoch()), updatedAt: d.Value(Time.nowEpoch()), lastModified: d.Value(Time.nowEpoch()), version: const d.Value(1), origin: const d.Value('local'),
    ));
    await db.into(db.employees).insert(EmployeesCompanion(
      name: d.Value('عبدالله طه'), basicSalary: d.Value(0), status: d.Value('active'), localUuid: d.Value('e-2'), createdAt: d.Value(Time.nowEpoch()), updatedAt: d.Value(Time.nowEpoch()), lastModified: d.Value(Time.nowEpoch()), version: const d.Value(1), origin: const d.Value('local'),
    ));
    await db.into(db.employees).insert(EmployeesCompanion(
      name: d.Value('عمار الشوب'), basicSalary: d.Value(0), status: d.Value('active'), localUuid: d.Value('e-3'), createdAt: d.Value(Time.nowEpoch()), updatedAt: d.Value(Time.nowEpoch()), lastModified: d.Value(Time.nowEpoch()), version: const d.Value(1), origin: const d.Value('local'),
    ));

    await db.into(db.expenses).insert(ExpensesCompanion(
      expenseType: d.Value('utilities'), description: d.Value('فاتورة كهرباء'), amount: d.Value(450000), date: d.Value(now.subtract(const Duration(days: 10)).toIso8601String().substring(0,10)), localUuid: d.Value('x-1'), createdAt: d.Value(Time.nowEpoch()), updatedAt: d.Value(Time.nowEpoch()), lastModified: d.Value(Time.nowEpoch()), version: const d.Value(1), origin: const d.Value('local'),
    ));
    await db.into(db.expenses).insert(ExpensesCompanion(
      expenseType: d.Value('other'), description: d.Value('ديزل'), amount: d.Value(21500), date: d.Value(now.subtract(const Duration(days: 1)).toIso8601String().substring(0,10)), localUuid: d.Value('x-2'), createdAt: d.Value(Time.nowEpoch()), updatedAt: d.Value(Time.nowEpoch()), lastModified: d.Value(Time.nowEpoch()), version: const d.Value(1), origin: const d.Value('local'),
    ));

    await db.into(db.cashTransactions).insert(CashTransactionsCompanion(
      transactionType: d.Value('income'), amount: d.Value(640000), referenceType: d.Value('booking'), referenceId: d.Value(b1), transactionTime: d.Value(now.toIso8601String()), localUuid: d.Value('c-1'), createdAt: d.Value(Time.nowEpoch()), updatedAt: d.Value(Time.nowEpoch()), lastModified: d.Value(Time.nowEpoch()), version: const d.Value(1), origin: const d.Value('local'),
    ));
    await db.into(db.cashTransactions).insert(CashTransactionsCompanion(
      transactionType: d.Value('income'), amount: d.Value(45000), referenceType: d.Value('booking'), referenceId: d.Value(b2), transactionTime: d.Value(now.toIso8601String()), localUuid: d.Value('c-2'), createdAt: d.Value(Time.nowEpoch()), updatedAt: d.Value(Time.nowEpoch()), lastModified: d.Value(Time.nowEpoch()), version: const d.Value(1), origin: const d.Value('local'),
    ));

    await db.into(db.payments).insert(PaymentsCompanion(
      bookingLocalId: d.Value(b1), amount: d.Value(90000), paymentDate: d.Value(now.toIso8601String()), paymentMethod: d.Value('نقدي'), revenueType: d.Value('room'), localUuid: d.Value('p-1'), createdAt: d.Value(Time.nowEpoch()), updatedAt: d.Value(Time.nowEpoch()), lastModified: d.Value(Time.nowEpoch()), version: const d.Value(1), origin: const d.Value('local'),
    ));
    await db.into(db.payments).insert(PaymentsCompanion(
      bookingLocalId: d.Value(b2), amount: d.Value(15000), paymentDate: d.Value(now.toIso8601String()), paymentMethod: d.Value('نقدي'), revenueType: d.Value('room'), localUuid: d.Value('p-2'), createdAt: d.Value(Time.nowEpoch()), updatedAt: d.Value(Time.nowEpoch()), lastModified: d.Value(Time.nowEpoch()), version: const d.Value(1), origin: const d.Value('local'),
    ));
  }
}
