// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payments_dao.dart';

// ignore_for_file: type=lint
mixin _$PaymentsDaoMixin on DatabaseAccessor<AppDatabase> {
  $RoomsTable get rooms => attachedDatabase.rooms;
  $BookingsTable get bookings => attachedDatabase.bookings;
  $CashTransactionsTable get cashTransactions => attachedDatabase.cashTransactions;
  $PaymentsTable get payments => attachedDatabase.payments;
  PaymentsDaoManager get managers => PaymentsDaoManager(this);
}

class PaymentsDaoManager {
  final _$PaymentsDaoMixin _db;
  PaymentsDaoManager(this._db);
  $$RoomsTableTableManager get rooms => $$RoomsTableTableManager(_db.attachedDatabase, _db.rooms);
  $$BookingsTableTableManager get bookings => $$BookingsTableTableManager(_db.attachedDatabase, _db.bookings);
  $$CashTransactionsTableTableManager get cashTransactions => $$CashTransactionsTableTableManager(
    _db.attachedDatabase,
    _db.cashTransactions,
  );
  $$PaymentsTableTableManager get payments => $$PaymentsTableTableManager(_db.attachedDatabase, _db.payments);
}
