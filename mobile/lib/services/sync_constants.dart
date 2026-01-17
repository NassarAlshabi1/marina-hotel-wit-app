class SyncConstants {
  static const List<String> allTablesInOrder = [
    'bookings',
    'payments',
    'expenses',
    'rooms',
    'debts',
    'employees',
    'shift_notes'
  ];

  static const List<String> allTablesInReverseOrder = [
    'shift_notes',
    'employees',
    'debts',
    'rooms',
    'expenses',
    'payments',
    'bookings'
  ];

  static const Duration guardianOutboxDebounce = Duration(seconds: 30);
  static const Duration defaultAutoSyncInterval = Duration(minutes: 5);
  static const Duration guardianLocalChangeDebounce = Duration(seconds: 10);
  static const Duration appForegroundDelay = Duration(seconds: 2);
  static const Duration appForegroundAppwriteDelay = Duration(seconds: 3);
}
