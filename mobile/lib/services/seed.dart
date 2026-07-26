import 'package:drift/drift.dart' as d;
import '../utils/time.dart';
import 'local_db.dart';

class Seeder {
  Seeder(this.db);
  final AppDatabase db;

  Future<void> seedIfEmpty() async {
    final roomsCount =
        (await db.customSelect('SELECT COUNT(*) c FROM rooms').getSingle())
                .data['c']
            as int;
    if (roomsCount > 0) {
      return;
    }
    final now = DateTime.now();

    final roomsCompanions = [
      const RoomsCompanion(
        roomNumber: d.Value('101'),
        type: d.Value('سرير عائلي'),
        price: d.Value(15000),
        status: d.Value('شاغرة'),
        localUuid: d.Value('r-101'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('102'),
        type: d.Value('سرير عائلي'),
        price: d.Value(15000),
        status: d.Value('محجوزة'),
        localUuid: d.Value('r-102'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('103'),
        type: d.Value('سرير فردي'),
        price: d.Value(12000),
        status: d.Value('شاغرة'),
        localUuid: d.Value('r-103'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('104'),
        type: d.Value('سرير فردي'),
        price: d.Value(10000),
        status: d.Value('شاغرة'),
        localUuid: d.Value('r-104'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('201'),
        type: d.Value('سرير فردي'),
        price: d.Value(15000),
        status: d.Value('شاغرة'),
        localUuid: d.Value('r-201'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('202'),
        type: d.Value('سرير عائلي'),
        price: d.Value(17000),
        status: d.Value('محجوزة'),
        localUuid: d.Value('r-202'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('203'),
        type: d.Value('سرير عائلي'),
        price: d.Value(17000),
        status: d.Value('شاغرة'),
        localUuid: d.Value('r-203'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('204'),
        type: d.Value('سرير فردي'),
        price: d.Value(15000),
        status: d.Value('شاغرة'),
        localUuid: d.Value('r-204'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('301'),
        type: d.Value('سرير عائلي'),
        price: d.Value(7000),
        status: d.Value('شاغرة'),
        localUuid: d.Value('r-301'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('302'),
        type: d.Value('سرير فردي'),
        price: d.Value(15000),
        status: d.Value('محجوزة'),
        localUuid: d.Value('r-302'),
      ),
    ];

    for (final r in roomsCompanions) {
      final t = Time.nowEpoch();
      await db
          .into(db.rooms)
          .insert(
            r.copyWith(
              createdAt: d.Value(t),
              updatedAt: d.Value(t),
              lastModified: d.Value(t),
              version: const d.Value(1),
              origin: const d.Value('local'),
            ),
          );
    }

    final b1 = await db
        .into(db.bookings)
        .insert(
          BookingsCompanion(
            roomNumber: const d.Value('102'),
            guestName: const d.Value('محمد علي'),
            guestPhone: const d.Value('773000111'),
            guestNationality: const d.Value('يمني'),
            guestEmail: const d.Value(null),
            guestAddress: const d.Value(null),
            checkinDate: d.Value(
              now.subtract(const Duration(days: 1)).toIso8601String(),
            ),
            checkoutDate: const d.Value(null),
            status: const d.Value('محجوزة'),
            notes: const d.Value(null),
            localUuid: const d.Value('b-1'),
            createdAt: d.Value(Time.nowEpoch()),
            updatedAt: d.Value(Time.nowEpoch()),
            lastModified: d.Value(Time.nowEpoch()),
            version: const d.Value(1),
            origin: const d.Value('local'),
          ),
        );

    final b2 = await db
        .into(db.bookings)
        .insert(
          BookingsCompanion(
            roomNumber: const d.Value('202'),
            guestName: const d.Value('فايز صالح'),
            guestPhone: const d.Value('774399835'),
            guestNationality: const d.Value('يمني'),
            guestEmail: const d.Value(null),
            guestAddress: const d.Value(null),
            checkinDate: d.Value(now.toIso8601String()),
            checkoutDate: const d.Value(null),
            status: const d.Value('محجوزة'),
            notes: const d.Value(''),
            localUuid: const d.Value('b-2'),
            createdAt: d.Value(Time.nowEpoch()),
            updatedAt: d.Value(Time.nowEpoch()),
            lastModified: d.Value(Time.nowEpoch()),
            version: const d.Value(1),
            origin: const d.Value('local'),
          ),
        );

    await db
        .into(db.employees)
        .insert(
          EmployeesCompanion(
            name: const d.Value('محمد احمد'),
            basicSalary: const d.Value(0),
            status: const d.Value('active'),
            localUuid: const d.Value('e-1'),
            createdAt: d.Value(Time.nowEpoch()),
            updatedAt: d.Value(Time.nowEpoch()),
            lastModified: d.Value(Time.nowEpoch()),
            version: const d.Value(1),
            origin: const d.Value('local'),
          ),
        );
    await db
        .into(db.employees)
        .insert(
          EmployeesCompanion(
            name: const d.Value('عبدالله طه'),
            basicSalary: const d.Value(0),
            status: const d.Value('active'),
            localUuid: const d.Value('e-2'),
            createdAt: d.Value(Time.nowEpoch()),
            updatedAt: d.Value(Time.nowEpoch()),
            lastModified: d.Value(Time.nowEpoch()),
            version: const d.Value(1),
            origin: const d.Value('local'),
          ),
        );
    await db
        .into(db.employees)
        .insert(
          EmployeesCompanion(
            name: const d.Value('عمار الشوب'),
            basicSalary: const d.Value(0),
            status: const d.Value('active'),
            localUuid: const d.Value('e-3'),
            createdAt: d.Value(Time.nowEpoch()),
            updatedAt: d.Value(Time.nowEpoch()),
            lastModified: d.Value(Time.nowEpoch()),
            version: const d.Value(1),
            origin: const d.Value('local'),
          ),
        );

    await db
        .into(db.expenses)
        .insert(
          ExpensesCompanion(
            expenseType: const d.Value('utilities'),
            description: const d.Value('فاتورة كهرباء'),
            amount: const d.Value(450000),
            date: d.Value(
              Time.dateToString(now.subtract(const Duration(days: 10))),
            ),
            localUuid: const d.Value('x-1'),
            createdAt: d.Value(Time.nowEpoch()),
            updatedAt: d.Value(Time.nowEpoch()),
            lastModified: d.Value(Time.nowEpoch()),
            version: const d.Value(1),
            origin: const d.Value('local'),
          ),
        );
    await db
        .into(db.expenses)
        .insert(
          ExpensesCompanion(
            expenseType: const d.Value('other'),
            description: const d.Value('ديزل'),
            amount: const d.Value(21500),
            date: d.Value(
              Time.dateToString(now.subtract(const Duration(days: 1))),
            ),
            localUuid: const d.Value('x-2'),
            createdAt: d.Value(Time.nowEpoch()),
            updatedAt: d.Value(Time.nowEpoch()),
            lastModified: d.Value(Time.nowEpoch()),
            version: const d.Value(1),
            origin: const d.Value('local'),
          ),
        );

    await db
        .into(db.cashTransactions)
        .insert(
          CashTransactionsCompanion(
            transactionType: const d.Value('income'),
            amount: const d.Value(640000),
            referenceType: const d.Value('booking'),
            referenceId: d.Value(b1),
            transactionTime: d.Value(now.toIso8601String()),
            localUuid: const d.Value('c-1'),
            createdAt: d.Value(Time.nowEpoch()),
            updatedAt: d.Value(Time.nowEpoch()),
            lastModified: d.Value(Time.nowEpoch()),
            version: const d.Value(1),
            origin: const d.Value('local'),
          ),
        );
    await db
        .into(db.cashTransactions)
        .insert(
          CashTransactionsCompanion(
            transactionType: const d.Value('income'),
            amount: const d.Value(45000),
            referenceType: const d.Value('booking'),
            referenceId: d.Value(b2),
            transactionTime: d.Value(now.toIso8601String()),
            localUuid: const d.Value('c-2'),
            createdAt: d.Value(Time.nowEpoch()),
            updatedAt: d.Value(Time.nowEpoch()),
            lastModified: d.Value(Time.nowEpoch()),
            version: const d.Value(1),
            origin: const d.Value('local'),
          ),
        );

    await db
        .into(db.payments)
        .insert(
          PaymentsCompanion(
            bookingLocalId: d.Value(b1),
            amount: const d.Value(90000),
            paymentDate: d.Value(now.toIso8601String()),
            paymentMethod: const d.Value('نقدي'),
            revenueType: const d.Value('room'),
            localUuid: const d.Value('p-1'),
            createdAt: d.Value(Time.nowEpoch()),
            updatedAt: d.Value(Time.nowEpoch()),
            lastModified: d.Value(Time.nowEpoch()),
            version: const d.Value(1),
            origin: const d.Value('local'),
          ),
        );
    await db
        .into(db.payments)
        .insert(
          PaymentsCompanion(
            bookingLocalId: d.Value(b2),
            amount: const d.Value(15000),
            paymentDate: d.Value(now.toIso8601String()),
            paymentMethod: const d.Value('نقدي'),
            revenueType: const d.Value('room'),
            localUuid: const d.Value('p-2'),
            createdAt: d.Value(Time.nowEpoch()),
            updatedAt: d.Value(Time.nowEpoch()),
            lastModified: d.Value(Time.nowEpoch()),
            version: const d.Value(1),
            origin: const d.Value('local'),
          ),
        );

    await db
        .into(db.debts)
        .insert(
          DebtsCompanion(
            bookingLocalId: d.Value(b1),
            guestName: const d.Value('محمد علي'),
            checkinDate: d.Value(
              Time.dateToString(now.subtract(const Duration(days: 3))),
            ),
            checkoutDate: d.Value(
              Time.dateToString(now.add(const Duration(days: 1))),
            ),
            totalAmount: const d.Value(120000),
            paidAmount: const d.Value(50000),
            remainingAmount: const d.Value(70000),
            paymentDate: d.Value(Time.dateToString(now)),
            pledge: const d.Value('جواز سفر'),
            pledgeType: const d.Value('وثيقة رسمية'),
            note: const d.Value('يتم السداد عند الخروج'),
            localUuid: const d.Value('d-1'),
            createdAt: d.Value(Time.nowEpoch()),
            updatedAt: d.Value(Time.nowEpoch()),
            lastModified: d.Value(Time.nowEpoch()),
            version: const d.Value(1),
            origin: const d.Value('local'),
          ),
        );
  }
}
