import 'package:drift/drift.dart' as d;

import '../daos/bookings_dao.dart';
import '../daos/cash_transactions_dao.dart';
import '../daos/debts_dao.dart';
import '../daos/employees_dao.dart';
import '../daos/expenses_dao.dart';
import '../daos/outbox_dao.dart';
import '../daos/payments_dao.dart';
import '../daos/rooms_dao.dart';
import '../google_drive_auto_sync_engine.dart';
import '../local_db.dart';

class BookingsRepositoryAutomated {
  BookingsRepositoryAutomated(this.db)
      : outbox = OutboxDao(db),
        dao = BookingsDao(db, OutboxDao(db));

  final AppDatabase db;
  final OutboxDao outbox;
  final BookingsDao dao;

  Stream<List<Booking>> watchList({String? roomNumber, String? status}) =>
      dao.watchList(roomNumber: roomNumber, status: status);

  Stream<Booking?> watchOne(int id) => dao.watchById(id);

  Future<int> create({
    required String roomNumber,
    required String guestName,
    required String guestPhone,
    String guestIdType = 'بطاقة شخصية',
    String guestIdNumber = '',
    String? guestIdIssueDate,
    String? guestIdIssuePlace,
    required String guestNationality,
    String? guestEmail,
    String? guestAddress,
    required String checkinDate,
    String? checkoutDate,
    String status = 'active',
    String? notes,
    int expectedNights = 1,
  }) async {
    final result = await dao.insertOne(
      BookingsCompanion(
        roomNumber: d.Value(roomNumber),
        guestName: d.Value(guestName),
        guestPhone: d.Value(guestPhone),
        guestIdType: d.Value(guestIdType),
        guestIdNumber: d.Value(guestIdNumber),
        guestIdIssueDate: d.Value(guestIdIssueDate),
        guestIdIssuePlace: d.Value(guestIdIssuePlace),
        guestNationality: d.Value(guestNationality),
        guestEmail: d.Value(guestEmail),
        guestAddress: d.Value(guestAddress),
        checkinDate: d.Value(checkinDate),
        checkoutDate: d.Value(checkoutDate),
        status: d.Value(status),
        notes: d.Value(notes),
        expectedNights: d.Value(expectedNights),
      ),
    );

    AutoSyncEngine.instance.notifyDataChange(
      table: 'bookings',
      operation: 'INSERT',
      count: 1,
      recordData: {'guest_name': guestName, 'room_number': roomNumber},
    );

    return result;
  }

  Future<int> update(int id, d.BookingsCompanion updates) async {
    final result = await dao.updateById(id, updates);

    AutoSyncEngine.instance.notifyDataChange(
      table: 'bookings',
      operation: 'UPDATE',
      count: 1,
    );

    return result;
  }

  Future<void> delete(int id) async {
    await dao.deleteById(id);

    AutoSyncEngine.instance.notifyDataChange(
      table: 'bookings',
      operation: 'DELETE',
      count: 1,
    );
  }

  Future<int> bulkCreate(List<BookingsCompanion> bookings) async {
    int count = 0;
    for (final booking in bookings) {
      try {
        await dao.insertOne(booking);
        count++;
      } catch (_) {
        continue;
      }
    }

    if (count > 0) {
      AutoSyncEngine.instance.notifyDataChange(
        table: 'bookings',
        operation: 'BATCH_INSERT',
        count: count,
      );
    }

    return count;
  }
}

class PaymentsRepositoryAutomated {
  PaymentsRepositoryAutomated(this.db) : dao = PaymentsDao(db, OutboxDao(db));

  final AppDatabase db;
  final PaymentsDao dao;

  Stream<List<Payment>> watchAll() => dao.watchList();
  Stream<Payment?> watchOne(int id) => dao.watchById(id);

  Future<int> create({
    required double amount,
    required String paymentDate,
    required String paymentMethod,
    String revenueType = 'room_revenue',
    int? bookingLocalId,
    String? roomNumber,
    String? notes,
  }) async {
    final result = await dao.insertOne(
      PaymentsCompanion(
        amount: d.Value(amount),
        paymentDate: d.Value(paymentDate),
        paymentMethod: d.Value(paymentMethod),
        revenueType: d.Value(revenueType),
        bookingLocalId: d.Value(bookingLocalId),
        roomNumber: d.Value(roomNumber),
        notes: d.Value(notes),
      ),
    );

    AutoSyncEngine.instance.notifyDataChange(
      table: 'payments',
      operation: 'INSERT',
      count: 1,
      recordData: {'amount': amount, 'payment_method': paymentMethod},
    );

    return result;
  }

