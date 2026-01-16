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

  static const int maxErrorMessageLength = 500;
  static const int maxMetricsPayloadLength = 4000;

  static const Duration defaultAutoSyncInterval = Duration(minutes: 15);
  static const Duration outboxDebounceWindow = Duration(seconds: 10);
  static const Duration guardianOutboxDebounce = Duration(seconds: 30);
  static const Duration guardianLocalChangeDebounce = Duration(seconds: 5);
  static const Duration shortPollingDelay = Duration(milliseconds: 500);
  static const Duration appForegroundDelay = Duration(milliseconds: 500);
  static const Duration appForegroundAppwriteDelay = Duration(milliseconds: 1000);

  static const int googleDriveDefaultShardBytes = 4 * 1024 * 1024;
  static const int estimatedBytesPerDeltaChange = 500;

  static const Duration driveApiTimeout = Duration(seconds: 60);
  static const Duration driveDownloadTimeout = Duration(seconds: 120);
  static const Duration driveUploadTimeout = Duration(seconds: 180);
  static const Duration syncOperationTimeout = Duration(minutes: 5);

  static const int maxRetryAttempts = 5;
  static const Duration initialRetryDelay = Duration(seconds: 2);
  static const Duration maxRetryDelay = Duration(minutes: 2);
}
