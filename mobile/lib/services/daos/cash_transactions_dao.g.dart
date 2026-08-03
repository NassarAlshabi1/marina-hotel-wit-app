// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cash_transactions_dao.dart';

// ignore_for_file: type=lint
mixin _$CashTransactionsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CashTransactionsTable get cashTransactions => attachedDatabase.cashTransactions;
  CashTransactionsDaoManager get managers => CashTransactionsDaoManager(this);
}

class CashTransactionsDaoManager {
  final _$CashTransactionsDaoMixin _db;
  CashTransactionsDaoManager(this._db);
  $$CashTransactionsTableTableManager get cashTransactions => $$CashTransactionsTableTableManager(
    _db.attachedDatabase,
    _db.cashTransactions,
  );
}