  Future<int> update(int id, PaymentsCompanion updates) async {
    final result = await dao.updateById(id, updates);

    AutoSyncEngine.instance.notifyDataChange(
      table: 'payments',
      operation: 'UPDATE',
      count: 1,
    );

    return result;
  }

  Future<void> delete(int id) async {
    await dao.softDelete(id);

    AutoSyncEngine.instance.notifyDataChange(
      table: 'payments',
      operation: 'DELETE',
      count: 1,
    );
  }
}

class ExpensesRepositoryAutomated {
  ExpensesRepositoryAutomated(this.db) : dao = ExpensesDao(db, OutboxDao(db));

  final AppDatabase db;
  final ExpensesDao dao;

  Stream<List<Expense>> watchAll() => dao.watchList();

  Future<int> create({
    required String expenseType,
    required String description,
    required double amount,
    required String date,
    int? relatedId,
  }) async {
    final result = await dao.insertOne(
      ExpensesCompanion(
        expenseType: d.Value(expenseType),
        description: d.Value(description),
        amount: d.Value(amount),
        date: d.Value(date),
        relatedId: d.Value(relatedId),
      ),
    );

    AutoSyncEngine.instance.notifyDataChange(
      table: 'expenses',
      operation: 'INSERT',
      count: 1,
      recordData: {'expense_type': expenseType, 'amount': amount},
    );

    return result;
  }

  Future<int> update(int id, ExpensesCompanion updates) async {
    final result = await dao.updateById(id, updates);

    AutoSyncEngine.instance.notifyDataChange(
      table: 'expenses',
      operation: 'UPDATE',
      count: 1,
    );

    return result;
  }

  Future<void> delete(int id) async {
    await dao.softDelete(id);

    AutoSyncEngine.instance.notifyDataChange(
      table: 'expenses',
      operation: 'DELETE',
      count: 1,
    );
  }
}

class RoomsRepositoryAutomated {
  RoomsRepositoryAutomated(this.db) : dao = RoomsDao(db, OutboxDao(db));

  final AppDatabase db;
  final RoomsDao dao;

  Stream<List<Room>> watchAll() => dao.watchList();
  Stream<Room?> watchOne(String roomNumber) => dao.watchByNumber(roomNumber);

  Future<String> create({
    required String roomNumber,
    required String type,
    required double price,
    String status = 'available',
    String? imageUrl,
  }) async {
    final result = await dao.insertOne(
      RoomsCompanion(
        roomNumber: d.Value(roomNumber),
        type: d.Value(type),
        price: d.Value(price),
        status: d.Value(status),
        imageUrl: d.Value(imageUrl),
      ),
    );

    AutoSyncEngine.instance.notifyDataChange(
      table: 'rooms',
      operation: 'INSERT',
      count: 1,
      recordData: {'room_number': roomNumber, 'type': type},
    );

    return result;
  }

  Future<int> updateStatus(String roomNumber, String newStatus) async {
    final result = await dao.updateByNumber(
      roomNumber,
      RoomsCompanion(status: d.Value(newStatus)),
    );

    AutoSyncEngine.instance.notifyDataChange(
      table: 'rooms',
      operation: 'UPDATE_STATUS',
      count: 1,
      recordData: {'room_number': roomNumber, 'status': newStatus},
    );

    return result;
  }

  Future<int> update(String roomNumber, RoomsCompanion updates) async {
    final result = await dao.updateByNumber(roomNumber, updates);

    AutoSyncEngine.instance.notifyDataChange(
      table: 'rooms',
      operation: 'UPDATE',
      count: 1,
    );

    return result;
  }
}

class DebtsRepositoryAutomated {
  DebtsRepositoryAutomated(this.db) : dao = DebtsDao(db, OutboxDao(db));

  final AppDatabase db;
  final DebtsDao dao;

  Stream<List<Debt>> watchAll() => dao.watchList();
  Stream<List<Debt>> watchUnsettled() =>
      dao.watchList().map((debts) => debts.where((d) => d.isSettled == 0).toList());

