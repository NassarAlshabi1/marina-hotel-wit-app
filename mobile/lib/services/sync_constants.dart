class SyncConstants {
  SyncConstants._();

  static const tableOrder = [
    'rooms',
    'employees',
    'bookings',
    'payments',
    'expenses',
    'debts',
    'booking_notes',
    'cash_transactions',
  ];

  static const extraTables = [
    'booking_nights',
    'hotel_day_ledger',
    'auto_fix_runs',
    'integrity_violations',
    'app_sessions',
    'salary_cycles',
    'salary_payments',
  ];

  static List<String> get allTablesInOrder => [
        ...tableOrder,
        ...extraTables,
      ];

  static List<String> get allTablesInReverseOrder => allTablesInOrder.reversed.toList();
}
