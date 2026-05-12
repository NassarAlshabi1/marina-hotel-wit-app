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
    'shift_notes',
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

  // ✅ SECURITY: قائمة بيضاء شاملة لجميع أسماء الجداول المسموح بها في SQL
  // تُستخدم لمنع SQL Injection في العمليات الديناميكية
  static const sqlAllowedTables = {
    // Main tables
    'rooms', 'employees', 'bookings', 'payments', 'expenses', 'debts',
    'booking_notes', 'shift_notes', 'cash_transactions',
    // Extra tables
    'booking_nights', 'hotel_day_ledger', 'auto_fix_runs',
    'integrity_violations', 'app_sessions', 'salary_cycles',
    'salary_payments',
    // Sync/Outbox tables
    'outbox', 'sync_log', 'sync_queue',
    // New tables
    'salary_withdrawals', 'blacklist', 'price_adjustments',
    'booking_price_adjustments', 'audit_logs', 'payment_voids',
    'guest_infos',
  };

  static List<String> get allTablesInOrder => [...tableOrder, ...extraTables];

  static List<String> get allTablesInReverseOrder =>
      allTablesInOrder.reversed.toList();

  static const int maxErrorMessageLength = 500;
  static const int maxMetricsPayloadLength = 4000;

  static const Duration defaultAutoSyncInterval = Duration(minutes: 15);
  static const Duration outboxDebounceWindow = Duration(seconds: 10);
  static const Duration guardianOutboxDebounce = Duration(seconds: 30);
  static const Duration guardianLocalChangeDebounce = Duration(seconds: 5);
  static const Duration shortPollingDelay = Duration(milliseconds: 500);
  static const Duration appForegroundDelay = Duration(milliseconds: 500);
  static const Duration appForegroundAppwriteDelay = Duration(
    milliseconds: 1000,
  );

  /// الفترة الزمنية الدنيا بين سحبين تلقائيين عند فتح التطبيق
  /// إذا مرت أقل من هذه المدة منذ آخر سحب تلقائي، يتم تخطي السحب
  static const Duration appOpenSyncInterval = Duration(hours: 1);

  /// مفتاح SharedPreferences لحفظ وقت آخر سحب تلقائي عند فتح التطبيق
  static const String lastAppOpenPullKey = 'last_app_open_pull_epoch_ms';

  static const int googleDriveDefaultShardBytes = 4 * 1024 * 1024;
  static const int estimatedBytesPerDeltaChange = 500;
}