  Future<int> create({
    required String guestName,
    required String checkinDate,
    required String checkoutDate,
    required String dateRecorded,
    required String debtReason,
    required double totalAmount,
    double paidAmount = 0.0,
    String? pledge,
    String? pledgeType,
    String? note,
  }) async {
    final remainingAmount = totalAmount - paidAmount;
    final isSettled = remainingAmount <= 0 ? 1 : 0;

    final result = await dao.insertOne(
      DebtsCompanion(
        guestName: d.Value(guestName),
        checkinDate: d.Value(checkinDate),
        checkoutDate: d.Value(checkoutDate),
        dateRecorded: d.Value(dateRecorded),
        debtReason: d.Value(debtReason),
        totalAmount: d.Value(totalAmount),
        paidAmount: d.Value(paidAmount),
        remainingAmount: d.Value(remainingAmount),
        isSettled: d.Value(isSettled),
        pledge: d.Value(pledge),
        pledgeType: d.Value(pledgeType),
        note: d.Value(note),
      ),
    );

    AutoSyncEngine.instance.notifyDataChange(
      table: 'debts',
      operation: 'INSERT',
      count: 1,
      recordData: {'guest_name': guestName, 'total_amount': totalAmount},
    );

    return result;
  }

  Future<int> recordPayment(int debtId, double paymentAmount, String paymentDate) async {
    final debt = await dao.getById(debtId);
    if (debt == null) return 0;

    final newPaidAmount = debt.paidAmount + paymentAmount;
    final newRemainingAmount = debt.totalAmount - newPaidAmount;
    final isSettled = newRemainingAmount <= 0 ? 1 : 0;

    final result = await dao.updateById(
      debtId,
      DebtsCompanion(
        paidAmount: d.Value(newPaidAmount),
        remainingAmount: d.Value(newRemainingAmount),
        paymentDate: d.Value(paymentDate),
        isSettled: d.Value(isSettled),
      ),
    );

    AutoSyncEngine.instance.notifyDataChange(
      table: 'debts',
      operation: 'PAYMENT',
      count: 1,
      recordData: {'debt_id': debtId, 'payment_amount': paymentAmount},
    );

    return result;
  }
}

class EmployeesRepositoryAutomated {
  EmployeesRepositoryAutomated(this.db) : dao = EmployeesDao(db, OutboxDao(db));

  final AppDatabase db;
  final EmployeesDao dao;

  Stream<List<Employee>> watchAll() => dao.watchList();
  Stream<List<Employee>> watchActive() =>
      dao.watchList().map((employees) => employees.where((e) => e.status == 'active').toList());

  Future<int> create({
    required String name,
    required double basicSalary,
    required String position,
    required String phone,
    required String hireDate,
    String status = 'active',
  }) async {
    final result = await dao.insertOne(
      EmployeesCompanion(
        name: d.Value(name),
        basicSalary: d.Value(basicSalary),
        position: d.Value(position),
        phone: d.Value(phone),
        hireDate: d.Value(hireDate),
        status: d.Value(status),
      ),
    );

    AutoSyncEngine.instance.notifyDataChange(
      table: 'employees',
      operation: 'INSERT',
      count: 1,
      recordData: {'name': name, 'position': position},
    );

    return result;
  }

  Future<int> update(int id, EmployeesCompanion updates) async {
    final result = await dao.updateById(id, updates);

    AutoSyncEngine.instance.notifyDataChange(
      table: 'employees',
      operation: 'UPDATE',
      count: 1,
    );

    return result;
  }

  Future<void> delete(int id) async {
    await dao.softDelete(id);

    AutoSyncEngine.instance.notifyDataChange(
      table: 'employees',
      operation: 'DELETE',
      count: 1,
    );
  }
}

class CashTransactionsRepositoryAutomated {
  CashTransactionsRepositoryAutomated(this.db)
      : dao = CashTransactionsDao(db, OutboxDao(db));

  final AppDatabase db;
  final CashTransactionsDao dao;

  Stream<List<CashTransaction>> watchAll() => dao.watchList();

  Future<int> create({
    required String transactionType,
    required double amount,
    String? referenceType,
    int? referenceId,
    String? description,
    int? createdBy,
  }) async {
    final result = await dao.insertOne(
      CashTransactionsCompanion(
        transactionType: d.Value(transactionType),
        amount: d.Value(amount),
        referenceType: d.Value(referenceType),
        referenceId: d.Value(referenceId),
        description: d.Value(description),
        createdBy: d.Value(createdBy),
      ),
    );

    AutoSyncEngine.instance.notifyDataChange(
      table: 'cash_transactions',
      operation: 'INSERT',
      count: 1,
      recordData: {'type': transactionType, 'amount': amount},
    );

    return result;
  }

  Future<int> update(int id, CashTransactionsCompanion updates) async {
    final result = await dao.updateById(id, updates);

    AutoSyncEngine.instance.notifyDataChange(
      table: 'cash_transactions',
      operation: 'UPDATE',
      count: 1,
    );

    return result;
  }
}

class MixedOperationsExample {
  final AppDatabase db;

  MixedOperationsExample(this.db);

  Future<void> checkoutBookingWithPayment({
    required int bookingId,
    required double totalAmount,
    required double paidAmount,
    required String paymentMethod,
    required String checkoutDate,
  }) async {
    final bookingsDao = BookingsDao(db, OutboxDao(db));
    final paymentsDao = PaymentsDao(db, OutboxDao(db));
    final debtsDao = DebtsDao(db, OutboxDao(db));

    int operationsCount = 0;

    await bookingsDao.updateById(
      bookingId,
      BookingsCompanion(
        status: const d.Value('checkout'),
        actualCheckout: d.Value(checkoutDate),
      ),
    );
    operationsCount++;

    if (paidAmount > 0) {
      final booking = await bookingsDao.getById(bookingId);
      await paymentsDao.insertOne(
        PaymentsCompanion(
          bookingLocalId: d.Value(bookingId),
          roomNumber: d.Value(booking?.roomNumber),
          amount: d.Value(paidAmount),
          paymentDate: d.Value(checkoutDate),
          paymentMethod: d.Value(paymentMethod),
          revenueType: const d.Value('room_revenue'),
        ),
      );
      operationsCount++;
    }

    final remainingAmount = totalAmount - paidAmount;
    if (remainingAmount > 0) {
      final booking = await bookingsDao.getById(bookingId);
      await debtsDao.insertOne(
        DebtsCompanion(
          bookingLocalId: d.Value(bookingId),
          guestName: d.Value(booking?.guestName ?? ''),
          checkinDate: d.Value(booking?.checkinDate ?? ''),
          checkoutDate: d.Value(checkoutDate),
          dateRecorded: d.Value(checkoutDate),
          debtReason: const d.Value('رصيد متبقي عند المغادرة'),
          totalAmount: d.Value(remainingAmount),
          paidAmount: const d.Value(0.0),
          remainingAmount: d.Value(remainingAmount),
          isSettled: const d.Value(0),
        ),
      );
      operationsCount++;
    }

    AutoSyncEngine.instance.notifyDataChange(
      table: 'bookings',
      operation: 'CHECKOUT_WITH_PAYMENT',
      count: operationsCount,
      recordData: {
        'booking_id': bookingId,
        'total_amount': totalAmount,
        'paid_amount': paidAmount,
        'remaining': remainingAmount,
      },
    );
  }

  Future<void> bulkCheckout(List<int> bookingIds, String checkoutDate) async {
    final bookingsDao = BookingsDao(db, OutboxDao(db));

    int successCount = 0;
    for (final id in bookingIds) {
      try {
        await bookingsDao.updateById(
          id,
          BookingsCompanion(
            status: const d.Value('checkout'),
            actualCheckout: d.Value(checkoutDate),
          ),
        );
        successCount++;
      } catch (_) {
        continue;
      }
    }

    if (successCount > 0) {
      AutoSyncEngine.instance.notifyDataChange(
        table: 'bookings',
        operation: 'BULK_CHECKOUT',
        count: successCount,
      );
    }
  }

  Future<void> dailyFinancialClose({
    required List<Payment> payments,
    required List<Expense> expenses,
    required double cashRegisterBalance,
  }) async {
    final paymentsDao = PaymentsDao(db, OutboxDao(db));
    final expensesDao = ExpensesDao(db, OutboxDao(db));

    int totalOperations = 0;

    for (final payment in payments) {
      await paymentsDao.insertOne(payment.toCompanion(true));
      totalOperations++;
    }

    for (final expense in expenses) {
      await expensesDao.insertOne(expense.toCompanion(true));
      totalOperations++;
    }

    AutoSyncEngine.instance.notifyDataChange(
      table: 'finance',
      operation: 'DAILY_CLOSE',
      count: totalOperations,
      recordData: {
        'payments_count': payments.length,
        'expenses_count': expenses.length,
        'balance': cashRegisterBalance,
      },
    );
  }
}

class AutomatedRepositoryFactory {
  final AppDatabase db;

  AutomatedRepositoryFactory(this.db);

  BookingsRepositoryAutomated get bookings => BookingsRepositoryAutomated(db);
  PaymentsRepositoryAutomated get payments => PaymentsRepositoryAutomated(db);
  ExpensesRepositoryAutomated get expenses => ExpensesRepositoryAutomated(db);
  RoomsRepositoryAutomated get rooms => RoomsRepositoryAutomated(db);
  DebtsRepositoryAutomated get debts => DebtsRepositoryAutomated(db);
  EmployeesRepositoryAutomated get employees => EmployeesRepositoryAutomated(db);
  CashTransactionsRepositoryAutomated get cashTransactions =>
      CashTransactionsRepositoryAutomated(db);
}
